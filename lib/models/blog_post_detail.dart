// ─────────────────────────────────────────────────────────────────────────────
// BlogPostDetail
//
// Full-content blog post — maps to GET /api/blog/{slug}'s "post" object
// (a richer payload than the lean BlogPost card model in landing_page.dart,
// which the list/search endpoints return without `content`).
// ─────────────────────────────────────────────────────────────────────────────

class BlogPostDetail {
  final String id;
  final String slug;
  final String title;
  final String excerpt;
  final String content; // HTML — see admin_blog_compose_screen.dart
  final String? featuredImage;
  final List<String> categories;
  final List<String> tags;
  final String? publishedAt;
  final int views;
  final int likes;
  final int commentCount;
  final Map<String, dynamic>? author;
  final Map<String, dynamic>? city;

  const BlogPostDetail({
    required this.id,
    required this.slug,
    required this.title,
    this.excerpt = '',
    this.content = '',
    this.featuredImage,
    this.categories = const [],
    this.tags = const [],
    this.publishedAt,
    this.views = 0,
    this.likes = 0,
    this.commentCount = 0,
    this.author,
    this.city,
  });

  factory BlogPostDetail.fromJson(Map<String, dynamic> j) {
    final stats = j['stats'] as Map<String, dynamic>?;
    return BlogPostDetail(
      id: j['id'] as String? ?? '',
      slug: j['slug'] as String? ?? '',
      title: j['title'] as String? ?? '',
      excerpt: j['excerpt'] as String? ?? '',
      content: j['content'] as String? ?? '',
      featuredImage: j['featuredImage'] as String?,
      categories: (j['categories'] as List<dynamic>?)
              ?.map((c) => c.toString())
              .toList() ??
          const [],
      tags: (j['tags'] as List<dynamic>?)?.map((c) => c.toString()).toList() ??
          const [],
      publishedAt: j['publishedAt'] as String?,
      views: (stats?['views'] as num?)?.toInt() ?? 0,
      likes: (stats?['likes'] as num?)?.toInt() ?? 0,
      commentCount: (stats?['comments'] as num?)?.toInt() ?? 0,
      author: j['author'] as Map<String, dynamic>?,
      city: j['city'] as Map<String, dynamic>?,
    );
  }

  String get authorName {
    final a = author;
    if (a == null) return 'Staff';
    final profile = a['profile'] as Map<String, dynamic>?;
    final src = profile ?? a;
    final fn = src['firstName'] as String? ?? '';
    final ln = src['lastName'] as String? ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : (a['email'] as String? ?? 'Staff');
  }

  String? get authorId => author?['id'] as String? ?? author?['_id'] as String?;
  String get authorEmail => author?['email'] as String? ?? '';
  String get cityName => (city?['name'] as String?) ?? '';

  String get formattedDate {
    if (publishedAt == null) return '';
    try {
      final dt = DateTime.parse(publishedAt!).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
