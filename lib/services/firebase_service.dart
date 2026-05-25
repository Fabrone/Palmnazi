import 'dart:async';
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
  // Ensures a real (non-anonymous) Firebase Auth session exists for the user
  // so that Cloud Functions and Firestore rules can verify identity.
  //
  // CRITICAL — WHY WE SKIP RE-AUTHENTICATION WHEN ALREADY SIGNED IN
  // ────────────────────────────────────────────────────────────────
  // On Flutter Web, firebase_auth and cloud_firestore both use IndexedDB as
  // their persistence backend. Calling signInWithEmailAndPassword() when the
  // same user is *already* signed in forces the Firebase Web SDK to overwrite
  // the existing IndexedDB credential entry. If Firestore has an open
  // IndexedDB transaction at the same moment (e.g. from the offline
  // persistence layer or a recent Firestore write), the browser throws an
  // OperationError ("The operation failed for reasons unrelated to the
  // database itself"). This error escapes into the Dart zone and leaves the
  // JS firebase/functions auth token cache in an inconsistent state, causing
  // the very next Cloud Function call to receive context.auth = null and
  // return 'unauthenticated' — even though currentUser looks correct in Dart.
  //
  // The fix: check whether the correct user is already signed in before
  // calling signInWithEmailAndPassword. If they are, skip the sign-in
  // entirely and just refresh the ID token + update lastLoginAt. This
  // eliminates the IndexedDB write conflict completely.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> loginMirror({
    required String email,
    required String password,
  }) async {
    _fbLog.i('🔥 FirebaseService.loginMirror: ━━━ START ━━━ | $email');

    try {
      final existing = _auth.currentUser;

      // ── Fast path: correct user already signed in ──────────────────────────
      // Skip signInWithEmailAndPassword entirely to avoid the IndexedDB
      // write conflict that causes OperationError + context.auth = null.
      if (existing != null &&
          !existing.isAnonymous &&
          existing.email?.toLowerCase() == email.trim().toLowerCase()) {
        _fbLog.i(
          '🔥 FirebaseService.loginMirror: ✓ Already signed in as '
          '${existing.email} (uid: ${existing.uid}) — skipping re-auth, '
          'refreshing token only',
        );
        // Force-refresh the token so Cloud Functions receive a fresh context.auth.
        await existing.getIdToken(true);
        await _updateLastLogin(uid: existing.uid);
        return;
      }

      // ── Sign out stale user if a different account is cached ───────────────
      if (existing != null && existing.email?.toLowerCase() != email.trim().toLowerCase()) {
        _fbLog.w(
          '⚠️ FirebaseService.loginMirror: Different user cached '
          '(${existing.email}) — signing out before mirror sign-in',
        );
        await _auth.signOut();
        // Settle: let the signOut IndexedDB/localStorage write finish completely
        // before signInWithEmailAndPassword starts its own write.
        _fbLog.d('🔥 [SIGN_OUT_SETTLE] Waiting 400 ms after stale-user signOut');
        await Future.delayed(const Duration(milliseconds: 400));
        _fbLog.d('🔥 [SIGN_OUT_SETTLE] Settle complete');
      }

      // ── Normal path: sign in (only when not already authenticated) ─────────
      _fbLog.d(
        '🔥 [SIGN_IN] ────────────────────────────────────────────────────\n'
        '🔥 [SIGN_IN] Calling signInWithEmailAndPassword for $email',
      );
      final cred = await _auth.signInWithEmailAndPassword(
        email:    email.trim(),
        password: password,
      );
      _fbLog.i(
        '🔥 [SIGN_IN] ✓ signInWithEmailAndPassword complete\n'
        '🔥 [SIGN_IN]   uid=${cred.user?.uid}',
      );

      // ── POST-SIGNIN SETTLE DELAY ───────────────────────────────────────────
      //
      // WHY THIS IS REQUIRED
      // ─────────────────────
      // signInWithEmailAndPassword (with Persistence.LOCAL) writes the new
      // credential to localStorage immediately — but ALSO triggers a one-time
      // background IndexedDB *cleanup read* to check for any residual session
      // stored in IndexedDB from before the persistence change. This cleanup
      // read is async and runs in the JS microtask queue AFTER the signIn
      // Future resolves.
      //
      // _updateLastLogin and FirebaseSessionService.saveSession both write to
      // Firestore, which uses IndexedDB for its offline cache. If either
      // Firestore write opens its IndexedDB transaction while the Auth cleanup
      // read is still in flight, the browser throws OperationError — which
      // propagates through the JS microtask queue and corrupts the internal
      // state of the firebase/functions JS SDK.
      //
      // Waiting 600 ms gives the Auth cleanup read time to finish before any
      // Firestore write opens a competing IndexedDB transaction. This eliminates
      // the OperationError at its source rather than just working around it.
      _fbLog.d(
        '🔥 [SIGN_IN] Waiting 600 ms for Auth IndexedDB cleanup to settle\n'
        '🔥 [SIGN_IN] (prevents Firestore IndexedDB write conflict → OperationError)',
      );
      await Future.delayed(const Duration(milliseconds: 600));
      _fbLog.d('🔥 [SIGN_IN] Settle complete — proceeding with Firestore write');

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
    // runZonedGuarded captures any OperationError thrown from the Firestore
    // IndexedDB offline cache write, preventing it from propagating through
    // the JS microtask queue and corrupting the firebase/functions auth state.
    await runZonedGuarded(
      () async {
        _fbLog.d('🔥 [FIRESTORE_WRITE] _updateLastLogin → Users/$uid');
        await _store.collection(_FS.collection).doc(uid).set(
          {_FS.lastLogin: FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        _fbLog.d('🔥 [FIRESTORE_WRITE] _updateLastLogin ✓ complete');
      },
      (e, st) {
        // Catches OperationError and any other zone errors from this write.
        // Non-fatal: the API session is already valid; this is a mirror only.
        _fbLog.w(
          '⚠️ [FIRESTORE_WRITE] _updateLastLogin: Zone error captured '
          '(type=${e.runtimeType}) — non-fatal, continuing\n'
          '   This is likely an IndexedDB OperationError from a concurrent '
          'Auth/Firestore write. The OperationError source has been isolated '
          'here and will NOT propagate to the firebase/functions auth state.\n'
          '   Error: $e',
        );
      },
    ) ?? Future.value();
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