import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/contact_message_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactMessageService
//
// Create is public from the client (see firestore.rules), submitted from
// contact_screen.dart. Read is MainAdmin-only — streamAll() backs
// admin_contact_messages_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────

class ContactMessageService {
  ContactMessageService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('ContactMessages');

  static Future<void> submit(ContactMessageModel message) =>
      _collection.add(message.toCreateMap());

  /// Live list of every submitted message, newest first — MainAdmin Messages
  /// tab. Firestore rules already restrict read access to MainAdmin.
  static Stream<List<ContactMessageModel>> streamAll() {
    return _collection.orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs
            .map((d) => ContactMessageModel.fromFirestore(d))
            .toList());
  }
}
