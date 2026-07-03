import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceQueryModel
//
// Firestore collection : PlaceQueries
// Document ID          : auto-generated
//
// A tourist's question about a specific place, answered by that place's
// Admin (or MainAdmin) from the Place Admin Panel's Queries tab. Deliberately
// minimal — one message in, one reply out, no threading.
// ─────────────────────────────────────────────────────────────────────────────

enum PlaceQueryStatus { open, answered }

class PlaceQueryModel {
  final String id;
  final String placeId;
  final String placeName;
  final String firebaseUid;
  final String userEmail;
  final String message;
  final PlaceQueryStatus status;
  final String? adminReply;
  final String? repliedBy;
  final DateTime? createdAt;
  final DateTime? repliedAt;

  const PlaceQueryModel({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.firebaseUid,
    required this.userEmail,
    required this.message,
    this.status = PlaceQueryStatus.open,
    this.adminReply,
    this.repliedBy,
    this.createdAt,
    this.repliedAt,
  });

  factory PlaceQueryModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PlaceQueryModel(
      id: doc.id,
      placeId: d['placeId'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '',
      firebaseUid: d['firebaseUid'] as String? ?? '',
      userEmail: d['userEmail'] as String? ?? '',
      message: d['message'] as String? ?? '',
      status: (d['status'] as String?) == 'answered'
          ? PlaceQueryStatus.answered
          : PlaceQueryStatus.open,
      adminReply: d['adminReply'] as String?,
      repliedBy: d['repliedBy'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      repliedAt: (d['repliedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'placeId': placeId,
        'placeName': placeName,
        'firebaseUid': firebaseUid,
        'userEmail': userEmail,
        'message': message,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      };
}
