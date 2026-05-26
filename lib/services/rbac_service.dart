import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RbacService
// ─────────────────────────────────────────────────────────────────────────────

class RbacResult {
  final bool   isSuccess;
  final String message;
  const RbacResult.success([this.message = 'Success']) : isSuccess = true;
  const RbacResult.failure(this.message) : isSuccess = false;
}

class RbacService {
  RbacService._();

  static final _db  = FirebaseFirestore.instance;
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount:      0,
      errorMethodCount: 8,
      lineLength:       100,
      colors:           true,
      printEmojis:      true,
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
    required String       userId,        // custom API id (stored for reference)
    required String       userEmail,
    required String       facilityName,
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
        id:              '',
        userId:          userId,
        userEmail:       userEmail,
        facilityName:    facilityName,
        servicesOffered: servicesOffered,
        agreedToTerms:   true,
        status:          AdminRequestStatus.pending,
        createdAt:       DateTime.now(), firebaseUid: '',
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
      _log.w('⚠️ RbacService.userRequestStream: No Firebase user — returning empty stream');
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
    required String targetUserId,       // custom API id (kept for reference)
    required String targetFirebaseUid,  // Firebase uid — used as document key
    required String grantedRole,
    required String respondedBy,
    required String respondedByEmail,
  }) async {
    try {
      // Sanitise the role before writing — trim() prevents trailing newlines
      // or whitespace from being stored, which would break all equality checks.
      final cleanedRole = grantedRole.trim();

      _log.i('🔐 RbacService.acceptRequest: '
          'requestId=$requestId targetFirebaseUid=$targetFirebaseUid role=$cleanedRole');

      final batch = _db.batch();

      // 1. Update the AdminRequests document
      batch.update(_requests.doc(requestId), {
        'status':           'accepted',
        'grantedRole':      cleanedRole,
        'respondedAt':      Timestamp.now(),
        'respondedBy':      respondedBy,
        'respondedByEmail': respondedByEmail,
      });

      // 2. Update the user's role — key is Firebase uid, NOT custom API userId
      batch.update(_userDoc(targetFirebaseUid), {
        'role': cleanedRole,
      });

      await batch.commit();
      _log.i('✅ RbacService.acceptRequest: Role $cleanedRole granted to $targetFirebaseUid');
      return RbacResult.success('Role $cleanedRole has been granted.');
    } catch (e, st) {
      _log.e('❌ RbacService.acceptRequest', error: e, stackTrace: st);
      return RbacResult.failure('Could not grant role: $e');
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
        'status':           'denied',
        'denialReason':     reason,
        'respondedAt':      Timestamp.now(),
        'respondedBy':      respondedBy,
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
      if (!snap.exists) return 'Tourist';

      // .trim() strips any accidental whitespace / newline 
      final raw     = (snap.data()?['role'] as String?) ?? 'Tourist';
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

      return cleaned;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED: One-shot role fetch.
  // firebaseUid — Firebase Auth uid, NOT the custom API userId.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String> getUserRole(String firebaseUid) async {
    try {
      final snap = await _userDoc(firebaseUid).get();
      if (!snap.exists) return 'Tourist';
      return ((snap.data()?['role'] as String?) ?? 'Tourist').trim();
    } catch (e) {
      _log.w('⚠️ RbacService.getUserRole: $e');
      return 'Tourist';
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