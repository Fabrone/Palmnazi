import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// category_screen.dart
//
// Migrated from channel_screen.dart
//   ChannelScreen  / ChannelItem  / ResortCityItem
//   →  CategoryScreen / CategoryModel / CityModel
//
// DATA SOURCE  (public read — no auth required)
//   GET /api/places?cityId={city.id}&categoryId={category.id}&status=ACTIVE
//     → paginated PlaceModel list for this city + category combination
//
// NAVIGATION CHAIN
//   LandingPage → ResortCityScreen → CategoryScreen → PlaceDetailsScreen
//
// FIXES IN THIS VERSION
//   • Removed unused `deepNavy` field  (was: warning unused_field)
//   • PlaceDetailsScreen constructor updated: city/category/place
//     (was: city/channel/place with old PlaceItem/ChannelItem/ResortCityItem)
//   • All getters resolved against PlaceModel:
//       - rating           → derived from place.attributes['rating']
//       - reviewCount      → derived from place.attributes['reviewCount']
//       - primaryCategoryName → place.categoryLinks.first?.categoryName
//       - primaryCategoryId   → place.categoryLinks.first?.categoryId
//       - features         → place.taxonomy list
//       - isOpen           → place.attributes['isOpen'] (nullable bool)
//       - priceRange       → derived from place.pricing
// ─────────────────────────────────────────────────────────────────────────────

// ── Shared palette ─────────────────────────────────────────────────────────
abstract final class _P {
  static const Color aqua       = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  // deepNavy removed — was unused (warning: unused_field)
  static const Color deepBlue   = Color(0xFF071829);
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaceModel extension helpers
//
// These computed values are derived from the fields PlaceModel DOES have.
// They are declared here as extension methods rather than adding them to the
// model itself, keeping the model as the single source of truth for backend
// field mapping while giving the UI the convenience accessors it needs.
// ─────────────────────────────────────────────────────────────────────────────
extension PlaceDisplayHelpers on PlaceModel {
  /// ID of the first linked category, or null if no category links exist.
  String? get primaryCategoryId =>
      categoryLinks.isNotEmpty ? categoryLinks.first.categoryId : null;

  /// Name of the first linked category, or null if no category links exist.
  String? get primaryCategoryName =>
      categoryLinks.isNotEmpty ? categoryLinks.first.categoryName : null;

  /// Rating from the flexible attributes map, cast to double? if present.
  double? get rating {
    final v = attributes['rating'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Review count from the flexible attributes map, cast to int? if present.
  int? get reviewCount {
    final v = attributes['reviewCount'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Whether the place is currently open, from attributes['isOpen'].
  /// Returns null (not shown) when the field is absent.
  bool? get isOpen {
    final v = attributes['isOpen'];
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true')  return true;
      if (v == 'false') return false;
    }
    return null;
  }

  /// Human-readable price range built from PlacePricing, e.g. "KES 2,000–5,000".
  /// Returns null when pricing is absent.
  String? get priceRange {
    final p = pricing;
    if (p == null) return null;
    final currency = p.currency;
    if (p.min != null && p.max != null) {
      return '$currency ${_fmtPrice(p.min!)}–${_fmtPrice(p.max!)}';
    }
    if (p.min != null) return 'From $currency ${_fmtPrice(p.min!)}';
    if (p.max != null) return 'Up to $currency ${_fmtPrice(p.max!)}';
    return null;
  }

  /// Feature / amenity list from taxonomy tags.
  List<String> get features => List<String>.unmodifiable(taxonomy);
}

String _fmtPrice(double v) =>
    v.truncateToDouble() == v ? v.toInt().toString() : v.toStringAsFixed(0);

// ─────────────────────────────────────────────────────────────────────────────
// Private API helper — no auth token required for public reads
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryApi {
  static const _timeout = Duration(seconds: 15);

  /// GET /api/places?cityId=…&categoryId=…&status=ACTIVE
  ///
  /// Returns all active places that belong to [cityId] and [categoryId].
  /// Returns an empty list on any non-200 response or parse failure so the
  /// UI degrades gracefully to an empty state instead of throwing.
  static Future<List<PlaceModel>> fetchPlaces({
    required String cityId,
    required String categoryId,
  }) async {
    final uri = Uri.parse(
      ApiEndpoints.url(
        '/api/places?cityId=$cityId&categoryId=$categoryId&status=ACTIVE',
      ),
    );
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data  = body['data'];

    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      // Backend wraps as { places: [...], pagination: {...} }
      raw = (data['places'] as List<dynamic>?)
          ?? (data['data']   as List<dynamic>?)
          ?? <dynamic>[];
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
// CategoryScreen
// ─────────────────────────────────────────────────────────────────────────────
class CategoryScreen extends StatefulWidget {
  /// The resort city this category belongs to — passed from ResortCityScreen.
  final CityModel city;

  /// The category the user selected — passed from ResortCityScreen.
  final CategoryModel category;

  const CategoryScreen({
    super.key,
    required this.city,
    required this.category,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen>
    with TickerProviderStateMixin {

  // ── Scroll / animation ────────────────────────────────────────────────────
  late final ScrollController    _scrollController;
  late final AnimationController _fadeController;
  late final Animation<double>   _fadeAnimation;
  double _scrollOffset = 0;

  // ── Subcategory filter ────────────────────────────────────────────────────
  /// null means "All" — no subcategory filter applied.
  String? _selectedSubcatId;

  // ── Live place data ───────────────────────────────────────────────────────
  List<PlaceModel> _places  = [];
  bool             _loading = true;
  String?          _error;

  // ── Derived list — filtered by active subcategory chip ───────────────────
  List<PlaceModel> get _filteredPlaces {
    if (_selectedSubcatId == null) return _places;

    // Match by primaryCategoryId (computed from categoryLinks.first).
    // Fall back to matching category name if no links are present.
    return _places.where((p) {
      final pid = p.primaryCategoryId;
      if (pid != null) return pid == _selectedSubcatId;

      final childName = widget.category.children
          .firstWhere(
            (c) => c.id == _selectedSubcatId,
            orElse: () => CategoryModel(
              id: '', name: '', slug: '',
              isActive: false, children: [], sortOrder: 0,
            ),
          )
          .name
          .toLowerCase();
      return (p.primaryCategoryName ?? '').toLowerCase() == childName;
    }).toList();
  }

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
    _loadPlaces();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadPlaces() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final places = await _CategoryApi.fetchPlaces(
        cityId:     widget.city.id,
        categoryId: widget.category.id,
      );
      if (mounted) {
        setState(() { _places = places; _loading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = 'Could not load places. Tap to retry.';
          _loading = false;
        });
      }
    }
  }

  void _onScroll() =>
      setState(() => _scrollOffset = _scrollController.offset);

  void _navigateToPlaceDetails(PlaceModel place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsScreen(
          city:     widget.city,
          category: widget.category,
          place:    place,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── City cover as full-screen background ─────────────────────────
          Positioned.fill(child: _buildBackground()),

          // ── Dark scrim ───────────────────────────────────────────────────
          Positioned.fill(
            child: Container(
                color: Colors.black.withValues(alpha: 0.50)),
          ),

          // ── Scrollable content ───────────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
              SliverToBoxAdapter(child: _buildBreadcrumb()),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildCategoryHero(),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildSubcategoryFilter(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 8),
                  child: _buildPlaceCount(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: _buildPlacesSliver(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),

          // ── Floating top nav bar ─────────────────────────────────────────
          _buildTopNav(),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    final coverUrl = widget.city.coverImage;
    if (coverUrl.isNotEmpty) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
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

  // ── Top nav ───────────────────────────────────────────────────────────────
  Widget _buildTopNav() {
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
    return Positioned(
      top: 0, left: 0, right: 0,
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
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:  Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30)),
                    ),
                    child: const Icon(
                        Icons.arrow_back, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36, height: 36,
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
                        blurRadius: 10, spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                      Icons.landscape, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Breadcrumb  City › Category ───────────────────────────────────────────
  Widget _buildBreadcrumb() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              widget.city.name,
              style: const TextStyle(
                color: _P.aquaBright,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right,
                color: Colors.white54, size: 16),
          ),
          Flexible(
            child: Text(
              widget.category.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Category hero card ────────────────────────────────────────────────────
  Widget _buildCategoryHero() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _P.aqua.withValues(alpha: 0.22),
            _P.aqua.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _P.aqua.withValues(alpha: 0.40), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.category.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.city.name}  ·  ${widget.city.region}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _P.aquaBright,
            ),
          ),
          if ((widget.category.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.category.description!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Subcategory filter chip row ───────────────────────────────────────────
  Widget _buildSubcategoryFilter() {
    final activeChildren = widget.category.children
        .where((c) => c.isActive)
        .toList();
    if (activeChildren.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _SubcatChip(
            label: 'All',
            selected: _selectedSubcatId == null,
            onTap: () => setState(() => _selectedSubcatId = null),
          ),
          const SizedBox(width: 8),
          ...activeChildren.map((child) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SubcatChip(
                  label: child.name,
                  selected: _selectedSubcatId == child.id,
                  onTap: () =>
                      setState(() => _selectedSubcatId = child.id),
                ),
              )),
        ],
      ),
    );
  }

  // ── Place count label ─────────────────────────────────────────────────────
  Widget _buildPlaceCount() {
    if (_loading || _error != null) return const SizedBox.shrink();
    final n = _filteredPlaces.length;
    return Text(
      '$n ${n == 1 ? 'place' : 'places'} found',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.80),
      ),
    );
  }

  // ── Places sliver ─────────────────────────────────────────────────────────
  Widget _buildPlacesSliver() {
    if (_loading) return _loadingSliver();
    if (_error != null) return _errorSliver();
    if (_filteredPlaces.isEmpty) return _emptySliver();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => FadeTransition(
          opacity: _fadeAnimation,
          child: _buildPlaceCard(_filteredPlaces[index]),
        ),
        childCount: _filteredPlaces.length,
      ),
    );
  }

  SliverToBoxAdapter _loadingSliver() => SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                    color: _P.aquaBright, strokeWidth: 2),
                const SizedBox(height: 14),
                Text('Loading places…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );

  SliverToBoxAdapter _errorSliver() => SliverToBoxAdapter(
        child: GestureDetector(
          onTap: _loadPlaces,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
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

  SliverToBoxAdapter _emptySliver() => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.place_outlined,
                  size: 48,
                  color: Colors.white.withValues(alpha: 0.30)),
              const SizedBox(height: 12),
              Text(
                'No places found in ${widget.category.name}'
                '${_selectedSubcatId != null ? ' for this subcategory' : ''}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13),
              ),
              if (_selectedSubcatId != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedSubcatId = null),
                  child: const Text('Show all places',
                      style: TextStyle(
                          color: _P.aquaBright,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      );

  // ── Place card ────────────────────────────────────────────────────────────
  Widget _buildPlaceCard(PlaceModel place) {
    return GestureDetector(
      onTap: () => _navigateToPlaceDetails(place),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: _P.deepBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _P.aqua.withValues(alpha: 0.20), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 16, spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image section with overlay badges
              _buildPlaceImage(place),

              // Text summary
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + rating
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        // Rating from attributes['rating'] via extension
                        if (place.rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  place.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Category name · review count
                    Row(
                      children: [
                        Text(
                          // primaryCategoryName from extension (categoryLinks.first)
                          place.primaryCategoryName
                              ?? widget.category.name,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _P.aquaBright,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // reviewCount from attributes['reviewCount'] via extension
                        if ((place.reviewCount ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Text('•',
                              style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.5))),
                          const SizedBox(width: 8),
                          Text(
                            '${place.reviewCount} reviews',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white
                                  .withValues(alpha: 0.70),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Description
                    if ((place.description ?? '').isNotEmpty) ...[
                      Text(
                        place.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.80),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Feature chips from taxonomy via extension
                    if (place.features.isNotEmpty) ...[
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children:
                            place.features.take(4).map((f) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.20)),
                            ),
                            child: Text(f,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // View Details button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_P.aquaBright, _P.aqua],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _P.aqua.withValues(alpha: 0.40),
                              blurRadius: 10, spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'View Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward,
                                color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Place image with Open/Closed and price badges ─────────────────────────
  Widget _buildPlaceImage(PlaceModel place) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageH = constraints.maxWidth * 0.55;
        return SizedBox(
          height: imageH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image (network) or initials fallback
              if ((place.coverImage ?? '').isNotEmpty)
                Image.network(
                  place.coverImage!,
                  fit: BoxFit.cover,
                  frameBuilder: (ctx, child, frame, _) =>
                      AnimatedOpacity(
                    opacity: frame == null ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                  errorBuilder: (_, __, ___) =>
                      _imageFallback(place.name),
                )
              else
                _imageFallback(place.name),

              // Bottom gradient scrim
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),

              // Open / Closed badge — derived from attributes['isOpen']
              // Only shown when the attribute is explicitly set.
              if (place.isOpen != null)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: place.isOpen!
                          ? Colors.green
                          : Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      place.isOpen! ? 'Open' : 'Closed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Price range badge — derived from place.pricing via extension
              if ((place.priceRange ?? '').isNotEmpty)
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.60),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      place.priceRange!,
                      style: const TextStyle(
                        color: _P.aquaBright,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _imageFallback(String name) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _P.aqua.withValues(alpha: 0.35),
              _P.deepBlue,
            ],
          ),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SubcatChip — animated filter chip used in the subcategory row
// ─────────────────────────────────────────────────────────────────────────────
class _SubcatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SubcatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _P.aqua.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? _P.aquaBright.withValues(alpha: 0.70)
                : Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _P.aquaBright : Colors.white70,
          ),
        ),
      ),
    );
  }
}