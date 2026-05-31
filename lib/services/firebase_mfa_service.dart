import 'package:firebase_auth/firebase_auth.dart';
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
// FIREBASE MFA SERVICE  —  Firebase Native Phone (SMS) MFA
//
// REPLACES the previous custom email-OTP Cloud Functions approach.
// Firebase handles all SMS delivery and verification natively.
// No Cloud Functions, no nodemailer, no Firestore mfaEnabled flag needed.
//
// ╔════════════════════════════════════════════════════════════╗
// ║  PREREQUISITE  —  must be true before enrollment works    ║
// ║  User's email must be verified (emailVerified = true).    ║
// ║  Firebase enforces this; enrollment will error otherwise. ║
// ╚════════════════════════════════════════════════════════════╝
//
// ── ENROLLMENT FLOW ─────────────────────────────────────────────────────────
//   1. getMultiFactorSession()
//        └─ returns MultiFactorSession (proves first-factor is complete)
//   2. startEnrollment(phone, session, onCodeSent, onFailed)
//        └─ Firebase sends SMS; onCodeSent(verificationId, resendToken) fires
//   3. completeEnrollment(verificationId, smsCode)
//        └─ user.multiFactor.enroll(PhoneMultiFactorGenerator.getAssertion(…))
//
// ── SIGN-IN CHALLENGE FLOW ───────────────────────────────────────────────────
//   FirebaseAuthMultiFactorException is caught in FirebaseService.loginMirror()
//   and the resolver is threaded back to the UI via LoginResult.mfaResolver.
//
//   1. startSignInChallenge(resolver, onCodeSent, onFailed)
//        └─ Firebase sends SMS to enrolled number; onCodeSent fires
//   2. resolveSignIn(resolver, verificationId, smsCode)
//        └─ resolver.resolveSignIn(PhoneMultiFactorGenerator.getAssertion(…))
//
// ── DISABLE ──────────────────────────────────────────────────────────────────
//   unenrollFactor(factor)
//        └─ user.multiFactor.unenroll(multiFactorInfo: factor)
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseMfaService {
  FirebaseMfaService._();

  static final Logger _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // READ MFA STATE — from Firebase Auth directly (no Firestore needed)
  // ══════════════════════════════════════════════════════════════════════════

  /// True if the signed-in user has at least one phone factor enrolled.
  /// Async because firebase_auth 5.x+ exposes this via getEnrolledFactors().
  static Future<bool> isPhoneMfaEnrolled() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final factors = await user.multiFactor.getEnrolledFactors();
    return factors.any((f) => f is PhoneMultiFactorInfo);
  }

  /// All enrolled factors for the current user (empty list if none).
  /// Named fetchEnrolledFactors to avoid shadowing the Firebase SDK method.
  static Future<List<MultiFactorInfo>> fetchEnrolledFactors() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    return user.multiFactor.getEnrolledFactors();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENROLLMENT — Step 1: get session
  // ══════════════════════════════════════════════════════════════════════════
  /// Call this once before [startEnrollment] to prove the user recently
  /// authenticated with their first factor.
  static Future<MultiFactorSession?> getMultiFactorSession() async {
    _log.d('🔐 [MFA_ENROLL] getMultiFactorSession()');
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _log.w('🔐 [MFA_ENROLL] getMultiFactorSession: no current user');
        return null;
      }
      final session = await user.multiFactor.getSession();
      _log.d('🔐 [MFA_ENROLL] getMultiFactorSession: ✓');
      return session;
    } on FirebaseAuthException catch (e) {
      _log.e('🔐 [MFA_ENROLL] getMultiFactorSession: FirebaseAuthException ${e.code}');
      return null;
    } catch (e, st) {
      _log.e('🔐 [MFA_ENROLL] getMultiFactorSession: unexpected error',
          error: e, stackTrace: st);
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENROLLMENT — Step 2: send SMS to the phone number
  // ══════════════════════════════════════════════════════════════════════════
  /// Triggers Firebase to deliver an SMS verification code.
  /// [onCodeSent] receives the [verificationId] required by [completeEnrollment].
  /// [onFailed] receives a [FirebaseAuthException] if delivery fails.
  ///
  /// Phone number must include the country code (e.g. +254712345678).
  static Future<void> startEnrollment({
    required String             phoneNumber,
    required MultiFactorSession session,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException error) onFailed,
  }) async {
    _log.i('🔐 [MFA_ENROLL] startEnrollment: phoneNumber=$phoneNumber');
    await _auth.verifyPhoneNumber(
      multiFactorSession:       session,
      phoneNumber:              phoneNumber,
      verificationCompleted:    (_) {},        // auto-retrieval — not used on web
      verificationFailed:       onFailed,
      codeSent:                 onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENROLLMENT — Step 3: verify code and enroll the factor
  // ══════════════════════════════════════════════════════════════════════════
  /// [verificationId] comes from the [onCodeSent] callback in [startEnrollment].
  /// [smsCode] is the 6-digit code the user typed.
  static Future<MfaResult> completeEnrollment({
    required String verificationId,
    required String smsCode,
    String? displayName,        // optional label shown in Firebase console
  }) async {
    _log.i('🔐 [MFA_ENROLL] completeEnrollment()');
    try {
      final user = _auth.currentUser;
      if (user == null) return MfaResult.failure('Not signed in.');

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode:        smsCode.trim(),
      );
      await user.multiFactor.enroll(
        PhoneMultiFactorGenerator.getAssertion(credential),
        displayName: displayName,
      );
      _log.i('🔐 [MFA_ENROLL] completeEnrollment: ✓ enrolled');
      return MfaResult.success(
        message: 'Phone two-factor authentication has been enabled.',
      );
    } on FirebaseAuthException catch (e) {
      _log.w('🔐 [MFA_ENROLL] completeEnrollment: ${e.code}');
      return MfaResult.failure(_mapAuthError(e));
    } catch (e, st) {
      _log.e('🔐 [MFA_ENROLL] completeEnrollment: unexpected error',
          error: e, stackTrace: st);
      return MfaResult.failure('Enrollment failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN-IN CHALLENGE — Step 1: send SMS to the enrolled number
  // ══════════════════════════════════════════════════════════════════════════
  /// Called after FirebaseAuthMultiFactorException is caught during loginMirror.
  /// The [resolver] comes from that exception (via LoginResult.mfaResolver).
  /// Firebase sends SMS to the number in [resolver.hints[hintIndex]].
  static Future<MfaResult> startSignInChallenge({
    required MultiFactorResolver resolver,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException error) onFailed,
    int hintIndex = 0,
  }) async {
    _log.i(
      '🔐 [MFA_SIGN_IN] startSignInChallenge: '
      'hints=${resolver.hints.length} hintIndex=$hintIndex',
    );

    if (resolver.hints.isEmpty) {
      return MfaResult.failure('No MFA factors enrolled on this account.');
    }
    if (hintIndex >= resolver.hints.length) {
      return MfaResult.failure('Invalid hint index.');
    }

    final hint = resolver.hints[hintIndex];
    if (hint is! PhoneMultiFactorInfo) {
      _log.w('🔐 [MFA_SIGN_IN] startSignInChallenge: '
          'hint type is ${hint.factorId} (expected phone)');
      return MfaResult.failure('Unsupported MFA factor type: ${hint.factorId}');
    }

    try {
      _log.d(
        '🔐 [MFA_SIGN_IN] startSignInChallenge: '
        'sending SMS to ${hint.phoneNumber}',
      );
      await _auth.verifyPhoneNumber(
        multiFactorSession:       resolver.session,
        multiFactorInfo:          hint,
        verificationCompleted:    (_) {},
        verificationFailed:       onFailed,
        codeSent:                 onCodeSent,
        codeAutoRetrievalTimeout: (_) {},
      );
      return MfaResult.success(
        message:
            'Verification code sent to ${_maskedPhone(hint.phoneNumber)}.',
      );
    } catch (e, st) {
      _log.e('🔐 [MFA_SIGN_IN] startSignInChallenge: error',
          error: e, stackTrace: st);
      return MfaResult.failure('Could not send verification code. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN-IN CHALLENGE — Step 2: verify code and complete sign-in
  // ══════════════════════════════════════════════════════════════════════════
  static Future<MfaResult> resolveSignIn({
    required MultiFactorResolver resolver,
    required String              verificationId,
    required String              smsCode,
  }) async {
    _log.i('🔐 [MFA_SIGN_IN] resolveSignIn()');
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode:        smsCode.trim(),
      );
      await resolver.resolveSignIn(
        PhoneMultiFactorGenerator.getAssertion(credential),
      );
      _log.i('🔐 [MFA_SIGN_IN] resolveSignIn: ✓ Firebase sign-in complete');
      return MfaResult.success(message: 'Signed in successfully.');
    } on FirebaseAuthException catch (e) {
      _log.w('🔐 [MFA_SIGN_IN] resolveSignIn: ${e.code}');
      return MfaResult.failure(_mapAuthError(e));
    } catch (e, st) {
      _log.e('🔐 [MFA_SIGN_IN] resolveSignIn: unexpected error',
          error: e, stackTrace: st);
      return MfaResult.failure('Verification failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISABLE — unenroll a specific factor
  // ══════════════════════════════════════════════════════════════════════════
  /// Pass a factor from [fetchEnrolledFactors()].
  static Future<MfaResult> unenrollFactor(MultiFactorInfo factor) async {
    _log.i('🔐 [MFA_DISABLE] unenrollFactor: factorId=${factor.factorId}');
    try {
      final user = _auth.currentUser;
      if (user == null) return MfaResult.failure('Not signed in.');
      await user.multiFactor.unenroll(multiFactorInfo: factor);
      _log.i('🔐 [MFA_DISABLE] unenrollFactor: ✓ unenrolled');
      return MfaResult.success(
        message: 'Phone two-factor authentication has been disabled.',
      );
    } on FirebaseAuthException catch (e) {
      _log.w('🔐 [MFA_DISABLE] unenrollFactor: ${e.code}');
      return MfaResult.failure(_mapAuthError(e));
    } catch (e, st) {
      _log.e('🔐 [MFA_DISABLE] unenrollFactor: unexpected error',
          error: e, stackTrace: st);
      return MfaResult.failure('Could not disable MFA. Please try again.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Mask the middle digits: +254712345678 → +254 *** 5678
  static String _maskedPhone(String? phone) {
    if (phone == null || phone.length < 6) return 'your phone';
    return '${phone.substring(0, phone.length - 4)}****';
  }

  // ── Public error mapper ───────────────────────────────────────────────────
  // auth_screen.dart calls this directly in onFailed callbacks, so it must
  // be public. It delegates to _mapAuthError internally.
  static String mapAuthErrorPublic(FirebaseAuthException e) =>
      _mapAuthError(e);

  static String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect code. Please check and try again.';
      case 'session-expired':
        return 'The verification session expired. Please request a new code.';
      case 'invalid-phone-number':
        return 'Invalid phone number. Include your country code (e.g. +254 712 345 678).';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'requires-recent-login':
        return 'For security, please sign out and sign in again before changing MFA settings.';
      case 'second-factor-already-in-use':
        return 'This phone number is already registered as a second factor.';
      case 'unsupported-first-factor':
        return 'Email verification is required before enabling two-factor authentication.';
      case 'unverified-email':
        return 'Please verify your email address before enabling MFA.';
      case 'maximum-second-factor-count-exceeded':
        return 'Maximum number of second factors reached.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}