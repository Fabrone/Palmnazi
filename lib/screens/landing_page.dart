import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/account_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/admin/admin_dashboard.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Design tokens  (unchanged from v1 — kept in one place)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class RC {
  static const Color navy = Color(0xFF010C18);
  static const Color deepBlue = Color(0xFF071829);
  static const Color surface = Color(0xFF0B2135);
  static const Color surfaceHi = Color(0xFF0F2840);
  static const Color teal = Color(0xFF00D4F5);
  static const Color tealMid = Color(0xFF0097B2);
  static const Color tealDark = Color(0xFF006580);
  static const Color gold = Color(0xFFF5A623);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color emerald = Color(0xFF00C98A);
  static const Color textPri = Color(0xFFFFFFFF);
  static const Color textSec = Color(0xFFAFC6D8);
  static const Color textMute = Color(0xFF4E6A7A);

  static const LinearGradient tealGrad =
      LinearGradient(colors: [teal, tealDark]);
  static const LinearGradient heroGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xCC010C18), Color(0xBB071829), Color(0xDD0A2030)],
    stops: [0.0, 0.45, 1.0],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BlogPost model  (public endpoint — no auth)
// ─────────────────────────────────────────────────────────────────────────────
class BlogPost {
  final String id;
  final String title;
  final String slug;
  final String excerpt;
  final String? featuredImage;
  final List<String> categories;
  final int? readingTimeMinutes;
  final int? views;
  final int? likes;
  final String? publishedAt;
  final Map<String, dynamic>? author;
  final Map<String, dynamic>? city;

  const BlogPost({
    required this.id,
    required this.title,
    required this.slug,
    required this.excerpt,
    this.featuredImage,
    this.categories = const [],
    this.readingTimeMinutes,
    this.views,
    this.likes,
    this.publishedAt,
    this.author,
    this.city,
  });

  factory BlogPost.fromJson(Map<String, dynamic> j) => BlogPost(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        excerpt: j['excerpt'] as String? ?? '',
        featuredImage: j['featuredImage'] as String?,
        categories: (j['categories'] as List<dynamic>?)
                ?.map((c) => c.toString())
                .toList() ??
            [],
        readingTimeMinutes: j['readingTimeMinutes'] as int?,
        views: (j['stats'] as Map<String, dynamic>?)?['views'] as int?,
        likes: (j['stats'] as Map<String, dynamic>?)?['likes'] as int?,
        publishedAt: j['publishedAt'] as String?,
        author: j['author'] as Map<String, dynamic>?,
        city: j['city'] as Map<String, dynamic>?,
      );

  String get authorName {
    final a = author;
    if (a == null) return 'Staff';
    final profile = a['profile'] as Map<String, dynamic>?;
    final src = profile ?? a;
    final fn = src['firstName'] as String? ?? '';
    final ln = src['lastName'] as String? ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : 'Staff';
  }

  String get cityName => (city?['name'] as String?) ?? '';

  String get formattedDate {
    if (publishedAt == null) return '';
    try {
      final dt = DateTime.parse(publishedAt!).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search result model  (unified across cities / places / categories)
// ─────────────────────────────────────────────────────────────────────────────
enum _SearchType { city, place, category, blog }

class _SearchResult {
  final String id;
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final _SearchType type;
  final dynamic raw; // CityModel, CategoryModel, or raw map for places

  const _SearchResult({
    required this.id,
    required this.name,
    this.subtitle,
    this.imageUrl,
    required this.type,
    this.raw,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API helpers
// ─────────────────────────────────────────────────────────────────────────────
class _LandingApi {
  static const _timeout = Duration(seconds: 15);

  // ── Cities ─────────────────────────────────────────────────────────────────
  static Future<List<CityModel>> fetchCities() async {
    final uri =
        Uri.parse(ApiEndpoints.url('/api/cities?isActive=true&limit=50'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];
    final List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['cities'] ?? data['data'] ?? <dynamic>[]) as List<dynamic>;
    } else {
      list = [];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map(CityModel.fromJson)
        .where((c) => c.isActive)
        .toList();
  }

  // ── Blog ───────────────────────────────────────────────────────────────────
  static Future<({List<BlogPost> posts, int total})> fetchBlogPosts({
    int limit = 6,
    int page = 1,
  }) async {
    final uri = Uri.parse(
        ApiEndpoints.url('/api/blog?limit=$limit&page=$page&sortBy=publishedAt&order=desc'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return (posts: <BlogPost>[], total: 0);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final posts = body['posts'] as List<dynamic>? ?? [];
    final pagination = body['pagination'] as Map<String, dynamic>?;
    final total = pagination?['total'] as int? ?? posts.length;
    return (
      posts: posts
          .whereType<Map<String, dynamic>>()
          .map(BlogPost.fromJson)
          .toList(),
      total: total,
    );
  }

  // ── All categories (tree) ──────────────────────────────────────────────────
  static Future<List<CategoryModel>> fetchAllCategories() async {
    final uri =
        Uri.parse(ApiEndpoints.url('/api/categories?tree=true&isActive=true'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = body['data'] as List<dynamic>? ??
        body['categories'] as List<dynamic>? ??
        [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CategoryModel.fromJson)
        .toList();
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  static Future<List<_SearchResult>> search(String q, _SearchType type) async {
    final enc = Uri.encodeQueryComponent(q.trim());
    switch (type) {
      case _SearchType.city:
        final uri = Uri.parse(
            ApiEndpoints.url('/api/cities?search=$enc&isActive=true&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) return [];
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = body['data'];
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = (data['cities'] ?? data['data'] ?? []) as List<dynamic>;
        } else {
          list = [];
        }
        return list
            .whereType<Map<String, dynamic>>()
            .map(CityModel.fromJson)
            .where((c) => c.isActive)
            .map((c) => _SearchResult(
                  id: c.id,
                  name: c.name,
                  subtitle: c.country.isNotEmpty
                      ? '${c.region.isNotEmpty ? "${c.region}, " : ""}${c.country}'
                      : null,
                  imageUrl: c.coverImage.isNotEmpty ? c.coverImage : null,
                  type: _SearchType.city,
                  raw: c,
                ))
            .toList();

      case _SearchType.place:
        final uri = Uri.parse(
            ApiEndpoints.url('/api/places?search=$enc&status=ACTIVE&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) return [];
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final places = (body['data'] as List<dynamic>?) ??
            (body['places'] as List<dynamic>?) ??
            [];
        return places
            .whereType<Map<String, dynamic>>()
            .map((p) => _SearchResult(
                  id: p['id'] as String? ?? '',
                  name: p['name'] as String? ?? '',
                  subtitle:
                      (p['city'] as Map<String, dynamic>?)?['name'] as String?,
                  imageUrl: (p['images'] as List<dynamic>?)?.isNotEmpty == true
                      ? (p['images'] as List<dynamic>).first as String?
                      : null,
                  type: _SearchType.place,
                  raw: p,
                ))
            .toList();

      case _SearchType.category:
        final uri = Uri.parse(ApiEndpoints.url(
            '/api/categories?search=$enc&isActive=true&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) return [];
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>?) ??
            (body['categories'] as List<dynamic>?) ??
            [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(CategoryModel.fromJson)
            .map((cat) => _SearchResult(
                  id: cat.id,
                  name: cat.name,
                  subtitle: cat.description,
                  type: _SearchType.category,
                  raw: cat,
                ))
            .toList();

      case _SearchType.blog:
        final uri = Uri.parse(
            ApiEndpoints.url('/api/blog/search?q=$enc&page=1&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) return [];
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final posts = (body['posts'] as List<dynamic>?) ?? [];
        return posts
            .whereType<Map<String, dynamic>>()
            .map(BlogPost.fromJson)
            .map((p) => _SearchResult(
                  id: p.id,
                  name: p.title,
                  subtitle: p.categories.isNotEmpty
                      ? p.categories.join(' · ')
                      : p.cityName.isNotEmpty
                          ? p.cityName
                          : null,
                  imageUrl: p.featuredImage,
                  type: _SearchType.blog,
                  raw: p,
                ))
            .toList();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LandingPage
// ─────────────────────────────────────────────────────────────────────────────
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Auth state (drives navbar button) ─────────────────────────────────────
  bool _isLoggedIn = false;

  // ── Data ──────────────────────────────────────────────────────────────────
  List<CityModel> _cities = [];
  List<BlogPost> _blogPosts = [];
  List<CategoryModel> _cachedCategories = [];   // pre-fetched for instant overlay
  bool _citiesLoading = true;
  bool _blogLoading = true;
  bool _blogLoadingMore = false;
  int _blogPage = 1;
  int _blogTotal = 0;
  String? _citiesError;

  // ── Scroll ────────────────────────────────────────────────────────────────
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  // Scroll-to section keys
  final _citiesKey = GlobalKey();
  final _blogKey = GlobalKey();

  // ── Hero animation ────────────────────────────────────────────────────────
  late AnimationController _heroCtrl;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;

  // ── Section reveal ────────────────────────────────────────────────────────
  late AnimationController _revealCtrl;
  late Animation<double> _revealFade;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // for didChangeAppLifecycleState
    _scrollCtrl.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollCtrl.offset);
    });

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));

    _revealCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _revealFade = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeIn);

    _heroCtrl.forward();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadCities();
    _loadBlog();
    _loadCategories(); // background pre-fetch so the overlay opens instantly
    _loadAuthState();  // check whether a session token exists
  }

  Future<void> _loadAuthState() async {
    final token = await ApiClient.getAccessToken();
    if (mounted) setState(() => _isLoggedIn = token != null && token.isNotEmpty);
  }

  /// Pre-fetches the category tree in the background. The result is cached and
  /// passed directly to [_PublicCategoriesOverlay] so it never needs to fetch.
  Future<void> _loadCategories() async {
    try {
      final cats = await _LandingApi.fetchAllCategories();
      if (mounted) setState(() => _cachedCategories = cats);
    } catch (_) {
      // Silently fail — the overlay will fetch on its own as fallback.
    }
  }

  Future<void> _loadCities() async {
    if (!mounted) return;
    setState(() {
      _citiesLoading = true;
      _citiesError = null;
    });
    try {
      final cities = await _LandingApi.fetchCities();
      if (mounted) {
        setState(() {
          _cities = cities;
          _citiesLoading = false;
        });
        _revealCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _citiesError = e.toString();
          _citiesLoading = false;
        });
      }
    }
  }

  Future<void> _loadBlog() async {
    try {
      final result = await _LandingApi.fetchBlogPosts(
          limit: 6, page: 1);
      if (mounted) {
        setState(() {
          _blogPosts = result.posts;
          _blogTotal = result.total;
          _blogPage = 1;
          _blogLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _blogLoading = false);
    }
  }

  Future<void> _loadMoreBlog() async {
    if (_blogLoadingMore) return;
    final nextPage = _blogPage + 1;
    setState(() => _blogLoadingMore = true);
    try {
      final result = await _LandingApi.fetchBlogPosts(
          limit: 6, page: nextPage);
      if (mounted) {
        setState(() {
          _blogPosts = [..._blogPosts, ...result.posts];
          _blogTotal = result.total;
          _blogPage = nextPage;
          _blogLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _blogLoadingMore = false);
    }
  }

  // ── Navigation helpers ───────────────────────────────────────────────────
  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 550), curve: Curves.easeInOut);
  }

  void _goToCity(CityModel city) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => ResortCityScreen(city: city),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── Categories overlay ────────────────────────────────────────────────────
  void _openCategoriesOverlay() {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            _PublicCategoriesOverlay(preloaded: _cachedCategories),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  // ── Search dialog ─────────────────────────────────────────────────────────
  void _openSearchDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => const _SearchDialog(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _heroCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  /// Refreshes auth state whenever the app returns to the foreground.
  /// This covers edge cases where zone crashes or background tab-switches
  /// prevent the normal post-navigation _loadAuthState() call from running.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadAuthState();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
    final isMobile = w < 600;

    return Scaffold(
      backgroundColor: RC.navy,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              SliverToBoxAdapter(child: _hero(w)),
              SliverToBoxAdapter(child: _citiesSection(w)),
              SliverToBoxAdapter(child: _blogSection(w)),
              SliverToBoxAdapter(child: _statsSection(w)),
              SliverToBoxAdapter(child: _footer(w)),
            ],
          ),
          _navBar(w, navOpacity, isMobile),
        ],
      ),
    );
  }

  Widget _navBar(double w, double opacity, bool isMobile) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: RC.navy.withValues(alpha: opacity > 0.1 ? 0.92 * opacity : 0),
          border: Border(
            bottom:
                BorderSide(color: RC.teal.withValues(alpha: opacity * 0.18)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 28, vertical: 10),
            child: Row(children: [
              _brand(),
              const Spacer(),
              // ── Full nav links (≥ 600 px) ──────────────────────────────────
              if (!isMobile) ...[
                _navLink('Destinations',
                    onTap: () => _scrollToKey(_citiesKey)),
                _navLink('Categories', onTap: _openCategoriesOverlay),
                _navLink('Blog', onTap: () => _scrollToKey(_blogKey)),
                const SizedBox(width: 8),
                _signInButton(),
              ],
              // ── Mobile: always show the account/sign-in icon + hamburger ──
              if (isMobile) ...[
                _signInButtonMobile(),
                const SizedBox(width: 4),
                _menuIconButton(),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _signInButton() {
    if (_isLoggedIn) {
      return GestureDetector(
        onTap: _goToAccount,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14FFEC).withValues(alpha: 0.28),
                blurRadius: 10,
              )
            ],
          ),
          child: const Icon(Icons.person_rounded,
              color: Colors.white, size: 18),
        ),
      );
    }
    return TextButton(
      onPressed: _goToSignIn,
      style: TextButton.styleFrom(
        foregroundColor: RC.textSec,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: const Text('Sign In', style: TextStyle(fontSize: 13)),
    );
  }

  /// Compact account/sign-in widget for the mobile navbar.
  /// Always visible so the user can see their auth state at a glance.
  /// • Logged in  → same teal circle avatar as the desktop button.
  /// • Logged out → a login icon button (no text, saves space next to hamburger).
  Widget _signInButtonMobile() {
    if (_isLoggedIn) {
      // Reuse the full desktop account button — it's already icon-sized.
      return _signInButton();
    }
    return IconButton(
      icon: const Icon(Icons.login_rounded, color: RC.textSec, size: 22),
      onPressed: _goToSignIn,
      splashRadius: 20,
      tooltip: 'Sign In',
    );
  }

  Widget _menuIconButton() => IconButton(
        icon: const Icon(Icons.menu_rounded, color: RC.textSec, size: 22),
        onPressed: _showMobileMenu,
        splashRadius: 20,
        tooltip: 'Menu',
      );

  Future<void> _goToSignIn() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const AuthScreen(isLogin: true),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
    // Re-check login state when returning from AuthScreen
    // (user may have just signed in).
    if (mounted) _loadAuthState();
  }

  void _goToAccount() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const AccountScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
    // Re-check login state when returning from AccountScreen
    // (user may have signed out while there).
    if (mounted) _loadAuthState();
  }

  void _showMobileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: RC.deepBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: RC.textMute,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              _mobileMenuItem(Icons.location_city_outlined, 'Destinations', () {
                Navigator.pop(context);
                _scrollToKey(_citiesKey);
              }),
              _mobileMenuItem(Icons.category_outlined, 'Categories', () {
                Navigator.pop(context);
                _openCategoriesOverlay();
              }),
              _mobileMenuItem(Icons.article_outlined, 'Blog', () {
                Navigator.pop(context);
                _scrollToKey(_blogKey);
              }),
              _mobileMenuItem(Icons.search_rounded, 'Search', () {
                Navigator.pop(context);
                _openSearchDialog();
              }),
              const Divider(color: Color(0xFF1A3550), height: 24),
              if (_isLoggedIn)
                _mobileMenuItem(Icons.person_rounded, 'My Account', () {
                  Navigator.pop(context);
                  _goToAccount();
                })
              else
                _mobileMenuItem(Icons.login_rounded, 'Sign In', () {
                  Navigator.pop(context);
                  _goToSignIn();
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileMenuItem(IconData icon, String label, VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon, color: RC.teal, size: 20),
        title: Text(label,
            style: const TextStyle(color: RC.textSec, fontSize: 14)),
        onTap: onTap,
        dense: true,
      );

  // ── Auth-gated admin navigation ──────────────────────────────────────────
  Future<void> _goToAdminWithAuthCheck() async {
    final accessToken = await ApiClient.getAccessToken();
    final isLoggedIn = accessToken != null && accessToken.isNotEmpty;

    if (isLoggedIn) {
      // Already authenticated — navigate directly.
      if (!mounted) return;
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, anim, __) => const AdminDashboard(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 320),
        ),
      );
      // Refresh auth state in case admin session changed while away.
      if (mounted) _loadAuthState();
    } else {
      // Not logged in — show login screen.
      // NOTE: _navigateToLanding() in AuthScreen calls Navigator.pop(context)
      // which does NOT pass an AuthResult back, so we cannot rely on the return
      // value here to detect a successful login.  Instead we simply re-read the
      // token after the push returns.
      if (!mounted) return;
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, anim, __) => const AuthScreen(isLogin: true),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 320),
        ),
      );

      if (!mounted) return;

      // Re-read the token — if the user just logged in, it will now be present.
      final newToken = await ApiClient.getAccessToken();
      if (!mounted) return;
      _loadAuthState(); // update the navbar icon regardless

      if (newToken != null && newToken.isNotEmpty) {
        // Login succeeded while on AuthScreen — go to admin.
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, anim, __) => const AdminDashboard(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 320),
          ),
        );
      }
      // If the user dismissed AuthScreen without logging in — nothing to do.
    }
  }

  Widget _brand() => Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: _goToAdminWithAuthCheck,
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                    gradient: RC.tealGrad, shape: BoxShape.circle),
                child: const Icon(Icons.travel_explore_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (b) =>
              const LinearGradient(colors: [RC.teal, Colors.white])
                  .createShader(b),
          child: const Text(
            'PALMNAZI RC',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 2),
          ),
        ),
      ]);

  Widget _navLink(String label, {required VoidCallback onTap}) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: RC.textSec,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );


  // ─────────────────────────────────────────────────────────────────────────
  // HERO  — background: assets/images/homepage.jpg + dark overlay
  // ─────────────────────────────────────────────────────────────────────────
  Widget _hero(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;

    return SizedBox(
      height: isMobile ? 640.0 : 740.0,
      child: Stack(
        children: [
          // ── Background image ──────────────────────────────────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/images/homepage.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(gradient: RC.heroGrad),
              ),
            ),
          ),

          // ── Dark gradient overlay (readability) ───────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99010C18),
                    Color(0xBB010C18),
                    Color(0xEE010C18),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // ── Dot grid texture ──────────────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _DotGridPainter(color: RC.teal.withValues(alpha: 0.035)),
            ),
          ),

          // ── Ambient glows ─────────────────────────────────────────────────
          Positioned(
              top: -100,
              right: -60,
              child: _glow(340, RC.teal.withValues(alpha: 0.08))),
          Positioned(
              bottom: 30,
              left: -50,
              child: _glow(260, RC.gold.withValues(alpha: 0.06))),

          // ── Hero content ──────────────────────────────────────────────────
          Positioned.fill(
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(hPad, isMobile ? 110 : 140, hPad, 52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag pill
                  FadeTransition(
                    opacity: _heroFade,
                    child: SlideTransition(
                      position: _heroSlide,
                      child: _tagPill(
                          '✦  Discover Africa\'s Premier Resort Destinations',
                          RC.teal),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Headline
                  FadeTransition(
                    opacity: _heroFade,
                    child: SlideTransition(
                      position: _heroSlide,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: isMobile ? 38 : 62,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                          children: [
                            const TextSpan(text: 'Find Your\n'),
                            TextSpan(
                              text: 'Perfect Escape',
                              style: TextStyle(
                                foreground: Paint()
                                  ..shader = const LinearGradient(
                                    colors: [RC.teal, RC.gold],
                                  ).createShader(
                                      const Rect.fromLTWH(0, 0, 420, 80)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Sub-headline
                  FadeTransition(
                    opacity: _heroFade,
                    child: Text(
                      'Explore handpicked resort cities, luxury stays,\nand unforgettable experiences across Africa.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: isMobile ? 15 : 18,
                        height: 1.65,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 6)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // ── Search trigger row ─────────────────────────────────────
                  FadeTransition(
                    opacity: _heroFade,
                    child: _heroSearchTrigger(isMobile),
                  ),

                  const Spacer(),

                  // ── Quick-nav chips ────────────────────────────────────────
                  FadeTransition(
                    opacity: _heroFade,
                    child: _heroQuickChips(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact search button that floats in the hero and opens the full dialog.
  Widget _heroSearchTrigger(bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main search button
        GestureDetector(
          onTap: _openSearchDialog,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 28,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: RC.deepBlue.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                  color: RC.teal.withValues(alpha: 0.35), width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
                BoxShadow(
                    color: RC.teal.withValues(alpha: 0.12), blurRadius: 24),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_rounded, color: RC.teal, size: 20),
                const SizedBox(width: 12),
                Text(
                  isMobile
                      ? 'Search destinations…'
                      : 'Search cities, places, or categories…',
                  style: const TextStyle(color: RC.textSec, fontSize: 14),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 20),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient:
                          const LinearGradient(colors: [RC.teal, RC.tealMid]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: RC.teal.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: const Text('Search',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Quick-access category/nav pills at the bottom of the hero.
  Widget _heroQuickChips() {
    final chips = [
      (Icons.location_city_outlined, 'Destinations'),
      (Icons.category_outlined, 'Categories'),
      (Icons.hotel_outlined, 'Stays'),
      (Icons.restaurant_outlined, 'Dining'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: chips
          .map((c) => GestureDetector(
                onTap: () {
                  if (c.$2 == 'Destinations') {
                    _scrollToKey(_citiesKey);
                  } else if (c.$2 == 'Categories') {
                    _openCategoriesOverlay();
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(c.$1, size: 14, color: RC.teal),
                    const SizedBox(width: 6),
                    Text(c.$2,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ))
          .toList(),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent])),
      );

  Widget _tagPill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4)),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // RESORT CITIES SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _citiesSection(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;

    return Container(
      key: _citiesKey,
      color: RC.navy,
      padding: EdgeInsets.fromLTRB(hPad, 64, hPad, 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('DESTINATIONS', RC.teal),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      'Explore Resort Cities',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 28 : 38,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (!isMobile)
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_forward_rounded,
                          color: RC.teal, size: 16),
                      label: const Text('View All',
                          style: TextStyle(color: RC.teal, fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Handpicked resort destinations with the best places to stay,\ndine, and experience across Africa.',
                style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 40),
              _buildCitiesBody(w, isMobile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCitiesBody(double w, bool isMobile) {
    if (_citiesLoading) return _citySkeletonGrid(w, isMobile);
    if (_citiesError != null) {
      return Center(
          child: Column(children: [
        const Icon(Icons.cloud_off_rounded, color: RC.textMute, size: 48),
        const SizedBox(height: 14),
        const Text('Could not load destinations',
            style: TextStyle(color: RC.textSec)),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _loadCities,
          icon: const Icon(Icons.refresh_rounded, color: RC.teal, size: 16),
          label: const Text('Try again', style: TextStyle(color: RC.teal)),
        ),
      ]));
    }
    if (_cities.isEmpty) {
      return Center(
          child: Column(children: [
        const Icon(Icons.location_city_outlined, color: RC.textMute, size: 56),
        const SizedBox(height: 16),
        const Text('No destinations available yet',
            style: TextStyle(color: RC.textSec, fontSize: 15)),
      ]));
    }

    return LayoutBuilder(builder: (_, constraints) {
      final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
      const gap = 22.0;
      final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(
            _cities.length,
            (i) => SizedBox(
                  width: cardW,
                  child: FadeTransition(
                    opacity: _revealFade,
                    child: _CityCard(
                        city: _cities[i], onTap: () => _goToCity(_cities[i])),
                  ),
                )),
      );
    });
  }

  Widget _citySkeletonGrid(double w, bool isMobile) {
    final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
    const gap = 22.0;
    return LayoutBuilder(builder: (_, c) {
      final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(
          cols == 1 ? 3 : cols * 2,
          (_) => _SkeletonBox(width: cardW, height: 310, radius: 20),
        ),
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLOG SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _blogSection(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;
    final hasMore = _blogPosts.length < _blogTotal;

    return Container(
      key: _blogKey,
      color: RC.deepBlue,
      padding: EdgeInsets.fromLTRB(hPad, 64, hPad, 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('TRAVEL BLOG', RC.gold),
                        const SizedBox(height: 12),
                        Text(
                          'Travel Inspiration',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 26 : 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _blogTotal > 0
                              ? 'Guides, tips and stories — $_blogTotal articles published.'
                              : 'Guides, tips and stories from our expert travel writers.',
                          style: const TextStyle(
                              color: RC.textSec, fontSize: 15, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile && hasMore) ...[
                    const SizedBox(width: 24),
                    TextButton.icon(
                      onPressed: _blogLoadingMore ? null : _loadMoreBlog,
                      icon: _blogLoadingMore
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: RC.teal, strokeWidth: 2))
                          : const Icon(Icons.expand_more_rounded,
                              color: RC.teal, size: 16),
                      label: const Text('Load More',
                          style: TextStyle(color: RC.teal, fontSize: 13)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 36),
              _buildBlogBody(w, isMobile),
              if (!_blogLoading && _blogPosts.isNotEmpty) ...[
                const SizedBox(height: 28),
                Center(
                  child: hasMore
                      ? _blogLoadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: RC.teal, strokeWidth: 2))
                          : OutlinedButton.icon(
                              onPressed: _loadMoreBlog,
                              icon: const Icon(Icons.expand_more_rounded,
                                  color: RC.teal, size: 18),
                              label: Text(
                                'Load More Articles (${_blogTotal - _blogPosts.length} remaining)',
                                style: const TextStyle(
                                    color: RC.teal, fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: RC.teal.withValues(alpha: 0.40)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30)),
                              ),
                            )
                      : Text(
                          'All ${_blogTotal > 0 ? '$_blogTotal ' : ''}articles loaded',
                          style: const TextStyle(
                              color: RC.textMute, fontSize: 12),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlogBody(double w, bool isMobile) {
    if (_blogLoading) {
      return LayoutBuilder(builder: (_, c) {
        final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
        const gap = 20.0;
        final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(
            isMobile ? 2 : cols * 2,
            (_) => _SkeletonBox(width: cardW, height: 290, radius: 16),
          ),
        );
      });
    }
    if (_blogPosts.isEmpty) {
      return Center(
          child: Column(children: [
        const Icon(Icons.article_outlined, color: RC.textMute, size: 48),
        const SizedBox(height: 12),
        const Text('No blog posts yet.', style: TextStyle(color: RC.textSec)),
        const SizedBox(height: 6),
        const Text('Check back soon for travel guides and inspiration.',
            style: TextStyle(color: RC.textMute, fontSize: 13)),
      ]));
    }
    return LayoutBuilder(builder: (_, constraints) {
      final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
      const gap = 20.0;
      final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: _blogPosts
            .map((post) => SizedBox(
                  width: cardW,
                  child: _BlogCard(post: post),
                ))
            .toList(),
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS SECTION  (moved here from hero)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _statsSection(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;
    final count = _cities.isEmpty ? '10' : '${_cities.length}';

    final items = [
      (Icons.location_city_rounded, '$count+', 'Resort Cities', RC.teal),
      (Icons.place_rounded, '500+', 'Curated Places', RC.gold),
      (Icons.star_rounded, '4.9★', 'Avg. Rating', RC.coral),
      (Icons.people_alt_rounded, '20K+', 'Happy Travellers', RC.emerald),
    ];

    return Container(
      color: RC.navy,
      padding: EdgeInsets.fromLTRB(hPad, 52, hPad, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('BY THE NUMBERS', RC.textSec),
              const SizedBox(height: 24),
              LayoutBuilder(builder: (_, c) {
                final cols = isMobile ? 2 : 4;
                const gap = 16.0;
                final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: items
                      .map((s) => SizedBox(
                            width: cardW,
                            child: _StatCard(
                                icon: s.$1,
                                value: s.$2,
                                label: s.$3,
                                color: s.$4),
                          ))
                      .toList(),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOOTER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _footer(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;

    return Container(
      color: const Color(0xFF010913),
      padding: EdgeInsets.fromLTRB(hPad, 52, hPad, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            children: [
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          _footerBrand(),
                          const SizedBox(height: 32),
                          _footerLinks('Explore', [
                            'Resort Cities',
                            'Categories',
                            'All Places',
                            'Blog'
                          ]),
                          const SizedBox(height: 28),
                          _footerLinks(
                              'Company', ['About Us', 'Contact Us', 'Careers']),
                          const SizedBox(height: 28),
                          _footerLinks(
                              'Legal', ['Privacy Policy', 'Terms of Service']),
                        ])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(flex: 2, child: _footerBrand()),
                          const SizedBox(width: 40),
                          Expanded(
                              child: _footerLinks('Explore', [
                            'Resort Cities',
                            'Categories',
                            'All Places',
                            'Blog'
                          ])),
                          const SizedBox(width: 24),
                          Expanded(
                              child: _footerLinks('Company',
                                  ['About Us', 'Contact Us', 'Careers'])),
                          const SizedBox(width: 24),
                          Expanded(
                              child: _footerLinks('Legal', [
                            'Privacy Policy',
                            'Terms of Service',
                            'Cookie Policy'
                          ])),
                        ]),
              const SizedBox(height: 40),
              Divider(color: Colors.white.withValues(alpha: 0.07)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                        '© 2026 Palmnazi Resort Cities. All rights reserved.',
                        style: TextStyle(color: RC.textMute, fontSize: 12)),
                  ),
                  if (!isMobile)
                    const Text('Made with ❤ for Africa\'s travellers',
                        style: TextStyle(color: RC.textMute, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerBrand() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                  gradient: RC.tealGrad, shape: BoxShape.circle),
              child: const Icon(Icons.travel_explore_rounded,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('PALMNAZI',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 14),
          const Text(
            'Discover Africa\'s most beautiful resort\ndestinations and unforgettable experiences.',
            style: TextStyle(color: RC.textSec, fontSize: 13, height: 1.7),
          ),
        ],
      );

  Widget _footerLinks(String heading, List<String> links) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ...links.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {},
                  child: Text(l,
                      style: const TextStyle(color: RC.textSec, fontSize: 13)),
                ),
              )),
        ],
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatCard  — for the stats section
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard(
      {required this.icon,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: RC.deepBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.1),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: RC.textSec, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchDialog  — floating search dialog  (City / Place / Category)
// ─────────────────────────────────────────────────────────────────────────────
class _SearchDialog extends StatefulWidget {
  const _SearchDialog();

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _ctrl = TextEditingController();
  _SearchType _type = _SearchType.city;
  bool _loading = false;
  bool _searched = false;
  List<_SearchResult> _results = [];
  String? _error;

  static const _labels = {
    _SearchType.city: (
      'City',
      'Search by city name…',
      Icons.location_city_outlined
    ),
    _SearchType.place: ('Place', 'Search by place name…', Icons.place_outlined),
    _SearchType.category: (
      'Category',
      'Search by category name…',
      Icons.category_outlined
    ),
    _SearchType.blog: (
      'Blog',
      'Search articles & guides…',
      Icons.article_outlined
    ),
  };

  Future<void> _doSearch() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _searched = false;
    });
    try {
      final results = await _LandingApi.search(q, _type);
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed. Please try again.';
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;
    final dlgW = isMobile ? w * 0.95 : 560.0;
    final info = _labels[_type]!;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          EdgeInsets.symmetric(horizontal: isMobile ? 12 : 40, vertical: 60),
      child: Container(
        width: dlgW,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78),
        decoration: BoxDecoration(
          color: RC.deepBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RC.teal.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 40,
                offset: const Offset(0, 16)),
            BoxShadow(color: RC.teal.withValues(alpha: 0.08), blurRadius: 40),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
              child: Row(children: [
                const Icon(Icons.search_rounded, color: RC.teal, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Search',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: RC.textMute, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Type selector ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _SearchType.values.map((t) {
                  final selected = t == _type;
                  final l = _labels[t]!;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _type = t;
                      _searched = false;
                      _results = [];
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? RC.teal.withValues(alpha: 0.15)
                            : RC.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? RC.teal.withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(l.$3,
                              size: 14,
                              color: selected ? RC.teal : RC.textMute),
                          const SizedBox(width: 5),
                          Text(l.$1,
                              style: TextStyle(
                                color: selected ? RC.teal : RC.textMute,
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              )),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            // ── Search input ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: RC.surface,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: RC.teal.withValues(alpha: 0.20)),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      onSubmitted: (_) => _doSearch(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: info.$2,
                        hintStyle:
                            const TextStyle(color: RC.textMute, fontSize: 13),
                        prefixIcon: Icon(info.$3, color: RC.teal, size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _loading ? null : _doSearch,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient:
                          const LinearGradient(colors: [RC.teal, RC.tealMid]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: RC.teal.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Results ───────────────────────────────────────────────────────
            Flexible(
              child: _buildResults(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (!_searched && !_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Icon(Icons.travel_explore_rounded,
                color: RC.textMute.withValues(alpha: 0.5), size: 48),
            const SizedBox(height: 10),
            const Text('Type to search across cities, places and categories',
                textAlign: TextAlign.center,
                style: TextStyle(color: RC.textMute, fontSize: 13)),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: CircularProgressIndicator(color: RC.teal, strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: RC.coral, size: 36),
          const SizedBox(height: 10),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: RC.textSec, fontSize: 13)),
        ]),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              color: RC.textMute.withValues(alpha: 0.6), size: 44),
          const SizedBox(height: 12),
          Text(
            'No ${_labels[_type]!.$1.toLowerCase()}s found for "${_ctrl.text.trim()}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: RC.textSec, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different spelling or search term.',
            style: TextStyle(color: RC.textMute, fontSize: 12),
          ),
        ]),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
      itemBuilder: (_, i) {
        final r = _results[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: _resultIcon(r),
          title: Text(r.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          subtitle: r.subtitle != null && r.subtitle!.isNotEmpty
              ? Text(r.subtitle!,
                  style: const TextStyle(color: RC.textMute, fontSize: 11))
              : null,
          trailing: const Icon(Icons.arrow_forward_ios_rounded,
              color: RC.textMute, size: 12),
          onTap: () => _onResultTap(r),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          hoverColor: RC.surfaceHi,
        );
      },
    );
  }

  Widget _resultIcon(_SearchResult r) {
    if (r.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(r.imageUrl!,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconFallback(r.type)),
      );
    }
    return _iconFallback(r.type);
  }

  Widget _iconFallback(_SearchType t) {
    final icon = t == _SearchType.city
        ? Icons.location_city_outlined
        : t == _SearchType.place
            ? Icons.place_outlined
            : t == _SearchType.blog
                ? Icons.article_outlined
                : Icons.category_outlined;
    final color = t == _SearchType.blog ? RC.gold : RC.teal;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _onResultTap(_SearchResult r) {
    Navigator.pop(context);
    switch (r.type) {
      case _SearchType.city:
        if (r.raw is CityModel) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, anim, __) =>
                  ResortCityScreen(city: r.raw as CityModel),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 350),
            ),
          );
        }
      case _SearchType.place:
        // Navigate to place detail when screen is available
        break;
      case _SearchType.category:
        // Navigate to category listing when screen is available
        break;
      case _SearchType.blog:
        // Navigate to blog post detail when screen is available
        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PublicCategoriesOverlay  — full-screen categories listing from backend
// ─────────────────────────────────────────────────────────────────────────────
class _PublicCategoriesOverlay extends StatefulWidget {
  final List<CategoryModel> preloaded;
  const _PublicCategoriesOverlay({this.preloaded = const []});

  @override
  State<_PublicCategoriesOverlay> createState() =>
      _PublicCategoriesOverlayState();
}

class _PublicCategoriesOverlayState extends State<_PublicCategoriesOverlay> {
  List<CategoryModel> _roots = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expanded = {};
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.preloaded.isNotEmpty) {
      // Data is already here — show instantly, no spinner.
      _roots = List.of(widget.preloaded);
      _loading = false;
      if (_roots.length <= 6) _expanded.addAll(_roots.map((r) => r.id));
    } else {
      _fetch(); // fallback: pre-fetch hadn't finished yet
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roots = await _LandingApi.fetchAllCategories();
      if (mounted) {
        setState(() {
          _roots = roots;
          _loading = false;
          // Auto-expand all if there are 6 or fewer root categories
          if (roots.length <= 6) _expanded.addAll(roots.map((r) => r.id));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<CategoryModel> get _filtered {
    if (_query.trim().isEmpty) return _roots;
    final q = _query.toLowerCase();
    return _roots.where((r) {
      if (r.name.toLowerCase().contains(q)) return true;
      return r.children.any((c) => c.name.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;

    return Scaffold(
      backgroundColor: RC.navy,
      appBar: AppBar(
        backgroundColor: RC.deepBlue,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: RC.textSec),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Categories',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text('Browse all system categories',
                style: TextStyle(color: RC.textMute, fontSize: 11)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: RC.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RC.teal.withValues(alpha: 0.20)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Filter categories…',
                  hintStyle: TextStyle(color: RC.textMute, fontSize: 13),
                  prefixIcon:
                      Icon(Icons.search_rounded, color: RC.teal, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(isMobile),
    );
  }

  Widget _buildBody(bool isMobile) {
    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SkeletonBox(width: double.infinity, height: 68, radius: 14),
        ),
      );
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, color: RC.textMute, size: 48),
        const SizedBox(height: 14),
        const Text('Could not load categories',
            style: TextStyle(color: RC.textSec)),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _fetch,
          icon: const Icon(Icons.refresh_rounded, color: RC.teal, size: 16),
          label: const Text('Try again', style: TextStyle(color: RC.teal)),
        ),
      ]));
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded,
            color: RC.textMute.withValues(alpha: 0.6), size: 44),
        const SizedBox(height: 12),
        Text(
          _query.isEmpty
              ? 'No categories available yet'
              : 'No categories match "$_query"',
          style: const TextStyle(color: RC.textSec, fontSize: 14),
        ),
      ]));
    }

    return ListView.builder(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 16),
      itemCount: list.length,
      itemBuilder: (_, i) => _RootCategoryTile(
        root: list[i],
        expanded: _expanded.contains(list[i].id),
        onToggle: (id) => setState(() {
          if (_expanded.contains(id)) {
            _expanded.remove(id);
          } else {
            _expanded.add(id);
          }
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RootCategoryTile  (used in public categories overlay)
// ─────────────────────────────────────────────────────────────────────────────
class _RootCategoryTile extends StatelessWidget {
  final CategoryModel root;
  final bool expanded;
  final void Function(String id) onToggle;

  const _RootCategoryTile(
      {required this.root, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: RC.deepBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          // ── Root row ─────────────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: root.children.isNotEmpty ? () => onToggle(root.id) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                // Icon badge
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: RC.teal.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: root.icon != null && root.icon!.length == 2
                        ? Text(root.icon!, style: const TextStyle(fontSize: 18))
                        : const Icon(Icons.category_outlined,
                            color: RC.teal, size: 18),
                  ),
                ),
                const SizedBox(width: 14),

                // Name + child count
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(root.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (root.description != null &&
                        root.description!.isNotEmpty)
                      Text(root.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: RC.textMute, fontSize: 11)),
                  ],
                )),

                // Child count pill
                if (root.children.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: RC.teal.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: RC.teal.withValues(alpha: 0.25)),
                    ),
                    child: Text('${root.children.length}',
                        style: const TextStyle(
                            color: RC.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: RC.textMute,
                    size: 20,
                  ),
                ],
              ]),
            ),
          ),

          // ── Children ────────────────────────────────────────────────────
          if (expanded && root.children.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: Column(
                children: root.children
                    .map((child) => ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.fromLTRB(68, 0, 16, 0),
                          leading: child.icon != null && child.icon!.length == 2
                              ? Text(child.icon!,
                                  style: const TextStyle(fontSize: 14))
                              : const Icon(
                                  Icons.subdirectory_arrow_right_rounded,
                                  color: RC.textMute,
                                  size: 14),
                          title: Text(child.name,
                              style: const TextStyle(
                                  color: RC.textSec, fontSize: 13)),
                          subtitle: child.placeLinksCount > 0
                              ? Text('${child.placeLinksCount} places',
                                  style: const TextStyle(
                                      color: RC.textMute, fontSize: 11))
                              : null,
                          onTap: () {},
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CityCard
// ─────────────────────────────────────────────────────────────────────────────
class _CityCard extends StatefulWidget {
  final CityModel city;
  final VoidCallback onTap;
  const _CityCard({required this.city, required this.onTap});

  @override
  State<_CityCard> createState() => _CityCardState();
}

class _CityCardState extends State<_CityCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _scale;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 1.025)
        .animate(CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _hoverCtrl.forward();
        setState(() => _hovered = true);
      },
      onExit: (_) {
        _hoverCtrl.reverse();
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _hovered
                      ? RC.teal.withValues(alpha: 0.20)
                      : Colors.black.withValues(alpha: 0.35),
                  blurRadius: _hovered ? 28 : 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: city.coverImage.isNotEmpty
                        ? Image.network(city.coverImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _gradientFallback())
                        : _gradientFallback(),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.50),
                            Colors.black.withValues(alpha: 0.88),
                          ],
                          stops: const [0.25, 0.60, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(city.country,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ),
                  ),
                  if (city.isActive)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RC.emerald.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 6, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Open',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(city.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2)),
                          if (city.region.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 12, color: RC.teal),
                              const SizedBox(width: 3),
                              Text(city.region,
                                  style: const TextStyle(
                                      color: RC.textSec, fontSize: 12)),
                            ]),
                          ],
                          if (city.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(city.description,
                                style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    height: 1.4),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 14),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [RC.teal, RC.tealMid]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: RC.teal.withValues(alpha: 0.40),
                                      blurRadius: 10)
                                ],
                              ),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Explore',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    SizedBox(width: 6),
                                    Icon(Icons.arrow_forward_rounded,
                                        size: 13, color: Colors.white),
                                  ]),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.map_outlined,
                                  size: 14, color: RC.teal),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradientFallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RC.tealDark, RC.navy],
          ),
        ),
        child: Center(
          child: Icon(Icons.location_city_rounded,
              size: 72, color: RC.teal.withValues(alpha: 0.25)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BlogCard
// ─────────────────────────────────────────────────────────────────────────────
class _BlogCard extends StatefulWidget {
  final BlogPost post;
  const _BlogCard({required this.post});

  @override
  State<_BlogCard> createState() => _BlogCardState();
}

class _BlogCardState extends State<_BlogCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 1.02)
        .animate(CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hoverCtrl.forward(),
      onExit: (_) => _hoverCtrl.reverse(),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            decoration: BoxDecoration(
              color: RC.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20), blurRadius: 12)
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: post.featuredImage != null
                      ? Image.network(post.featuredImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgFallback())
                      : _imgFallback(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.categories.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: post.categories
                              .take(2)
                              .map((c) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: RC.gold.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color:
                                              RC.gold.withValues(alpha: 0.30)),
                                    ),
                                    child: Text(c,
                                        style: const TextStyle(
                                            color: RC.gold,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList(),
                        ),
                      const SizedBox(height: 10),
                      Text(post.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Text(post.excerpt,
                          style: const TextStyle(
                              color: RC.textSec, fontSize: 12, height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 14),
                      // ── Date row ─────────────────────────────────────────
                      if (post.formattedDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 11, color: RC.textMute),
                            const SizedBox(width: 4),
                            Text(post.formattedDate,
                                style: const TextStyle(
                                    color: RC.textMute, fontSize: 11)),
                            if (post.cityName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.location_on_outlined,
                                  size: 11, color: RC.textMute),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(post.cityName,
                                    style: const TextStyle(
                                        color: RC.textMute, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                        ),
                      // ── Author / reading time / views ─────────────────────
                      Row(children: [
                        const Icon(Icons.person_outline_rounded,
                            size: 13, color: RC.textMute),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(post.authorName,
                                style: const TextStyle(
                                    color: RC.textMute, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                        if (post.readingTimeMinutes != null) ...[
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.readingTimeMinutes}m',
                              style: const TextStyle(
                                  color: RC.textMute, fontSize: 11)),
                        ],
                        if (post.views != null && post.views! > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.visibility_outlined,
                              size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.views}',
                              style: const TextStyle(
                                  color: RC.textMute, fontSize: 11)),
                        ],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imgFallback() => Container(
        color: RC.deepBlue,
        child: const Center(
            child: Icon(Icons.article_outlined, color: RC.textMute, size: 40)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton box  (loading placeholder)
// ─────────────────────────────────────────────────────────────────────────────
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox(
      {required this.width, required this.height, required this.radius});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.8)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: RC.deepBlue.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Background dot grid painter
// ─────────────────────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 52.0;
    const radius = 1.2;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}