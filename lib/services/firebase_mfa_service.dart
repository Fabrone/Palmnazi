import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MFA RESULT
// ─────────────────────────────────────────────────────────────────────────────
class MfaResult {
  final bool   isSuccess;
  final String message;
  const MfaResult._({required this.isSuccess, required this.message});

  factory MfaResult.success({String message = 'Success'}) =>
      MfaResult._(isSuccess: true,  message: message);
  factory MfaResult.failure(String message) =>
      MfaResult._(isSuccess: false, message: message);

  @override
  String toString() => 'MfaResult(isSuccess: $isSuccess, message: $message)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE MFA SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseMfaService {
  FirebaseMfaService._();

  static final Logger _log = Logger(
    printer: PrettyPrinter(methodCount: 0, errorMethodCount: 8, lineLength: 100),
  );

  static const String _region = 'us-central1';

  static Future<User?> _requireAuthenticatedUser() async {
    _log.d(
      '🔐 [AUTH_GUARD] ─────────────────────────────────────────────────────\n'
      '🔐 [AUTH_GUARD] Step 1 — Checking Dart-layer currentUser snapshot',
    );

    User? user = FirebaseAuth.instance.currentUser;
    _log.d(
      '🔐 [AUTH_GUARD] Step 1 result: '
      'uid=${user?.uid ?? "null"} | isAnon=${user?.isAnonymous}',
    );

    // If absent or anonymous, wait for a real auth event on the stream.
    if (user == null || user.isAnonymous) {
      _log.w(
        '🔐 [AUTH_GUARD] Step 2 — No real user in snapshot; '
        'waiting on authStateChanges() (10 s timeout)…',
      );
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .where((u) => u != null && !u.isAnonymous)
            .first
            .timeout(const Duration(seconds: 10));
        _log.d(
          '🔐 [AUTH_GUARD] Step 2 result: '
          'uid=${user?.uid} confirmed via authStateChanges',
        );
      } on TimeoutException {
        _log.w('🔐 [AUTH_GUARD] Step 2 result: TIMEOUT — no real user arrived');
        user = null;
      } catch (e) {
        _log.w('🔐 [AUTH_GUARD] Step 2 result: Stream error — $e');
        user = null;
      }
    }

    if (user == null || user.isAnonymous) {
      _log.w(
        '🔐 [AUTH_GUARD] RESULT: NO VALID USER — '
        'uid=${user?.uid ?? "null"} | isAnon=${user?.isAnonymous}',
      );
      return null;
    }

    _log.d(
      '🔐 [AUTH_GUARD] RESULT: ✓ User object ready\n'
      '🔐 [AUTH_GUARD]           uid=${user.uid} | email=${user.email}\n'
      '🔐 [AUTH_GUARD]           (Token will be force-refreshed in _callFunctionViaHttp)',
    );
    return user;
  }

  static Future<Map<String, dynamic>> _callFunctionViaHttp({
    required User   user,
    required String functionName,
    Map<String, dynamic> data = const {},
  }) async {
    _log.d(
      '🌐 [HTTP_CALL] ─────────────────────────────────────────────────────\n'
      '🌐 [HTTP_CALL] Function : $functionName\n'
      '🌐 [HTTP_CALL] UID      : ${user.uid}\n'
      '🌐 [HTTP_CALL] Payload  : $data',
    );

    // ── A: Force-refresh the ID token from Firebase Auth REST API
    _log.d('🌐 [HTTP_CALL] Step A — Force-refreshing ID token (getIdToken: true)');
    final String idToken;
    try {
      final raw = await user.getIdToken(true); // ← v4 FIX: true, not false
      if (raw == null || raw.isEmpty) {
        throw Exception('getIdToken returned null/empty');
      }
      idToken = raw;
      _log.d(
        '🌐 [HTTP_CALL] Step A: ✓ Fresh token obtained '
        '(${idToken.length} chars, first 20: ${idToken.substring(0, 20)}…)',
      );
    } catch (e) {
      _log.w('🌐 [HTTP_CALL] Step A: ✗ Token refresh failed — $e');
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Could not obtain auth token. Please sign in again.',
      );
    }

    // ── B: Cloud Function URL ─────────────────────────────────────────────────
    final projectId = Firebase.app().options.projectId;
    final uri = Uri.parse(
      'https://$_region-$projectId.cloudfunctions.net/$functionName',
    );
    _log.d('🌐 [HTTP_CALL] Step B: URL = $uri');

    // ── C: POST with Authorization: Bearer header ─────────────────────────────
    _log.d(
      '🌐 [HTTP_CALL] Step C — Sending HTTP POST\n'
      '🌐 [HTTP_CALL]           Authorization: Bearer ${idToken.substring(0, 20)}…',
    );
    final http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'data': data}),
      ).timeout(const Duration(seconds: 30));

      _log.d(
        '🌐 [HTTP_CALL] Step C: ✓ Response received\n'
        '🌐 [HTTP_CALL]           HTTP status : ${response.statusCode}\n'
        '🌐 [HTTP_CALL]           Body        : '
        '${response.body.length > 400 ? "${response.body.substring(0, 400)}…" : response.body}',
      );
    } on TimeoutException {
      _log.w('🌐 [HTTP_CALL] Step C: ✗ Request timed out after 30 s');
      throw FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'The request timed out. Please try again.',
      );
    } catch (e) {
      _log.w('🌐 [HTTP_CALL] Step C: ✗ HTTP error — $e');
      rethrow;
    }

    // ── D: Parse response ─────────────────────────────────────────────────────
    _log.d('🌐 [HTTP_CALL] Step D — Parsing response body');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final result = (body['result'] as Map<String, dynamic>?) ?? {};
        _log.d('🌐 [HTTP_CALL] Step D: ✓ Success → $result');
        return result;
      }

      // Error: {"error": {"status": "UNAUTHENTICATED", "message": "..."}}
      final error   = (body['error'] as Map<String, dynamic>?) ?? {};
      final rawCode = (error['status'] as String? ?? 'INTERNAL');
      final code    = rawCode.toLowerCase().replaceAll('_', '-');
      final message = (error['message'] as String?) ?? 'Unknown error from server';

      _log.w(
        '🌐 [HTTP_CALL] Step D: ✗ Function returned error\n'
        '🌐 [HTTP_CALL]           HTTP status : ${response.statusCode}\n'
        '🌐 [HTTP_CALL]           Error code  : $code  (raw: $rawCode)\n'
        '🌐 [HTTP_CALL]           Message     : $message',
      );
      throw FirebaseFunctionsException(code: code, message: message);
    } catch (e) {
      if (e is FirebaseFunctionsException) rethrow;
      _log.w(
        '🌐 [HTTP_CALL] Step D: ✗ Could not parse response body\n'
        '🌐 [HTTP_CALL]           Raw body : ${response.body}\n'
        '🌐 [HTTP_CALL]           Error    : $e',
      );
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected response from server.',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEND OTP
  // ══════════════════════════════════════════════════════════════════════════
  static Future<MfaResult> sendOtp({required String email}) async {
    _log.i(
      '🔐 [SEND_OTP] ══════════════════════════════════════════════════════\n'
      '🔐 [SEND_OTP] ━━━ START ━━━ | email=$email',
    );

    _log.d('🔐 [SEND_OTP] Phase 1 — Acquiring authenticated user');
    final user = await _requireAuthenticatedUser();
    if (user == null) {
      _log.w('🔐 [SEND_OTP] Phase 1: ✗ No authenticated user — aborting');
      return MfaResult.failure('Please sign in again before enabling MFA.');
    }
    _log.d('🔐 [SEND_OTP] Phase 1: ✓ uid=${user.uid}');

    _log.d(
      '🔐 [SEND_OTP] Phase 2 — Calling mfaSendOtp via direct HTTP\n'
      '🔐 [SEND_OTP]            (token will be force-refreshed in _callFunctionViaHttp)',
    );
    try {
      final result = await _callFunctionViaHttp(
        user:         user,
        functionName: 'mfaSendOtp',
        data:         {'email': email.trim()},
      );
      _log.i(
        '🔐 [SEND_OTP] Phase 2: ✓ Cloud Function succeeded\n'
        '🔐 [SEND_OTP]            Result : $result',
      );
      return MfaResult.success(
        message: 'A verification code has been sent to $email.',
      );
    } on FirebaseFunctionsException catch (e) {
      _log.w(
        '🔐 [SEND_OTP] Phase 2: ✗ Function error\n'
        '🔐 [SEND_OTP]            code    : ${e.code}\n'
        '🔐 [SEND_OTP]            message : ${e.message}',
      );
      return MfaResult.failure(_mapFunctionError(e));
    } catch (e, st) {
      _log.e(
        '🔐 [SEND_OTP] Phase 2: ✗ Unexpected error (${e.runtimeType})',
        error: e, stackTrace: st,
      );
      return MfaResult.failure('Could not send verification code. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VERIFY OTP
  // ══════════════════════════════════════════════════════════════════════════
  static Future<MfaResult> verifyOtp({required String otp}) async {
    _log.i(
      '🔐 [VERIFY_OTP] ════════════════════════════════════════════════════\n'
      '🔐 [VERIFY_OTP] ━━━ START ━━━',
    );

    _log.d('🔐 [VERIFY_OTP] Phase 1 — Acquiring authenticated user');
    final user = await _requireAuthenticatedUser();
    if (user == null) {
      _log.w('🔐 [VERIFY_OTP] Phase 1: ✗ No authenticated user — aborting');
      return MfaResult.failure('Please sign in again before verifying your code.');
    }
    _log.d('🔐 [VERIFY_OTP] Phase 1: ✓ uid=${user.uid}');

    _log.d('🔐 [VERIFY_OTP] Phase 2 — Calling mfaVerifyOtp via direct HTTP');
    try {
      final result = await _callFunctionViaHttp(
        user:         user,
        functionName: 'mfaVerifyOtp',
        data:         {'otp': otp.trim()},
      );
      final msg = (result['message'] as String?) ?? 'MFA enabled.';
      _log.i(
        '🔐 [VERIFY_OTP] Phase 2: ✓ MFA enabled\n'
        '🔐 [VERIFY_OTP]            message : $msg',
      );
      return MfaResult.success(message: '🔒 $msg Your account is now more secure.');
    } on FirebaseFunctionsException catch (e) {
      _log.w(
        '🔐 [VERIFY_OTP] Phase 2: ✗ Function error\n'
        '🔐 [VERIFY_OTP]            code    : ${e.code}\n'
        '🔐 [VERIFY_OTP]            message : ${e.message}',
      );
      return MfaResult.failure(_mapFunctionError(e));
    } catch (e, st) {
      _log.e(
        '🔐 [VERIFY_OTP] Phase 2: ✗ Unexpected error (${e.runtimeType})',
        error: e, stackTrace: st,
      );
      return MfaResult.failure('Verification failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISABLE MFA
  // ══════════════════════════════════════════════════════════════════════════
  static Future<MfaResult> disableMfa() async {
    _log.i(
      '🔐 [DISABLE_MFA] ═══════════════════════════════════════════════════\n'
      '🔐 [DISABLE_MFA] ━━━ START ━━━',
    );

    _log.d('🔐 [DISABLE_MFA] Phase 1 — Acquiring authenticated user');
    final user = await _requireAuthenticatedUser();
    if (user == null) {
      _log.w('🔐 [DISABLE_MFA] Phase 1: ✗ No authenticated user — aborting');
      return MfaResult.failure('Please sign in again before disabling MFA.');
    }
    _log.d('🔐 [DISABLE_MFA] Phase 1: ✓ uid=${user.uid}');

    _log.d('🔐 [DISABLE_MFA] Phase 2 — Calling mfaDisable via direct HTTP');
    try {
      await _callFunctionViaHttp(
        user:         user,
        functionName: 'mfaDisable',
        data:         {},
      );
      _log.i('🔐 [DISABLE_MFA] Phase 2: ✓ MFA disabled');
      return MfaResult.success(message: 'Email MFA has been disabled.');
    } on FirebaseFunctionsException catch (e) {
      _log.w(
        '🔐 [DISABLE_MFA] Phase 2: ✗ Function error\n'
        '🔐 [DISABLE_MFA]            code    : ${e.code}\n'
        '🔐 [DISABLE_MFA]            message : ${e.message}',
      );
      return MfaResult.failure(_mapFunctionError(e));
    } catch (e, st) {
      _log.e(
        '🔐 [DISABLE_MFA] Phase 2: ✗ Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaResult.failure('Could not disable MFA. Please try again.');
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────────
  static String _mapFunctionError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in again before enabling MFA.';
      case 'resource-exhausted':
        return e.message ?? 'Too many requests. Please wait a moment.';
      case 'invalid-argument':
        return e.message ?? 'Incorrect or expired code. Please try again.';
      case 'not-found':
        return 'No pending code found. Please request a new one.';
      case 'deadline-exceeded':
        return 'Your code has expired. Please request a new one.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}