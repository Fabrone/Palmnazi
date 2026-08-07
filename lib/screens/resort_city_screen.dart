import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/widgets/main_app_bar.dart';
import 'package:palmnazi/widgets/place_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// resort_city_screen.dart
//
// Public detail screen shown when a user taps a city card on LandingPage.
// Reads live categories from the backend and uses them to build a filter
// chip row above a single responsive place grid.
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
//
// NAVIGATION
//   Single listings view — a "Browse by Service" filter-chip row (built from
//   _categories) filters the same _listings array client-side by category
//   instead of navigating to a separate CategoryScreen.
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
      n.contains('accomodation') ||
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

  // ── "Browse by Service" filter chips — null = "All" (no filter) ──────────
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();

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

  /// Filters `_listings` by the selected "Browse by Service" chip, matching
  /// on `primaryCategoryId` (computed from `categoryLinks.first`) with a
  /// name-based fallback — same pattern as `category_screen.dart`'s
  /// `_filteredPlaces` getter. `null` selection ("All") applies no filter.
  List<PlaceModel> get _filteredListings {
    if (_selectedCategoryId == null) return _listings;

    final selected = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => _placeholderCategory(''),
    );
    final selectedName = selected.name.toLowerCase();

    return _listings.where((p) {
      final pid = p.primaryCategoryId;
      if (pid != null) return pid == _selectedCategoryId;
      return (p.primaryCategoryName ?? '').toLowerCase() == selectedName;
    }).toList();
  }

  /// Navigates straight to PlaceDetailsScreen from the listings grid, where
  /// there is no single category context. Derives a category from the
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

              // Listings heading
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildListingsHeading(),
                ),
              ),

              // "Browse by Service" filter chip row — filters _listings
              // client-side instead of navigating to CategoryScreen.
              SliverToBoxAdapter(child: _buildFilterChipRow()),

              // Responsive place grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: _buildListingsSliver(),
              ),

              SliverToBoxAdapter(child: _buildFooter()),
            ],
          ),

          // ── Floating top nav bar ─────────────────────────────────────────
          PalmnaziNavBar(
            showBack: true,
            heroOpacity: (_scrollOffset / 80).clamp(0.0, 1.0),
          ),
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

  // ── "Browse by Service" filter chip row ───────────────────────────────────
  //
  // Replaces the old separate "Browse by Service" tab: an "All" chip plus one
  // chip per root category, filtering `_listings` client-side (via
  // `_filteredListings`) instead of navigating to CategoryScreen.
  Widget _buildFilterChipRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: SizedBox(
        height: 40,
        child: _catsError != null
            ? GestureDetector(
                onTap: _loadCategories,
                child: Text(
                  context.tr('common_tap_to_retry'),
                  style: const TextStyle(
                      color: _P.aquaBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              )
            : ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CityFilterChip(
                    label: 'All',
                    selected: _selectedCategoryId == null,
                    onTap: () => setState(() => _selectedCategoryId = null),
                  ),
                  if (_catsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _P.aquaBright),
                      ),
                    )
                  else
                    for (int i = 0; i < _categories.length; i++) ...[
                      const SizedBox(width: 10),
                      _CityFilterChip(
                        label: _categories[i].name,
                        selected: _selectedCategoryId == _categories[i].id,
                        accent: _accentFor(i),
                        onTap: () => setState(
                            () => _selectedCategoryId = _categories[i].id),
                      ),
                    ],
                ],
              ),
      ),
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

  /// Responsive grid, per the file's documented breakpoints: mobile (<600dp)
  /// gets a 340dp max cross-axis extent (1-wide), tablet/desktop (>=600dp)
  /// gets 400dp (2-wide/3-wide depending on available width) — the delegate
  /// reflows column count automatically from `maxCrossAxisExtent`, so no
  /// manual breakpoint→column-count mapping is needed. `mainAxisExtent` (not
  /// `childAspectRatio`) is used so each card gets a fixed, generously tall
  /// height regardless of column width, since `PlaceCard`'s content
  /// (image + name/rating + category + description + feature chips + button)
  /// is not itself flexible and would overflow a too-short tight box.
  Widget _buildListingsSliver() {
    if (_listingsLoading) return _buildListingsLoadingSliver();
    if (_listingsError != null) return _buildListingsErrorSliver();

    final filtered = _filteredListings;
    if (filtered.isEmpty) return _buildListingsEmptySliver();

    final maxExtent = MediaQuery.sizeOf(context).width < 600 ? 340.0 : 400.0;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisExtent: 600,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => FadeTransition(
          opacity: _fadeAnimation,
          child: PlaceCard(
            place: filtered[index],
            fallbackCategoryName: TourismLabels.categorySingular,
            onTap: () => _navigateToPlaceDetails(filtered[index]),
          ),
        ),
        childCount: filtered.length,
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
                Text(
                  context.tr('common_tap_to_retry'),
                  style: const TextStyle(
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
                _selectedCategoryId != null
                    ? 'No ${TourismLabels.placePlural.toLowerCase()} found for that ${TourismLabels.categorySingular.toLowerCase()} in ${widget.city.name}.'
                    : 'No ${TourismLabels.placePlural.toLowerCase()} available yet for ${widget.city.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
            ],
          ),
        ),
      );

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
            children: [
              context.tr('footer_about'),
              context.tr('footer_contact'),
              context.tr('footer_privacy'),
              context.tr('footer_terms'),
            ]
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
            context.tr('resort_city_footer_copyright'),
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

/// "Browse by Service" filter chip — visually modelled on `landing_page.dart`'s
/// private `_FilterChip` (gold-on-navy) but restyled with this screen's own
/// aqua accent palette since that class is file-private and not reusable.
/// `accent` optionally tints the selected state per-category (from
/// `_accentFor`); falls back to `_P.aquaBright` for the "All" chip.
class _CityFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  const _CityFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final Color tint = accent ?? _P.aquaBright;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? tint.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? tint.withValues(alpha: 0.80)
                : Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? tint : Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
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
