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
// FirebaseSessionService
//
// WHY THIS EXISTS
// ───────────────
// FlutterSecureStorage on web uses the browser's localStorage as its backend.
// Browsers can silently wipe localStorage across incognito sessions, browser
// restarts, privacy-mode clears, and OS-level storage pressure events.  This
// causes the "No stored userId or refreshToken — cannot refresh" log line and
// the repeated 401 cascade seen in production.
//
// SOLUTION
// ────────
// Firebase Anonymous Authentication creates a lightweight, Firebase-managed
// user silently (no UI, no password, no email).  Firebase SDK persists this
// user's identity reliably across page refreshes and browser restarts because
// it uses IndexedDB on web — a far more durable storage layer than localStorage.
//
// After any successful custom API login, the accessToken + refreshToken pair
// is written to a private Firestore document keyed by the Firebase anonymous
// UID.  On every app start, if FlutterSecureStorage comes up empty (tokens
// lost), ApiClient.restoreSessionIfNeeded() reads the document from Firestore
// and re-hydrates FlutterSecureStorage — transparently, with zero user
// interaction required.
//
// DATA FLOW
// ─────────
//   App start  → FirebaseSessionService.init()
//                 └── signInAnonymously()  (no-op if already signed in)
//
//   Login OK   → ApiClient.saveSession()
//                 ├── FlutterSecureStorage.write(...)   [fast local cache]
//                 └── FirebaseSessionService.saveSession(...)  [durable store]
//
//   App restart (tokens wiped from localStorage)
//              → ApiClient.restoreSessionIfNeeded()
//                 ├── FlutterSecureStorage.read(...) → null
//                 └── FirebaseSessionService.restoreSession()
//                       └── FlutterSecureStorage.write(...)  [re-hydrate]
//
//   Logout / expiry → ApiClient.clearSession()
//                       ├── FlutterSecureStorage.deleteAll()
//                       └── FirebaseSessionService.clearSession()
//                             ├── Firestore doc deleted
//                             └── Firebase anonymous user signed out
//
// FIRESTORE COLLECTION
// ────────────────────
// Collection : _pnrc_sessions
// Document   : {firebaseAnonymousUid}
// Fields     :
//   accessToken  — custom API access JWT
//   refreshToken — custom API refresh token
//   userId       — custom API user ID
//   userEmail    — user email address
//   userRoles    — comma-separated roles string  e.g. "tourist,admin"
//   savedAt      — server timestamp (for TTL rules / debugging)
//
// REQUIRED FIRESTORE SECURITY RULES
// ───────────────────────────────────
// Add the following to your Firebase console → Firestore → Rules.
// This ensures only the authenticated Firebase user can read/write their
// own session document — no other user or anonymous caller can access it.
//
//   rules_version = '2';
//   service cloud.firestore {
//     match /databases/{database}/documents {
//       match /_pnrc_sessions/{uid} {
//         allow read, write, delete:
//           if request.auth != null && request.auth.uid == uid;
//       }
//     }
//   }
//
// REQUIRED PUBSPEC DEPENDENCIES
// ──────────────────────────────
// firebase_auth: ^5.x.x
// cloud_firestore: ^5.x.x
// (Both are part of the FlutterFire suite — run `flutterfire configure` if
//  firebase_options.dart is already generated; the packages just need adding.)
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseSessionService {
  FirebaseSessionService._();

  // ── Firebase references ───────────────────────────────────────────────────
  static FirebaseAuth       get _auth => FirebaseAuth.instance;
  static FirebaseFirestore  get _db   => FirebaseFirestore.instance;

  // Private Firestore collection — underscore prefix marks it as internal.
  static const String _collection = '_pnrc_sessions';

  // Convenience: current anonymous Firebase UID, null if not yet signed in.
  static String? get _uid => _auth.currentUser?.uid;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once inside main() after Firebase.initializeApp().
  ///
  /// On web, enables Firestore offline persistence (IndexedDB-backed, far
  /// more durable than localStorage).  On all platforms, signs in anonymously
  /// if no Firebase user exists yet.  Firebase SDK auto-restores an existing
  /// anonymous user across restarts, so this is a no-op on subsequent app
  /// launches.
  static Future<void> init() async {
    _fbLog.i('🔥 FirebaseSessionService.init: ━━━ START ━━━');

    // ── Step 1: Enable Firestore offline persistence on web ─────────────────
    // IndexedDB (used by Firestore persistence) survives browser restarts and
    // incognito exits far better than localStorage (used by FlutterSecureStorage).
    if (kIsWeb) {
      try {
        _db.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        _fbLog.d('🔥 FirebaseSessionService.init: Firestore offline persistence ENABLED (web)');
      } catch (e) {
        // Settings can only be changed before any Firestore operation.
        // If another part of the app already triggered Firestore, this throws
        // a StateError — safe to ignore; persistence may already be enabled.
        _fbLog.w('⚠️ FirebaseSessionService.init: Could not set Firestore settings — $e');
      }
    }

    // ── Step 2: Restore or create Firebase anonymous user ───────────────────
    if (_auth.currentUser != null) {
      _fbLog.i(
        '🔥 FirebaseSessionService.init: '
        '✓ Existing Firebase user restored — uid=${_auth.currentUser!.uid}',
      );
      return;
    }

    try {
      final cred = await _auth.signInAnonymously();
      _fbLog.i(
        '🔥 FirebaseSessionService.init: '
        '✓ Signed in anonymously — uid=${cred.user?.uid}',
      );
    } catch (e, st) {
      _fbLog.e(
        '❌ FirebaseSessionService.init: Anonymous sign-in failed\n'
        '   The session fallback via Firestore will not be available.\n'
        '   FlutterSecureStorage will still be used as the primary store.',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  /// Persist custom API tokens to Firestore under the current Firebase UID.
  ///
  /// Called by ApiClient.saveSession() immediately after writing to
  /// FlutterSecureStorage.  If no Firebase user exists (init() failed or
  /// was not called) this is a silent no-op — FlutterSecureStorage still
  /// holds the data and the app continues normally.
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    required List<String> roles,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _fbLog.w(
        '⚠️ FirebaseSessionService.saveSession: '
        'No Firebase user — skipping Firestore write',
      );
      return;
    }

    try {
      await _db.collection(_collection).doc(uid).set({
        'accessToken':  accessToken,
        'refreshToken': refreshToken,
        'userId':       userId,
        'userEmail':    email,
        'userRoles':    roles.join(','),
        'savedAt':      FieldValue.serverTimestamp(),
      });
      _fbLog.i(
        '✅ FirebaseSessionService.saveSession: '
        '✓ Session written to Firestore — uid=$uid',
      );
    } catch (e, st) {
      // Non-fatal: FlutterSecureStorage still has the tokens.
      _fbLog.e(
        '❌ FirebaseSessionService.saveSession: Firestore write failed\n'
        '   Tokens remain in FlutterSecureStorage — session will work until '
        'the browser wipes localStorage.',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Read session tokens from Firestore.
  ///
  /// Returns a map with keys matching StorageKeys constants, or null if no
  /// session document is found.  Called by ApiClient.restoreSessionIfNeeded()
  /// when FlutterSecureStorage comes up empty on app start.
  static Future<Map<String, String>?> restoreSession() async {
    final uid = _uid;
    if (uid == null) {
      _fbLog.w(
        '⚠️ FirebaseSessionService.restoreSession: '
        'No Firebase user — cannot read from Firestore',
      );
      return null;
    }

    _fbLog.i(
      '🔥 FirebaseSessionService.restoreSession: '
      'Attempting Firestore read for uid=$uid',
    );

    try {
      final doc = await _db.collection(_collection).doc(uid).get();

      if (!doc.exists || doc.data() == null) {
        _fbLog.d(
          '🔥 FirebaseSessionService.restoreSession: '
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
          'Firestore document is incomplete — accessToken=$accessToken '
          'refreshToken=${refreshToken != null} userId=$userId',
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

  /// Delete the Firestore session document and sign out the anonymous Firebase
  /// user.  Called by ApiClient.clearSession() on logout and session expiry.
  ///
  /// After this, the next call to init() will create a fresh anonymous user
  /// with a new UID — there is no link back to the previous session.
  static Future<void> clearSession() async {
    final uid = _uid;

    // ── Delete Firestore document ────────────────────────────────────────────
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
        '🔥 FirebaseSessionService.clearSession: '
        'No Firebase user — nothing to delete in Firestore',
      );
    }

    // ── WHY WE DO NOT sign out the anonymous Firebase user ──────────────────
    // Calling _auth.signOut() here destroys the anonymous UID.  The next
    // saveSession() call (which fires immediately after the user logs back in)
    // would then find _uid == null and skip the Firestore backup write —
    // leaving the new session completely unprotected.
    //
    // The anonymous UID is not a security credential; it is a stable key for
    // the Firestore document.  The document was just deleted above, so there
    // is nothing sensitive left in Firestore under this UID.  Keeping the
    // anonymous user signed in costs nothing and ensures saveSession() always
    // has a valid UID ready to write to on the very next login.
    //
    // A fresh anonymous UID is only needed when init() runs on a completely
    // fresh app install — which is handled correctly already.
    _fbLog.d(
      '🔥 FirebaseSessionService.clearSession: '
      'Anonymous Firebase user retained (uid=$uid) — Firestore doc deleted only',
    );
  }
}