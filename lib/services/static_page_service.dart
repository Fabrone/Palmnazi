import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:palmnazi/models/static_page_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaticPageService
//
// Reads/writes the StaticPages collection — see StaticPageModel for the
// shape and why this lives outside the /api contract.
// ─────────────────────────────────────────────────────────────────────────────

class StaticPageService {
  StaticPageService._();

  static const List<String> managedSlugs = [
    'about',
    'privacy-policy',
    'terms-of-service',
    'cookie-policy',
  ];

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('StaticPages');

  static Stream<StaticPageModel?> stream(String slug) => _collection
      .doc(slug)
      .snapshots()
      .map((snap) => snap.exists ? StaticPageModel.fromFirestore(snap) : null);

  static Future<StaticPageModel?> get(String slug) async {
    final snap = await _collection.doc(slug).get();
    return snap.exists ? StaticPageModel.fromFirestore(snap) : null;
  }

  static Future<void> save(StaticPageModel page) {
    final me = FirebaseAuth.instance.currentUser;
    return _collection.doc(page.slug).set({
      ...page.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': me?.email ?? '',
    }, SetOptions(merge: true));
  }
}
