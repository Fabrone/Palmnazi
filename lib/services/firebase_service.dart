import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE SERVICE
//
// Mirrors every API-based auth action into Firebase Auth + Firestore so that:
//   • Users exist in Firebase Auth for MFA, email-link, and identity services.
//   • A Firestore document is created/updated under "Users/{uid}" with:
//       email        : string
//       role         : "Tourist"  (default; elevated roles set by admins)
//       createdAt    : Timestamp
//       lastLoginAt  : Timestamp
//       provider     : "email" | "google" | "emailLink"
//       mfaEnabled   : bool
//
// This file is purely additive — it never replaces the API database.
// All methods are fire-and-forget-safe: if Firebase fails the API auth
// has already succeeded, so the user is not blocked.
//
// MFA (SMS) — Firebase console: Authentication → Sign-in method → Multi-factor
//   auth must be ENABLED.  Phone numbers are enrolled post-login.
//
// Email Link — Firebase console: Authentication → Sign-in method → Email/Password
//   → "Email link (passwordless sign-in)" must be ENABLED.
// ─────────────────────────────────────────────────────────────────────────────

final Logger _fbLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// ── Firestore collection + field constants ────────────────────────────────────
class _FS {
  static const collection  = 'Users';
  static const email       = 'email';
  static const role        = 'role';
  static const defaultRole = 'Tourist';
  static const createdAt   = 'createdAt';
  static const lastLogin   = 'lastLoginAt';
  static const provider    = 'provider';
  static const mfaEnabled  = 'mfaEnabled';
  static const displayName = 'displayName';
  static const photoUrl    = 'photoUrl';
}

// ── Email-link action code settings ──────────────────────────────────────────
// IMPORTANT: add your app's deep-link domain in Firebase console:
//   Authentication → Settings → Authorized domains  AND
//   Authentication → Sign-in method → Email link
// The continueUrl below is the URL Firebase redirects back to after the
// user taps the link in their inbox.  For mobile, configure Dynamic Links or
// App Links / Universal Links in Firebase console and update this URL.
const String _emailLinkContinueUrl = 'https://palmnazi.page.link/emailSignIn';

class FirebaseService {
  static final FirebaseAuth      _auth  = FirebaseAuth.instance;
  static final FirebaseFirestore _store = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // CURRENT USER
  // ══════════════════════════════════════════════════════════════════════════
  static User? get currentUser => _auth.currentUser;

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER — mirror of AuthService.register
  //
  // Creates a Firebase Auth account with email + password, then writes the
  // Firestore user document.  Called right after the API register succeeds.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> registerMirror({
    required String email,
    required String password,
  }) async {
    _fbLog.i('🔥 FirebaseService.registerMirror: ━━━ START ━━━ | $email');
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email:    email.trim(),
        password: password,
      );
      _fbLog.i(
        '🔥 FirebaseService.registerMirror: ✓ Firebase user created '
        '| uid: ${cred.user?.uid}',
      );

      await cred.user?.sendEmailVerification();
      _fbLog.i('🔥 FirebaseService.registerMirror: ✓ Verification email sent');

      await _writeUserDocument(
        uid:      cred.user!.uid,
        email:    email.trim(),
        provider: 'email',
        isNew:    true,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _fbLog.w(
          '⚠️ FirebaseService.registerMirror: Firebase account already exists '
          'for $email — skipping creation',
        );
        return;
      }
      _fbLog.e(
        '❌ FirebaseService.registerMirror: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.registerMirror: Unexpected error',
        error: e, stackTrace: st,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGIN MIRROR — mirror of AuthService.login
  //
  // Signs the user into Firebase Auth with the same credentials so that
  // Firebase session is active (required for MFA enrollment and email-link).
  // Called after the API login succeeds.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<MfaResult> loginMirror({
    required String email,
    required String password,
  }) async {
    _fbLog.i('🔥 FirebaseService.loginMirror: ━━━ START ━━━ | $email');
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email:    email.trim(),
        password: password,
      );
      _fbLog.i(
        '🔥 FirebaseService.loginMirror: ✓ Signed in '
        '| uid: ${cred.user?.uid}',
      );
      await _updateLastLogin(uid: cred.user!.uid);
      return MfaResult.success();
    } on FirebaseAuthMultiFactorException catch (e) {
      _fbLog.i('🔥 FirebaseService.loginMirror: MFA required — returning resolver');
      return MfaResult.mfaRequired(resolver: e.resolver);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _fbLog.w(
          '⚠️ FirebaseService.loginMirror: Firebase user missing — '
          'creating account for existing API user',
        );
        return await _createMissingFirebaseAccount(
          email:    email.trim(),
          password: password,
        );
      }
      _fbLog.e(
        '❌ FirebaseService.loginMirror: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
      return MfaResult.success(); // non-blocking
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.loginMirror: Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaResult.success();
    }
  }

  /// Creates a Firebase Auth account for a user who authenticated via API
  /// before Firebase was introduced to the project.
  static Future<MfaResult> _createMissingFirebaseAccount({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email:    email,
        password: password,
      );
      _fbLog.i(
        '🔥 FirebaseService: Retroactive Firebase account created '
        '| uid: ${cred.user?.uid}',
      );
      await _writeUserDocument(
        uid:      cred.user!.uid,
        email:    email,
        provider: 'email',
        isNew:    true,
      );
      return MfaResult.success();
    } catch (e) {
      _fbLog.e('❌ FirebaseService._createMissingFirebaseAccount: Failed | $e');
      return MfaResult.success();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN MIRROR
  //
  // Signs the user into Firebase using the Google idToken that was already
  // obtained by AuthService.googleSignIn(), so we don't trigger a second
  // account picker.  Called after the API Google auth succeeds.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> googleSignInMirror({required String idToken}) async {
    _fbLog.i('🔥 FirebaseService.googleSignInMirror: ━━━ START ━━━');
    try {
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final cred       = await _auth.signInWithCredential(credential);
      _fbLog.i(
        '🔥 FirebaseService.googleSignInMirror: ✓ Signed in '
        '| uid: ${cred.user?.uid} | isNew: ${cred.additionalUserInfo?.isNewUser}',
      );
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;
      await _writeUserDocument(
        uid:         cred.user!.uid,
        email:       cred.user!.email ?? '',
        provider:    'google',
        isNew:       isNew,
        displayName: cred.user!.displayName,
        photoUrl:    cred.user!.photoURL,
      );
    } on FirebaseAuthException catch (e) {
      _fbLog.e(
        '❌ FirebaseService.googleSignInMirror: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.googleSignInMirror: Unexpected error',
        error: e, stackTrace: st,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EMAIL LINK (PASSWORDLESS) SIGN-IN
  //
  // Step 1 — sendSignInLinkToEmail : sends the magic link to the user's inbox.
  // Step 2 — signInWithEmailLink   : called from the deep-link handler with
  //                                  the full link URL Firebase returns.
  // ══════════════════════════════════════════════════════════════════════════

  /// Step 1: Send the sign-in link to the user's email address.
  static Future<EmailLinkResult> sendSignInLink({
    required String email,
  }) async {
    _fbLog.i('🔥 FirebaseService.sendSignInLink: Sending to $email');
    try {
      final settings = ActionCodeSettings(
        url:                   _emailLinkContinueUrl,
        handleCodeInApp:       true,
        androidPackageName:    'com.palmnazi.app',
        androidInstallApp:     true,
        androidMinimumVersion: '21',
        iOSBundleId:           'com.palmnazi.app',
      );
      await _auth.sendSignInLinkToEmail(
        email:              email.trim(),
        actionCodeSettings: settings,
      );
      _fbLog.i('🔥 FirebaseService.sendSignInLink: ✓ Link sent to $email');
      return EmailLinkResult.sent();
    } on FirebaseAuthException catch (e) {
      _fbLog.e(
        '❌ FirebaseService.sendSignInLink: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
      return EmailLinkResult.failure(_friendlyEmailLinkError(e.code));
    } catch (e) {
      _fbLog.e('❌ FirebaseService.sendSignInLink: $e');
      return EmailLinkResult.failure('Could not send sign-in link. Please try again.');
    }
  }

  /// Step 2: Complete sign-in using the deep-link URL and the stored email.
  /// Returns [EmailLinkSignInResult] — if MFA is required, the resolver is
  /// included so the UI can prompt for OTP.
  static Future<EmailLinkSignInResult> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    _fbLog.i('🔥 FirebaseService.signInWithEmailLink: email=$email');
    try {
      if (!_auth.isSignInWithEmailLink(emailLink)) {
        _fbLog.w('⚠️ FirebaseService.signInWithEmailLink: Not a valid sign-in link');
        return EmailLinkSignInResult.failure('Invalid or expired sign-in link.');
      }

      final cred = await _auth.signInWithEmailLink(
        email:     email.trim(),
        emailLink: emailLink,
      );
      _fbLog.i(
        '🔥 FirebaseService.signInWithEmailLink: ✓ Signed in '
        '| uid: ${cred.user?.uid}',
      );

      final isNew = cred.additionalUserInfo?.isNewUser ?? false;
      await _writeUserDocument(
        uid:      cred.user!.uid,
        email:    email.trim(),
        provider: 'emailLink',
        isNew:    isNew,
      );

      // getIdToken() returns String? — fall back to '' so we satisfy the
      // non-nullable String parameter on EmailLinkSignInResult.success().
      final idToken = await cred.user!.getIdToken() ?? '';
      return EmailLinkSignInResult.success(
        firebaseUser: cred.user!,
        idToken:      idToken,
      );
    } on FirebaseAuthMultiFactorException catch (e) {
      _fbLog.i('🔥 FirebaseService.signInWithEmailLink: MFA required');
      return EmailLinkSignInResult.mfaRequired(resolver: e.resolver);
    } on FirebaseAuthException catch (e) {
      _fbLog.e(
        '❌ FirebaseService.signInWithEmailLink: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
      return EmailLinkSignInResult.failure(_friendlyEmailLinkError(e.code));
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.signInWithEmailLink: Unexpected error',
        error: e, stackTrace: st,
      );
      return EmailLinkSignInResult.failure('Sign-in failed. Please request a new link.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SMS MFA — ENROLL
  //
  // Must be called when the user is already signed into Firebase Auth.
  // Flow:
  //   1. startMfaEnrollment()  → Firebase sends an SMS.
  //   2. completeMfaEnrollment() → user enters OTP → done.
  // ══════════════════════════════════════════════════════════════════════════

  /// Step 1: Begin MFA enrollment for the currently signed-in Firebase user.
  static Future<MfaEnrollmentResult> startMfaEnrollment({
    required String           phoneNumber,
    required BuildableMfaSession session,
  }) async {
    _fbLog.i('🔥 FirebaseService.startMfaEnrollment: phone=$phoneNumber');
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return MfaEnrollmentResult.failure('You must be signed in to enable MFA.');
      }

      final mfaSession = await user.multiFactor.getSession();

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber:          phoneNumber,
        multiFactorSession:   mfaSession,
        verificationCompleted: (_) {
          _fbLog.d('🔥 verifyPhoneNumber: auto-resolved (Android only)');
        },
        verificationFailed: (e) {
          _fbLog.e(
            '❌ FirebaseService.startMfaEnrollment: verificationFailed '
            '| code: ${e.code} | ${e.message}',
          );
          session.completeWithError(_friendlyPhoneError(e.code));
        },
        codeSent: (String vid, int? resendToken) {
          _fbLog.i('🔥 startMfaEnrollment: SMS sent');
          session.completeWithVerificationId(vid);
        },
        codeAutoRetrievalTimeout: (vid) {
          _fbLog.d('🔥 startMfaEnrollment: codeAutoRetrievalTimeout');
          session.completeWithVerificationIdIfNotCompleted(vid);
        },
      );

      return await session.result;
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.startMfaEnrollment: Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaEnrollmentResult.failure('Could not initiate MFA. Please try again.');
    }
  }

  /// Step 2: Complete MFA enrollment with the OTP the user received via SMS.
  static Future<MfaEnrollmentResult> completeMfaEnrollment({
    required String verificationId,
    required String otpCode,
    String?         displayName,
  }) async {
    _fbLog.i('🔥 FirebaseService.completeMfaEnrollment');
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return MfaEnrollmentResult.failure('Session expired. Please sign in again.');
      }

      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode:        otpCode.trim(),
      );
      final assertion = PhoneMultiFactorGenerator.getAssertion(phoneCredential);

      await user.multiFactor.enroll(
        assertion,
        displayName: displayName ?? 'Phone',
      );
      _fbLog.i('🔥 FirebaseService.completeMfaEnrollment: ✓ MFA enrolled');

      await _store
          .collection(_FS.collection)
          .doc(user.uid)
          .update({_FS.mfaEnabled: true});

      return MfaEnrollmentResult.success();
    } on FirebaseAuthException catch (e) {
      _fbLog.e(
        '❌ FirebaseService.completeMfaEnrollment: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
      return MfaEnrollmentResult.failure(_friendlyOtpError(e.code));
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.completeMfaEnrollment: Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaEnrollmentResult.failure('Could not complete MFA setup. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SMS MFA — VERIFY (during login when MFA is enrolled)
  //
  // When loginMirror() returns MfaResult.mfaRequired(), the UI must:
  //   1. Call startMfaVerification() to send the SMS.
  //   2. Collect OTP from the user.
  //   3. Call completeMfaVerification() to finish sign-in.
  // ══════════════════════════════════════════════════════════════════════════

  /// Step 1: Trigger the SMS for an MFA-enrolled user who is mid-login.
  static Future<MfaVerificationStartResult> startMfaVerification({
    required MultiFactorResolver  resolver,
    required BuildableMfaSession  session,
  }) async {
    _fbLog.i('🔥 FirebaseService.startMfaVerification');
    try {
      final hint = resolver.hints.firstWhere(
        (h) => h.factorId == 'phone',
        orElse: () => resolver.hints.first,
      ) as PhoneMultiFactorInfo;

      await FirebaseAuth.instance.verifyPhoneNumber(
        multiFactorSession:   resolver.session,
        multiFactorInfo:      hint,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          _fbLog.e(
            '❌ FirebaseService.startMfaVerification: verificationFailed '
            '| code: ${e.code}',
          );
          session.completeWithError(_friendlyPhoneError(e.code));
        },
        codeSent: (String vid, int? _) {
          _fbLog.i('🔥 startMfaVerification: SMS sent');
          session.completeWithVerificationId(vid);
        },
        codeAutoRetrievalTimeout: (vid) {
          session.completeWithVerificationIdIfNotCompleted(vid);
        },
      );

      final result = await session.result;
      if (!result.isSuccess) {
        return MfaVerificationStartResult.failure(result.errorMessage!);
      }

      return MfaVerificationStartResult.success(
        verificationId:    result.verificationId!,
        maskedPhoneNumber: hint.phoneNumber,  // non-nullable String in Firebase SDK
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.startMfaVerification: Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaVerificationStartResult.failure(
        'Could not send verification SMS. Please try again.',
      );
    }
  }

  /// Step 2: Complete MFA verification with the OTP and the resolver.
  static Future<MfaResult> completeMfaVerification({
    required MultiFactorResolver resolver,
    required String              verificationId,
    required String              otpCode,
  }) async {
    _fbLog.i('🔥 FirebaseService.completeMfaVerification');
    try {
      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode:        otpCode.trim(),
      );
      final assertion = PhoneMultiFactorGenerator.getAssertion(phoneCredential);
      final cred      = await resolver.resolveSignIn(assertion);

      _fbLog.i(
        '🔥 FirebaseService.completeMfaVerification: ✓ MFA verified '
        '| uid: ${cred.user?.uid}',
      );
      await _updateLastLogin(uid: cred.user!.uid);
      return MfaResult.success();
    } on FirebaseAuthException catch (e) {
      _fbLog.e(
        '❌ FirebaseService.completeMfaVerification: FirebaseAuthException '
        '| code: ${e.code} | ${e.message}',
      );
      return MfaResult.failure(_friendlyOtpError(e.code));
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.completeMfaVerification: Unexpected error',
        error: e, stackTrace: st,
      );
      return MfaResult.failure('Verification failed. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> signOut() async {
    _fbLog.i('🔥 FirebaseService.signOut');
    try {
      await _auth.signOut();
      _fbLog.i('🔥 FirebaseService.signOut: ✓');
    } catch (e) {
      _fbLog.e('❌ FirebaseService.signOut: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA ENROLLMENT CHECK
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns true if the current Firebase user has at least one MFA factor enrolled.
  static Future<bool> isMfaEnrolled() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final factors = await user.multiFactor.getEnrolledFactors();
    return factors.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIRESTORE HELPERS (private)
  // ══════════════════════════════════════════════════════════════════════════

  /// Creates a new Firestore user document (isNew=true) or updates lastLoginAt.
  /// On first creation the "role" field is set to "Tourist".
  static Future<void> _writeUserDocument({
    required String  uid,
    required String  email,
    required String  provider,
    required bool    isNew,
    String?          displayName,
    String?          photoUrl,
  }) async {
    _fbLog.i('🔥 FirebaseService._writeUserDocument: uid=$uid isNew=$isNew');
    try {
      final docRef = _store.collection(_FS.collection).doc(uid);
      if (isNew) {
        await docRef.set({
          _FS.email:      email,
          _FS.role:       _FS.defaultRole, // always "Tourist" on creation
          _FS.createdAt:  FieldValue.serverTimestamp(),
          _FS.lastLogin:  FieldValue.serverTimestamp(),
          _FS.provider:   provider,
          _FS.mfaEnabled: false,
          if (displayName != null) _FS.displayName: displayName,
          if (photoUrl    != null) _FS.photoUrl:    photoUrl,
        }, SetOptions(merge: true)); // merge:true won't overwrite role if doc exists
        _fbLog.i('🔥 FirebaseService._writeUserDocument: ✓ Document created for $uid');
      } else {
        await _updateLastLogin(uid: uid);
      }
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService._writeUserDocument: Firestore write failed',
        error: e, stackTrace: st,
      );
    }
  }

  static Future<void> _updateLastLogin({required String uid}) async {
    try {
      await _store.collection(_FS.collection).doc(uid).set(
        {_FS.lastLogin: FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      _fbLog.w('⚠️ FirebaseService._updateLastLogin: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROLE READER (public — used by the rest of the app to gate features)
  // ══════════════════════════════════════════════════════════════════════════

  /// Reads the "role" field from Firestore for the current user.
  /// Returns "Tourist" if not found or on error.
  static Future<String> readCurrentUserRole() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return _FS.defaultRole;
      final doc = await _store.collection(_FS.collection).doc(uid).get();
      return (doc.data()?[_FS.role] as String?) ?? _FS.defaultRole;
    } catch (e) {
      _fbLog.e('❌ FirebaseService.readCurrentUserRole: $e');
      return _FS.defaultRole;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ERROR MESSAGE HELPERS (private)
  // ══════════════════════════════════════════════════════════════════════════
  static String _friendlyEmailLinkError(String code) {
    switch (code) {
      case 'invalid-email':       return 'Please enter a valid email address.';
      case 'invalid-action-code': return 'The link is invalid or has already been used.';
      case 'expired-action-code': return 'The sign-in link has expired. Please request a new one.';
      case 'user-disabled':       return 'This account has been disabled. Please contact support.';
      default:                    return 'Sign-in failed ($code). Please try again.';
    }
  }

  static String _friendlyPhoneError(String code) {
    switch (code) {
      case 'invalid-phone-number': return 'Please enter a valid phone number with country code (e.g. +254712345678).';
      case 'too-many-requests':    return 'Too many SMS requests. Please wait a few minutes.';
      case 'quota-exceeded':       return 'SMS quota exceeded. Please try again later.';
      case 'captcha-check-failed': return 'Security check failed. Please try again.';
      default:                     return 'Could not send SMS ($code). Please try again.';
    }
  }

  static String _friendlyOtpError(String code) {
    switch (code) {
      case 'invalid-verification-code': return 'Incorrect code. Please check and try again.';
      case 'session-expired':           return 'The code has expired. Please request a new one.';
      case 'code-expired':              return 'The code has expired. Please request a new one.';
      default:                          return 'Verification failed ($code). Please try again.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULT MODELS
// ─────────────────────────────────────────────────────────────────────────────

// ── MfaResult — returned by loginMirror / completeMfaVerification ─────────────
class MfaResult {
  final bool                isSuccess;
  final bool                requiresMfa;
  final MultiFactorResolver? resolver;
  final String?             errorMessage;

  MfaResult._({
    required this.isSuccess,
    required this.requiresMfa,
    this.resolver,
    this.errorMessage,
  });

  factory MfaResult.success() =>
      MfaResult._(isSuccess: true,  requiresMfa: false);

  factory MfaResult.mfaRequired({required MultiFactorResolver resolver}) =>
      MfaResult._(isSuccess: false, requiresMfa: true, resolver: resolver);

  factory MfaResult.failure(String message) =>
      MfaResult._(isSuccess: false, requiresMfa: false, errorMessage: message);
}

// ── EmailLinkResult — returned by sendSignInLink ──────────────────────────────
class EmailLinkResult {
  final bool    isSent;
  final String? errorMessage;

  EmailLinkResult._({required this.isSent, this.errorMessage});

  factory EmailLinkResult.sent()                  => EmailLinkResult._(isSent: true);
  factory EmailLinkResult.failure(String message) => EmailLinkResult._(isSent: false, errorMessage: message);
}

// ── EmailLinkSignInResult — returned by signInWithEmailLink ───────────────────
class EmailLinkSignInResult {
  final bool                isSuccess;
  final bool                requiresMfa;
  final User?               firebaseUser;
  final String              idToken;
  final MultiFactorResolver? resolver;
  final String?             errorMessage;

  EmailLinkSignInResult._({
    required this.isSuccess,
    required this.requiresMfa,
    required this.idToken,
    this.firebaseUser,
    this.resolver,
    this.errorMessage,
  });

  factory EmailLinkSignInResult.success({
    required User   firebaseUser,
    required String idToken,
  }) => EmailLinkSignInResult._(
    isSuccess:    true,
    requiresMfa:  false,
    idToken:      idToken,
    firebaseUser: firebaseUser,
  );

  factory EmailLinkSignInResult.mfaRequired({
    required MultiFactorResolver resolver,
  }) => EmailLinkSignInResult._(
    isSuccess:   false,
    requiresMfa: true,
    idToken:     '',
    resolver:    resolver,
  );

  factory EmailLinkSignInResult.failure(String message) =>
      EmailLinkSignInResult._(
        isSuccess:    false,
        requiresMfa:  false,
        idToken:      '',
        errorMessage: message,
      );
}

// ── MfaEnrollmentResult — returned by startMfaEnrollment/completeMfaEnrollment
class MfaEnrollmentResult {
  final bool    isSuccess;
  final String? errorMessage;
  final String? verificationId;

  MfaEnrollmentResult._({
    required this.isSuccess,
    this.errorMessage,
    this.verificationId,
  });

  factory MfaEnrollmentResult.success() =>
      MfaEnrollmentResult._(isSuccess: true);

  factory MfaEnrollmentResult.verificationIdReady(String vid) =>
      MfaEnrollmentResult._(isSuccess: true, verificationId: vid);

  factory MfaEnrollmentResult.failure(String message) =>
      MfaEnrollmentResult._(isSuccess: false, errorMessage: message);
}

// ── MfaVerificationStartResult — returned by startMfaVerification ────────────
class MfaVerificationStartResult {
  final bool    isSuccess;
  final String? verificationId;
  final String  maskedPhoneNumber;
  final String? errorMessage;

  MfaVerificationStartResult._({
    required this.isSuccess,
    required this.maskedPhoneNumber,
    this.verificationId,
    this.errorMessage,
  });

  factory MfaVerificationStartResult.success({
    required String verificationId,
    required String maskedPhoneNumber,
  }) => MfaVerificationStartResult._(
    isSuccess:         true,
    verificationId:    verificationId,
    maskedPhoneNumber: maskedPhoneNumber,
  );

  factory MfaVerificationStartResult.failure(String message) =>
      MfaVerificationStartResult._(
        isSuccess:         false,
        maskedPhoneNumber: '',
        errorMessage:      message,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildableMfaSession
//
// A lightweight bridge that lets the async verifyPhoneNumber callbacks
// communicate back to the calling Future<MfaEnrollmentResult>.
//
// Usage:
//   final session = BuildableMfaSession();
//   await FirebaseAuth.instance.verifyPhoneNumber(
//     codeSent: (vid, _) => session.completeWithVerificationId(vid),
//     verificationFailed: (e) => session.completeWithError(e.message ?? '…'),
//     …
//   );
//   final result = await session.result;  // waits for codeSent to fire
// ─────────────────────────────────────────────────────────────────────────────
class BuildableMfaSession {
  final _completer = Completer<MfaEnrollmentResult>();

  Future<MfaEnrollmentResult> get result => _completer.future;

  void completeWithVerificationId(String vid) {
    if (!_completer.isCompleted) {
      _completer.complete(MfaEnrollmentResult.verificationIdReady(vid));
    }
  }

  void completeWithVerificationIdIfNotCompleted(String vid) {
    if (!_completer.isCompleted) {
      _completer.complete(MfaEnrollmentResult.verificationIdReady(vid));
    }
  }

  void completeWithError(String message) {
    if (!_completer.isCompleted) {
      _completer.complete(MfaEnrollmentResult.failure(message));
    }
  }
}