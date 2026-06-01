import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:palmnazi/services/firebase_email_link_service.dart';

final Logger _fbLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

class _FS {
  static const collection  = 'Users';
  static const email       = 'email';
  static const role        = 'role';
  static const defaultRole = 'Tourist';
  static const createdAt   = 'createdAt';
  static const lastLogin   = 'lastLoginAt';
  static const provider    = 'provider';
  static const displayName = 'displayName';
  static const photoUrl    = 'photoUrl';
}

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _store = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  static Future<void> registerMirror({
    required String email,
    required String password,
  }) async {
    _fbLog.i('🔥 FirebaseService.registerMirror: ━━━ START ━━━ | $email');
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _fbLog.i('🔥 Firebase user created | uid: ${cred.user?.uid}');

      final linkResult = await FirebaseEmailLinkService.sendSignInLink(
        email: email.trim(),
        purpose: EmailLinkPurpose.verify,
      );
      if (!linkResult.isSuccess) {
        await cred.user?.sendEmailVerification();
      }

      await _writeUserDocument(
        uid: cred.user!.uid,
        email: email.trim(),
        provider: 'email',
        isNew: true,
      );
    } catch (e, st) {
      _fbLog.e('❌ registerMirror failed', error: e, stackTrace: st);
    }
  }

  static Future<MultiFactorResolver?> loginMirror({
    required String email,
    required String password,
  }) async {
    _fbLog.i('🔥 FirebaseService.loginMirror: ━━━ START ━━━ | $email');

    try {
      final existing = _auth.currentUser;

      if (existing != null &&
          !existing.isAnonymous &&
          existing.email?.toLowerCase() == email.trim().toLowerCase()) {
        await existing.getIdToken(true);
        _updateLastLogin(uid: existing.uid);
        return null;
      }

      if (existing != null &&
          existing.email?.toLowerCase() != email.trim().toLowerCase()) {
        await _auth.signOut();
        await Future.delayed(const Duration(milliseconds: 400));
      }

      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _fbLog.i('🔥 [SIGN_IN] ✓ complete | uid=${cred.user?.uid}');

      if (cred.user != null) {
        _updateLastLogin(uid: cred.user!.uid);
      }

      return null;
    } on FirebaseAuthMultiFactorException catch (e) {
      return e.resolver;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _fbLog.w('⚠️ Firebase user missing — creating retroactively');
        await _createMissingFirebaseAccount(email: email.trim(), password: password);
      }
      return null;
    } catch (e, st) {
      _fbLog.e('❌ loginMirror error (non-blocking)', error: e, stackTrace: st);
      return null;
    }
  }

  static Future<void> _createMissingFirebaseAccount({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _writeUserDocument(
        uid: cred.user!.uid,
        email: email,
        provider: 'email',
        isNew: true,
      );
    } catch (e) {
      _fbLog.e('❌ _createMissingFirebaseAccount failed', error: e);
    }
  }

  /// Sends a Firebase email verification link.
  ///
  /// [emailOverride] MUST be supplied by callers that use the API-only auth
  /// flow (i.e. where Firebase Auth persistence is set to NONE and
  /// `_auth.currentUser` is null between navigations).  Omitting it falls
  /// back to the active Firebase session email, which only exists when the
  /// user was explicitly signed into Firebase Auth (e.g. magic-link flow).
  static Future<bool> sendEmailVerificationLink({String? emailOverride}) async {
    try {
      // Prefer the explicitly supplied email over the Firebase session email.
      // With Persistence.NONE the session email is null after every navigation,
      // so API-only callers must pass the email from their own session store.
      final email = (emailOverride?.trim().isNotEmpty == true)
          ? emailOverride!.trim()
          : _auth.currentUser?.email;

      if (email == null || email.isEmpty) {
        _fbLog.w('⚠️ sendEmailVerificationLink: no email available — skipping');
        return false;
      }

      // If the currently signed-in Firebase user already has this address
      // verified there is nothing left to do.
      final user = _auth.currentUser;
      if (user != null &&
          user.email?.toLowerCase() == email.toLowerCase() &&
          user.emailVerified) {
        return true;
      }

      final result = await FirebaseEmailLinkService.sendSignInLink(
        email: email,
        purpose: EmailLinkPurpose.verify,
      );
      return result.isSuccess;
    } catch (e) {
      _fbLog.e('❌ sendEmailVerificationLink: $e');
      return false;
    }
  }

  static Future<bool> sendEmailVerification({String? emailOverride}) async =>
      sendEmailVerificationLink(emailOverride: emailOverride);

  static Future<bool> reloadAndCheckEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      await user.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (e) {
      _fbLog.e('❌ reloadAndCheckEmailVerified: $e');
      return false;
    }
  }

  static Future<void> googleSignInMirror({required String idToken}) async {
    _fbLog.i('🔥 FirebaseService.googleSignInMirror: ━━━ START ━━━');
    try {
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final cred = await _auth.signInWithCredential(credential);
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;
      await _writeUserDocument(
        uid: cred.user!.uid,
        email: cred.user!.email ?? '',
        provider: 'google',
        isNew: isNew,
        displayName: cred.user!.displayName,
        photoUrl: cred.user!.photoURL,
      );
    } catch (e, st) {
      _fbLog.e('❌ googleSignInMirror failed', error: e, stackTrace: st);
    }
  }

  static Future<void> signOut() async {
    try {
      await _auth.signOut();
      _fbLog.i('🔥 FirebaseService.signOut: ✓');
    } catch (e) {
      _fbLog.e('❌ signOut failed', error: e);
    }
  }

  static Future<void> _writeUserDocument({
    required String uid,
    required String email,
    required String provider,
    required bool isNew,
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      final docRef = _store.collection(_FS.collection).doc(uid);
      if (isNew) {
        await docRef.set({
          _FS.email: email,
          _FS.role: _FS.defaultRole,
          _FS.createdAt: FieldValue.serverTimestamp(),
          _FS.lastLogin: FieldValue.serverTimestamp(),
          _FS.provider: provider,
          if (displayName != null) _FS.displayName: displayName,
          if (photoUrl != null) _FS.photoUrl: photoUrl,
        }, SetOptions(merge: true));
      } else {
        _updateLastLogin(uid: uid);
      }
    } catch (e, st) {
      _fbLog.w('❌ _writeUserDocument failed (non-critical)', error: e, stackTrace: st);
    }
  }

  static void _updateLastLogin({required String uid}) {
    unawaited(_performLastLoginUpdate(uid));
  }

  static Future<void> _performLastLoginUpdate(String uid) async {
    try {
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 2000)); // Increased delay
      }

      _fbLog.d('🔥 [FIRESTORE_WRITE] _updateLastLogin → Users/$uid');

      await _store.collection(_FS.collection).doc(uid).set(
        {_FS.lastLogin: FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      _fbLog.d('🔥 [FIRESTORE_WRITE] _updateLastLogin ✓ complete');
    } catch (e, st) {
      _fbLog.w('⚠️ [FIRESTORE_WRITE] _updateLastLogin failed (expected on Web)', 
          error: e, stackTrace: st);
    }
  }

  static Future<String> readCurrentUserRole() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return _FS.defaultRole;
      final doc = await _store.collection(_FS.collection).doc(uid).get();
      return (doc.data()?[_FS.role] as String?) ?? _FS.defaultRole;
    } catch (e) {
      _fbLog.e('❌ readCurrentUserRole: $e');
      return _FS.defaultRole;
    }
  }
}