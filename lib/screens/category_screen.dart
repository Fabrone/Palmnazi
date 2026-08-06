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
import 'package:palmnazi/widgets/place_card.dart';

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
  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
}

// ─────────────────────────────────────────────────────────────────────────────
// Private API helper — no auth token required for public reads
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryApi {
  static const _timeout = Duration(seconds: 15);

  /// GET /api/places?cityId=…&categoryId=…&status=ACTIVE&includeAttributes=true
  ///
  /// Returns all active places that belong to [cityId] and [categoryId],
  /// featured places first (see [PlaceModel.isFeatured] — an admin-promoted
  /// flag stored in `attributes`, which is why includeAttributes=true is
  /// required here; the plain list endpoint omits it for payload size).
  /// Returns an empty list on any non-200 response or parse failure so the
  /// UI degrades gracefully to an empty state instead of throwing.
  static Future<List<PlaceModel>> fetchPlaces({
    required String cityId,
    required String categoryId,
  }) async {
    final uri = Uri.parse(
      ApiEndpoints.url(
        '/api/places?cityId=$cityId&categoryId=$categoryId&status=ACTIVE'
        '&includeAttributes=true',
      ),
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

    final places =
        raw.whereType<Map<String, dynamic>>().map(PlaceModel.fromJson).toList();

    // Featured places surface first; original order preserved within each
    // group (List.sort isn't guaranteed stable, so index is a tiebreaker).
    final indexed = places.asMap().entries.toList()
      ..sort((a, b) {
        final featuredCmp =
            (b.value.isFeatured ? 1 : 0).compareTo(a.value.isFeatured ? 1 : 0);
        return featuredCmp != 0 ? featuredCmp : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
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
  late final ScrollController _scrollController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  double _scrollOffset = 0;

  // ── Subcategory filter ────────────────────────────────────────────────────
  /// null means "All" — no subcategory filter applied.
  String? _selectedSubcatId;

  // ── Live-typed name filter — client-side, since the full place list for
  // this city+category is already loaded upfront (no new endpoint needed).
  final _searchCtrl = TextEditingController();
  String _nameQuery = '';

  // ── Live place data ───────────────────────────────────────────────────────
  List<PlaceModel> _places = [];
  bool _loading = true;
  String? _error;

  // ── Derived list — filtered by active subcategory chip + live name query ─
  List<PlaceModel> get _filteredPlaces {
    Iterable<PlaceModel> result = _places;

    if (_selectedSubcatId != null) {
      // Match by primaryCategoryId (computed from categoryLinks.first).
      // Fall back to matching category name if no links are present.
      final childName = widget.category.children
          .firstWhere(
            (c) => c.id == _selectedSubcatId,
            orElse: () => CategoryModel(
              id: '',
              name: '',
              slug: '',
              isActive: false,
              children: [],
              sortOrder: 0,
            ),
          )
          .name
          .toLowerCase();
      result = result.where((p) {
        final pid = p.primaryCategoryId;
        if (pid != null) return pid == _selectedSubcatId;
        return (p.primaryCategoryName ?? '').toLowerCase() == childName;
      });
    }

    final q = _nameQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((p) => p.name.toLowerCase().contains(q));
    }

    return result.toList();
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
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadPlaces() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await _CategoryApi.fetchPlaces(
        cityId: widget.city.id,
        categoryId: widget.category.id,
      );
      if (mounted) {
        setState(() {
          _places = places;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Could not load ${TourismLabels.placePlural.toLowerCase()}. Tap to retry.';
          _loading = false;
        });
      }
    }
  }

  void _onScroll() => setState(() => _scrollOffset = _scrollController.offset);

  void _navigateToPlaceDetails(PlaceModel place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsScreen(
          city: widget.city,
          category: widget.category,
          place: place,
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
            child: Container(color: Colors.black.withValues(alpha: 0.50)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildSearchField(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
              children: [
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
            child: Icon(Icons.chevron_right, color: Colors.white54, size: 16),
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
        border: Border.all(color: _P.aqua.withValues(alpha: 0.40), width: 1.2),
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
    final activeChildren =
        widget.category.children.where((c) => c.isActive).toList();
    if (activeChildren.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _SubcatChip(
            label: context.tr('category_subcat_all'),
            selected: _selectedSubcatId == null,
            onTap: () => setState(() => _selectedSubcatId = null),
          ),
          const SizedBox(width: 8),
          ...activeChildren.map((child) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SubcatChip(
                  label: child.name,
                  selected: _selectedSubcatId == child.id,
                  onTap: () => setState(() => _selectedSubcatId = child.id),
                ),
              )),
        ],
      ),
    );
  }

  // ── Live name search field ────────────────────────────────────────────────
  Widget _buildSearchField() {
    if (_loading || _error != null || _places.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _nameQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText:
                'Search ${TourismLabels.placePlural.toLowerCase()} in ${widget.category.name}…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: _P.aquaBright, size: 18),
            suffixIcon: _nameQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _nameQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Place count label ─────────────────────────────────────────────────────
  Widget _buildPlaceCount() {
    if (_loading || _error != null) return const SizedBox.shrink();
    final n = _filteredPlaces.length;
    return Text(
      '$n ${n == 1 ? TourismLabels.placeSingular.toLowerCase() : TourismLabels.placePlural.toLowerCase()} found',
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
          child: PlaceCard(
            place: _filteredPlaces[index],
            fallbackCategoryName: widget.category.name,
            onTap: () => _navigateToPlaceDetails(_filteredPlaces[index]),
          ),
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
                Text('Loading ${TourismLabels.placePlural.toLowerCase()}…',
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
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 10),
                Text(
                  _error!,
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

  SliverToBoxAdapter _emptySliver() => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.place_outlined,
                  size: 48, color: Colors.white.withValues(alpha: 0.30)),
              const SizedBox(height: 12),
              Text(
                'No ${TourismLabels.placePlural.toLowerCase()} found in ${widget.category.name}'
                '${_selectedSubcatId != null ? ' for this subcategory' : ''}'
                '${_nameQuery.trim().isNotEmpty ? ' matching "${_nameQuery.trim()}"' : ''}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
              if (_selectedSubcatId != null ||
                  _nameQuery.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedSubcatId = null;
                    _nameQuery = '';
                    _searchCtrl.clear();
                  }),
                  child: Text(
                      'Show all ${TourismLabels.placePlural.toLowerCase()}',
                      style: const TextStyle(
                          color: _P.aquaBright,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _P.aquaBright : Colors.white70,
          ),
        ),
      ),
    );
  }
}
