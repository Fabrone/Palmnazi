import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingNotificationService
//
// Firestore-backed in-app notification center. Persists the same booking
// events that already trigger FCM push (see functions/index.js:
// onBookingCreated → admins, onBookingStatusChanged → tourist) so a signed-in
// user has a real bell/badge/history instead of only a transient OS push.
// Documents are written server-side only (Cloud Functions, Admin SDK bypasses
// rules) — this service is read/mark-read only from the client.
//
// Named distinctly from the pre-existing lib/services/notification_service.dart
// (which handles a separate concern: admin-role-request local notifications)
// to avoid confusion between the two.
// ─────────────────────────────────────────────────────────────────────────────
class BookingNotificationModel {
  final String id;
  final String recipientUid;
  final String type; // 'booking_created' | 'booking_status_changed'
  final String title;
  final String body;
  final String? bookingId;
  final bool read;
  final DateTime? createdAt;

  const BookingNotificationModel({
    required this.id,
    required this.recipientUid,
    required this.type,
    required this.title,
    required this.body,
    this.bookingId,
    required this.read,
    this.createdAt,
  });

  factory BookingNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BookingNotificationModel(
      id: doc.id,
      recipientUid: data['recipientUid'] as String? ?? '',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      bookingId: data['bookingId'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class BookingNotificationService {
  BookingNotificationService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('Notifications');

  static Stream<List<BookingNotificationModel>> streamForUser(String uid) =>
      _collection
          .where('recipientUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((snap) =>
              snap.docs.map(BookingNotificationModel.fromFirestore).toList());

  static Stream<int> unreadCountStream(String uid) => _collection
      .where('recipientUid', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((snap) => snap.docs.length);

  static Future<void> markRead(String id) =>
      _collection.doc(id).update({'read': true});

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
}
