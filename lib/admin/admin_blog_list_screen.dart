import 'dart:async';
import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_blog_compose_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminBlogListScreen
//
// Blog management screen inside AdminDashboard (tab index 4).
// Rendered inside the dashboard body — no Scaffold of its own.
//
// Fixed / added vs v1:
//   ✅ Server-side search  — debounced 400 ms → searchBlogPosts()
//      (replaces client-side filter that only searched the already-loaded page)
//   ✅ Full post fetch on edit — getBlogPostBySlug() called before opening
//      compose so the `content` field (omitted by the list endpoint) is
//      always present and the Quill editor pre-fills correctly
//   ✅ Hard delete  — two-step dialog; soft = archive, hard = permanent
//   ✅ Comments     — bottom sheet with getBlogComments() + addBlogComment()
//      including nested reply support
//   ✅ My Drafts    — dedicated filter chip → getBlogDrafts() endpoint
//   ✅ Likes badge  — surfaced from stats.likes on the post card
// ─────────────────────────────────────────────────────────────────────────────

class AdminBlogListScreen extends StatefulWidget {
  final AdminApiService apiService;

  const AdminBlogListScreen({super.key, required this.apiService});

  @override
  State<AdminBlogListScreen> createState() => _AdminBlogListScreenState();
}

class _AdminBlogListScreenState extends State<AdminBlogListScreen> {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const _accent = Color(0xFF14FFEC);

  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _posts = [];
  bool   _loading      = true;
  bool   _loadingMore  = false;
  bool   _fetchingPost = false; // overlay while loading full post before edit
  String? _error;

  // Filter: ALL | PUBLISHED | DRAFT | SCHEDULED | MY_DRAFTS
  String _statusFilter = 'ALL';
  int    _page         = 1;
  int    _totalPages   = 1;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 160 &&
        !_loadingMore &&
        _page < _totalPages) {
      _loadMore();
    }
  }

  /// Debounce keystrokes 400 ms before firing a server-side search.
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _load(reset: true);
    });
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading     = true;
        _error       = null;
        _page        = 1;
        _posts       = [];
      });
    }

    try {
      final query = _searchCtrl.text.trim();
      List<Map<String, dynamic>> fetched;
      int totalPages = 1;

      if (_statusFilter == 'MY_DRAFTS') {
        // ── Dedicated drafts endpoint — returns current user's own drafts only
        fetched    = await widget.apiService.getBlogDrafts();
        totalPages = 1; // endpoint returns all at once, no pagination
      } else if (query.isNotEmpty) {
        // ── Server-side full-text search across all pages
        final result = await widget.apiService.searchBlogPosts(
          query,
          page:  _page,
          limit: 20,
        );
        fetched    = (result['posts'] as List).cast<Map<String, dynamic>>();
        totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;
      } else {
        // ── Standard paginated list with optional status filter
        final status = _statusFilter == 'ALL' ? null : _statusFilter;
        final result = await widget.apiService.getBlogPosts(
          page:   _page,
          limit:  20,
          status: status,
        );
        fetched    = (result['posts'] as List).cast<Map<String, dynamic>>();
        totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;
      }

      if (mounted) {
        setState(() {
          _posts       = reset ? fetched : [..._posts, ...fetched];
          _totalPages  = totalPages;
          _loading     = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error       = e is AdminApiException ? e.message : e.toString();
          _loading     = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() { _loadingMore = true; _page++; });
    await _load();
  }

  Future<void> _refresh() => _load(reset: true);

  // ── Edit — fetch full post (with `content`) before opening compose ──────────

  Future<void> _openCompose({Map<String, dynamic>? post}) async {
    if (post != null) {
      // The list endpoint omits `content`. Always fetch the single-post
      // endpoint so the Quill editor pre-fills with the full HTML body.
      final slug = post['slug'] as String?;
      if (slug == null) return;

      setState(() => _fetchingPost = true);
      Map<String, dynamic>? fullPost;
      try {
        fullPost = await widget.apiService.getBlogPostBySlug(slug);
      } catch (e) {
        if (!mounted) return;
        setState(() => _fetchingPost = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not load post: ${e is AdminApiException ? e.message : e}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      if (!mounted) return;
      setState(() => _fetchingPost = false);

      final refreshed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AdminBlogComposeScreen(
            apiService:   widget.apiService,
            existingPost: fullPost,
          ),
        ),
      );
      if (refreshed == true) _load(reset: true);
    } else {
      // Create mode — no pre-fetch needed
      final refreshed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AdminBlogComposeScreen(
            apiService: widget.apiService,
          ),
        ),
      );
      if (refreshed == true) _load(reset: true);
    }
  }

  // ── Delete — soft (archive) + hard (permanent) ─────────────────────────────

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final slug  = post['slug']  as String?;
    final title = post['title'] as String? ?? 'this post';
    if (slug == null) return;

    // Step 1: Choose mode
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: Colors.white54, fontSize: 13, height: 1.5),
            children: [
              const TextSpan(text: 'How would you like to remove '),
              TextSpan(
                text: '"$title"',
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '?'),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            // Soft delete — archive only
            TextButton.icon(
              icon: const Icon(Icons.archive_outlined, size: 15),
              label: const Text('Archive'),
              style: TextButton.styleFrom(foregroundColor: Colors.white60),
              onPressed: () => Navigator.pop(ctx, 'soft'),
            ),
            const SizedBox(width: 4),
            // Hard delete — irreversible
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.redAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
              icon: const Icon(Icons.delete_forever_rounded, size: 15),
              label: const Text('Permanent',
                  style: TextStyle(fontSize: 12)),
              onPressed: () => Navigator.pop(ctx, 'hard'),
            ),
          ]),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    // Step 2: Extra confirmation for hard delete
    if (choice == 'hard') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Text('Permanent Delete',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ]),
          content: RichText(
            text: const TextSpan(
              style: TextStyle(
                  color: Colors.white54, fontSize: 13, height: 1.5),
              children: [
                TextSpan(
                    text: 'This action is ',
                    style: TextStyle(color: Colors.white54)),
                TextSpan(
                    text: 'IRREVERSIBLE',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700)),
                TextSpan(
                    text:
                        '. The post, all its comments, likes, and view '
                        'history will be permanently erased from the '
                        'database.\n\nAre you absolutely sure?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Delete Permanently'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      if (choice == 'hard') {
        await widget.apiService.deleteBlogPostHard(slug);
      } else {
        await widget.apiService.deleteBlogPost(slug);
      }
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p['slug'] == slug));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(choice == 'hard'
            ? '"$title" permanently deleted.'
            : '"$title" archived.'),
        backgroundColor: const Color(0xFF111827),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            e is AdminApiException ? e.message : 'Delete failed: $e'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Comments bottom sheet ──────────────────────────────────────────────────

  void _showComments(Map<String, dynamic> post) {
    final slug  = post['slug']  as String? ?? '';
    final title = post['title'] as String? ?? 'Post';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        apiService: widget.apiService,
        slug:       slug,
        postTitle:  title,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Column(children: [
        _BlogToolbar(
          searchCtrl:      _searchCtrl,
          statusFilter:    _statusFilter,
          onFilterChanged: (s) {
            setState(() => _statusFilter = s);
            _load(reset: true);
          },
          onNewPost: () => _openCompose(),
        ),
        Expanded(child: _buildBody()),
      ]),

      // ── Translucent overlay while fetching full post before edit
      if (_fetchingPost)
        Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: _accent),
              SizedBox(height: 14),
              Text('Loading post…',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _refresh);
    }
    if (_posts.isEmpty) {
      return _EmptyState(
          filter: _statusFilter, onNewPost: () => _openCompose());
    }

    return RefreshIndicator(
      color: _accent,
      backgroundColor: const Color(0xFF111827),
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
        itemCount: _posts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _posts.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                    color: _accent, strokeWidth: 2),
              ),
            );
          }
          return _PostCard(
            post:       _posts[i],
            onEdit:     () => _openCompose(post: _posts[i]),
            onDelete:   () => _deletePost(_posts[i]),
            onComments: () => _showComments(_posts[i]),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar — search bar, status filter chips, new-post button
// ─────────────────────────────────────────────────────────────────────────────

class _BlogToolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String                statusFilter;
  final ValueChanged<String>  onFilterChanged;
  final VoidCallback          onNewPost;

  const _BlogToolbar({
    required this.searchCtrl,
    required this.statusFilter,
    required this.onFilterChanged,
    required this.onNewPost,
  });

  static const _blogColor = Color(0xFFE91E8C);
  static const _accent    = Color(0xFF14FFEC);

  Color _chipColor(String s) {
    switch (s) {
      case 'PUBLISHED': return Colors.greenAccent;
      case 'DRAFT':     return Colors.white54;
      case 'SCHEDULED': return Colors.blueAccent;
      case 'MY_DRAFTS': return Colors.orangeAccent;
      default:          return _accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // Row 1 — search + new-post button
        Row(children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search posts… (server-side, all pages)',
                hintStyle: const TextStyle(
                    color: Colors.white24, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Colors.white38, size: 18),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: searchCtrl,
                  builder: (_, __, ___) => searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              size: 16, color: Colors.white38),
                          onPressed: searchCtrl.clear,
                        )
                      : const SizedBox.shrink(),
                ),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _accent, width: 1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _blogColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 11),
            ),
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('New Post',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            onPressed: onNewPost,
          ),
        ]),

        const SizedBox(height: 14),

        // Row 2 — status filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in const {
              'ALL':       'All Posts',
              'PUBLISHED': 'Published',
              'DRAFT':     'Drafts',
              'SCHEDULED': 'Scheduled',
              'MY_DRAFTS': 'My Drafts',
            }.entries)
              _FilterChip(
                label:      entry.value,
                isSelected: statusFilter == entry.key,
                color:      _chipColor(entry.key),
                onTap:      () => onFilterChanged(entry.key),
              ),
          ]),
        ),

        const SizedBox(height: 2),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String    label;
  final bool      isSelected;
  final Color     color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8, bottom: 12),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.5)
                  : Colors.white12,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color: isSelected ? color : Colors.white38,
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              )),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComments;

  const _PostCard({
    required this.post,
    required this.onEdit,
    required this.onDelete,
    required this.onComments,
  });

  static const _blogColor = Color(0xFFE91E8C);

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'PUBLISHED': return Colors.greenAccent;
      case 'SCHEDULED': return Colors.blueAccent;
      default:          return Colors.white38;
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toUpperCase()) {
      case 'PUBLISHED': return Icons.public_rounded;
      case 'SCHEDULED': return Icons.schedule_rounded;
      default:          return Icons.drafts_rounded;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
          '-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title        = post['title']        as String? ?? 'Untitled';
    final excerpt      = post['excerpt']      as String? ?? '';
    final slug         = post['slug']         as String? ?? '';
    final status       = post['status']       as String? ?? 'DRAFT';
    final featuredImg  = post['featuredImage'] as String?;
    final readingTime  = post['readingTimeMinutes'];
    final publishedAt  = post['publishedAt']  as String?;
    final scheduledFor = post['scheduledFor'] as String?;
    final categories   =
        (post['categories'] as List?)?.cast<String>() ?? [];
    final tags = (post['tags'] as List?)?.cast<String>() ?? [];
    final stats = post['stats'] as Map<String, dynamic>?;

    // Engagement counts from stats payload
    final viewCount    = (stats?['views']    as num?)?.toInt() ?? 0;
    final likeCount    = (stats?['likes']    as num?)?.toInt() ?? 0;
    final commentCount = (stats?['comments'] as num?)?.toInt() ?? 0;

    final author     = post['author'] as Map<String, dynamic>?;
    final authorName = author != null
        ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'
            .trim()
        : '';

    final city     = post['city'] as Map<String, dynamic>?;
    final cityName = city?['name'] as String?;

    final statusColor = _statusColor(status);

    String dateLabel = '';
    if (status.toUpperCase() == 'SCHEDULED' && scheduledFor != null) {
      dateLabel = 'Scheduled ${_formatDate(scheduledFor)}';
    } else if (publishedAt != null) {
      dateLabel = _formatDate(publishedAt);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Main content row ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _Thumbnail(url: featuredImg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Badges row — status + city + engagement
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _Badge(
                    icon:  _statusIcon(status),
                    label: _capitalize(status),
                    color: statusColor,
                  ),
                  if (cityName != null)
                    _Badge(
                      icon:  Icons.location_city_rounded,
                      label: cityName,
                      color: Colors.white38,
                    ),
                  if (viewCount > 0)
                    _Badge(
                      icon:  Icons.visibility_outlined,
                      label: '$viewCount',
                      color: Colors.white24,
                    ),
                  if (likeCount > 0)
                    _Badge(
                      icon:  Icons.favorite_border_rounded,
                      label: '$likeCount',
                      color: Colors.pinkAccent,
                    ),
                ]),

                const SizedBox(height: 8),

                // Title
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),

                if (excerpt.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.4)),
                ],
              ]),
            ),
          ]),
        ),

        // ── Category / tag chips ──────────────────────────────────────
        if (categories.isNotEmpty || tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final c in categories.take(4))
                  _Chip(label: c, color: _blogColor),
                for (final t in tags.take(3))
                  _Chip(label: '#$t', color: Colors.white38),
              ]),
            ),
          ),

        // ── Footer bar ────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(children: [
            if (authorName.isNotEmpty)
              _MetaItem(
                  icon: Icons.person_outline_rounded,
                  label: authorName),

            if (dateLabel.isNotEmpty) ...[
              if (authorName.isNotEmpty) const SizedBox(width: 10),
              _MetaItem(
                  icon: Icons.calendar_today_rounded,
                  label: dateLabel),
            ],

            if (readingTime != null) ...[
              const SizedBox(width: 10),
              _MetaItem(
                  icon: Icons.timer_outlined,
                  label: '${readingTime}m read'),
            ],

            const Spacer(),

            // Slug
            if (slug.isNotEmpty)
              Text('/$slug',
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 10)),

            const SizedBox(width: 10),

            // Comments button (with count badge when non-zero)
            _ActionBtn(
              icon: Icons.chat_bubble_outline_rounded,
              label: commentCount > 0
                  ? 'Comments ($commentCount)'
                  : 'Comments',
              color: Colors.white54,
              onTap: onComments,
            ),

            const SizedBox(width: 6),

            // Edit
            _ActionBtn(
              icon:  Icons.edit_rounded,
              label: 'Edit',
              color: const Color(0xFF14FFEC),
              onTap: onEdit,
            ),

            const SizedBox(width: 6),

            // Delete (opens soft/hard dialog)
            _ActionBtn(
              icon:  Icons.delete_outline_rounded,
              label: 'Delete',
              color: Colors.redAccent,
              onTap: onDelete,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comments bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final AdminApiService apiService;
  final String          slug;
  final String          postTitle;

  const _CommentsSheet({
    required this.apiService,
    required this.slug,
    required this.postTitle,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const _accent = Color(0xFF14FFEC);

  List<Map<String, dynamic>> _comments    = [];
  bool   _loading     = true;
  bool   _submitting  = false;
  bool   _loadingMore = false;
  String? _error;
  int    _page        = 1;
  int    _totalPages  = 1;
  int    _total       = 0;

  // Reply-to context: null = top-level comment, set = reply
  Map<String, dynamic>? _replyTo;

  final _commentCtrl = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _inputFocus  = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadComments(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 100 &&
        !_loadingMore &&
        _page < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _loadComments({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading  = true;
        _error    = null;
        _page     = 1;
        _comments = [];
      });
    }
    try {
      final result = await widget.apiService
          .getBlogComments(widget.slug, page: _page, limit: 20);
      final fetched =
          (result['comments'] as List).cast<Map<String, dynamic>>();
      final totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;
      final total      = (result['total']      as num?)?.toInt() ?? fetched.length;

      if (mounted) {
        setState(() {
          _comments    = reset ? fetched : [..._comments, ...fetched];
          _totalPages  = totalPages;
          _total       = total;
          _loading     = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error       = e is AdminApiException ? e.message : e.toString();
          _loading     = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() { _loadingMore = true; _page++; });
    await _loadComments();
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await widget.apiService.addBlogComment(
        widget.slug,
        text,
        parentId: _replyTo?['id'] as String?,
      );
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _submitting = false;
        _replyTo    = null;
      });
      // Reload from page 1 to reflect the new comment
      await _loadComments(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is AdminApiException
            ? e.message
            : 'Failed to post comment'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize:     0.40,
      maxChildSize:     0.95,
      snap:             true,
      snapSizes:        const [0.40, 0.72, 0.95],
      builder: (_, sheetCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // ── Drag handle ────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  color: Color(0xFF14FFEC), size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Comments${_total > 0 ? ' ($_total)' : ''}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.07),
          ),

          // ── Comment list ───────────────────────────────────────────
          Expanded(child: _buildList(sheetCtrl)),

          // ── Reply-to banner ────────────────────────────────────────
          if (_replyTo != null) _ReplyBanner(
            replyTo:     _replyTo!,
            onCancel:    _cancelReply,
          ),

          // ── Input row ──────────────────────────────────────────────
          _CommentInput(
            ctrl:        _commentCtrl,
            focusNode:   _inputFocus,
            submitting:  _submitting,
            onSubmit:    _submitComment,
            hintText:    _replyTo != null
                ? 'Write a reply…'
                : 'Add a comment…',
          ),
        ]),
      ),
    );
  }

  Widget _buildList(ScrollController ctrl) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 32),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _loadComments(reset: true),
              child: const Text('Retry',
                  style: TextStyle(color: _accent)),
            ),
          ]),
        ),
      );
    }
    if (_comments.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined,
              color: Colors.white24, size: 36),
          SizedBox(height: 12),
          Text('No comments yet.',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          SizedBox(height: 6),
          Text('Be the first to comment below.',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ]),
      );
    }

    return ListView.builder(
      controller:  ctrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount:   _comments.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _comments.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: CircularProgressIndicator(
                    color: _accent, strokeWidth: 2)),
          );
        }
        return _CommentTile(
          comment:    _comments[i],
          onReply:    () => _startReply(_comments[i]),
        );
      },
    );
  }
}

// ── Comment tile (shows top-level comment + its nested replies) ──────────────

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final VoidCallback          onReply;

  const _CommentTile({required this.comment, required this.onReply});

  @override
  Widget build(BuildContext context) {
    final author  = comment['author'] as Map<String, dynamic>?;
    final name    = author != null
        ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim()
        : 'Anonymous';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final content  = comment['content']   as String? ?? '';
    final createdAt = comment['createdAt'] as String?;
    final replies  = (comment['replies'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];

    String timeLabel = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeLabel = '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
            '-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        timeLabel = createdAt.split('T').first;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main comment ─────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Author row
            Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor:
                    const Color(0xFF14FFEC).withValues(alpha: 0.15),
                child: Text(initials,
                    style: const TextStyle(
                        color: Color(0xFF14FFEC),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              if (timeLabel.isNotEmpty)
                Text(timeLabel,
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 10)),
            ]),
            const SizedBox(height: 8),
            // Content
            Text(content,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.45)),
            const SizedBox(height: 8),
            // Reply button
            GestureDetector(
              onTap: onReply,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.reply_rounded,
                    size: 13, color: Color(0xFF14FFEC)),
                SizedBox(width: 4),
                Text('Reply',
                    style: TextStyle(
                        color: Color(0xFF14FFEC), fontSize: 11)),
              ]),
            ),
          ]),
        ),

        // ── Nested replies ────────────────────────────────────────────
        if (replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Column(
              children: replies.map((r) {
                final rAuthor = r['author'] as Map<String, dynamic>?;
                final rName   = rAuthor != null
                    ? '${rAuthor['firstName'] ?? ''} '
                        '${rAuthor['lastName'] ?? ''}'.trim()
                    : 'Anonymous';
                final rInitial = rName.isNotEmpty
                    ? rName[0].toUpperCase()
                    : '?';
                final rContent = r['content'] as String? ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.08),
                      child: Text(rInitial,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(rName,
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(rContent,
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                height: 1.4)),
                      ]),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 6),
      ],
    );
  }
}

// ── Reply banner ──────────────────────────────────────────────────────────────

class _ReplyBanner extends StatelessWidget {
  final Map<String, dynamic> replyTo;
  final VoidCallback          onCancel;

  const _ReplyBanner({required this.replyTo, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final author = replyTo['author'] as Map<String, dynamic>?;
    final name   = author != null
        ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim()
        : 'someone';

    return Container(
      color: const Color(0xFF14FFEC).withValues(alpha: 0.07),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.reply_rounded,
            size: 14, color: Color(0xFF14FFEC)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Replying to $name',
              style: const TextStyle(
                  color: Color(0xFF14FFEC), fontSize: 12)),
        ),
        GestureDetector(
          onTap: onCancel,
          child: const Icon(Icons.close_rounded,
              size: 16, color: Colors.white38),
        ),
      ]),
    );
  }
}

// ── Comment input row ─────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode             focusNode;
  final bool                  submitting;
  final VoidCallback          onSubmit;
  final String                hintText;

  const _CommentInput({
    required this.ctrl,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller:  ctrl,
            focusNode:   focusNode,
            maxLines:    4,
            minLines:    1,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText:  hintText,
              hintStyle: const TextStyle(
                  color: Colors.white24, fontSize: 13),
              filled:    true,
              fillColor: const Color(0xFF0D1117),
              isDense:   true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFF14FFEC), width: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: submitting ? null : onSubmit,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: submitting
                  ? Colors.white12
                  : const Color(0xFF14FFEC).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: submitting
                    ? Colors.white12
                    : const Color(0xFF14FFEC).withValues(alpha: 0.4),
              ),
            ),
            child: submitting
                ? const Center(
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Color(0xFF14FFEC), strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.send_rounded,
                    size: 16, color: Color(0xFF14FFEC)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final String? url;
  const _Thumbnail({this.url});

  static const _blogColor = Color(0xFFE91E8C);

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty && url!.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url!,
          width: 80, height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: _blogColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _blogColor.withValues(alpha: 0.15)),
        ),
        child: const Icon(Icons.article_rounded,
            color: _blogColor, size: 28),
      );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;

  const _Badge(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6, bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500)),
      );
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white38),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
        ],
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String       filter;
  final VoidCallback onNewPost;
  const _EmptyState({required this.filter, required this.onNewPost});

  @override
  Widget build(BuildContext context) {
    final isAll      = filter == 'ALL';
    final isMyDrafts = filter == 'MY_DRAFTS';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFE91E8C).withValues(alpha: 0.07),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFFE91E8C)
                      .withValues(alpha: 0.2)),
            ),
            child: Icon(
              isAll || isMyDrafts
                  ? Icons.article_outlined
                  : Icons.filter_alt_outlined,
              color: const Color(0xFFE91E8C),
              size: 36,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            isAll
                ? 'No blog posts yet'
                : isMyDrafts
                    ? 'No drafts yet'
                    : 'No ${filter.toLowerCase()} posts',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isAll || isMyDrafts
                ? 'Hit "New Post" to write your first article.'
                : 'Try switching the filter above.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white38, fontSize: 13, height: 1.5),
          ),
          if (isAll || isMyDrafts) ...[
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E8C),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Write First Post',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              onPressed: onNewPost,
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 40),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.5)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF14FFEC),
                side: const BorderSide(
                    color: Color(0xFF14FFEC), width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ]),
        ),
      );
}