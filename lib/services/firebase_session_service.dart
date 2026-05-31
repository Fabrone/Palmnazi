import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

final Logger _fbLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

class FirebaseSessionService {
  FirebaseSessionService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const String _collection = '_pnrc_sessions';

  static String? get _uid {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    _fbLog.i('FirebaseSessionService.init: ━━━ START ━━━');

    if (kIsWeb) {
      // ── Disable Firestore offline persistence ──────────────────────────────
      // Prevents Firestore from opening its own IndexedDB store, which can
      // conflict with the Auth IndexedDB and compound OperationError frequency.
      try {
        _db.settings = const Settings(
          persistenceEnabled: false,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        _fbLog.i('FirebaseSessionService.init: ✓ Firestore offline persistence DISABLED on web');
      } catch (e) {
        _fbLog.w('FirebaseSessionService.init: Could not disable Firestore persistence: $e');
      }

      // ── Set Firebase Auth persistence to NONE ─────────────────────────────
      //
      // WHY NOT LOCAL (the previous value):
      //   Persistence.LOCAL uses IndexedDB via the browser's WebCrypto API.
      //   When the Firebase JS SDK migrates its in-memory auth state into
      //   IndexedDB it does so via *detached JS Promises* that run seconds
      //   after setPersistence() returns.  Those Promises throw OperationError
      //   directly into Flutter's root zone — completely bypassing any Dart
      //   try/catch — causing a widget-tree rebuild that disposes
      //   _AuthScreenState while _handleLogin() is still running.  The
      //   `if (!mounted) return` guard then fires and navigation never happens.
      //
      // WHY NOT SESSION:
      //   Persistence.SESSION uses window.sessionStorage (no WebCrypto, no
      //   OperationError), but it keeps an active Firebase Auth session alive
      //   across the tab lifetime.  Since login() no longer calls loginMirror()
      //   there is no Firebase Auth session to preserve, so SESSION would just
      //   hold a stale/empty state for no benefit.
      //
      // WHY NONE:
      //   Firebase Auth is entirely in-memory.  No IndexedDB.  No WebCrypto.
      //   No detached Promises.  No OperationError.  The API/JWT session
      //   (flutter_secure_storage → localStorage) is the sole auth store.
      //
      // Note: the previous `authStateChanges().first` wait was only needed to
      // block until IndexedDB had restored a prior session.  With NONE there
      // is nothing to restore, so the wait has been removed.
      try {
        await _auth.setPersistence(Persistence.NONE);
        _fbLog.i('FirebaseSessionService.init: ✓ Firebase Auth persistence set to NONE (no IndexedDB)');
      } catch (e) {
        _fbLog.w('FirebaseSessionService.init: setPersistence failed: $e');
      }
    }

    final current = _auth.currentUser;
    if (current != null && !current.isAnonymous) {
      _fbLog.i('FirebaseSessionService.init: ✓ Real Firebase user present — uid=${current.uid}');
    } else {
      _fbLog.i('FirebaseSessionService.init: No real Firebase user yet — session backup ready');
    }

    _fbLog.i('FirebaseSessionService.init: ━━━ DONE ━━━');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SAVE SESSION
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    required List<String> roles,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _fbLog.w('FirebaseSessionService.saveSession: No Firebase user — skipping Firestore write');
      return;
    }

    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await runZonedGuarded(
      () async {
        await _db.collection(_collection).doc(uid).set({
          'accessToken':  accessToken,
          'refreshToken': refreshToken,
          'userId':       userId,
          'userEmail':    email,
          'userRoles':    roles.join(','),
          'savedAt':      FieldValue.serverTimestamp(),
        });
        _fbLog.i('✅ [SESSION_SAVE] Session written to Firestore — uid=$uid');
      },
      (e, st) {
        _fbLog.e('❌ [SESSION_SAVE] Firestore write failed (non-fatal)', error: e, stackTrace: st);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESTORE SESSION
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, String>?> restoreSession() async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final doc = await _db.collection(_collection).doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;

      final data = doc.data()!;
      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      final userId = data['userId'] as String?;

      if (accessToken == null || refreshToken == null || userId == null) return null;

      _fbLog.i('✅ FirebaseSessionService.restoreSession: Success — userId=$userId');
      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'userId': userId,
        'userEmail': data['userEmail'] as String? ?? '',
        'userRoles': data['userRoles'] as String? ?? '',
      };
    } catch (e, st) {
      _fbLog.e('❌ restoreSession failed', error: e, stackTrace: st);
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLEAR SESSION
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> clearSession() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await _db.collection(_collection).doc(uid).delete();
      _fbLog.i('✅ FirebaseSessionService.clearSession: Deleted for uid=$uid');
    } catch (e, st) {
      _fbLog.e('❌ clearSession failed', error: e, stackTrace: st);
    }
  }
}