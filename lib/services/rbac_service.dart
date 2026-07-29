import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RbacService
// ─────────────────────────────────────────────────────────────────────────────

class RbacResult {
  final bool isSuccess;
  final String message;
  const RbacResult.success([this.message = 'Success']) : isSuccess = true;
  const RbacResult.failure(this.message) : isSuccess = false;
}

class RbacService {
  RbacService._();

  // ── Role identifiers ──────────────────────────────────────────────────────
  // Firestore is the single source of truth for the 'role' field. The three
  // admin-side roles form a hierarchy:
  //   MainAdmin    — full system control; the ONLY role that can assign or
  //                  revoke other users' roles (see acceptRequest/denyRequest).
  //   CityManager  — scoped to one managedPlaceId (via getManagedPlace); can
  //                  add/edit content within that scope. Formerly called
  //                  'Admin' — see [normalizeRole] for the legacy alias.
  //   ContentAdmin — same managedPlaceId scoping as CityManager, but may not
  //                  delete core data (see [canDeleteCoreData]).
  static const String roleMainAdmin = 'MainAdmin';
  static const String roleCityManager = 'CityManager';
  static const String roleContentAdmin = 'ContentAdmin';
  static const String roleTourist = 'Tourist';

  // Legacy alias: accounts granted the role before the City Manager /
  // Content Admin split were stored as plain 'Admin'. Treat that as
  // CityManager everywhere a role is read, so existing accounts keep working
  // without a manual Firestore migration.
  static String normalizeRole(String role) =>
      role == 'Admin' ? roleCityManager : role;

  /// True for any role scoped to a single managedPlaceId (City Manager or
  /// Content Admin), as opposed to MainAdmin (system-wide) or Tourist (none).
  static bool isPlaceScopedRole(String role) =>
      role == roleCityManager || role == roleContentAdmin;

  /// True for any of the three admin-side roles.
  static bool isAdminRole(String role) =>
      role == roleMainAdmin || isPlaceScopedRole(role);

  /// Content Admin can add/edit within its managed place but never delete
  /// core data; MainAdmin and City Manager can.
  static bool canDeleteCoreData(String role) =>
      role == roleMainAdmin || role == roleCityManager;

  /// Human-readable label for UI display (badges, pickers, notifications).
  static String roleLabel(String role) {
    switch (normalizeRole(role)) {
      case roleMainAdmin:
        return 'Main Admin/SuperAdmin';
      case roleCityManager:
        return 'City Manager';
      case roleContentAdmin:
        return 'Content Admin';
      default:
        return roleTourist;
    }
  }

  static final _db = FirebaseFirestore.instance;
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  // ── Collection references ─────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('AdminRequests');

  // IMPORTANT: document key is the Firebase Auth uid, NOT the custom API userId.
  static DocumentReference<Map<String, dynamic>> _userDoc(String firebaseUid) =>
      _db.collection('Users').doc(firebaseUid);

  // ── Firebase Auth uid helper ──────────────────────────────────────────────

  static String? get _firebaseUid => FirebaseAuth.instance.currentUser?.uid;

  // ─────────────────────────────────────────────────────────────────────────
  // TOURIST: Submit a new admin role request
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RbacResult> submitAdminRequest({
    required String userId, // custom API id (stored for reference)
    required String userEmail,
    required String facilityName,
    required String placeId,
    required String placeName,
    required String cityId,
    required String cityName,
    required List<String> servicesOffered,
  }) async {
    try {
      final firebaseUid = _firebaseUid;
      if (firebaseUid == null) {
        return const RbacResult.failure(
            'Not signed in. Please sign in and try again.');
      }

      _log.i('🔐 RbacService.submitAdminRequest: '
          'firebaseUid=$firebaseUid user=$userEmail facility=$facilityName');

      // Guard: no duplicate pending requests — query by firebaseUid
      final existing = await _requests
          .where('firebaseUid', isEqualTo: firebaseUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return const RbacResult.failure(
            'You already have a pending request. Please wait for a response.');
      }

      final request = AdminRequest(
        id: '',
        userId: userId,
        userEmail: userEmail,
        facilityName: facilityName,
        placeId: placeId,
        placeName: placeName,
        cityId: cityId,
        cityName: cityName,
        servicesOffered: servicesOffered,
        agreedToTerms: true,
        status: AdminRequestStatus.pending,
        createdAt: DateTime.now(),
        firebaseUid: '',
      );

      // toMap() fields + firebaseUid anchor for security rules
      final data = request.toMap()..['firebaseUid'] = firebaseUid;
      await _requests.add(data);

      _log.i('✅ RbacService.submitAdminRequest: Request saved');
      return const RbacResult.success(
          'Your request has been submitted successfully.');
    } catch (e, st) {
      _log.e('❌ RbacService.submitAdminRequest', error: e, stackTrace: st);
      return RbacResult.failure('Could not submit request: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOURIST: Stream of user's most recent request (any status).
  // ─────────────────────────────────────────────────────────────────────────
  static Stream<AdminRequest?> userRequestStream(String userId) {
    final firebaseUid = _firebaseUid;
    if (firebaseUid == null) {
      // Not signed in — return an empty stream rather than a denied one
      _log.w(
          '⚠️ RbacService.userRequestStream: No Firebase user — returning empty stream');
      return const Stream.empty();
    }

    return _requests
        .where('firebaseUid', isEqualTo: firebaseUid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return AdminRequest.fromFirestore(snap.docs.first);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Stream of ALL pending requests (FIFO — oldest first)
  // ─────────────────────────────────────────────────────────────────────────
  static Stream<List<AdminRequest>> pendingRequestsStream() {
    return _requests
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AdminRequest.fromFirestore(d)).toList());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Live count of pending requests (for the badge dot)
  // ─────────────────────────────────────────────────────────────────────────
  static Stream<int> pendingRequestsCountStream() {
    return _requests
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.size);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Accept a request → update request doc + user role in batch.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RbacResult> acceptRequest({
    required String requestId,
    required String targetUserId, // custom API id (kept for reference)
    required String targetFirebaseUid, // Firebase uid — used as document key
    required String grantedRole,
    required String respondedBy,
    required String respondedByEmail,
    // The place this request was submitted against — copied onto the user's
    // Users doc as managedPlaceId so a City Manager / Content Admin is scoped
    // to exactly one place everywhere else in the app (Bookings,
    // Place_details, the new Place Admin Panel). Pass empty strings for a
    // MainAdmin grant, since MainAdmin isn't scoped to any single place.
    String placeId = '',
    String placeName = '',
    String cityId = '',
    String cityName = '',
  }) async {
    try {
      // Sanitise the role before writing — trim() prevents trailing newlines
      // or whitespace from being stored, which would break all equality checks.
      final cleanedRole = grantedRole.trim();

      _log.i('🔐 RbacService.acceptRequest: '
          'requestId=$requestId targetFirebaseUid=$targetFirebaseUid role=$cleanedRole '
          'placeId=$placeId');

      final batch = _db.batch();

      // 1. Update the AdminRequests document
      batch.update(_requests.doc(requestId), {
        'status': 'accepted',
        'grantedRole': cleanedRole,
        'respondedAt': Timestamp.now(),
        'respondedBy': respondedBy,
        'respondedByEmail': respondedByEmail,
      });

      // 2. Update the user's role — key is Firebase uid, NOT custom API userId
      batch.update(_userDoc(targetFirebaseUid), {
        'role': cleanedRole,
        'managedPlaceId': placeId,
        'managedPlaceName': placeName,
        'managedCityId': cityId,
        'managedCityName': cityName,
      });

      await batch.commit();
      _log.i(
          '✅ RbacService.acceptRequest: Role $cleanedRole granted to $targetFirebaseUid');
      return RbacResult.success('Role $cleanedRole has been granted.');
    } catch (e, st) {
      _log.e('❌ RbacService.acceptRequest', error: e, stackTrace: st);
      return RbacResult.failure('Could not grant role: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Reassign an already-accepted Admin's managed place — for
  // fixing/changing an assignment without forcing a brand-new request.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RbacResult> reassignManagedPlace({
    required String targetFirebaseUid,
    required String placeId,
    required String placeName,
    required String cityId,
    required String cityName,
  }) async {
    try {
      await _userDoc(targetFirebaseUid).update({
        'managedPlaceId': placeId,
        'managedPlaceName': placeName,
        'managedCityId': cityId,
        'managedCityName': cityName,
      });
      _log.i(
          '✅ RbacService.reassignManagedPlace: $targetFirebaseUid → $placeId');
      return const RbacResult.success('Managed place updated.');
    } catch (e, st) {
      _log.e('❌ RbacService.reassignManagedPlace', error: e, stackTrace: st);
      return RbacResult.failure('Could not update managed place: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Switch an already-accepted user to a different role —
  // lets MainAdmin correct/change an assignment (e.g. CityManager →
  // ContentAdmin, or either → MainAdmin) from the same screen used to grant
  // it, without first revoking back to Tourist and re-approving.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RbacResult> switchGrantedRole({
    required String requestId,
    required String targetFirebaseUid,
    required String newRole,
    required String respondedBy,
    required String respondedByEmail,
    // The place the new role should be scoped to. Ignored (and cleared) when
    // newRole is MainAdmin, since MainAdmin isn't scoped to any single place.
    String placeId = '',
    String placeName = '',
    String cityId = '',
    String cityName = '',
  }) async {
    try {
      final cleanedRole = newRole.trim();
      final isPlaceScoped = isPlaceScopedRole(cleanedRole);

      _log.i('🔐 RbacService.switchGrantedRole: '
          'requestId=$requestId targetFirebaseUid=$targetFirebaseUid newRole=$cleanedRole');

      final batch = _db.batch();

      batch.update(_requests.doc(requestId), {
        'grantedRole': cleanedRole,
        'respondedAt': Timestamp.now(),
        'respondedBy': respondedBy,
        'respondedByEmail': respondedByEmail,
      });

      batch.update(_userDoc(targetFirebaseUid), {
        'role': cleanedRole,
        'managedPlaceId': isPlaceScoped ? placeId : '',
        'managedPlaceName': isPlaceScoped ? placeName : '',
        'managedCityId': isPlaceScoped ? cityId : '',
        'managedCityName': isPlaceScoped ? cityName : '',
      });

      await batch.commit();
      _log.i(
          '✅ RbacService.switchGrantedRole: $targetFirebaseUid switched to $cleanedRole');
      return RbacResult.success('Role switched to ${roleLabel(cleanedRole)}.');
    } catch (e, st) {
      _log.e('❌ RbacService.switchGrantedRole', error: e, stackTrace: st);
      return RbacResult.failure('Could not switch role: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN ADMIN: Deny a request
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RbacResult> denyRequest({
    required String requestId,
    required String respondedBy,
    required String respondedByEmail,
    required String reason,
  }) async {
    try {
      _log.i('🔐 RbacService.denyRequest: requestId=$requestId');

      await _requests.doc(requestId).update({
        'status': 'denied',
        'denialReason': reason,
        'respondedAt': Timestamp.now(),
        'respondedBy': respondedBy,
        'respondedByEmail': respondedByEmail,
      });

      _log.i('✅ RbacService.denyRequest: Request denied');
      return const RbacResult.success('Request has been denied.');
    } catch (e, st) {
      _log.e('❌ RbacService.denyRequest', error: e, stackTrace: st);
      return RbacResult.failure('Could not deny request: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED: Live role stream.
  // ─────────────────────────────────────────────────────────────────────────
  static Stream<String> userRoleStream(String firebaseUid) {
    return _userDoc(firebaseUid).snapshots().map((snap) {
      if (!snap.exists) return roleTourist;

      // .trim() strips any accidental whitespace / newline
      final raw = (snap.data()?['role'] as String?) ?? roleTourist;
      final cleaned = raw.trim();

      // Log a warning if the stored value is not already clean so the
      // developer knows to fix it in the Firebase console (see note above).
      if (raw != cleaned) {
        _log.w(
          '⚠️ RbacService.userRoleStream: dirty role detected for $firebaseUid — '
          'stored="${raw.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}" '
          'using cleaned="$cleaned". '
          'Fix: edit the role field in Firebase console to remove the trailing whitespace.',
        );
      }

      return normalizeRole(cleaned);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED: One-shot role fetch.
  // firebaseUid — Firebase Auth uid, NOT the custom API userId.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String> getUserRole(String firebaseUid) async {
    try {
      final snap = await _userDoc(firebaseUid).get();
      if (!snap.exists) return roleTourist;
      return normalizeRole(
          ((snap.data()?['role'] as String?) ?? roleTourist).trim());
    } catch (e) {
      _log.w('⚠️ RbacService.getUserRole: $e');
      return roleTourist;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED: One-shot fetch of the place a City Manager / Content Admin is
  // scoped to. Returns null when unset (e.g. a MainAdmin, or a place-scoped
  // admin predating this feature who hasn't been reassigned yet —
  // admin_dashboard.dart shows an empty state in that case rather than
  // crashing).
  // ─────────────────────────────────────────────────────────────────────────
  static Future<
          ({String placeId, String placeName, String cityId, String cityName})?>
      getManagedPlace(String firebaseUid) async {
    try {
      final snap = await _userDoc(firebaseUid).get();
      final placeId = snap.data()?['managedPlaceId'] as String?;
      if (placeId == null || placeId.isEmpty) return null;
      return (
        placeId: placeId,
        placeName: snap.data()?['managedPlaceName'] as String? ?? '',
        cityId: snap.data()?['managedCityId'] as String? ?? '',
        cityName: snap.data()?['managedCityName'] as String? ?? '',
      );
    } catch (e) {
      _log.w('⚠️ RbacService.getManagedPlace: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED: Check if the user already has a pending request
  // ─────────────────────────────────────────────────────────────────────────
  static Future<bool> hasPendingRequest(String userId) async {
    final firebaseUid = _firebaseUid;
    if (firebaseUid == null) return false;
    try {
      final snap = await _requests
          .where('firebaseUid', isEqualTo: firebaseUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
