import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:palmnazi/models/blog_post_detail.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BlogPostService
//
// Public (no-auth) reads for the tourist-facing blog detail page. Deliberately
// NOT built on AdminApiService — those methods go through ApiClient.authGet,
// which force-signs-out the session on an unrecoverable 401. That's the
// right behaviour for an admin screen, but wrong for an anonymous tourist
// reading a public blog post, so this uses plain http calls instead, same
// pattern as category_screen.dart / resort_city_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────

class BlogComment {
  final String id;
  final String content;
  final String authorName;
  final DateTime? createdAt;

  const BlogComment({
    required this.id,
    required this.content,
    required this.authorName,
    this.createdAt,
  });

  factory BlogComment.fromJson(Map<String, dynamic> j) {
    final author = j['author'] as Map<String, dynamic>?;
    final profile = author?['profile'] as Map<String, dynamic>?;
    final src = profile ?? author ?? const {};
    final fn = src['firstName'] as String? ?? '';
    final ln = src['lastName'] as String? ?? '';
    final full = '$fn $ln'.trim();
    return BlogComment(
      id: j['id'] as String? ?? j['_id'] as String? ?? '',
      content: j['content'] as String? ?? '',
      authorName: full.isNotEmpty
          ? full
          : (author?['email'] as String? ?? 'Guest'),
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'] as String)
          : null,
    );
  }
}

class BlogPostService {
  BlogPostService._();

  static const _timeout = Duration(seconds: 15);

  /// GET /api/blog/{slug} — public read, no auth required.
  static Future<BlogPostDetail?> fetchBySlug(String slug) async {
    final uri = Uri.parse(ApiEndpoints.url('/api/blog/$slug'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final post = body['post'] ?? body['data'] ?? body;
    if (post is! Map<String, dynamic>) return null;
    return BlogPostDetail.fromJson(post);
  }

  static Future<List<BlogComment>> fetchComments(String slug) async {
    final uri = Uri.parse(ApiEndpoints.url('/api/blog/$slug/comments'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = body['comments'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(BlogComment.fromJson).toList();
  }

  /// Best-effort — attaches the caller's token if signed in, but doesn't
  /// require it (the backend decides whether guest comments are allowed).
  static Future<bool> addComment(String slug, String content) async {
    final uri = Uri.parse(ApiEndpoints.url('/api/blog/$slug/comments'));
    final token = await ApiClient.getAccessToken();
    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// Fire-and-forget view tracking.
  static void trackView(String slug) {
    final uri = Uri.parse(ApiEndpoints.url('/api/blog/$slug/views'));
    http.post(uri).timeout(_timeout).catchError((_) => http.Response('', 0));
  }
}
