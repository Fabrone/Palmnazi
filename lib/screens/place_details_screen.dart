import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/models/place_query_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/booking_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/payment_methods_service.dart';
import 'package:palmnazi/services/place_details_service.dart';
import 'package:palmnazi/services/place_query_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// place_details_screen.dart
//
// Fully migrated from hardcoded PlaceItem / ChannelItem / ResortCityItem to
// live backend data via PlaceModel / CategoryModel / CityModel.
//
// DATA SOURCE  (public read — no auth required)
//   GET /api/places/:id?includeAttributes=true
//     → full PlaceModel for detail view (contact, description, attributes,
//       images, bookingSettings all included)
//
// NAVIGATION CHAIN
//   LandingPage → ResortCityScreen → CategoryScreen → PlaceDetailsScreen
//
// DESIGN NOTES
//   • `rating`, `reviewCount`, `features`, `isOpen`, `priceRange`,
//     `primaryCategoryName`, `primaryCategoryId` — these never existed on
//     PlaceModel.  The screen now derives equivalent display values from the
//     fields that DO exist:
//       - rating / reviewCount  → not in backend schema; sections hidden
//         gracefully (future: add via /api/places/:id/reviews endpoint)
//       - features              → place.taxonomy list (backend array of tags)
//       - isOpen                → not in backend schema; badge omitted
//       - priceRange            → derived from place.pricing (min/max/currency)
//       - primaryCategoryName   → place.categoryLinks.first?.categoryName
//       - primaryCategoryId     → place.categoryLinks.first?.categoryId
//   • channel.color (fixed Color on ChannelItem) → _P.aqua palette constant
//   • Background: place.coverImage (network) with initials fallback
//   • Image gallery: place.images list with horizontal scroll
//   • Contact: place.contact.phone / email / website + place.address
//   • Attributes: place.attributes map rendered as feature chips
// ─────────────────────────────────────────────────────────────────────────────

// ── Shared palette ─────────────────────────────────────────────────────────
abstract final class _P {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color aqua = Color(0xFF00B8D4);
  //static const Color amber      = Color(0xFFFFB300);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
}

// ─────────────────────────────────────────────────────────────────────────────
// Private API helper — no auth token required for public reads
// ─────────────────────────────────────────────────────────────────────────────
class _PlaceDetailApi {
  static const _timeout = Duration(seconds: 15);

  /// GET /api/places/:id?includeAttributes=true
  ///
  /// Returns the full place detail object including contact, description,
  /// attributes, images, bookingSettings, and categoryLinks.
  /// Returns null on any non-200 response or parse failure.
  static Future<PlaceModel?> fetchPlace(String placeId) async {
    final uri = Uri.parse(
      ApiEndpoints.url('/api/places/$placeId?includeAttributes=true'),
    );
    try {
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return PlaceModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// GET /api/places/:id/{rooms|menu-items|shows}
  ///
  /// Same public-read convention as fetchPlace above. Returns an empty list
  /// on any error so the calling section simply doesn't render rather than
  /// showing an error banner for what is a "nice to have" section.
  static Future<List<Map<String, dynamic>>> fetchNestedItems(
      String placeId, String path) async {
    final uri = Uri.parse(ApiEndpoints.url('/api/places/$placeId/$path'));
    try {
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      List<dynamic> raw;
      if (data is List) {
        raw = data;
      } else if (data is Map) {
        raw = (data['rooms'] as List<dynamic>?) ??
            (data['menuItems'] as List<dynamic>?) ??
            (data['shows'] as List<dynamic>?) ??
            const [];
      } else if (body is Map<String, dynamic>) {
        raw = (body['rooms'] as List<dynamic>?) ??
            (body['menuItems'] as List<dynamic>?) ??
            (body['shows'] as List<dynamic>?) ??
            const [];
      } else {
        raw = const [];
      }
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL safety guard — same pattern used in admin screens.
// Firebase Storage URLs are always https://; any http:// value is old test
// data and must be dropped before Image.network is called.
// ─────────────────────────────────────────────────────────────────────────────
String? _safeImageUrl(String? url) {
  if (url == null) return null;
  final t = url.trim();
  if (t.isEmpty) return null;
  if (!t.startsWith('https://')) return null;
  return t;
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaceDetailsScreen
// ─────────────────────────────────────────────────────────────────────────────
class PlaceDetailsScreen extends StatefulWidget {
  /// The resort city — passed from CategoryScreen.
  final CityModel city;

  /// The category the user navigated through — passed from CategoryScreen.
  final CategoryModel category;

  /// The lean PlaceModel from the list.  The screen immediately fetches the
  /// full detail record on mount; the lean model is used as the initial
  /// display state so the screen never shows completely empty content.
  final PlaceModel place;

  const PlaceDetailsScreen({
    super.key,
    required this.city,
    required this.category,
    required this.place,
  });

  @override
  State<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}

class _PlaceDetailsScreenState extends State<PlaceDetailsScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  double _scrollOffset = 0;

  // ── Full detail record (loaded from backend) ─────────────────────────────
  // Starts as the lean model from the list, upgraded once the detail fetch
  // completes.  All UI reads from [_place] so it always has something to show.
  late PlaceModel _place;
  bool _detailLoading = false;
  bool _detailError = false;

  // ── Nested services (rooms / menu items / shows) — Place_details images ──
  //
  // The backend item list comes from a public GET on /api/places/:id/{path};
  // per-item photos come from Firestore Place_details.{rooms|menuItems|shows}
  // (see PlaceDetailsService — written by the admin place wizard). Both are
  // index-aligned the same way the wizard writes them.
  List<Map<String, dynamic>> _nestedItems = [];
  List<List<String>> _nestedItemImages = [];
  String _nestedItemsLabel = '';
  String _nestedItemsType =
      ''; // 'rooms' | 'menuItems' | 'shows' | 'exhibitions' | ''
  bool _loadingNestedItems = false;
  String _nestedItemsSearchQuery = '';

  // Cultural places only: artifacts shown as a read-only display-case
  // section (they're informational, not something a tourist books, unlike
  // exhibitions above which can have visiting slots).
  List<Map<String, dynamic>> _artifactItems = [];
  List<List<String>> _artifactItemImages = [];

  // ── Accepted payment methods (Firestore) ──────────────────────────────────
  List<PaymentMethodModel> _acceptedPaymentMethods = [];

  // ── Derived display helpers ───────────────────────────────────────────────

  /// First linked category name, or fall back to the category passed in.
  String get _primaryCategoryName => _place.categoryLinks.isNotEmpty
      ? _place.categoryLinks.first.categoryName
      : widget.category.name;

  bool get _isAccommodationType => _place.taxonomy.any((t) =>
      t.contains('accommodation') ||
      t.contains('hotel') ||
      t.contains('resort') ||
      t.contains('lodge'));

  bool get _isDiningType => _place.taxonomy.any((t) =>
      t.contains('dining') ||
      t.contains('restaurant') ||
      t.contains('food') ||
      t.contains('cafe'));

  bool get _isEntertainmentType => _place.taxonomy.any((t) =>
      t.contains('entertainment') ||
      t.contains('event') ||
      t.contains('show') ||
      t.contains('cinema'));

  bool get _isCulturalType => _place.taxonomy.any((t) =>
      t.contains('museum') ||
      t.contains('cultural') ||
      t.contains('heritage') ||
      t.contains('art'));

  /// Human-readable price range built from PlacePricing, e.g. "KES 2,000–5,000/night".
  String? get _priceRangeLabel {
    final p = _place.pricing;
    if (p == null) return null;
    final currency = p.currency;
    final unit = p.unit;
    if (p.min != null && p.max != null) {
      return '$currency ${_fmt(p.min!)}–${_fmt(p.max!)}/$unit';
    }
    if (p.min != null) return 'From $currency ${_fmt(p.min!)}/$unit';
    if (p.max != null) return 'Up to $currency ${_fmt(p.max!)}/$unit';
    return null;
  }

  String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toStringAsFixed(0);

  /// Features derived from taxonomy tags + selected attributes.
  List<String> get _featureTags {
    final tags = <String>[...(_place.taxonomy)];
    // Pull boolean/string attributes that look like features
    _place.attributes.forEach((key, value) {
      if (value == true) {
        // Convert camelCase/snake_case keys to readable labels
        tags.add(_attrLabel(key));
      } else if (value is String && value.isNotEmpty && value != 'false') {
        // Only short attribute values are worth showing as chips
        if (value.length <= 30) tags.add('${_attrLabel(key)}: $value');
      }
    });
    return tags;
  }

  String _attrLabel(String key) {
    // Convert camelCase or snake_case to Title Case words
    final spaced = key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .replaceAll('_', ' ')
        .trim();
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _place = widget.place;
    _scrollController = ScrollController()..addListener(_onScroll);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _fadeController.forward();
    _fetchDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onScroll() => setState(() => _scrollOffset = _scrollController.offset);

  Future<void> _fetchDetail() async {
    if (!mounted) return;
    setState(() {
      _detailLoading = true;
      _detailError = false;
    });
    final full = await _PlaceDetailApi.fetchPlace(widget.place.id);
    if (!mounted) return;
    setState(() {
      _detailLoading = false;
      if (full != null) {
        _place = full;
      } else {
        _detailError = true;
      }
    });
    // Taxonomy (used to decide which nested items to show) only arrives on
    // the full detail record, so this runs after the state above lands.
    _fetchPlaceDetailsExtras();
  }

  /// Loads everything that lives in Firestore's Place_details doc — nested
  /// item images and accepted payment methods — in a single read, plus the
  /// nested item list itself from the public REST endpoint. Both sections
  /// are "nice to have"; any failure here is swallowed so the core place
  /// detail view above still renders fine.
  Future<void> _fetchPlaceDetailsExtras() async {
    final String type;
    final String path;
    final String label;
    if (_isAccommodationType) {
      type = 'rooms';
      path = 'rooms';
      label = 'Rooms';
    } else if (_isDiningType) {
      type = 'menuItems';
      path = 'menu-items';
      label = 'Menu';
    } else if (_isEntertainmentType) {
      type = 'shows';
      path = 'shows';
      label = 'Shows';
    } else if (_isCulturalType) {
      type = 'exhibitions';
      path = 'exhibitions';
      label = 'Exhibitions';
    } else {
      type = '';
      path = '';
      label = '';
    }

    if (type.isNotEmpty) setState(() => _loadingNestedItems = true);
    try {
      // Kick requests off in parallel, then await — they're independent.
      final detailsFuture = PlaceDetailsService.getPlaceDetails(_place.id);
      final itemsFuture = type.isNotEmpty
          ? _PlaceDetailApi.fetchNestedItems(_place.id, path)
          : Future.value(const <Map<String, dynamic>>[]);
      final artifactsFuture = _isCulturalType
          ? _PlaceDetailApi.fetchNestedItems(_place.id, 'artifacts')
          : Future.value(const <Map<String, dynamic>>[]);
      final details = await detailsFuture;
      final items = await itemsFuture;
      final artifacts = await artifactsFuture;

      List<String> imagesAt(List<dynamic> saved, int index) {
        if (index >= saved.length) return const [];
        final entry = saved[index];
        if (entry is Map<String, dynamic>) {
          return List<String>.from(
              (entry['images'] as List<dynamic>?) ?? const []);
        }
        return const [];
      }

      if (type.isNotEmpty) {
        final saved = (details?[type] as List<dynamic>?) ?? const [];
        if (mounted) {
          setState(() {
            _nestedItemsType = type;
            _nestedItemsLabel = label;
            _nestedItems = items;
            _nestedItemImages =
                List.generate(items.length, (i) => imagesAt(saved, i));
          });
        }
      }

      if (_isCulturalType) {
        final savedArtifacts =
            (details?['artifacts'] as List<dynamic>?) ?? const [];
        if (mounted) {
          setState(() {
            _artifactItems = artifacts;
            _artifactItemImages = List.generate(
                artifacts.length, (i) => imagesAt(savedArtifacts, i));
          });
        }
      }

      final paymentIds = List<String>.from(
          (details?['paymentMethods'] as List<dynamic>?) ?? const []);
      if (paymentIds.isNotEmpty) {
        final all = await PaymentMethodsService.getActive();
        final matched = all.where((m) => paymentIds.contains(m.id)).toList();
        if (mounted) setState(() => _acceptedPaymentMethods = matched);
      }
    } catch (_) {
      // Nice-to-have sections — fail silently, just don't render them.
    } finally {
      if (type.isNotEmpty && mounted) {
        setState(() => _loadingNestedItems = false);
      }
    }
  }

  // NOTE: AuthScreen always pushAndRemoveUntil's to LandingPage on a
  // successful sign-in (see auth_screen.dart _navigateToLanding) — it never
  // returns control to whoever pushed it. So a logged-out tourist tapping
  // "Book Now" can't be seamlessly carried through to BookingScreen; the
  // honest UX is to ask them to sign in first and come back to this place.
  Future<void> _startBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final shouldSignIn = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _P.deepNavy,
          title: const Text('Sign in required',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You need an account to request a booking. Sign in (or create one), then come back to this place to continue.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _P.aquaBright),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Sign In', style: TextStyle(color: _P.deepNavy)),
            ),
          ],
        ),
      );
      if (shouldSignIn == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          place: _place,
          city: widget.city,
          serviceOptions: _nestedItems,
          serviceLabel: _nestedItemsLabel,
          serviceType: _nestedItemsType,
          paymentMethods: _acceptedPaymentMethods,
        ),
      ),
    );
  }

  // ── Ask a question ────────────────────────────────────────────────────────
  Future<void> _askQuestion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final shouldSignIn = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _P.deepNavy,
          title: const Text('Sign in required',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You need an account to ask a question. Sign in (or create one), then come back to this place to continue.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _P.aquaBright),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Sign In', style: TextStyle(color: _P.deepNavy)),
            ),
          ],
        ),
      );
      if (shouldSignIn == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)),
        );
      }
      return;
    }
    if (!mounted) return;

    final ctrl = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _P.deepNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ask ${_place.name} a question',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'What would you like to know?',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _P.aquaBright),
            onPressed: () async {
              final message = ctrl.text.trim();
              if (message.isEmpty) return;
              await PlaceQueryService.submit(PlaceQueryModel(
                id: '',
                placeId: _place.id,
                placeName: _place.name,
                firebaseUid: user.uid,
                userEmail: user.email ?? '',
                message: message,
              ));
              if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
            },
            child: const Text('Send', style: TextStyle(color: _P.deepNavy)),
          ),
        ],
      ),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your question has been sent.'),
        backgroundColor: Color(0xFF006064),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Place cover image as full-screen background ───────────────────
          Positioned.fill(child: _buildBackground()),

          // ── Dark scrim ────────────────────────────────────────────────────
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.52)),
          ),

          // ── Scrollable content ────────────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBreadcrumb(),
                      _buildPlaceInfoCard(),
                      if (_detailLoading) _buildDetailLoadingBanner(),
                      if (_detailError) _buildDetailErrorBanner(),
                      _buildQuickActions(),
                      _buildDescriptionSection(),
                      _buildImageGallery(),
                      if (_featureTags.isNotEmpty) _buildFeaturesSection(),
                      _buildNestedItemsSection(),
                      _buildArtifactsSection(),
                      _buildContactSection(),
                      _buildBookingInfoSection(),
                      _buildPaymentMethodsSection(),
                      _buildCategoriesSection(),
                      _buildActionButtons(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Top nav bar ────────────────────────────────────────────────────
          _buildTopNav(),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    final cover = _safeImageUrl(_place.coverImage);
    if (cover != null) {
      return Image.network(
        cover,
        fit: BoxFit.cover,
        frameBuilder: (ctx, child, frame, _) => AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: child,
        ),
        errorBuilder: (_, __, ___) => _backgroundFallback(),
      );
    }
    return _backgroundFallback();
  }

  Widget _backgroundFallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_P.aqua.withValues(alpha: 0.50), _P.deepBlue],
          ),
        ),
        child: Center(
          child: Text(
            _place.name.isNotEmpty ? _place.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      );

  // ── Top nav bar ─────────────────────────────────────────────────────────
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
                // Back
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
                      colors: [_P.aquaBright, _P.aqua],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: _P.aqua.withValues(alpha: 0.50),
                          blurRadius: 10),
                    ],
                  ),
                  child: const Icon(Icons.landscape,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),

                // Brand
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [_P.aquaBright, Colors.white],
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
                const Spacer(),

                // Place name pill
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _P.aqua.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _place.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  // ── Breadcrumb  City › Category › Place ──────────────────────────────────
  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.popUntil(
                context, (r) => r.isFirst || r.settings.name == '/city'),
            child: Text(
              widget.city.name,
              style: const TextStyle(
                color: _P.aquaBright,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right,
              size: 16, color: Colors.white.withValues(alpha: 0.50)),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              widget.category.name,
              style: const TextStyle(
                color: _P.aquaBright,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right,
              size: 16, color: Colors.white.withValues(alpha: 0.50)),
          Text(
            _place.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Place info card ───────────────────────────────────────────────────────
  Widget _buildPlaceInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _P.aqua.withValues(alpha: 0.30),
            _P.aqua.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.aqua.withValues(alpha: 0.50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + city
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _place.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _primaryCategoryName,
                      style: const TextStyle(
                        fontSize: 15,
                        color: _P.aquaBright,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_place.cityName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_city,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.55)),
                          const SizedBox(width: 4),
                          Text(
                            _place.cityName,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Bookable badge
              if (_place.isBookable)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Bookable',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Price range + address row
          Row(
            children: [
              if (_priceRangeLabel != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _P.deepNavy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _P.aquaBright.withValues(alpha: 0.40)),
                  ),
                  child: Text(
                    _priceRangeLabel!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _P.aquaBright,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if ((_place.address ?? '').isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.55)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _place.address!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Short description
          if ((_place.shortDescription ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _place.shortDescription!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.75),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Detail loading / error banners ────────────────────────────────────────
  Widget _buildDetailLoadingBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _P.aqua.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(color: _P.aquaBright, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Loading full details…',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.60))),
        ],
      ),
    );
  }

  Widget _buildDetailErrorBanner() {
    return GestureDetector(
      onTap: _fetchDetail,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not load full details. Tap to retry.',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final phone = _place.contact?.phone ?? '';
    final website = _place.contact?.website ?? '';
    final hasMap = _place.hasLocation;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          if (phone.isNotEmpty) ...[
            Expanded(
              child: _buildQuickActionButton(Icons.phone, 'Call', _P.aqua, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Call $phone')),
                );
              }),
            ),
            const SizedBox(width: 12),
          ],
          if (hasMap) ...[
            Expanded(
              child: _buildQuickActionButton(
                  Icons.directions, 'Directions', const Color(0xFF2979FF), () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Maps integration coming soon!')),
                );
              }),
            ),
            const SizedBox(width: 12),
          ],
          if (website.isNotEmpty) ...[
            Expanded(
              child: _buildQuickActionButton(
                  Icons.language, 'Website', const Color(0xFFAA00FF), () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Open $website')),
                );
              }),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _buildQuickActionButton(
                Icons.share, 'Share', const Color(0xFF00BFA5), () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share feature coming soon!')),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.50)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Description ───────────────────────────────────────────────────────────
  Widget _buildDescriptionSection() {
    final desc = _place.description ?? _place.shortDescription ?? '';
    if (desc.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            style: const TextStyle(
                fontSize: 15, color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Image gallery ─────────────────────────────────────────────────────────
  Widget _buildImageGallery() {
    if (_place.images.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 10),
          child: Text(
            'Gallery',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _place.images.length,
            itemBuilder: (context, i) {
              final img = _place.images[i];
              // Skip gallery slots whose URL is not a valid https:// link
              // (e.g. old http:// test data) — show broken-image placeholder.
              final safeUrl = _safeImageUrl(img.url);
              return Container(
                width: 220,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _P.aqua.withValues(alpha: 0.25)),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    safeUrl != null
                        ? Image.network(
                            safeUrl,
                            fit: BoxFit.cover,
                            frameBuilder: (ctx, child, frame, _) =>
                                AnimatedOpacity(
                              opacity: frame == null ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 400),
                              child: child,
                            ),
                            errorBuilder: (_, __, ___) => Container(
                              color: _P.deepBlue,
                              child: Icon(Icons.broken_image_outlined,
                                  color: Colors.white.withValues(alpha: 0.25),
                                  size: 36),
                            ),
                          )
                        : Container(
                            color: _P.deepBlue,
                            child: Icon(Icons.broken_image_outlined,
                                color: Colors.white.withValues(alpha: 0.25),
                                size: 36),
                          ),
                    if ((img.caption ?? '').isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.70),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            img.caption!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Features / taxonomy ───────────────────────────────────────────────────
  Widget _buildFeaturesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Features & Amenities',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _featureTags.map((tag) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _P.aqua.withValues(alpha: 0.30),
                      _P.aqua.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _P.aqua.withValues(alpha: 0.50)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: _P.aquaBright),
                    const SizedBox(width: 8),
                    Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Nested services (rooms / menu / shows) ───────────────────────────────
  Widget _buildNestedItemsSection() {
    if (_loadingNestedItems) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
            child: CircularProgressIndicator(
                color: _P.aquaBright, strokeWidth: 2)),
      );
    }
    if (_nestedItems.isEmpty) return const SizedBox.shrink();

    final query = _nestedItemsSearchQuery.trim().toLowerCase();
    final visibleEntries = _nestedItems.asMap().entries.where((e) =>
        query.isEmpty ||
        ((e.value['name'] as String?)?.toLowerCase().contains(query) ?? false));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_nestedItemsLabel,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          if (_nestedItems.length > 3) ...[
            TextField(
              onChanged: (v) => setState(() => _nestedItemsSearchQuery = v),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search ${_nestedItemsLabel.toLowerCase()}…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Colors.white38, size: 16),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (visibleEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'No ${_nestedItemsLabel.toLowerCase()} match "$query".',
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            )
          else
            ...visibleEntries.map((e) {
              final images = e.key < _nestedItemImages.length
                  ? _nestedItemImages[e.key]
                  : const <String>[];
              return _NestedServiceCard(
                item: e.value,
                images: images,
                itemType: _nestedItemsType,
              );
            }),
        ],
      ),
    );
  }

  // ── Artifacts (cultural places only — display case, not bookable) ────────
  Widget _buildArtifactsSection() {
    if (_artifactItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Artifacts',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          ..._artifactItems.asMap().entries.map((e) {
            final images = e.key < _artifactItemImages.length
                ? _artifactItemImages[e.key]
                : const <String>[];
            return _NestedServiceCard(
              item: e.value,
              images: images,
              itemType: 'artifacts',
            );
          }),
        ],
      ),
    );
  }

  // ── Accepted payment methods ──────────────────────────────────────────────
  Widget _buildPaymentMethodsSection() {
    if (_acceptedPaymentMethods.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accepted Payment Methods',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _acceptedPaymentMethods.map((m) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _P.aqua.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _P.aqua.withValues(alpha: 0.40)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (m.icon != null && m.icon!.isNotEmpty) ...[
                    Text(m.icon!, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                  ] else ...[
                    const Icon(Icons.payments_outlined,
                        size: 14, color: _P.aquaBright),
                    const SizedBox(width: 6),
                  ],
                  Text(m.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Contact ───────────────────────────────────────────────────────────────
  Widget _buildContactSection() {
    final contact = _place.contact;
    final address = _place.address;
    final area = _place.area;

    // Only render if there is something to show
    final hasAny = contact?.phone != null ||
        contact?.email != null ||
        contact?.website != null ||
        (address ?? '').isNotEmpty ||
        (area ?? '').isNotEmpty;

    if (!hasAny) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact Information',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          if ((address ?? '').isNotEmpty) ...[
            _buildContactItem(Icons.location_on, 'Address', address!),
            const SizedBox(height: 12),
          ],
          if ((area ?? '').isNotEmpty) ...[
            _buildContactItem(Icons.map_outlined, 'Area', area!),
            const SizedBox(height: 12),
          ],
          if ((contact?.phone ?? '').isNotEmpty) ...[
            _buildContactItem(Icons.phone, 'Phone', contact!.phone!),
            const SizedBox(height: 12),
          ],
          if ((contact?.email ?? '').isNotEmpty) ...[
            _buildContactItem(Icons.email_outlined, 'Email', contact!.email!),
            const SizedBox(height: 12),
          ],
          if ((contact?.website ?? '').isNotEmpty)
            _buildContactItem(Icons.language, 'Website', contact!.website!),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _P.aquaBright, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Booking info ──────────────────────────────────────────────────────────
  Widget _buildBookingInfoSection() {
    final bs = _place.bookingSettings;
    if (!_place.isBookable && bs == null && _priceRangeLabel == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _P.aqua.withValues(alpha: 0.18),
            _P.aqua.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _P.aqua.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking & Pricing',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 14),
          if (_priceRangeLabel != null) ...[
            _buildInfoRow(Icons.sell_outlined, 'Price', _priceRangeLabel!),
            const SizedBox(height: 10),
          ],
          if (bs?.advanceNotice != null) ...[
            _buildInfoRow(
                Icons.schedule, 'Advance notice', '${bs!.advanceNotice} hours'),
            const SizedBox(height: 10),
          ],
          if (bs?.minDuration != null) ...[
            _buildInfoRow(
                Icons.timelapse, 'Min stay', '${bs!.minDuration} nights'),
            const SizedBox(height: 10),
          ],
          if (bs?.maxDuration != null) ...[
            _buildInfoRow(
                Icons.calendar_today, 'Max stay', '${bs!.maxDuration} nights'),
            const SizedBox(height: 10),
          ],
          if ((bs?.cancellationPolicy ?? '').isNotEmpty)
            _buildInfoRow(
                Icons.policy_outlined, 'Cancellation', bs!.cancellationPolicy!),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _P.aquaBright, size: 18),
        const SizedBox(width: 10),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13,
                color: Colors.white54,
                fontWeight: FontWeight.w600)),
        Flexible(
          child: Text(value,
              style: const TextStyle(fontSize: 13, color: Colors.white)),
        ),
      ],
    );
  }

  // ── Categories ────────────────────────────────────────────────────────────
  Widget _buildCategoriesSection() {
    if (_place.categoryLinks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TourismLabels.categoryPlural,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _place.categoryLinks.map((link) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _P.aqua.withValues(alpha: 0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((link.parentName ?? '').isNotEmpty) ...[
                      Text(
                        link.parentName!,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.50)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.40)),
                      ),
                    ],
                    Text(
                      link.categoryName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Container(
      margin: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_place.isBookable)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startBooking,
                icon: const Icon(Icons.calendar_today, size: 20),
                label: const Text(
                  'Book Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _P.aquaBright,
                  foregroundColor: _P.deepNavy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: _P.aqua.withValues(alpha: 0.50),
                ),
              ),
            )
          else
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _askQuestion,
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: const Text(
                  'Enquire',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _P.aquaBright,
                  side: const BorderSide(color: _P.aquaBright, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          if (_place.isBookable) ...[
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _P.aquaBright, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: _askQuestion,
                tooltip: 'Ask a Question',
                icon: const Icon(Icons.chat_bubble_outline,
                    color: _P.aquaBright, size: 20),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _P.aquaBright, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Favourites feature coming soon!'),
                    backgroundColor: Color(0xFF006064),
                  ),
                );
              },
              icon: const Icon(Icons.favorite_border,
                  color: _P.aquaBright, size: 24),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NestedServiceCard
//
// One row per room / menu item / show, with a horizontal strip of its
// Firestore-stored photos (see PlaceDetailsService, written by the admin
// place wizard's Step 6 dialogs). Falls back gracefully with no photo strip
// when none have been uploaded for that item yet.
// ─────────────────────────────────────────────────────────────────────────────

class _NestedServiceCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final List<String> images;
  final String itemType;

  const _NestedServiceCard({
    required this.item,
    required this.images,
    required this.itemType,
  });

  String get _title => item['name'] as String? ?? 'Untitled';

  String? get _subtitle {
    switch (itemType) {
      case 'rooms':
        final price = item['basePrice'];
        final currency = item['currency'] as String? ?? '';
        final type = item['roomType'] as String? ?? '';
        final parts = <String>[
          if (type.isNotEmpty) type,
          if (price != null) '$currency $price',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
      case 'menuItems':
        final price = item['price'];
        final currency = item['currency'] as String? ?? '';
        final mealType = item['mealType'] as String? ?? '';
        final parts = <String>[
          if (mealType.isNotEmpty) mealType,
          if (price != null) '$currency $price',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
      case 'shows':
        final category = item['category'] as String? ?? '';
        final duration = item['durationMinutes'];
        final parts = <String>[
          if (category.isNotEmpty) category,
          if (duration != null) '$duration min',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
      case 'exhibitions':
      case 'artifacts':
        final desc = item['description'] as String?;
        return (desc != null && desc.isNotEmpty) ? desc : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _P.aqua.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          if (_subtitle != null) ...[
            const SizedBox(height: 4),
            Text(_subtitle!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                itemBuilder: (context, i) {
                  final safeUrl = _safeImageUrl(images[i]);
                  return Container(
                    width: 96,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _P.aqua.withValues(alpha: 0.25)),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: safeUrl != null
                        ? Image.network(safeUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: _P.deepBlue,
                                child: const Icon(Icons.broken_image_outlined,
                                    color: Colors.white24, size: 20)))
                        : Container(
                            color: _P.deepBlue,
                            child: const Icon(Icons.broken_image_outlined,
                                color: Colors.white24, size: 20)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
