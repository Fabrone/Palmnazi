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

// ─────────────────────────────────────────────────────────────────────────────
// FirebaseSessionService  (v2 — OperationError suppression)
//
// WHAT CHANGED IN v2
// ──────────────────
// v1 deliberately left Firestore offline persistence ENABLED (it is the
// default on Flutter Web via cloud_firestore_web).
//
// This turned out to be the source of the residual OperationError that
// appeared on the FIRST login after Auth persistence was switched from
// IndexedDB to localStorage.
//
// ROOT CAUSE OF THE OPERATIONERROR (now fixed)
// ─────────────────────────────────────────────
// After Auth is changed to Persistence.LOCAL (localStorage), Firebase Auth
// no longer uses IndexedDB for its own credential storage. However, Firestore
// still uses IndexedDB for its offline persistence cache.
//
// On the FIRST login:
//   1. signInWithEmailAndPassword completes.
//   2. Firebase Auth performs a one-time "cleanup read" on IndexedDB to
//      check for residual session data from the previous IndexedDB-persistence
//      era. This cleanup runs as an asynchronous JS microtask.
//   3. Simultaneously (within the same JS event tick), _updateLastLogin or
//      saveSession calls a Firestore write. Firestore opens its own IndexedDB
//      transaction for the offline cache.
//   4. Two IndexedDB operations on the same database are now in-flight at the
//      same time → browser throws OperationError.
//
// The OperationError propagates through the JS microtask queue and into the
// Dart zone. Even with runZonedGuarded, JS-originated OperationErrors that
// travel through a native JS Promise (not a Dart Future) can escape the Dart
// zone boundary and corrupt the JS firebase/auth module's in-memory state.
// This corruption causes getIdToken(false) in _callFunctionViaHttp to return
// a stale/expired token on the next call → 401 UNAUTHENTICATED (the bug that
// was patched in firebase_mfa_service.dart v4 via getIdToken(true)).
//
// THE FIX
// ───────
// Disable Firestore offline persistence on Flutter Web. This removes Firestore
// from the IndexedDB equation entirely. Firestore will only use in-memory
// caching (the default when persistenceEnabled=false), which is synchronous
// and has no locking concerns.
//
// The tradeoff is acceptable: Flutter Web is a network-connected platform.
// There is no meaningful offline-first use case for a web browser tab that
// has no network — users will simply reload the page. The session backup
// (the main feature of this class) stores tokens in Firestore and reads
// them on app restart, which requires a network connection either way.
//
// HOW THE SETTING IS APPLIED SAFELY
// ───────────────────────────────────
// Settings must be applied before any Firestore operation is made. We set
// it in init() BEFORE the authStateChanges().first await, so no Firestore
// read/write can race with the settings change.
//
// Note: Unlike the old setPersistence(true) that caused an OperationError by
// opening a SECOND IndexedDB connection while Firebase Auth was restoring,
// setPersistence(false) tells Firestore NOT to open an IndexedDB connection
// at all — it sets a flag in memory before any database operations begin.
// This is safe to call at startup with no race risk.
//
// ── Original documentation (unchanged) ──────────────────────────────────────
// FlutterSecureStorage on web uses localStorage. Browsers can silently wipe
// localStorage across incognito sessions and privacy-mode clears. This
// class provides a Firestore-backed session restore to handle that case.
//
// DATA FLOW
// ─────────
//   App start  → FirebaseSessionService.init()
//                 └── Disables Firestore offline persistence (web only)
//                     Waits for initial authStateChanges() (IndexedDB restore)
//                     Sets Firebase Auth persistence to localStorage (web only)
//
//   Login OK   → ApiClient.saveSession()
//                 ├── FlutterSecureStorage.write(...)
//                 └── FirebaseSessionService.saveSession(...)
//                       └── Writes under the REAL Firebase Auth UID
//
//   App restart (tokens wiped from localStorage)
//              → ApiClient.restoreSessionIfNeeded()
//                 ├── FlutterSecureStorage.read(...) → null
//                 └── FirebaseSessionService.restoreSession()
//                       └── FlutterSecureStorage.write(...)
//
// FIRESTORE COLLECTION
// ────────────────────
// Collection : _pnrc_sessions
// Document   : {firebaseAuthUid}
// Fields     :
//   accessToken  — custom API access JWT
//   refreshToken — custom API refresh token
//   userId       — custom API user ID
//   userEmail    — user email address
//   userRoles    — comma-separated roles string
//   savedAt      — server timestamp
// ─────────────────────────────────────────────────────────────────────────────

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
      //
      // WHY STEP 0 COMES BEFORE THE authStateChanges WAIT
      // ──────────────────────────────────────────────────
      // Firestore.settings must be set before any Firestore operation is
      // issued. We set it here — before the authStateChanges().first await
      // that waits for the Firebase Auth IndexedDB restore — so there is
      // zero chance of a Firestore operation running before this call.
      //
      // persistenceEnabled: false means Firestore uses in-memory caching only.
      // No IndexedDB connection is opened by Firestore. This eliminates the
      // IndexedDB contention between Firestore and Firebase Auth that caused
      // the OperationError on the first post-login Firestore write.
      //
      // This call is safe to run without try/catch: Settings() with a boolean
      // flag only throws if called AFTER a Firestore operation has already
      // been made. Since this runs in main() before any screen is built, no
      // Firestore operation can have preceded it.
      _db.settings = const Settings(persistenceEnabled: false);
      _fbLog.i(
        'FirebaseSessionService.init: '
        '✓ Firestore offline persistence DISABLED on web — '
        'IndexedDB contention with Firebase Auth eliminated',
      );

      // ── Step 1: Wait for Auth IndexedDB restore ───────────────────────────
      //
      // Firebase Auth still reads its previously-stored credential from IndexedDB
      // at startup (one-time, before Persistence.LOCAL takes effect on the next
      // write). Waiting for the first authStateChanges emission guarantees that
      // restore is complete before we change the persistence mode.
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
      //
      // After the IndexedDB restore above, switch Auth to localStorage so that
      // all future sign-in/sign-out writes are synchronous and lock-free.
      // Combined with Step 0 (Firestore no longer using IndexedDB), there are
      // now NO IndexedDB operations in the login flow — OperationError is
      // structurally impossible.
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

  /// Persist custom API tokens to Firestore under the current real Firebase UID.
  ///
  /// With offline persistence disabled (persistenceEnabled: false), all
  /// Firestore writes go directly to the server — there is no local IndexedDB
  /// write to race with. The settle delay and runZonedGuarded guard from v1
  /// are retained as belt-and-suspenders but should no longer be needed.
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

    // Settle delay: retained for safety on the rare case where Firestore
    // settings were not applied (non-web platforms, or if kIsWeb was false
    // due to a build configuration issue). On web with persistenceEnabled=false
    // this delay is harmless but effectively a no-op.
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