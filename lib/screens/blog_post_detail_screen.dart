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
import 'package:palmnazi/theme/rc_palette.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/services/analytics_service.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/app_strings.dart';
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
        _error = context.tr('blog_detail_not_found');
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('blog_detail_error_post_comment')),
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
      backgroundColor: RC.deepBlue,
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
                backgroundColor: RC.gold.withValues(alpha: 0.15),
                child: Text(
                    post.authorName.isNotEmpty
                        ? post.authorName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: RC.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName,
                        style: TextStyle(
                            color: RC.textPri,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (post.authorEmail.isNotEmpty)
                      Text(post.authorEmail,
                          style: TextStyle(color: RC.textMute, fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text(context.tr('blog_detail_author_bio'),
                style: TextStyle(color: RC.textSec, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _openRelatedLink(BlogRelatedLink link) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('blog_detail_loading')),
      duration: const Duration(milliseconds: 600),
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
      backgroundColor: RC.navy,
      appBar: AppBar(
        backgroundColor: RC.deepBlue,
        iconTheme: IconThemeData(color: RC.textPri),
        title: Text(context.tr('blog_detail_title'),
            style: TextStyle(color: RC.textPri)),
        actions: [
          if (_post != null)
            IconButton(
              icon: Icon(Icons.share_outlined, color: RC.textSec),
              onPressed: _share,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RC.gold))
          : _error != null
              ? Center(
                  child: Text(_error!, style: TextStyle(color: RC.textSec)))
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
                              color: RC.surface,
                              child: Icon(Icons.image_outlined,
                                  color: RC.textMute, size: 48))),
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
                          color: RC.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: RC.gold.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                            details.sponsorLabel.isNotEmpty
                                ? '${context.tr('blog_detail_sponsored_by_prefix')} ${details.sponsorLabel}'
                                : context.tr('blog_detail_sponsored'),
                            style: const TextStyle(
                                color: RC.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
                Text(post.title,
                    style: TextStyle(
                        color: RC.textPri,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.25)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _showAuthorPanel,
                  child: Row(children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: RC.gold.withValues(alpha: 0.15),
                      child: Text(
                          post.authorName.isNotEmpty
                              ? post.authorName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: RC.gold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Text(post.authorName,
                        style: const TextStyle(
                            color: RC.teal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (post.formattedDate.isNotEmpty) ...[
                      Text('  ·  ',
                          style: TextStyle(color: RC.textMute, fontSize: 13)),
                      Text(post.formattedDate,
                          style: TextStyle(color: RC.textMute, fontSize: 13)),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
                Divider(color: RC.overlay(0.12)),
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
                          Text(context.tr('blog_detail_related_heading'),
                              style: TextStyle(
                                  color: RC.textPri,
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
                                          color: RC.teal),
                                      label: Text(l.label),
                                      labelStyle: TextStyle(
                                          color: RC.textPri, fontSize: 12),
                                      backgroundColor: RC.surface,
                                      side: BorderSide(color: RC.overlay(0.12)),
                                      onPressed: () => _openRelatedLink(l),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Divider(color: RC.overlay(0.12)),
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
        Text(
            '${context.tr('blog_detail_comments_heading')}${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
            style: TextStyle(
                color: RC.textPri, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              style: TextStyle(color: RC.textPri, fontSize: 13),
              decoration: InputDecoration(
                hintText: context.tr('blog_detail_comment_hint'),
                hintStyle: TextStyle(color: RC.textMute, fontSize: 13),
                filled: true,
                fillColor: RC.surface,
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
                        strokeWidth: 2, color: RC.gold))
                : const Icon(Icons.send_rounded, color: RC.gold),
          ),
        ]),
        const SizedBox(height: 16),
        if (_loadingComments)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: RC.gold, strokeWidth: 2),
          ))
        else if (_comments.isEmpty)
          Text(context.tr('blog_detail_no_comments'),
              style: TextStyle(color: RC.textMute, fontSize: 12))
        else
          ..._comments.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RC.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.authorName,
                          style: const TextStyle(
                              color: RC.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(c.content,
                          style: TextStyle(
                              color: RC.textSec, fontSize: 13, height: 1.4)),
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
      return Text(context.tr('blog_detail_no_content'),
          style: TextStyle(color: RC.textMute, fontSize: 13));
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
          style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.7));
    }
    return QuillEditor(
      controller: controller,
      focusNode: FocusNode(canRequestFocus: false),
      scrollController: ScrollController(),
      config: QuillEditorConfig(
        padding: EdgeInsets.zero,
        autoFocus: false,
        expands: false,
        scrollable: false,
        showCursor: false,
        customStyles: DefaultStyles(
          paragraph: DefaultTextBlockStyle(
            TextStyle(color: RC.textSec, fontSize: 15, height: 1.7),
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(6, 6),
            const VerticalSpacing(0, 0),
            null,
          ),
        ),
      ),
    );
  }
}
