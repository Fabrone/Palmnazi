import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactMessageModel
//
// Firestore collection : ContactMessages
// Document ID          : auto-generated
//
// A message submitted through the landing page footer's "Contact Us" form.
// Public write (no sign-in required — a footer contact link must work for a
// visitor who isn't logged in); read/reply is a MainAdmin-only concern for a
// future admin-panel inbox (out of scope for this pass — messages persist
// safely in Firestore either way).
// ─────────────────────────────────────────────────────────────────────────────

class ContactMessageModel {
  final String id;
  final String name;
  final String email;
  final String message;
  final DateTime? createdAt;

  const ContactMessageModel({
    required this.id,
    required this.name,
    required this.email,
    required this.message,
    this.createdAt,
  });

  factory ContactMessageModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ContactMessageModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      email: d['email'] as String? ?? '',
      message: d['message'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'name': name,
        'email': email,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
