import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminRequest Model
//
// Firestore collection : AdminRequests
// Document ID          : auto-generated
//
// Fields:
//   userId           – custom API UID of the requesting user
//   firebaseUid      – Firebase Auth uid (Firestore identity anchor, checked by rules)
//   userEmail        – email (snapshot for display)
//   facilityName     – hotel / place / facility name
//   servicesOffered  – list of service strings
//   agreedToTerms    – must be true for request to be submitted
//   status           – 'pending' | 'accepted' | 'denied'
//   grantedRole      – 'Admin' | 'MainAdmin'  (set by MainAdmin on accept)
//   denialReason     – free-text reason (set on denial)
//   createdAt        – request submission timestamp
//   respondedAt      – timestamp of MainAdmin action
//   respondedBy      – UID of the MainAdmin who acted
//   respondedByEmail – email of that MainAdmin (snapshot)
// ─────────────────────────────────────────────────────────────────────────────

enum AdminRequestStatus { pending, accepted, denied }

class AdminRequest {
  final String              id;
  final String              userId;
  final String              firebaseUid;   // Firebase Auth uid — Firestore doc key anchor
  final String              userEmail;
  final String              facilityName;
  final List<String>        servicesOffered;
  final bool                agreedToTerms;
  final AdminRequestStatus  status;
  final String?             grantedRole;      // 'Admin' or 'MainAdmin'
  final String?             denialReason;
  final DateTime            createdAt;
  final DateTime?           respondedAt;
  final String?             respondedBy;
  final String?             respondedByEmail;

  const AdminRequest({
    required this.id,
    required this.userId,
    required this.firebaseUid,
    required this.userEmail,
    required this.facilityName,
    required this.servicesOffered,
    required this.agreedToTerms,
    required this.status,
    this.grantedRole,
    this.denialReason,
    required this.createdAt,
    this.respondedAt,
    this.respondedBy,
    this.respondedByEmail,
  });

  // ── Firestore → Model ──────────────────────────────────────────────────────
  factory AdminRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AdminRequest(
      id:               doc.id,
      userId:           d['userId']           as String? ?? '',
      firebaseUid:      d['firebaseUid']       as String? ?? '',
      userEmail:        d['userEmail']         as String? ?? '',
      facilityName:     d['facilityName']      as String? ?? '',
      servicesOffered:  List<String>.from(d['servicesOffered'] ?? []),
      agreedToTerms:    d['agreedToTerms']     as bool?   ?? false,
      status:           _statusFromString(d['status'] as String? ?? 'pending'),
      grantedRole:      d['grantedRole']       as String?,
      denialReason:     d['denialReason']      as String?,
      createdAt:        (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt:      (d['respondedAt'] as Timestamp?)?.toDate(),
      respondedBy:      d['respondedBy']       as String?,
      respondedByEmail: d['respondedByEmail']  as String?,
    );
  }

  // ── Model → Firestore ──────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    'userId':           userId,
    'firebaseUid':      firebaseUid,
    'userEmail':        userEmail,
    'facilityName':     facilityName,
    'servicesOffered':  servicesOffered,
    'agreedToTerms':    agreedToTerms,
    'status':           status.name,
    if (grantedRole     != null) 'grantedRole':      grantedRole,
    if (denialReason    != null) 'denialReason':     denialReason,
    'createdAt':        Timestamp.fromDate(createdAt),
    if (respondedAt     != null) 'respondedAt':      Timestamp.fromDate(respondedAt!),
    if (respondedBy     != null) 'respondedBy':      respondedBy,
    if (respondedByEmail!= null) 'respondedByEmail': respondedByEmail,
  };

  // ── Helpers ────────────────────────────────────────────────────────────────
  bool get isPending  => status == AdminRequestStatus.pending;
  bool get isAccepted => status == AdminRequestStatus.accepted;
  bool get isDenied   => status == AdminRequestStatus.denied;

  AdminRequest copyWith({
    String?             id,
    String?             userId,
    String?             firebaseUid,
    String?             userEmail,
    String?             facilityName,
    List<String>?       servicesOffered,
    bool?               agreedToTerms,
    AdminRequestStatus? status,
    String?             grantedRole,
    String?             denialReason,
    DateTime?           createdAt,
    DateTime?           respondedAt,
    String?             respondedBy,
    String?             respondedByEmail,
  }) => AdminRequest(
    id:               id               ?? this.id,
    userId:           userId           ?? this.userId,
    firebaseUid:      firebaseUid      ?? this.firebaseUid,
    userEmail:        userEmail        ?? this.userEmail,
    facilityName:     facilityName     ?? this.facilityName,
    servicesOffered:  servicesOffered  ?? this.servicesOffered,
    agreedToTerms:    agreedToTerms    ?? this.agreedToTerms,
    status:           status           ?? this.status,
    grantedRole:      grantedRole      ?? this.grantedRole,
    denialReason:     denialReason     ?? this.denialReason,
    createdAt:        createdAt        ?? this.createdAt,
    respondedAt:      respondedAt      ?? this.respondedAt,
    respondedBy:      respondedBy      ?? this.respondedBy,
    respondedByEmail: respondedByEmail ?? this.respondedByEmail,
  );

  static AdminRequestStatus _statusFromString(String s) {
    switch (s) {
      case 'accepted': return AdminRequestStatus.accepted;
      case 'denied':   return AdminRequestStatus.denied;
      default:         return AdminRequestStatus.pending;
    }
  }

  @override
  String toString() =>
      'AdminRequest(id=$id, user=$userEmail, status=${status.name}, role=$grantedRole)';
}