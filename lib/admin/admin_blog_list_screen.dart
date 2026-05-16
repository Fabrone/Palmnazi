import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_blog_compose_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminBlogListScreen
//
// Blog management screen inside AdminDashboard (tab index 4).
// Rendered inside the dashboard body — no Scaffold of its own; the parent
// dashboard's _AdminTopBar provides the header.
//
// Features:
//   • Status filter tabs — All / Published / Draft / Scheduled
//   • Search bar (live filter — currently filters client-side; swap the
//     getBlogPosts call for a server-side search when the API supports it)
//   • Infinite scroll pagination via _scrollCtrl
//   • Pull-to-refresh
//   • Post card with thumbnail, status badge, meta, edit + delete actions
//   • Delete confirmation dialog
//   • Navigates to AdminBlogComposeScreen for create / edit
// ─────────────────────────────────────────────────────────────────────────────

class AdminBlogListScreen extends StatefulWidget {
  final AdminApiService apiService;

  const AdminBlogListScreen({super.key, required this.apiService});

  @override
  State<AdminBlogListScreen> createState() => _AdminBlogListScreenState();
}

class _AdminBlogListScreenState extends State<AdminBlogListScreen> {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const _accent     = Color(0xFF14FFEC);
  //static const _blogColor  = Color(0xFFE91E8C);

  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _posts     = [];
  bool   _loading     = true;
  bool   _loadingMore = false;
  String? _error;

  String _statusFilter = 'ALL';  // ALL | PUBLISHED | DRAFT | SCHEDULED
  int    _page         = 1;
  int    _totalPages   = 1;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

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
    _scrollCtrl.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Scroll / search listeners ──────────────────────────────────────────────

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 160 &&
        !_loadingMore &&
        _page < _totalPages) {
      _loadMore();
    }
  }

  void _onSearchChanged() => _load(reset: true);

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading    = true;
        _error      = null;
        _page       = 1;
        _posts      = [];
      });
    }
    try {
      final status = _statusFilter == 'ALL' ? null : _statusFilter;
      final result = await widget.apiService.getBlogPosts(
        page:   _page,
        limit:  20,
        status: status,
      );

      final fetched    = (result['posts'] as List).cast<Map<String, dynamic>>();
      final totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;

      // Client-side search filter (replace with server ?search= when available)
      final query = _searchCtrl.text.trim().toLowerCase();
      final filtered = query.isEmpty
          ? fetched
          : fetched.where((p) {
              final t = (p['title']   as String? ?? '').toLowerCase();
              final e = (p['excerpt'] as String? ?? '').toLowerCase();
              return t.contains(query) || e.contains(query);
            }).toList();

      if (mounted) {
        setState(() {
          _posts       = reset ? filtered : [..._posts, ...filtered];
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

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final slug  = post['slug']  as String?;
    final title = post['title'] as String? ?? 'this post';
    if (slug == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            children: [
              const TextSpan(text: 'Delete '),
              TextSpan(
                text: '"$title"',
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                  text: '?\n\nThis is a soft delete — the post is archived '
                      'and can be permanently removed later.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.apiService.deleteBlogPost(slug);
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p['slug'] == slug));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"$title" has been deleted.'),
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

  // ── Navigate to compose ────────────────────────────────────────────────────

  Future<void> _openCompose({Map<String, dynamic>? post}) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminBlogComposeScreen(
          apiService:   widget.apiService,
          existingPost: post,
        ),
        fullscreenDialog: post == null, // create → slide-up; edit → push
      ),
    );
    if (refreshed == true) _load(reset: true);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Toolbar ─────────────────────────────────────────────────────────
      _BlogToolbar(
        searchCtrl:      _searchCtrl,
        statusFilter:    _statusFilter,
        onFilterChanged: (s) {
          setState(() => _statusFilter = s);
          _load(reset: true);
        },
        onNewPost: () => _openCompose(),
      ),

      // ── Body ────────────────────────────────────────────────────────────
      Expanded(child: _buildBody()),
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
            post:     _posts[i],
            onEdit:   () => _openCompose(post: _posts[i]),
            onDelete: () => _deletePost(_posts[i]),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar — search bar, status filters, new-post button
// ─────────────────────────────────────────────────────────────────────────────

class _BlogToolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String statusFilter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onNewPost;

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1 — search + button
        Row(children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search posts by title or excerpt…',
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 13),
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
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
  final String label;
  final bool isSelected;
  final Color color;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

  const _PostCard({
    required this.post,
    required this.onEdit,
    required this.onDelete,
  });

  static const _blogColor = Color(0xFFE91E8C);

  // ── Status helpers ─────────────────────────────────────────────────────────

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'PUBLISHED': return Colors.greenAccent;
      case 'SCHEDULED': return Colors.blueAccent;
      default:          return Colors.white38;      // DRAFT / unknown
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
    final categories   = (post['categories']  as List?)?.cast<String>() ?? [];
    final tags         = (post['tags']        as List?)?.cast<String>() ?? [];
    final stats        = post['stats']        as Map<String, dynamic>?;

    final author     = post['author'] as Map<String, dynamic>?;
    final authorName = author != null
        ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim()
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
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Main content row ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Thumbnail
            _Thumbnail(url: featuredImg),

            const SizedBox(width: 14),

            // Text area
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Badges row
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
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
                    if (stats?['views'] != null)
                      _Badge(
                        icon:  Icons.visibility_outlined,
                        label: '${stats!['views']}',
                        color: Colors.white24,
                      ),
                  ],
                ),

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

        // ── Chips row ────────────────────────────────────────────────────
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

        // ── Footer bar ───────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(children: [
            // Author
            if (authorName.isNotEmpty)
              _MetaItem(
                  icon: Icons.person_outline_rounded,
                  label: authorName),

            // Date
            if (dateLabel.isNotEmpty) ...[
              if (authorName.isNotEmpty) const SizedBox(width: 10),
              _MetaItem(
                  icon: Icons.calendar_today_rounded,
                  label: dateLabel),
            ],

            // Reading time
            if (readingTime != null) ...[
              const SizedBox(width: 10),
              _MetaItem(
                  icon:  Icons.timer_outlined,
                  label: '${readingTime}m'),
            ],

            const Spacer(),

            // Slug
            if (slug.isNotEmpty)
              Text('/$slug',
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 10)),

            const SizedBox(width: 12),

            // Edit button
            _ActionBtn(
              icon:  Icons.edit_rounded,
              label: 'Edit',
              color: const Color(0xFF14FFEC),
              onTap: onEdit,
            ),

            const SizedBox(width: 6),

            // Delete button
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
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 80,
        height: 80,
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
  final String label;
  final Color color;

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
  final Color color;
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
  final String label;
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
  final IconData icon;
  final String label;
  final Color color;
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
  final String filter;
  final VoidCallback onNewPost;
  const _EmptyState({required this.filter, required this.onNewPost});

  @override
  Widget build(BuildContext context) {
    final isAll = filter == 'ALL';
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
              isAll
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
                : 'No ${filter.toLowerCase()} posts',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isAll
                ? 'Hit "New Post" to write your first article.'
                : 'Try switching the filter above.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.5),
          ),
          if (isAll) ...[
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
  final String message;
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