import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE SERVICE
//
// Mirrors every API-based auth action into Firebase Auth + Firestore so that:
//   • Users exist in Firebase Auth for identity services.
//   • A Firestore document is created/updated under "Users/{uid}" with:
//       email        : string
//       role         : "Tourist"  (default; elevated roles set by admins)
//       createdAt    : Timestamp
//       lastLoginAt  : Timestamp
//       provider     : "email" | "google"
//       mfaEnabled   : bool
//
// This file is purely additive — it never replaces the API database.
// All methods are fire-and-forget-safe: if Firebase fails the API auth
// has already succeeded, so the user is not blocked.
//
// NOTE: SMS MFA, email-link sign-in, and BuildableMfaSession have been
// removed from this layer.  MFA is now handled natively in the app via
// email OTP through the API (see ApiEndpoints.mfaSendOtp / mfaVerifyOtp).
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

class FirebaseService {
  static final FirebaseAuth      _auth  = FirebaseAuth.instance;
  static final FirebaseFirestore _store = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // CURRENT USER
  // ══════════════════════════════════════════════════════════════════════════
  static User? get currentUser => _auth.currentUser;

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER MIRROR — mirror of AuthService.register
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
  // Signs the user into Firebase Auth with the same credentials so that the
  // Firebase session is active (required for Firestore identity services).
  // Called after the API login succeeds.
  //
  // Returns true on success (or non-blocking failure), false only on a
  // hard credential error that the caller may want to log.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> loginMirror({
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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _fbLog.w(
          '⚠️ FirebaseService.loginMirror: Firebase user missing — '
          'creating account for existing API user',
        );
        await _createMissingFirebaseAccount(
          email:    email.trim(),
          password: password,
        );
        return;
      }
      // All other FirebaseAuth errors are non-blocking — API auth already
      // succeeded so the user is logged in; Firebase is just the mirror.
      _fbLog.e(
        '❌ FirebaseService.loginMirror: FirebaseAuthException (non-blocking) '
        '| code: ${e.code} | ${e.message}',
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.loginMirror: Unexpected error (non-blocking)',
        error: e, stackTrace: st,
      );
    }
  }

  /// Creates a Firebase Auth account for a user who authenticated via API
  /// before Firebase was introduced to the project.
  static Future<void> _createMissingFirebaseAccount({
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
    } catch (e) {
      _fbLog.e('❌ FirebaseService._createMissingFirebaseAccount: Failed (non-blocking) | $e');
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
        '❌ FirebaseService.googleSignInMirror: FirebaseAuthException (non-blocking) '
        '| code: ${e.code} | ${e.message}',
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseService.googleSignInMirror: Unexpected error (non-blocking)',
        error: e, stackTrace: st,
      );
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
        '❌ FirebaseService._writeUserDocument: Firestore write failed (non-blocking)',
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
}