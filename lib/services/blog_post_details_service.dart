import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/blog_post_details_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BlogPostDetailsService
//
// Reads/writes the BlogPostDetails collection — see BlogPostDetailsModel for
// the shape and why this lives outside the /api/blog contract.
// ─────────────────────────────────────────────────────────────────────────────

class BlogPostDetailsService {
  BlogPostDetailsService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('BlogPostDetails');

  static Future<Map<String, BlogPostDetailsModel>> getAll() async {
    final snap = await _collection.get();
    return {
      for (final doc in snap.docs)
        doc.id: BlogPostDetailsModel.fromFirestore(doc),
    };
  }

  static Stream<BlogPostDetailsModel> stream(String slug) => _collection
      .doc(slug)
      .snapshots()
      .map((snap) => snap.exists
          ? BlogPostDetailsModel.fromFirestore(snap)
          : BlogPostDetailsModel(slug: slug));

  static Future<void> setFeatured(String slug, bool featured) {
    return _collection.doc(slug).set(
      {'isFeatured': featured},
      SetOptions(merge: true),
    );
  }

  static Future<void> save({
    required String slug,
    required bool isFeatured,
    required bool isPaidAdvert,
    required String sponsorLabel,
    required List<BlogRelatedLink> relatedLinks,
  }) {
    return _collection.doc(slug).set({
      'isFeatured': isFeatured,
      'isPaidAdvert': isPaidAdvert,
      'sponsorLabel': sponsorLabel,
      'relatedLinks': relatedLinks.map((l) => l.toMap()).toList(),
    }, SetOptions(merge: true));
  }
}
