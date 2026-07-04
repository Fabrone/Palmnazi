import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/category_screen.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/widgets/place_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// resort_city_screen.dart
//
// Public detail screen shown when a user taps a city card on LandingPage.
// Reads live categories from the backend and navigates to CategoryScreen.
//
// DATA SOURCES  (public reads — no auth required)
//   GET /api/categories?isActive=true&includeChildren=true
//     → active root categories, each with its children[] embedded
//
// FIELD MAP  (ResortCityItem  →  CityModel)
//   city.assetPath     → city.coverImage   (network URL, Image.network)
//   city.color         → _accentFor(index) palette / _P.aqua fallback
//   city.tagline       → "${city.region}, ${city.country}"
//   city.highlights    → stats chips built from city.totalPlaces,
//                        city.totalEvents and city.categoryCounts
//   ChannelItem        → CategoryModel
//   ChannelScreen      → CategoryScreen
//
// NAVIGATION
//   Category card → CategoryScreen(city: CityModel, category: CategoryModel)
//
// RESPONSIVE BREAKPOINTS  (inherited from LandingPage convention)
//   mobile  < 600 dp → grid maxCrossAxisExtent 340, 1-wide
//   tablet  < 900 dp → grid maxCrossAxisExtent 400, 2-wide
//   desktop ≥ 900 dp → grid maxCrossAxisExtent 400, 3-wide
// ─────────────────────────────────────────────────────────────────────────────

// ── Shared palette ────────────────────────────────────────────────────────────
abstract final class _P {
  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
}

// ── Vivid category accent palette — cycles when there are more categories ─────
const List<Color> _kCategoryColors = [
  Color(0xFF00ACC1), // vivid cyan         — Accommodation
  Color(0xFFF50057), // vivid pink-red     — Dining
  Color(0xFFFF6D00), // vivid deep orange  — Events
  Color(0xFFAA00FF), // vivid purple       — Shopping
  Color(0xFF2979FF), // electric blue      — Adventure
  Color(0xFF00BFA5), // vivid teal-green   — Wellness
  Color(0xFFFFD600), // vivid yellow
  Color(0xFFE040FB), // vivid magenta
];

Color _accentFor(int index) =>
    _kCategoryColors[index % _kCategoryColors.length];

// ── Icon resolver — maps category name / slug → IconData ──────────────────────
IconData _iconFor(CategoryModel cat) {
  final n = '${cat.name} ${cat.slug}'.toLowerCase();
  if (n.contains('accommodation') ||
      n.contains('hotel') ||
      n.contains('lodge') ||
      n.contains('stay') ||
      n.contains('resort')) {
    return Icons.king_bed_outlined;
  }
  if (n.contains('dining') ||
      n.contains('food') ||
      n.contains('restaurant') ||
      n.contains('eat') ||
      n.contains('cuisine')) {
    return Icons.restaurant_menu;
  }
  if (n.contains('event') ||
      n.contains('festival') ||
      n.contains('entertainment') ||
      n.contains('nightlife')) {
    return Icons.celebration;
  }
  if (n.contains('shop') ||
      n.contains('market') ||
      n.contains('mall') ||
      n.contains('retail') ||
      n.contains('craft')) {
    return Icons.shopping_bag_outlined;
  }
  if (n.contains('adventure') ||
      n.contains('outdoor') ||
      n.contains('nature') ||
      n.contains('hike') ||
      n.contains('safari')) {
    return Icons.terrain;
  }
  if (n.contains('wellness') ||
      n.contains('spa') ||
      n.contains('health') ||
      n.contains('yoga') ||
      n.contains('retreat')) {
    return Icons.spa_outlined;
  }
  if (n.contains('culture') ||
      n.contains('art') ||
      n.contains('museum') ||
      n.contains('heritage') ||
      n.contains('historic')) {
    return Icons.account_balance_outlined;
  }
  if (n.contains('tour') || n.contains('excursion') || n.contains('guide')) {
    return Icons.explore_outlined;
  }
  if (n.contains('transport') || n.contains('transit') || n.contains('car')) {
    return Icons.directions_car_outlined;
  }
  if (n.contains('beach') || n.contains('pool') || n.contains('water')) {
    return Icons.pool;
  }
  if (n.contains('sport') || n.contains('gym') || n.contains('fitness')) {
    return Icons.sports_tennis;
  }
  if (n.contains('night') ||
      n.contains('bar') ||
      n.contains('club') ||
      n.contains('lounge')) {
    return Icons.nightlife;
  }
  return Icons.place_outlined;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API helper — no auth required for public reads
// ─────────────────────────────────────────────────────────────────────────────
class _ResortApi {
  static const _timeout = Duration(seconds: 15);

  /// GET /api/categories?isActive=true&includeChildren=true
  ///
  /// Returns only active root categories (parentId == null / isRoot == true).
  /// Children are embedded inside each root — used as subcategory chips on
  /// the category card.
  static Future<List<CategoryModel>> fetchCategories() async {
    final uri = Uri.parse(
      ApiEndpoints.url('/api/categories?isActive=true&includeChildren=true'),
    );
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];
    List<dynamic> raw;

    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['categories'] as List<dynamic>?) ??
          (data['data'] as List<dynamic>?) ??
          <dynamic>[];
    } else {
      raw = [];
    }

    final categories = raw
        .whereType<Map<String, dynamic>>()
        .map(CategoryModel.fromJson)
        .where((c) => c.isActive && c.isRoot)
        .toList();

    // Respect backend sortOrder when present
    categories.sort((a, b) => (a.sortOrder).compareTo(b.sortOrder));

    return categories;
  }

  /// GET /api/places?cityId=…&status=ACTIVE
  ///
  /// Every active place in the city, with no category filter — backs the
  /// "All Listings" tab so a tourist can browse places directly instead of
  /// always having to drill through a category first.
  static Future<List<PlaceModel>> fetchAllPlaces({
    required String cityId,
  }) async {
    final uri = Uri.parse(
      ApiEndpoints.url('/api/places?cityId=$cityId&status=ACTIVE'),
    );
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];

    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      // Backend wraps as { places: [...], pagination: {...} }
      raw = (data['places'] as List<dynamic>?) ??
          (data['data'] as List<dynamic>?) ??
          <dynamic>[];
    } else {
      raw = [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(PlaceModel.fromJson)
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ResortCityScreen
// ─────────────────────────────────────────────────────────────────────────────
class ResortCityScreen extends StatefulWidget {
  /// Backend city model passed from LandingPage — fixes the
  /// `argument_type_not_assignable` error (CityModel ↔ ResortCityItem).
  final CityModel city;

  const ResortCityScreen({super.key, required this.city});

  @override
  State<ResortCityScreen> createState() => _ResortCityScreenState();
}

class _ResortCityScreenState extends State<ResortCityScreen>
    with TickerProviderStateMixin {
  // ── Scroll / animation ────────────────────────────────────────────────────
  late final ScrollController _scrollController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  double _scrollOffset = 0;

  // ── Live category data ────────────────────────────────────────────────────
  List<CategoryModel> _categories = [];
  bool _catsLoading = true;
  String? _catsError;

  // ── Live "All Listings" data — places for this city, no category filter ──
  List<PlaceModel> _listings = [];
  bool _listingsLoading = true;
  String? _listingsError;

  // ── "Browse by Service" vs "All Listings" ─────────────────────────────────
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _scrollController = ScrollController()..addListener(_onScroll);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _fadeController.forward();

    _loadCategories();
    _loadListings();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() {
      _catsLoading = true;
      _catsError = null;
    });
    try {
      final cats = await _ResortApi.fetchCategories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _catsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catsError =
              'Could not load ${TourismLabels.categoryPlural.toLowerCase()}. Tap to retry.';
          _catsLoading = false;
        });
      }
    }
  }

  Future<void> _loadListings() async {
    if (!mounted) return;
    setState(() {
      _listingsLoading = true;
      _listingsError = null;
    });
    try {
      final places = await _ResortApi.fetchAllPlaces(cityId: widget.city.id);
      if (mounted) {
        setState(() {
          _listings = places;
          _listingsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _listingsError =
              'Could not load ${TourismLabels.placePlural.toLowerCase()}. Tap to retry.';
          _listingsLoading = false;
        });
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _onScroll() => setState(() => _scrollOffset = _scrollController.offset);

  void _navigateToCategory(CategoryModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryScreen(
          city: widget.city,
          category: category,
        ),
      ),
    );
  }

  /// Navigates straight to PlaceDetailsScreen from the "All Listings" tab,
  /// where there is no single category context. Derives a category from the
  /// place's own first category link when available, mirroring the
  /// `_placeholderCategory` pattern already used for icon lookups —
  /// PlaceDetailsScreen only reads `.name` as a breadcrumb/fallback label,
  /// so this is safe even when it's empty.
  void _navigateToPlaceDetails(PlaceModel place) {
    final category = place.categoryLinks.isNotEmpty
        ? CategoryModel(
            id: place.categoryLinks.first.categoryId,
            name: place.categoryLinks.first.categoryName,
            slug: '',
            isActive: true,
            children: const [],
            sortOrder: 0,
          )
        : _placeholderCategory(TourismLabels.categorySingular);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsScreen(
          city: widget.city,
          category: category,
          place: place,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── City cover image background ──────────────────────────────────
          Positioned.fill(child: _buildBackground()),

          // ── Dark scrim for readability ───────────────────────────────────
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),

          // ── Main scrollable content ──────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Space below the floating top nav
              const SliverToBoxAdapter(child: SizedBox(height: 80)),

              // City info card
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildCityInfo(),
                ),
              ),

              // Pinned "Browse by Service" / "All Listings" tab bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(_buildTabBar()),
              ),

              // Each tab owns its own scrollable content (including its own
              // footer) so it can scroll independently within the remaining
              // viewport below the pinned tab bar.
              SliverFillRemaining(
                hasScrollBody: true,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildServicesTab(),
                    _buildListingsTab(),
                  ],
                ),
              ),
            ],
          ),

          // ── Floating top nav bar ─────────────────────────────────────────
          _buildTopNav(),
        ],
      ),
    );
  }

  // ── Background ────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    final coverUrl = widget.city.coverImage;
    if (coverUrl.isNotEmpty) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        // Fade in once loaded
        frameBuilder: (context, child, frame, _) => AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: child,
        ),
        errorBuilder: (_, __, ___) => _buildBackgroundFallback(),
      );
    }
    return _buildBackgroundFallback();
  }

  Widget _buildBackgroundFallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_P.aqua, Colors.black],
          ),
        ),
      );

  // ── Floating top nav ──────────────────────────────────────────────────────
  Widget _buildTopNav() {
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.30 + 0.45 * navOpacity),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Back + PALMNAZI brand ──────────────────────────────
                Row(children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30)),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Logo orb
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_P.aquaBright, _P.aqua],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _P.aqua.withValues(alpha: 0.55),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.landscape,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),

                  // Brand name
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_P.aquaBright, Colors.white],
                    ).createShader(bounds),
                    child: const Text(
                      'PALMNAZI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ]),

                // ── Right: Sign In | Blog | Get Started ───────────────
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AuthScreen(isLogin: true))),
                    child: const Text('Sign In',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Blog',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AuthScreen(isLogin: false))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _P.aquaBright,
                      foregroundColor: _P.deepNavy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      elevation: 4,
                      shadowColor: _P.aqua.withValues(alpha: 0.50),
                    ),
                    child: const Text('Get Started',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── City info card ────────────────────────────────────────────────────────
  Widget _buildCityInfo() {
    final city = widget.city;
    // Build stat chips from live CityModel fields
    final statChips = <_StatChipData>[
      if (city.totalPlaces > 0)
        _StatChipData(
            icon: Icons.place_outlined,
            label: '${city.totalPlaces} ${TourismLabels.placePlural}'),
      if (city.totalEvents > 0)
        _StatChipData(
            icon: Icons.event_outlined, label: '${city.totalEvents} Events'),
    ];

    // If the backend also sends categoryCounts, surface the top ones
    if (city.categoryCounts != null) {
      final sorted = city.categoryCounts!.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sorted.take(3)) {
        if (entry.value > 0) {
          statChips.add(_StatChipData(
              icon: _iconFor(_placeholderCategory(entry.key)),
              label: '${entry.value} ${_capitalize(entry.key)}'));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _P.aqua.withValues(alpha: 0.25),
            _P.aqua.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _P.aqua.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City name
          Text(
            city.name,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),

          // Region · Country  (replaces old ResortCityItem.tagline)
          Text(
            '${city.region}, ${city.country}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _P.aquaBright,
            ),
          ),
          const SizedBox(height: 12),

          // Description
          if (city.description.isNotEmpty)
            Text(
              city.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.55,
              ),
            ),

          if (statChips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statChips.map((s) => _buildStatChip(s)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(_StatChipData data) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _P.aqua.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: _P.aqua.withValues(alpha: 0.45), width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: 13, color: _P.aquaBright),
            const SizedBox(width: 6),
            Text(
              data.label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  // ── "Explore Categories" heading ──────────────────────────────────────────
  Widget _buildCategoriesHeading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_P.aquaBright, Colors.white],
            ).createShader(bounds),
            child: Text(
              'Explore ${TourismLabels.categoryPlural}',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a ${TourismLabels.categorySingular.toLowerCase()} to discover amazing ${TourismLabels.placePlural.toLowerCase()} and experiences in ${widget.city.name}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.80),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Categories grid sliver ────────────────────────────────────────────────
  Widget _buildCategoriesSliver() {
    if (_catsLoading) return _buildLoadingSliver();
    if (_catsError != null) return _buildErrorSliver();
    if (_categories.isEmpty) return _buildEmptySliver();

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 1.0,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final cat = _categories[index];
          return FadeTransition(
            opacity: _fadeAnimation,
            child: _buildCategoryCard(cat, index),
          );
        },
        childCount: _categories.length,
      ),
    );
  }

  SliverToBoxAdapter _buildLoadingSliver() => SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                    color: _P.aquaBright, strokeWidth: 2),
                const SizedBox(height: 14),
                Text('Loading ${TourismLabels.categoryPlural.toLowerCase()}…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );

  SliverToBoxAdapter _buildErrorSliver() => SliverToBoxAdapter(
        child: GestureDetector(
          onTap: _loadCategories,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 10),
                Text(
                  _catsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap to retry',
                  style: TextStyle(
                      color: _P.aquaBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );

  SliverToBoxAdapter _buildEmptySliver() => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.category_outlined,
                  size: 48, color: Colors.white.withValues(alpha: 0.30)),
              const SizedBox(height: 12),
              Text(
                'No ${TourismLabels.categoryPlural.toLowerCase()} available yet for ${widget.city.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
            ],
          ),
        ),
      );

  // ── Browse-by-Service / All-Listings tab bar ──────────────────────────────
  Widget _buildTabBar() {
    return Container(
      color: _P.deepNavy.withValues(alpha: 0.94),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _P.aquaBright,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: [
          Tab(
            icon: const Icon(Icons.category_outlined, size: 18),
            text: 'Browse by ${TourismLabels.categorySingular}',
          ),
          Tab(
            icon: const Icon(Icons.place_outlined, size: 18),
            text: 'All ${TourismLabels.placePlural}',
          ),
        ],
      ),
    );
  }

  // ── "Browse by Service" tab — unchanged category grid + footer ───────────
  Widget _buildServicesTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildCategoriesHeading(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: _buildCategoriesSliver(),
        ),
        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  // ── "All Listings" tab — every place in the city, no category filter ─────
  Widget _buildListingsTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildListingsHeading(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: _buildListingsSliver(),
        ),
        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  Widget _buildListingsHeading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_P.aquaBright, Colors.white],
            ).createShader(bounds),
            child: Text(
              'All ${TourismLabels.placePlural}',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every ${TourismLabels.placeSingular.toLowerCase()} in ${widget.city.name}, in one browsable list — no need to pick a ${TourismLabels.categorySingular.toLowerCase()} first.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.80),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildListingsSliver() {
    if (_listingsLoading) return _buildListingsLoadingSliver();
    if (_listingsError != null) return _buildListingsErrorSliver();
    if (_listings.isEmpty) return _buildListingsEmptySliver();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => FadeTransition(
          opacity: _fadeAnimation,
          child: PlaceCard(
            place: _listings[index],
            fallbackCategoryName: TourismLabels.categorySingular,
            onTap: () => _navigateToPlaceDetails(_listings[index]),
          ),
        ),
        childCount: _listings.length,
      ),
    );
  }

  SliverToBoxAdapter _buildListingsLoadingSliver() => SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                    color: _P.aquaBright, strokeWidth: 2),
                const SizedBox(height: 14),
                Text('Loading ${TourismLabels.placePlural.toLowerCase()}…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );

  SliverToBoxAdapter _buildListingsErrorSliver() => SliverToBoxAdapter(
        child: GestureDetector(
          onTap: _loadListings,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 10),
                Text(
                  _listingsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap to retry',
                  style: TextStyle(
                      color: _P.aquaBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );

  SliverToBoxAdapter _buildListingsEmptySliver() => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.place_outlined,
                  size: 48, color: Colors.white.withValues(alpha: 0.30)),
              const SizedBox(height: 12),
              Text(
                'No ${TourismLabels.placePlural.toLowerCase()} available yet for ${widget.city.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
            ],
          ),
        ),
      );

  // ── Category card ─────────────────────────────────────────────────────────
  Widget _buildCategoryCard(CategoryModel category, int index) {
    final accent = _accentFor(index);
    final icon = _iconFor(category);

    // Collect subcategory names from children (if the API returned them)
    final subcats =
        category.children.where((c) => c.isActive).map((c) => c.name).toList();

    return GestureDetector(
      onTap: () => _navigateToCategory(category),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Solid background when there is no image
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.30),
                        _P.deepBlue,
                      ],
                    ),
                  ),
                ),
              ),

              // Gradient overlay — lighter at top, darker at bottom
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),

              // Card content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon orb
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: accent.withValues(alpha: 0.80), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(icon, size: 30, color: Colors.white),
                      ),
                      const SizedBox(height: 14),

                      // Title
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),

                      // Description — falls back gracefully when null/empty
                      if ((category.description ?? '').isNotEmpty)
                        Text(
                          category.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                      // Subcategory chips — from live children[]
                      if (subcats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: subcats
                              .take(4)
                              .map((s) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color:
                                              accent.withValues(alpha: 0.40)),
                                    ),
                                    child: Text(s,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500)),
                                  ))
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // "Explore" pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.55),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Explore',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                )),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward,
                                size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.70),
          ],
        ),
      ),
      child: Column(
        children: [
          // Teal accent divider (was widget.city.color)
          Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, _P.aqua, Colors.transparent],
              ),
            ),
          ),

          // Nav links
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: ['About', 'Contact', 'Privacy', 'Terms']
                .map((t) => TextButton(
                      onPressed: () {},
                      child: Text(t,
                          style: const TextStyle(
                            color: _P.aquaBright,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          )),
                    ))
                .toList(),
          ),

          const SizedBox(height: 16),

          Text(
            '© 2026 Palmnazi Resort Cities. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Pins the "Browse by Service" / "All Listings" TabBar in place while the
/// tab's own content scrolls beneath it.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _TabBarDelegate(this.child);

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _StatChipData {
  final IconData icon;
  final String label;
  const _StatChipData({required this.icon, required this.label});
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// Lightweight stand-in CategoryModel used only by _iconFor() when resolving an
// icon for a plain category-count key string from CityModel.categoryCounts.
// Constructor only sets the fields _iconFor() actually reads (name + slug).
// isRoot is a computed getter on CategoryModel (parentId == null) so it is not
// a constructor parameter. createdAt / updatedAt are server-assigned timestamps
// and are also absent from the constructor. sortOrder defaults to 0 (int).
CategoryModel _placeholderCategory(String name) => CategoryModel(
      id: '',
      name: name,
      slug: name.toLowerCase(),
      isActive: true,
      children: [],
      sortOrder: 0,
    );
