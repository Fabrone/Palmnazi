import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'package:palmnazi/models/blog_post_detail.dart';
import 'package:palmnazi/models/blog_post_details_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/services/analytics_service.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/blog_post_details_service.dart';
import 'package:palmnazi/services/blog_post_service.dart';
import 'package:palmnazi/services/place_lookup_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BlogPostDetailScreen
//
// The public-facing blog post reading page — previously missing entirely
// (the landing page only ever showed excerpt cards). Fetches full content
// via BlogPostService (public, no-auth), renders it read-only through the
// same Quill/HTML pipeline the admin compose screen writes with, and
// surfaces the admin-configurable extras from BlogPostDetailsService:
// featured/paid-advert badges and "related to this story" links to resort
// cities and places (the internal-linking requirement).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color navy = Color(0xFF121F2E);
  static const Color deepBlue = Color(0xFF1C2E42);
  static const Color surface = Color(0xFF23374D);
  static const Color gold = Color(0xFFD4AF37);
  static const Color teal = Color(0xFF3FA9C4);
  static const Color textSec = Color(0xFFC7D6E3);
  static const Color textMute = Color(0xFF7C93A8);
}

class BlogPostDetailScreen extends StatefulWidget {
  final String slug;
  const BlogPostDetailScreen({super.key, required this.slug});

  @override
  State<BlogPostDetailScreen> createState() => _BlogPostDetailScreenState();
}

class _BlogPostDetailScreenState extends State<BlogPostDetailScreen> {
  BlogPostDetail? _post;
  bool _loading = true;
  String? _error;

  List<BlogComment> _comments = [];
  bool _loadingComments = true;
  final _commentCtrl = TextEditingController();
  bool _submittingComment = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final post = await BlogPostService.fetchBySlug(widget.slug);
    if (!mounted) return;
    if (post == null) {
      setState(() {
        _loading = false;
        _error = 'This story could not be found.';
      });
      return;
    }
    setState(() {
      _post = post;
      _loading = false;
    });
    BlogPostService.trackView(widget.slug);
    AnalyticsService.logEvent('blog_post_view',
        params: {'slug': widget.slug, 'title': post.title});
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    final comments = await BlogPostService.fetchComments(widget.slug);
    if (mounted) {
      setState(() {
        _comments = comments;
        _loadingComments = false;
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submittingComment = true);
    final ok = await BlogPostService.addComment(widget.slug, text);
    if (mounted) {
      setState(() => _submittingComment = false);
      if (ok) {
        _commentCtrl.clear();
        _loadComments();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not post your comment. Please try again.'),
        ));
      }
    }
  }

  void _share() {
    final post = _post;
    if (post == null) return;
    final url = ApiEndpoints.url('/blog/${post.slug}');
    Share.share('${post.title}\n$url', subject: post.title);
  }

  void _showAuthorPanel() {
    final post = _post;
    if (post == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.deepBlue,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _P.gold.withValues(alpha: 0.15),
                child: Text(
                    post.authorName.isNotEmpty
                        ? post.authorName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: _P.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (post.authorEmail.isNotEmpty)
                      Text(post.authorEmail,
                          style: const TextStyle(
                              color: _P.textMute, fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Text(
                'Writes stories for Palmnazi Resort Cities — guides, '
                'features and updates about resort destinations across '
                'the platform.',
                style: TextStyle(color: _P.textSec, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _openRelatedLink(BlogRelatedLink link) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Loading…'),
      duration: Duration(milliseconds: 600),
    ));
    if (link.type == 'place') {
      final place = await PlaceLookupService.fetchPlace(link.id);
      if (place == null || !mounted) return;
      final cityRaw = <String, dynamic>{
        ...?place.city,
        'id': place.cityId,
        'name': place.cityName.isNotEmpty ? place.cityName : link.label,
      };
      final city = CityModel.fromJson(cityRaw);
      final catLink =
          place.categoryLinks.isNotEmpty ? place.categoryLinks.first : null;
      final category = catLink != null
          ? CategoryModel(
              id: catLink.categoryId,
              name: catLink.categoryName,
              slug: catLink.categorySlug,
              isActive: true,
              sortOrder: 0)
          : const CategoryModel(
              id: '', name: '', slug: '', isActive: false, sortOrder: 0);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceDetailsScreen(
                city: city, category: category, place: place),
          ));
    } else if (link.type == 'city') {
      try {
        final uri = Uri.parse(ApiEndpoints.url('/api/cities/${link.id}'));
        final resp = await http.get(uri).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200 || !mounted) return;
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = (body['data'] ?? body) as Map<String, dynamic>;
        final city = CityModel.fromJson(data);
        if (!mounted) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ResortCityScreen(city: city)));
      } catch (_) {
        // Best-effort — a broken related link just doesn't navigate.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.navy,
      appBar: AppBar(
        backgroundColor: _P.deepBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Story', style: TextStyle(color: Colors.white)),
        actions: [
          if (_post != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.white70),
              onPressed: _share,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _P.gold))
          : _error != null
              ? Center(
                  child:
                      Text(_error!, style: const TextStyle(color: _P.textSec)))
              : _buildBody(_post!),
    );
  }

  Widget _buildBody(BlogPostDetail post) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((post.featuredImage ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(post.featuredImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: _P.surface,
                              child: const Icon(Icons.image_outlined,
                                  color: _P.textMute, size: 48))),
                    ),
                  ),
                const SizedBox(height: 20),
                StreamBuilder<BlogPostDetailsModel>(
                  stream: BlogPostDetailsService.stream(post.slug),
                  builder: (context, snap) {
                    final details = snap.data ?? BlogPostDetailsModel.empty;
                    if (!details.isPaidAdvert) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _P.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: _P.gold.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                            details.sponsorLabel.isNotEmpty
                                ? 'Sponsored by ${details.sponsorLabel}'
                                : 'Sponsored',
                            style: const TextStyle(
                                color: _P.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
                Text(post.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.25)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _showAuthorPanel,
                  child: Row(children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: _P.gold.withValues(alpha: 0.15),
                      child: Text(
                          post.authorName.isNotEmpty
                              ? post.authorName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: _P.gold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Text(post.authorName,
                        style: const TextStyle(
                            color: _P.teal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (post.formattedDate.isNotEmpty) ...[
                      const Text('  ·  ',
                          style: TextStyle(color: _P.textMute, fontSize: 13)),
                      Text(post.formattedDate,
                          style: const TextStyle(
                              color: _P.textMute, fontSize: 13)),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 20),
                _QuillContent(html: post.content),
                const SizedBox(height: 28),
                StreamBuilder<BlogPostDetailsModel>(
                  stream: BlogPostDetailsService.stream(post.slug),
                  builder: (context, snap) {
                    final links =
                        (snap.data ?? BlogPostDetailsModel.empty).relatedLinks;
                    if (links.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Related to This Story',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: links
                                .map((l) => ActionChip(
                                      avatar: Icon(
                                          l.type == 'city'
                                              ? Icons.location_city_rounded
                                              : Icons.storefront_rounded,
                                          size: 15,
                                          color: _P.teal),
                                      label: Text(l.label),
                                      labelStyle: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                      backgroundColor: _P.surface,
                                      side: const BorderSide(
                                          color: Colors.white12),
                                      onPressed: () => _openRelatedLink(l),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 20),
                _buildComments(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Share your thoughts…',
                hintStyle: const TextStyle(color: _P.textMute, fontSize: 13),
                filled: true,
                fillColor: _P.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _submittingComment ? null : _submitComment,
            icon: _submittingComment
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _P.gold))
                : const Icon(Icons.send_rounded, color: _P.gold),
          ),
        ]),
        const SizedBox(height: 16),
        if (_loadingComments)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: _P.gold, strokeWidth: 2),
          ))
        else if (_comments.isEmpty)
          const Text('Be the first to comment.',
              style: TextStyle(color: _P.textMute, fontSize: 12))
        else
          ..._comments.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _P.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.authorName,
                          style: const TextStyle(
                              color: _P.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(c.content,
                          style: const TextStyle(
                              color: _P.textSec, fontSize: 13, height: 1.4)),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Read-only render of the post's stored HTML content, via the same
// HTML ⇄ Delta pipeline admin_blog_compose_screen.dart writes with. ────────
class _QuillContent extends StatelessWidget {
  final String html;
  const _QuillContent({required this.html});

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return const Text('This story has no content yet.',
          style: TextStyle(color: _P.textMute, fontSize: 13));
    }
    late final QuillController controller;
    try {
      final delta = HtmlToDelta().convert(html);
      controller = QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      return Text(html,
          style: const TextStyle(color: _P.textSec, fontSize: 15, height: 1.7));
    }
    return QuillEditor(
      controller: controller,
      focusNode: FocusNode(canRequestFocus: false),
      scrollController: ScrollController(),
      config: const QuillEditorConfig(
        padding: EdgeInsets.zero,
        autoFocus: false,
        expands: false,
        scrollable: false,
        showCursor: false,
        customStyles: DefaultStyles(
          paragraph: DefaultTextBlockStyle(
            TextStyle(color: _P.textSec, fontSize: 15, height: 1.7),
            HorizontalSpacing(0, 0),
            VerticalSpacing(6, 6),
            VerticalSpacing(0, 0),
            null,
          ),
        ),
      ),
    );
  }
}
