import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingMessageService
//
// Append-only two-way thread on a single booking — Bookings/{bookingId}/
// messages/{messageId} (see firestore.rules: readable/writable by the
// booking's own tourist or the place's admin/MainAdmin). Lets a tourist and
// a place admin actually talk about a booking instead of the previous
// one-way confirm/cancel with no reply channel.
// ─────────────────────────────────────────────────────────────────────────────

class BookingMessageModel {
  final String id;
  final String senderUid;
  final String senderRole; // 'tourist' | 'admin'
  final String text;
  final DateTime? createdAt;

  const BookingMessageModel({
    required this.id,
    required this.senderUid,
    required this.senderRole,
    required this.text,
    this.createdAt,
  });

  factory BookingMessageModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BookingMessageModel(
      id: doc.id,
      senderUid: d['senderUid'] as String? ?? '',
      senderRole: d['senderRole'] as String? ?? 'tourist',
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class BookingMessageService {
  BookingMessageService._();

  static CollectionReference<Map<String, dynamic>> _thread(String bookingId) =>
      FirebaseFirestore.instance
          .collection('Bookings')
          .doc(bookingId)
          .collection('messages');

  static Stream<List<BookingMessageModel>> stream(String bookingId) =>
      _thread(bookingId).orderBy('createdAt').snapshots().map(
          (snap) => snap.docs.map(BookingMessageModel.fromFirestore).toList());

  static Future<void> send(
    String bookingId, {
    required String text,
    required bool isAdmin,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Must be signed in to send a message.');
    return _thread(bookingId).add({
      'senderUid': uid,
      'senderRole': isAdmin ? 'admin' : 'tourist',
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
