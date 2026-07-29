import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/category_details_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CategoryDetailsService
//
// Reads/writes the CategoryDetails collection — see CategoryDetailsModel for
// the shape and why this lives outside the /api/categories contract.
// ─────────────────────────────────────────────────────────────────────────────

class CategoryDetailsService {
  CategoryDetailsService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('CategoryDetails');

  static Future<Map<String, CategoryDetailsModel>> getAll() async {
    final snap = await _collection.get();
    return {
      for (final doc in snap.docs)
        doc.id: CategoryDetailsModel.fromFirestore(doc),
    };
  }

  static Stream<CategoryDetailsModel> stream(String categoryId) =>
      _collection.doc(categoryId).snapshots().map((snap) => snap.exists
          ? CategoryDetailsModel.fromFirestore(snap)
          : CategoryDetailsModel(categoryId: categoryId));

  static Future<void> setScoping({
    required String categoryId,
    required List<String> cityIds,
    required List<String> tags,
  }) {
    return _collection.doc(categoryId).set(
      {'cityIds': cityIds, 'tags': tags},
      SetOptions(merge: true),
    );
  }
}
