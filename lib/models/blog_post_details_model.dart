import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BlogPostDetailsModel
//
// Firestore collection : BlogPostDetails
// Document ID          : the post's slug (one doc per post)
//
// Extends a blog post beyond the /api/blog contract: whether it's featured
// (surfaces first in the blog section), a paid-advert flag/sponsor label for
// business-sponsored posts, and structured "related links" to resort
// cities/places/categories (the internal-linking requirement — implemented
// as structured chips rather than inline rich-text hyperlinks, since posts
// are authored as Quill/HTML and a link picker is far more reliable than
// parsing arbitrary anchor tags out of freeform content).
// Same pattern as CityDetailsModel/CategoryDetailsModel — the /api/blog
// REST contract is frozen.
// ─────────────────────────────────────────────────────────────────────────────

class BlogRelatedLink {
  final String type; // 'city' | 'place' | 'category'
  final String id;
  final String label;

  const BlogRelatedLink(
      {required this.type, required this.id, required this.label});

  factory BlogRelatedLink.fromMap(Map<String, dynamic> m) => BlogRelatedLink(
        type: m['type'] as String? ?? '',
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {'type': type, 'id': id, 'label': label};
}

class BlogPostDetailsModel {
  final String slug;
  final bool isFeatured;
  final bool isPaidAdvert;
  final String sponsorLabel;
  final List<BlogRelatedLink> relatedLinks;

  const BlogPostDetailsModel({
    required this.slug,
    this.isFeatured = false,
    this.isPaidAdvert = false,
    this.sponsorLabel = '',
    this.relatedLinks = const [],
  });

  factory BlogPostDetailsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return BlogPostDetailsModel(
      slug: doc.id,
      isFeatured: d['isFeatured'] as bool? ?? false,
      isPaidAdvert: d['isPaidAdvert'] as bool? ?? false,
      sponsorLabel: d['sponsorLabel'] as String? ?? '',
      relatedLinks: (d['relatedLinks'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(BlogRelatedLink.fromMap)
              .toList() ??
          const [],
    );
  }

  static const empty = BlogPostDetailsModel(slug: '');
}
