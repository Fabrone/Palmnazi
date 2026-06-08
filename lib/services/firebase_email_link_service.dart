import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html show window; // web-only: cross-tab verification signal

// ─────────────────────────────────────────────────────────────────────────────
// RESULT TYPE
// ─────────────────────────────────────────────────────────────────────────────
class EmailLinkResult {
  final bool isSuccess;
  final String message;

  final String? idToken;

  const EmailLinkResult._({
    required this.isSuccess,
    required this.message,
    this.idToken,
  });

  factory EmailLinkResult.success({
    String message = 'Success',
    String? idToken,
  }) =>
      EmailLinkResult._(isSuccess: true, message: message, idToken: idToken);

  factory EmailLinkResult.failure(String message) =>
      EmailLinkResult._(isSuccess: false, message: message);

  @override
  String toString() =>
      'EmailLinkResult(isSuccess: $isSuccess, message: "$message")';
}

// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE ENUM — embedded in the link URL so the deep-link handler knows
// which completion path to use.
// ─────────────────────────────────────────────────────────────────────────────
enum EmailLinkPurpose {
  /// Full passwordless sign-in (no password entered).
  signIn,

  /// Email address verification sent immediately after registration.
  verify,

  /// Second-factor confirmation sent after a successful password sign-in.
  secondFactor,
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseEmailLinkService {
  FirebaseEmailLinkService._();

  // ── DOMAIN CONFIGURATION ──────────────────────────────────────────────────

  static const String _fallbackDomain = 'palmnazi-5259e.web.app';

  static String _buildContinueUrl(EmailLinkPurpose purpose) {
    if (kIsWeb) {
      try {
        // origin example: "http://localhost:8080"  or
        //                  "https://palmnazi-5259e.web.app"
        final origin = html.window.location.origin;
        return '$origin/?purpose=${purpose.name}';
      } catch (_) {}
    }
    return 'https://$_fallbackDomain/?purpose=${purpose.name}';
  }

  // ── APP IDENTIFIERS ───────────────────────────────────────────────────────
  // Replace these before releasing to production.
  static const String _iosBundleId    = 'com.palmnazi.app'; // ← replace
  static const String _androidPackage = 'com.palmnazi.app'; // ← replace
  static const String _androidMinVer  = '21';

  // SharedPreferences keys — scoped to avoid collisions with other packages.
  static const String _kPendingEmail   = 'palmnazi_el_email';
  static const String _kPendingPurpose = 'palmnazi_el_purpose';

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final Logger _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // SEND SIGN-IN / VERIFICATION LINK
  // ══════════════════════════════════════════════════════════════════════════

  /// In all cases, clicking the link marks the address as `emailVerified=true`.
  static Future<EmailLinkResult> sendSignInLink({
    required String email,
    EmailLinkPurpose purpose = EmailLinkPurpose.signIn,
  }) async {
    _log.i('📧 [EL] sendSignInLink: email=$email purpose=${purpose.name}');
    try {
      await _auth.sendSignInLinkToEmail(
        email: email.trim(),
        actionCodeSettings: _acs(purpose),
      );
      await _storePending(email: email.trim(), purpose: purpose);
      _log.i('📧 [EL] sendSignInLink: ✓ link sent');
      return EmailLinkResult.success(message: _sentMsg(purpose, email.trim()));
    } on FirebaseAuthException catch (e) {
      _log.e('📧 [EL] sendSignInLink error: ${e.code}');
      return EmailLinkResult.failure(_mapError(e));
    } catch (e, st) {
      _log.e('📧 [EL] sendSignInLink unexpected', error: e, stackTrace: st);
      return EmailLinkResult.failure(
        'Could not send sign-in link. Please try again.',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHECK INCOMING LINK
  // ══════════════════════════════════════════════════════════════════════════
  /// Returns true when [link] is a Firebase email sign-in link.
  /// Call this in your deep-link handler BEFORE [handleIncomingLink].
  static bool isEmailLink(String link) => _auth.isSignInWithEmailLink(link);

  // ══════════════════════════════════════════════════════════════════════════
  // UNIVERSAL INCOMING-LINK HANDLER  (called from main.dart)
  // ══════════════════════════════════════════════════════════════════════════

  static Future<EmailLinkResult?> handleIncomingLink(String link) async {
    if (!isEmailLink(link)) return null;

    final email   = await getPendingEmail();
    final purpose = await getPendingPurpose();
    _log.i('📧 [EL] handleIncomingLink: purpose=${purpose?.name} email=$email');

    if (email == null) {
      return EmailLinkResult.failure(
        'Enter the email address you used to request this link.',
      );
    }

    final current = _auth.currentUser;
    if (current != null &&
        current.email?.toLowerCase() == email.toLowerCase()) {
      // Already signed in → link credential to mark email verified.
      return _linkCredential(email: email, link: link);
    }

    // Not signed in (or different user) → fresh passwordless sign-in.
    return completeSignIn(email: email, emailLink: link);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMPLETE PASSWORDLESS SIGN-IN
  // ══════════════════════════════════════════════════════════════════════════
  static Future<EmailLinkResult> completeSignIn({
    required String email,
    required String emailLink,
  }) async {
    _log.i('📧 [EL] completeSignIn: email=$email');
    try {
      final cred    = await _auth.signInWithEmailLink(
        email:     email.trim(),
        emailLink: emailLink,
      );
      final idToken = await cred.user?.getIdToken();
      await clearPendingData();
      _notifyVerificationComplete(email.trim()); // ← signals other tabs
      _log.i('📧 [EL] completeSignIn: ✓ uid=${cred.user?.uid}');
      return EmailLinkResult.success(
        message: 'Email verified and signed in successfully!',
        idToken: idToken,
      );
    } on FirebaseAuthException catch (e) {
      _log.e('📧 [EL] completeSignIn error: ${e.code}');
      return EmailLinkResult.failure(_mapError(e));
    } catch (e, st) {
      _log.e('📧 [EL] completeSignIn unexpected', error: e, stackTrace: st);
      return EmailLinkResult.failure('Sign-in failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LINK CREDENTIAL TO CURRENT USER  (email verification for signed-in user)
  // ══════════════════════════════════════════════════════════════════════════
  static Future<EmailLinkResult> _linkCredential({
    required String email,
    required String link,
  }) async {
    _log.i('📧 [EL] _linkCredential: email=$email');
    try {
      final user = _auth.currentUser;
      if (user == null) return EmailLinkResult.failure('Not signed in.');
      final credential = EmailAuthProvider.credentialWithLink(
        email:     email.trim(),
        emailLink: link,
      );
      await user.linkWithCredential(credential);
      await clearPendingData();
      _notifyVerificationComplete(email.trim()); // ← signals other tabs
      _log.i('📧 [EL] _linkCredential: ✓ email verified');
      return EmailLinkResult.success(message: 'Email verified successfully!');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        await clearPendingData();
        _notifyVerificationComplete(email.trim()); // already verified — still signal
        return EmailLinkResult.success(message: 'Email already verified.');
      }
      _log.e('📧 [EL] _linkCredential error: ${e.code}');
      return EmailLinkResult.failure(_mapError(e));
    } catch (e, st) {
      _log.e('📧 [EL] _linkCredential unexpected', error: e, stackTrace: st);
      return EmailLinkResult.failure('Verification failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED PREFERENCES — persist pending email between app restarts
  // ══════════════════════════════════════════════════════════════════════════
  static Future<String?> getPendingEmail() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_kPendingEmail);
    } catch (_) {
      return null;
    }
  }

  static Future<EmailLinkPurpose?> getPendingPurpose() async {
    try {
      final p    = await SharedPreferences.getInstance();
      final name = p.getString(_kPendingPurpose);
      if (name == null) return null;
      return EmailLinkPurpose.values.firstWhere(
        (e) => e.name == name,
        orElse: () => EmailLinkPurpose.signIn,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPendingData() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kPendingEmail);
      await p.remove(_kPendingPurpose);
    } catch (_) {}
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<void> _storePending({
    required String email,
    required EmailLinkPurpose purpose,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPendingEmail,   email);
      await p.setString(_kPendingPurpose, purpose.name);
    } catch (_) {}
  }

  static ActionCodeSettings _acs(EmailLinkPurpose purpose) =>
      ActionCodeSettings(
        url: _buildContinueUrl(purpose),   // ← dynamic origin (see above)
        handleCodeInApp:       true,
        iOSBundleId:           _iosBundleId,
        androidPackageName:    _androidPackage,
        androidInstallApp:     true,
        androidMinimumVersion: _androidMinVer,
      );

  // ══════════════════════════════════════════════════════════════════════════
  // CROSS-TAB VERIFICATION SIGNAL
  // ══════════════════════════════════════════════════════════════════════════
  // localStorage keys consumed by AccountScreen's onStorage listener.
  static const String kVerifiedEmail = 'pn_verified_email';
  static const String kVerifiedAt    = 'pn_verified_at';

  static void _notifyVerificationComplete(String email) {
    if (!kIsWeb) return;
    try {
      html.window.localStorage[kVerifiedAt]    =
          DateTime.now().millisecondsSinceEpoch.toString();
      html.window.localStorage[kVerifiedEmail] = email.toLowerCase();
      _log.d('📧 [EL] _notifyVerificationComplete: localStorage updated for $email');
    } catch (e) {
      _log.w('📧 [EL] _notifyVerificationComplete: localStorage unavailable — $e');
    }
  }

  static String _sentMsg(EmailLinkPurpose purpose, String email) {
    switch (purpose) {
      case EmailLinkPurpose.verify:
        return 'Verification link sent to $email. '
            'Open the email and tap the link to verify your account.';
      case EmailLinkPurpose.secondFactor:
        return 'Confirmation link sent to $email. '
            'Open the email and tap the link to confirm your sign-in.';
      case EmailLinkPurpose.signIn:
        return 'Sign-in link sent to $email. '
            'Open the email and tap the link — no password needed!';
    }
  }

  static String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address.';
      case 'invalid-action-code':
        return 'This link is invalid or has already been used. '
            'Please request a new one.';
      case 'expired-action-code':
        return 'This link has expired. Please request a new sign-in link.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found for this email. Please register first.';
      case 'provider-already-linked':
        return 'Email is already verified on this account.';
      case 'invalid-continue-uri':
      case 'unauthorized-continue-uri':
      case 'missing-continue-uri':
        return 'App configuration error (continue URI). Please contact support.';
      case 'invalid-hosting-link-domain':
        return 'App configuration error (hosting domain). Please contact support.';
      case 'missing-android-pkg-name':
      case 'missing-ios-bundle-id':
        return 'App configuration error (bundle ID). Please contact support.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}