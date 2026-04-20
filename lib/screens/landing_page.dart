import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// landing_page.dart
//
// Public home screen. Live data from:
//   GET /api/cities?isActive=true   → resort city cards
//   GET /api/blog?limit=6           → blog / travel inspiration
//
// NAVIGATION
//   City card → ResortCityScreen(city: CityModel)
//   ⚠  ResortCityScreen must have its constructor updated from
//      `ResortCityItem city` → `CityModel city` before this compiles.
//      That update is done when resort_city_screen.dart is migrated.
//
// RESPONSIVE BREAKPOINTS
//   mobile   <  600 dp  → 1-col layout, stacked search inputs
//   tablet   <  900 dp  → 2-col cities, 2-row search
//   desktop  ≥  900 dp  → 3-col cities, single-row inline search bar
//
// ANIMATIONS
//   • Hero headline  → SlideTransition + FadeTransition on load
//   • City cards     → staggered FadeTransition after data loads
//   • Hover (web/desktop) → subtle scale lift on CityCard and BlogCard
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
abstract final class RC {
  // ── Backgrounds ─────────────────────────────────────────────────────────
  static const Color navy      = Color(0xFF010C18); // deepest page bg
  static const Color deepBlue  = Color(0xFF071829); // section / card bg
  static const Color surface   = Color(0xFF0B2135); // input / elevated surface
  static const Color surfaceHi = Color(0xFF0F2840); // hover surface

  // ── Primary accent — teal/aqua ───────────────────────────────────────────
  static const Color teal      = Color(0xFF00D4F5); // primary CTA, focus
  static const Color tealMid   = Color(0xFF0097B2); // mid gradient stop
  static const Color tealDark  = Color(0xFF006580); // dark gradient stop

  // ── Secondary accents ───────────────────────────────────────────────────
  static const Color gold      = Color(0xFFF5A623); // blog, ratings, stars
  static const Color coral     = Color(0xFFFF6B6B); // secondary CTA / tags
  static const Color emerald   = Color(0xFF00C98A); // open/active badge

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPri  = Color(0xFFFFFFFF);
  static const Color textSec  = Color(0xFFAFC6D8);
  static const Color textMute = Color(0xFF4E6A7A);

  // ── Gradients (helpers) ─────────────────────────────────────────────────
  static const LinearGradient tealGrad = LinearGradient(
    colors: [teal, tealDark],
  );
  static const LinearGradient heroGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF010C18), Color(0xFF071829), Color(0xFF0A2030)],
    stops: [0.0, 0.55, 1.0],
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
    this.author,
    this.city,
  });

  factory BlogPost.fromJson(Map<String, dynamic> j) => BlogPost(
        id:                  j['id']    as String? ?? '',
        title:               j['title'] as String? ?? '',
        slug:                j['slug']  as String? ?? '',
        excerpt:             j['excerpt'] as String? ?? '',
        featuredImage:       j['featuredImage'] as String?,
        categories:          (j['categories'] as List<dynamic>?)
                                 ?.map((c) => c.toString()).toList() ?? [],
        readingTimeMinutes:  j['readingTimeMinutes'] as int?,
        views:               (j['stats'] as Map<String, dynamic>?)?['views'] as int?,
        author:              j['author'] as Map<String, dynamic>?,
        city:                j['city']   as Map<String, dynamic>?,
      );

  String get authorName {
    final a = author;
    if (a == null) return 'Staff';
    final profile = a['profile'] as Map<String, dynamic>?;
    final src = profile ?? a;
    final fn = src['firstName'] as String? ?? '';
    final ln = src['lastName']  as String? ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : 'Staff';
  }

  String get cityName => (city?['name'] as String?) ?? '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API helpers  (no auth headers needed for public reads)
// ─────────────────────────────────────────────────────────────────────────────
class _LandingApi {
  static const _timeout = Duration(seconds: 15);

  static Future<List<CityModel>> fetchCities() async {
    final uri = Uri.parse(ApiEndpoints.url('/api/cities?isActive=true&limit=50'));
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

  static Future<List<BlogPost>> fetchBlogPosts({int limit = 6}) async {
    final uri = Uri.parse(ApiEndpoints.url('/api/blog?limit=$limit'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final posts = body['posts'] as List<dynamic>? ?? [];
    return posts
        .whereType<Map<String, dynamic>>()
        .map(BlogPost.fromJson)
        .toList();
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
    with TickerProviderStateMixin {

  // ── Data ──────────────────────────────────────────────────────────────────
  List<CityModel> _cities     = [];
  List<BlogPost>  _blogPosts  = [];
  bool _citiesLoading = true;
  bool _blogLoading   = true;
  String? _citiesError;

  // ── Scroll ────────────────────────────────────────────────────────────────
  final _scrollCtrl  = ScrollController();
  double _scrollOffset = 0;

  // ── Hero animation ────────────────────────────────────────────────────────
  late AnimationController _heroCtrl;
  late Animation<double>   _heroFade;
  late Animation<Offset>   _heroSlide;

  // ── Section reveal (cities / blog) ───────────────────────────────────────
  late AnimationController _revealCtrl;
  late Animation<double>   _revealFade;

  // ── Search state ──────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _adults   = 2;
  int _children = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollCtrl.offset);
    });

    _heroCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _heroFade  = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));

    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _revealFade = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeIn);

    _heroCtrl.forward();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadCities();
    _loadBlog();
  }

  Future<void> _loadCities() async {
    if (!mounted) return;
    setState(() { _citiesLoading = true; _citiesError = null; });
    try {
      final cities = await _LandingApi.fetchCities();
      if (mounted) {
        setState(() { _cities = cities; _citiesLoading = false; });
        _revealCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() { _citiesError = e.toString(); _citiesLoading = false; });
    }
  }

  Future<void> _loadBlog() async {
    try {
      final posts = await _LandingApi.fetchBlogPosts();
      if (mounted) setState(() { _blogPosts = posts; _blogLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _blogLoading = false);
    }
  }

  Future<void> _pickDate(bool isCheckIn) async {
    final now   = DateTime.now();
    final first = isCheckIn ? now : (_checkIn ?? now);
    final initial = isCheckIn
        ? (_checkIn ?? now)
        : (_checkOut ?? first.add(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: RC.teal,
            onPrimary: Colors.black,
            surface: RC.deepBlue,
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (_checkOut != null && !_checkOut!.isAfter(picked)) _checkOut = null;
      } else {
        _checkOut = picked;
      }
    });
  }

  void _doSearch() {
    // ToDO: Navigate to a dedicated search-results screen when built.
    // The screen will call GET /api/places with:
    //   search=_searchCtrl.text  (place name / keyword)
    //   checkIn, checkOut, adults, children (map to your booking model)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Searching: "${_searchCtrl.text.isEmpty ? "All places" : _searchCtrl.text}" '
          '· $_adults adult${_adults > 1 ? "s" : ""}, $_children child${_children != 1 ? "ren" : ""}',
        ),
        backgroundColor: RC.tealDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _goToCity(CityModel city) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => ResortCityScreen(city: city),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _heroCtrl.dispose();
    _revealCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final w          = MediaQuery.of(context).size.width;
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
    final isMobile   = w < 600;

    return Scaffold(
      backgroundColor: RC.navy,
      body: Stack(
        children: [
          // ── Scrollable page body ─────────────────────────────────────────
          CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              SliverToBoxAdapter(child: _hero(w)),
              SliverToBoxAdapter(child: _citiesSection(w)),
              SliverToBoxAdapter(child: _blogSection(w)),
              SliverToBoxAdapter(child: _footer(w)),
            ],
          ),

          // ── Sticky nav bar (always on top) ───────────────────────────────
          _navBar(w, navOpacity, isMobile),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NAV BAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _navBar(double w, double opacity, bool isMobile) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: RC.navy.withValues(alpha: opacity > 0.1 ? 0.92 * opacity : 0),
          border: Border(
            bottom: BorderSide(
              color: RC.teal.withValues(alpha: opacity * 0.18),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 36,
              vertical: 12,
            ),
            child: Row(children: [
              // ── Brand ──────────────────────────────────────────────────
              _brand(),
              const Spacer(),
              // ── Nav links (hidden on mobile) ───────────────────────────
              if (!isMobile) ...[
                _navLink('Destinations', onTap: () {}),
                _navLink('Categories',   onTap: () {}),
                _navLink('Blog',         onTap: () {}),
                const SizedBox(width: 12),
              ],
              // ── Auth CTAs ──────────────────────────────────────────────
              if (!isMobile)
                TextButton(
                  onPressed: () {
                    // Navigator.push → AuthScreen(isLogin: true)
                  },
                  child: const Text(
                    'Sign In',
                    style: TextStyle(color: RC.textSec, fontSize: 13),
                  ),
                ),
              const SizedBox(width: 6),
              _pillButton(
                label: isMobile ? 'Get Started' : 'Get Started',
                onTap: () {
                  // Navigator.push → AuthScreen(isLogin: false)
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _brand() => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 34, height: 34,
      decoration: const BoxDecoration(gradient: RC.tealGrad, shape: BoxShape.circle),
      child: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 18),
    ),
    const SizedBox(width: 10),
    ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [RC.teal, Colors.white],
      ).createShader(b),
      child: const Text(
        'PALMNAZI',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    ),
  ]);

  Widget _navLink(String label, {required VoidCallback onTap}) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: RC.textSec,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );

  Widget _pillButton({required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [RC.teal, RC.tealMid]),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: RC.teal.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // HERO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _hero(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;

    return Container(
      constraints: BoxConstraints(minHeight: isMobile ? 620 : 720),
      decoration: const BoxDecoration(gradient: RC.heroGrad),
      child: Stack(
        children: [
          // Background decorative grid
          Positioned.fill(
            child: CustomPaint(
              painter: _DotGridPainter(color: RC.teal.withValues(alpha: 0.045)),
            ),
          ),
          // Teal glow — top right
          Positioned(
            top: -120, right: -80,
            child: _glow(380, RC.teal.withValues(alpha: 0.10)),
          ),
          // Gold glow — bottom left
          Positioned(
            bottom: 20, left: -60,
            child: _glow(280, RC.gold.withValues(alpha: 0.07)),
          ),

          // Main content
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, isMobile ? 100 : 130, hPad, 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Tag pill ──────────────────────────────────────────────
                FadeTransition(
                  opacity: _heroFade,
                  child: SlideTransition(
                    position: _heroSlide,
                    child: _tagPill('✦  Discover Africa\'s Premier Resort Destinations', RC.teal),
                  ),
                ),
                const SizedBox(height: 22),

                // ── Headline ──────────────────────────────────────────────
                FadeTransition(
                  opacity: _heroFade,
                  child: SlideTransition(
                    position: _heroSlide,
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: isMobile ? 38 : 60,
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
                                ).createShader(const Rect.fromLTWH(0, 0, 400, 80)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // ── Subheadline ───────────────────────────────────────────
                FadeTransition(
                  opacity: _heroFade,
                  child: Text(
                    'Explore handpicked resort cities, luxury stays,\nand unforgettable experiences across Africa.',
                    style: TextStyle(
                      color: RC.textSec,
                      fontSize: isMobile ? 15 : 18,
                      height: 1.65,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Search panel ──────────────────────────────────────────
                FadeTransition(
                  opacity: _heroFade,
                  child: _searchPanel(w),
                ),
                const SizedBox(height: 44),

                // ── Stats row ─────────────────────────────────────────────
                FadeTransition(
                  opacity: _heroFade,
                  child: _statsRow(w),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );

  Widget _tagPill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withValues(alpha: 0.40)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _statsRow(double w) {
    final isMobile = w < 600;
    final count    = _cities.isEmpty ? '10' : '${_cities.length}';
    final items    = [
      ('$count+', 'Resort Cities'),
      ('500+', 'Curated Places'),
      ('4.9★', 'Avg. Rating'),
    ];
    return Wrap(
      spacing: isMobile ? 28 : 56,
      runSpacing: 16,
      children: items.map((s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.$1, style: TextStyle(
            color: RC.teal,
            fontSize: isMobile ? 24 : 30,
            fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 2),
          Text(s.$2, style: const TextStyle(color: RC.textSec, fontSize: 13)),
        ],
      )).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEARCH PANEL
  // ─────────────────────────────────────────────────────────────────────────
  Widget _searchPanel(double w) {
    final isMobile = w < 600;
    final isTablet = w < 900;

    return Container(
      decoration: BoxDecoration(
        color: RC.deepBlue.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RC.teal.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: RC.teal.withValues(alpha: 0.06), blurRadius: 32)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: isMobile
            ? _mobileSearch()
            : isTablet
                ? _tabletSearch()
                : _desktopSearch(),
      ),
    );
  }

  // Single-row inline (desktop ≥900)
  Widget _desktopSearch() => Row(children: [
    Expanded(flex: 3, child: _searchInput()),
    const SizedBox(width: 8),
    Expanded(flex: 2, child: _dateInput('Check-in',  _checkIn,  () => _pickDate(true))),
    const SizedBox(width: 8),
    Expanded(flex: 2, child: _dateInput('Check-out', _checkOut, () => _pickDate(false))),
    const SizedBox(width: 8),
    _counter('Adults',   _adults,   1,  (v) => setState(() => _adults   = v)),
    const SizedBox(width: 8),
    _counter('Children', _children, 0,  (v) => setState(() => _children = v)),
    const SizedBox(width: 12),
    _searchBtn(),
  ]);

  // Two rows (tablet 600–899)
  Widget _tabletSearch() => Column(children: [
    Row(children: [
      Expanded(child: _searchInput()),
      const SizedBox(width: 8),
      Expanded(child: _dateInput('Check-in',  _checkIn,  () => _pickDate(true))),
      const SizedBox(width: 8),
      Expanded(child: _dateInput('Check-out', _checkOut, () => _pickDate(false))),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _counter('Adults',   _adults,   1, (v) => setState(() => _adults   = v)),
      const SizedBox(width: 8),
      _counter('Children', _children, 0, (v) => setState(() => _children = v)),
      const Spacer(),
      _searchBtn(),
    ]),
  ]);

  // Stacked (mobile <600)
  Widget _mobileSearch() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _searchInput(),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _dateInput('Check-in',  _checkIn,  () => _pickDate(true))),
        const SizedBox(width: 8),
        Expanded(child: _dateInput('Check-out', _checkOut, () => _pickDate(false))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _counter('Adults',   _adults,   1, (v) => setState(() => _adults   = v)),
        const SizedBox(width: 8),
        _counter('Children', _children, 0, (v) => setState(() => _children = v)),
      ]),
      const SizedBox(height: 12),
      _searchBtn(fullWidth: true),
    ],
  );

  Widget _searchInput() => _inputBox(
    child: TextField(
      controller: _searchCtrl,
      onSubmitted: (_) => _doSearch(),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: const InputDecoration(
        hintText: 'Where do you want to go?',
        hintStyle: TextStyle(color: RC.textMute, fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, color: RC.teal, size: 20),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      ),
    ),
  );

  Widget _dateInput(String label, DateTime? date, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: _inputBox(
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, color: RC.teal, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: RC.textMute, fontSize: 10, height: 1.2)),
                Text(
                  date != null ? _fmtDate(date) : 'Select date',
                  style: TextStyle(
                    color: date != null ? Colors.white : RC.textMute,
                    fontSize: 13,
                    fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            )),
          ]),
          padded: true,
        ),
      );

  Widget _counter(String label, int value, int min, ValueChanged<int> onChange) =>
      _inputBox(
        padded: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: RC.textMute, fontSize: 10, height: 1.2)),
              Text('$value',  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(width: 6),
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () { if (value < 20) onChange(value + 1); },
              child: const Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: RC.teal),
            ),
            GestureDetector(
              onTap: () { if (value > min) onChange(value - 1); },
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: RC.teal),
            ),
          ]),
        ]),
      );

  Widget _inputBox({required Widget child, bool padded = false}) => Container(
    padding: padded
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : EdgeInsets.zero,
    decoration: BoxDecoration(
      color: RC.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _searchBtn({bool fullWidth = false}) {
    final btn = GestureDetector(
      onTap: _doSearch,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [RC.teal, RC.tealMid]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: RC.teal.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESORT CITIES SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _citiesSection(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;

    return Container(
      color: RC.navy,
      padding: EdgeInsets.fromLTRB(hPad, 64, hPad, 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              _sectionLabel('DESTINATIONS', RC.teal),
              const SizedBox(height: 12),
              Text(
                'Explore Resort Cities',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 28 : 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Handpicked resort destinations with the best places to stay,\ndine, and experience across Africa.',
                style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 40),

              // ── City grid ──────────────────────────────────────────────
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
          Text('Could not load destinations', style: const TextStyle(color: RC.textSec)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loadCities,
            icon: const Icon(Icons.refresh_rounded, color: RC.teal, size: 16),
            label: const Text('Try again', style: TextStyle(color: RC.teal)),
          ),
        ]),
      );
    }
    if (_cities.isEmpty) {
      return Center(
        child: Column(children: [
          const Icon(Icons.location_city_outlined, color: RC.textMute, size: 56),
          const SizedBox(height: 16),
          const Text('No destinations available yet', style: TextStyle(color: RC.textSec, fontSize: 15)),
        ]),
      );
    }

    return LayoutBuilder(builder: (_, constraints) {
      final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
      const gap  = 22.0;
      final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(_cities.length, (i) {
          return SizedBox(
            width: cardW,
            child: FadeTransition(
              opacity: _revealFade,
              child: _CityCard(
                city:  _cities[i],
                onTap: () => _goToCity(_cities[i]),
              ),
            ),
          );
        }),
      );
    });
  }

  Widget _citySkeletonGrid(double w, bool isMobile) {
    final cols  = isMobile ? 1 : (w < 1024 ? 2 : 3);
    const gap   = 22.0;
    return LayoutBuilder(builder: (_, c) {
      final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap, runSpacing: gap,
        children: List.generate(cols == 1 ? 3 : cols * 2, (_) =>
          _SkeletonBox(width: cardW, height: 310, radius: 20),
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

    return Container(
      color: RC.deepBlue,
      padding: EdgeInsets.fromLTRB(hPad, 64, hPad, 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ─────────────────────────────────────────────
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
                        const Text(
                          'Guides, tips and stories from our expert travel writers.',
                          style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 24),
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_forward_rounded, color: RC.teal, size: 16),
                      label: const Text('View All', style: TextStyle(color: RC.teal, fontSize: 13)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 36),

              // ── Blog grid ──────────────────────────────────────────────
              _buildBlogBody(w, isMobile),

              if (isMobile) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_forward_rounded, color: RC.teal, size: 15),
                    label: const Text('View All Posts', style: TextStyle(color: RC.teal)),
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
      return Wrap(
        spacing: 20, runSpacing: 20,
        children: List.generate(isMobile ? 2 : 3, (_) =>
          _SkeletonBox(
            width: isMobile ? double.infinity : 300,
            height: 290,
            radius: 16,
          ),
        ),
      );
    }
    if (_blogPosts.isEmpty) {
      return Center(child: Column(children: [
        const Icon(Icons.article_outlined, color: RC.textMute, size: 48),
        const SizedBox(height: 12),
        const Text('No blog posts yet', style: TextStyle(color: RC.textSec)),
      ]));
    }

    return LayoutBuilder(builder: (_, constraints) {
      final cols  = isMobile ? 1 : (w < 1024 ? 2 : 3);
      const gap   = 20.0;
      final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      final take  = isMobile ? 3 : (cols == 2 ? 4 : 6);

      return Wrap(
        spacing: gap, runSpacing: gap,
        children: _blogPosts.take(take).map((post) => SizedBox(
          width: cardW,
          child: _BlogCard(post: post),
        )).toList(),
      );
    });
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
              // ── Top footer ───────────────────────────────────────────
              isMobile
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _footerBrand(),
                      const SizedBox(height: 32),
                      _footerLinks('Explore',  ['Resort Cities', 'Categories', 'All Places', 'Blog']),
                      const SizedBox(height: 28),
                      _footerLinks('Company',  ['About Us', 'Contact Us', 'Careers']),
                      const SizedBox(height: 28),
                      _footerLinks('Legal',    ['Privacy Policy', 'Terms of Service']),
                    ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 2, child: _footerBrand()),
                      const SizedBox(width: 40),
                      Expanded(child: _footerLinks('Explore', ['Resort Cities', 'Categories', 'All Places', 'Blog'])),
                      const SizedBox(width: 24),
                      Expanded(child: _footerLinks('Company', ['About Us', 'Contact Us', 'Careers'])),
                      const SizedBox(width: 24),
                      Expanded(child: _footerLinks('Legal',   ['Privacy Policy', 'Terms of Service', 'Cookie Policy'])),
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
                      style: TextStyle(color: RC.textMute, fontSize: 12),
                    ),
                  ),
                  if (!isMobile)
                    const Text(
                      'Made with ❤ for Africa\'s travellers',
                      style: TextStyle(color: RC.textMute, fontSize: 12),
                    ),
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
          width: 30, height: 30,
          decoration: const BoxDecoration(gradient: RC.tealGrad, shape: BoxShape.circle),
          child: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        const Text('PALMNAZI', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
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
      Text(heading, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
      ...links.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: () {},
          child: Text(l, style: const TextStyle(color: RC.textSec, fontSize: 13)),
        ),
      )),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 1.025)
        .animate(CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _hoverCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hoverCtrl.forward(),
      onExit:  (_) => _hoverCtrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // ── Cover image / fallback ──────────────────────────────
                  Positioned.fill(
                    child: city.coverImage.isNotEmpty
                        ? Image.network(
                            city.coverImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _gradientFallback(),
                          )
                        : _gradientFallback(),
                  ),

                  // ── Dark gradient overlay ─────────────────────────────
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x80000000), Color(0xE0000000)],
                          stops: [0.25, 0.60, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // ── Country badge (top-left) ───────────────────────────
                  Positioned(
                    top: 14, left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(city.country, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                  ),

                  // ── Active pill (top-right) ────────────────────────────
                  if (city.isActive)
                    Positioned(
                      top: 14, right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RC.emerald.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 6, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Open', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),

                  // ── Content at bottom ─────────────────────────────────
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(city.name, style: const TextStyle(
                            color: Colors.white, fontSize: 22,
                            fontWeight: FontWeight.bold, height: 1.2,
                          )),
                          if (city.region.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 12, color: RC.teal),
                              const SizedBox(width: 3),
                              Text(city.region, style: const TextStyle(color: RC.textSec, fontSize: 12)),
                            ]),
                          ],
                          if (city.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              city.description,
                              style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 14),
                          // ── Explore pill ───────────────────────────────
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [RC.teal, RC.tealMid]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: RC.teal.withValues(alpha: 0.40), blurRadius: 10)],
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('Explore', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.white),
                              ]),
                            ),
                            ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.map_outlined, size: 14, color: RC.teal),
                            ),
                          ],
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
      child: Icon(Icons.location_city_rounded, size: 72, color: RC.teal.withValues(alpha: 0.25)),
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
    _hoverCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 1.02)
        .animate(CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _hoverCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hoverCtrl.forward(),
      onExit:  (_) => _hoverCtrl.reverse(),
      child: GestureDetector(
        onTap: () {}, // ToDO: navigate to blog detail screen
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
          child: Container(
            decoration: BoxDecoration(
              color: RC.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 12)],
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Image ────────────────────────────────────────────────
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: post.featuredImage != null
                      ? Image.network(
                          post.featuredImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgFallback(),
                        )
                      : _imgFallback(),
                ),

                // ── Body ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category chips
                      if (post.categories.isNotEmpty)
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: post.categories.take(2).map((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: RC.gold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: RC.gold.withValues(alpha: 0.30)),
                            ),
                            child: Text(c, style: const TextStyle(color: RC.gold, fontSize: 10, fontWeight: FontWeight.w600)),
                          )).toList(),
                        ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        post.title,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Excerpt
                      Text(
                        post.excerpt,
                        style: const TextStyle(color: RC.textSec, fontSize: 12, height: 1.5),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),

                      // Meta row
                      Row(children: [
                        const Icon(Icons.person_outline_rounded, size: 13, color: RC.textMute),
                        const SizedBox(width: 4),
                        Expanded(child: Text(post.authorName, style: const TextStyle(color: RC.textMute, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        if (post.readingTimeMinutes != null) ...[
                          const Icon(Icons.schedule_rounded, size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.readingTimeMinutes}m', style: const TextStyle(color: RC.textMute, fontSize: 11)),
                        ],
                        if (post.views != null && post.views! > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.visibility_outlined, size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.views}', style: const TextStyle(color: RC.textMute, fontSize: 11)),
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
    child: const Center(child: Icon(Icons.article_outlined, color: RC.textMute, size: 40)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton box  (loading placeholder)
// ─────────────────────────────────────────────────────────────────────────────
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox({required this.width, required this.height, required this.radius});

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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.8)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
// Background painter  (subtle dot grid)
// ─────────────────────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 52.0;
    const radius  = 1.2;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}