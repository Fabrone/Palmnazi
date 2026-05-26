import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGGER
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

class FirebaseSessionService {
  FirebaseSessionService._();

  static FirebaseAuth      get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db   => FirebaseFirestore.instance;

  static const String _collection = '_pnrc_sessions';

  static String? get _uid {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once inside main() after Firebase.initializeApp().
  static Future<void> init() async {
    _fbLog.i('FirebaseSessionService.init: ━━━ START ━━━');

    if (kIsWeb) {
      // ── Step 0: Disable Firestore offline persistence ─────────────────────

      _db.settings = const Settings(persistenceEnabled: false);
      _fbLog.i(
        'FirebaseSessionService.init: '
        '✓ Firestore offline persistence DISABLED on web — '
        'IndexedDB contention with Firebase Auth eliminated',
      );

      // ── Step 1: Wait for Auth IndexedDB restore ───────────────────────────
      
      try {
        await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 8));
        _fbLog.d(
          'FirebaseSessionService.init: '
          'Initial authStateChanges received — Auth IndexedDB restore complete',
        );
      } catch (_) {
        _fbLog.w(
          '⚠️ FirebaseSessionService.init: '
          'authStateChanges timed out — proceeding with setPersistence anyway',
        );
      }

      // ── Step 2: Switch Auth to localStorage ───────────────────────────────
      
      try {
        await _auth.setPersistence(Persistence.LOCAL);
        _fbLog.i(
          'FirebaseSessionService.init: '
          '✓ Firebase Auth persistence set to localStorage — '
          'IndexedDB write-lock race eliminated',
        );
      } catch (e) {
        _fbLog.w(
          '⚠️ FirebaseSessionService.init: '
          'Could not set Auth persistence (non-fatal — IndexedDB remains): $e',
        );
      }
    }

    // ── Log current auth state ─────────────────────────────────────────────
    final current = _auth.currentUser;
    if (current != null && !current.isAnonymous) {
      _fbLog.i(
        'FirebaseSessionService.init: '
        '✓ Real Firebase user already present — uid=${current.uid}',
      );
    } else {
      _fbLog.i(
        'FirebaseSessionService.init: '
        'No real Firebase user yet — session backup ready for post-login write.',
      );
    }

    _fbLog.i('FirebaseSessionService.init: ━━━ DONE ━━━');
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<void> saveSession({
    required String       accessToken,
    required String       refreshToken,
    required String       userId,
    required String       email,
    required List<String> roles,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _fbLog.w(
        '⚠️ FirebaseSessionService.saveSession: '
        'No real Firebase user — skipping Firestore write. '
        'Session is held in FlutterSecureStorage only.',
      );
      return;
    }

    if (kIsWeb) {
      _fbLog.d(
        '🗄️ [SESSION_SAVE] Waiting 300 ms before Firestore write (uid=$uid)',
      );
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await runZonedGuarded(
      () async {
        _fbLog.d(
          '🗄️ [SESSION_SAVE] Writing to Firestore\n'
          '🗄️ [SESSION_SAVE]   collection : $_collection\n'
          '🗄️ [SESSION_SAVE]   uid        : $uid\n'
          '🗄️ [SESSION_SAVE]   userId     : $userId | email: $email',
        );
        await _db.collection(_collection).doc(uid).set({
          'accessToken':  accessToken,
          'refreshToken': refreshToken,
          'userId':       userId,
          'userEmail':    email,
          'userRoles':    roles.join(','),
          'savedAt':      FieldValue.serverTimestamp(),
        });
        _fbLog.i(
          '✅ [SESSION_SAVE] ✓ Session written to Firestore — uid=$uid',
        );
      },
      (e, st) {
        _fbLog.e(
          '❌ [SESSION_SAVE] Zone error captured during Firestore write\n'
          '   Type       : ${e.runtimeType}\n'
          '   Error      : $e\n'
          '   Impact     : NON-FATAL — tokens remain in FlutterSecureStorage',
          error: e,
          stackTrace: st,
        );
      },
    ) ?? Future.value();
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Read session tokens from Firestore (network-only, no local cache).
  static Future<Map<String, String>?> restoreSession() async {
    final uid = _uid;
    if (uid == null) {
      _fbLog.w(
        '⚠️ FirebaseSessionService.restoreSession: '
        'No real Firebase user — cannot read from Firestore.',
      );
      return null;
    }

    _fbLog.i(
      'FirebaseSessionService.restoreSession: '
      'Attempting Firestore read for uid=$uid',
    );

    try {
      final doc = await _db.collection(_collection).doc(uid).get();

      if (!doc.exists || doc.data() == null) {
        _fbLog.d(
          'FirebaseSessionService.restoreSession: '
          'No session document found for uid=$uid',
        );
        return null;
      }

      final data         = doc.data()!;
      final accessToken  = data['accessToken']  as String?;
      final refreshToken = data['refreshToken'] as String?;
      final userId       = data['userId']       as String?;
      final userEmail    = data['userEmail']    as String? ?? '';
      final userRoles    = data['userRoles']    as String? ?? '';

      if (accessToken == null || refreshToken == null || userId == null) {
        _fbLog.w(
          '⚠️ FirebaseSessionService.restoreSession: '
          'Firestore document is incomplete — '
          'accessToken=${accessToken != null} '
          'refreshToken=${refreshToken != null} '
          'userId=$userId',
        );
        return null;
      }

      _fbLog.i(
        '✅ FirebaseSessionService.restoreSession: '
        '✓ Session restored from Firestore — userId=$userId',
      );

      return {
        'accessToken':  accessToken,
        'refreshToken': refreshToken,
        'userId':       userId,
        'userEmail':    userEmail,
        'userRoles':    userRoles,
      };
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseSessionService.restoreSession: Firestore read failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  /// Delete the Firestore session document on logout.
  static Future<void> clearSession() async {
    final uid = _uid;

    if (uid != null) {
      try {
        await _db.collection(_collection).doc(uid).delete();
        _fbLog.i(
          '✅ FirebaseSessionService.clearSession: '
          '✓ Firestore session document deleted for uid=$uid',
        );
      } catch (e, st) {
        _fbLog.e(
          '❌ FirebaseSessionService.clearSession: '
          'Firestore delete failed — uid=$uid',
          error: e,
          stackTrace: st,
        );
      }
    } else {
      _fbLog.d(
        'FirebaseSessionService.clearSession: '
        'No real Firebase user — nothing to delete in Firestore.',
      );
    }
  }
}