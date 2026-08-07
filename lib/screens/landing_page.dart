import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html
    show window; // web-only: used for last-section storage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:palmnazi/main.dart' show emailLinkResultNotifier;
import 'package:palmnazi/models/city_details_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/models/system_settings_model.dart';
import 'package:palmnazi/services/blog_post_details_service.dart';
import 'package:palmnazi/services/analytics_service.dart';
import 'package:palmnazi/services/page_view_service.dart';
import 'package:palmnazi/services/system_settings_service.dart';
import 'package:palmnazi/screens/about_screen.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/account_screen.dart';
import 'package:palmnazi/screens/careers_screen.dart';
import 'package:palmnazi/screens/contact_screen.dart';
import 'package:palmnazi/screens/blog_post_detail_screen.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/screens/static_info_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/city_details_service.dart';
import 'package:palmnazi/services/firebase_service.dart';
import 'package:palmnazi/services/rbac_service.dart';
import 'package:palmnazi/admin/admin_dashboard.dart';
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/theme/rc_palette.dart';
import 'package:palmnazi/widgets/main_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logger
// ─────────────────────────────────────────────────────────────────────────────
final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// Design tokens (RC — gold-forward navy palette) now live in
// lib/theme/rc_palette.dart, shared with lib/widgets/main_app_bar.dart so the
// nav bar matches this screen exactly instead of using a third palette.

// ─────────────────────────────────────────────────────────────────────────────
// Last-section persistence (survives tab close; cleared on explicit logout)
// Keys are stored in window.localStorage so re-login can resume where the
// user left off after their session expires.
// ─────────────────────────────────────────────────────────────────────────────
const String _kLastSectionKey = 'pn_last_section'; // 'city' | 'account'
const String _kLastCityPayload = 'pn_last_city_json'; // JSON of CityModel

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
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
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
    // FIX: was List<<dynamic> (double angle-bracket)
    final List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      // FIX: was List<<dynamic>
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

  // ── Featured places ────────────────────────────────────────────────────────
  // GET /api/places?status=ACTIVE&includeAttributes=true&limit=…
  //
  // No dedicated "featured" query param exists on the backend, so this pulls
  // a generous page of active places (attributes included, since isFeatured
  // lives in that freeform bag — see PlaceModel.isFeatured) and filters
  // client-side. Fine for a homepage highlight strip; would need a real
  // backend filter if the catalogue grows past a few hundred active places.
  static Future<List<PlaceModel>> fetchFeaturedPlaces({int limit = 60}) async {
    final uri = Uri.parse(ApiEndpoints.url(
        '/api/places?status=ACTIVE&includeAttributes=true&limit=$limit'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];
    final List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['places'] ?? data['data'] ?? <dynamic>[]) as List<dynamic>;
    } else {
      list = [];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map(PlaceModel.fromJson)
        .where((p) => p.isFeatured)
        .toList();
  }

  // ── Blog ───────────────────────────────────────────────────────────────────
  // FIX: was Future<<({...})> (double angle-bracket)
  static Future<({List<BlogPost> posts, int total})> fetchBlogPosts({
    int limit = 6,
    int page = 1,
  }) async {
    final uri = Uri.parse(ApiEndpoints.url(
        '/api/blog?limit=$limit&page=$page&sortBy=publishedAt&order=desc'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return (posts: <BlogPost>[], total: 0);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    // FIX: was List<<dynamic>
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
  // FIX: was Future<List<<CategoryModel>> (double angle-bracket)
  static Future<List<CategoryModel>> fetchAllCategories() async {
    final uri =
        Uri.parse(ApiEndpoints.url('/api/categories?tree=true&isActive=true'));
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    // FIX: was List<<dynamic> (×2)
    final list = body['data'] as List<dynamic>? ??
        body['categories'] as List<dynamic>? ??
        [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CategoryModel.fromJson)
        .toList();
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  /// The backend's `search` query param only actually filters `/api/places`
  /// — `/api/cities`, `/api/categories`, and `/api/blog` silently ignore it
  /// and return every record regardless of what was typed (verified against
  /// the live API). Since the REST contract is frozen, results are filtered
  /// locally here so every type genuinely narrows as the user types,
  /// independent of what the backend actually does with the param.
  static List<_SearchResult> _filterByQuery(
      List<_SearchResult> results, String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return results;
    return results.where((r) => r.name.toLowerCase().contains(needle)).toList();
  }

  static Future<List<_SearchResult>> search(String q, _SearchType type) async {
    final enc = Uri.encodeQueryComponent(q.trim());
    switch (type) {
      case _SearchType.city:
        final uri = Uri.parse(
            ApiEndpoints.url('/api/cities?search=$enc&isActive=true&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) {
          developer.log('City search returned ${resp.statusCode}: ${resp.body}',
              name: 'LandingSearch');
          return [];
        }
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = body['data'];
        // FIX: was List<<dynamic> (×2)
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = (data['cities'] ?? data['data'] ?? []) as List<dynamic>;
        } else {
          list = [];
        }
        return _filterByQuery(
            list
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
                .toList(),
            q);

      case _SearchType.place:
        final uri = Uri.parse(
            ApiEndpoints.url('/api/places?search=$enc&status=ACTIVE&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) {
          developer.log(
              'Place search returned ${resp.statusCode}: ${resp.body}',
              name: 'LandingSearch');
          return [];
        }
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        // The real API shape wraps the list as data: { places: [...] } —
        // `body['data'] as List<dynamic>?` used to throw here (a Map isn't
        // a List, so the cast fails instead of returning null), which
        // silently killed the whole Future.wait search batch every time.
        final data = body['data'];
        final List<dynamic> places;
        if (data is List) {
          places = data;
        } else if (data is Map) {
          places = (data['places'] as List<dynamic>?) ?? [];
        } else {
          places = (body['places'] as List<dynamic>?) ?? [];
        }
        return _filterByQuery(
            places
                .whereType<Map<String, dynamic>>()
                .map((p) => _SearchResult(
                      id: p['id'] as String? ?? '',
                      name: p['name'] as String? ?? '',
                      subtitle: (p['city'] as Map<String, dynamic>?)?['name']
                          as String?,
                      imageUrl:
                          (p['images'] as List<dynamic>?)?.isNotEmpty == true
                              ? (p['images'] as List<dynamic>).first as String?
                              : null,
                      type: _SearchType.place,
                      raw: p,
                    ))
                .toList(),
            q);

      case _SearchType.category:
        final uri = Uri.parse(ApiEndpoints.url(
            '/api/categories?search=$enc&isActive=true&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) {
          developer.log(
              'Category search returned ${resp.statusCode}: ${resp.body}',
              name: 'LandingSearch');
          return [];
        }
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        // FIX: was List<<dynamic> (×2)
        final list = (body['data'] as List<dynamic>?) ??
            (body['categories'] as List<dynamic>?) ??
            [];
        return _filterByQuery(
            list
                .whereType<Map<String, dynamic>>()
                .map(CategoryModel.fromJson)
                .map((cat) => _SearchResult(
                      id: cat.id,
                      name: cat.name,
                      subtitle: cat.description,
                      type: _SearchType.category,
                      raw: cat,
                    ))
                .toList(),
            q);

      case _SearchType.blog:
        // NOTE: '/api/blog/search' is not a real endpoint (it 404s — the
        // backend has no such route). The working search path is the
        // regular listing endpoint with a `search` query param.
        final uri =
            Uri.parse(ApiEndpoints.url('/api/blog?search=$enc&limit=20'));
        final resp = await http.get(uri).timeout(_timeout);
        if (resp.statusCode != 200) {
          developer.log('Blog search returned ${resp.statusCode}: ${resp.body}',
              name: 'LandingSearch');
          return [];
        }
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        // FIX: was List<<dynamic>
        final posts = (body['posts'] as List<dynamic>?) ?? [];
        return _filterByQuery(
            posts
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
                .toList(),
            q);
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

  // ── Admin / Role gate ───────────────────────────────────────────────────────
  bool _isAdmin = false;
  String? _userRole;

  // ── Data ──────────────────────────────────────────────────────────────────
  List<CityModel> _cities = [];
  List<BlogPost> _blogPosts = [];
  // FIX: was List<<CategoryModel>
  List<CategoryModel> _cachedCategories = []; // pre-fetched for instant overlay
  List<PlaceModel> _featuredPlaces = [];
  Set<String> _featuredBlogSlugs = {};
  bool _citiesLoading = true;
  bool _maintenanceMode = false;
  String _maintenanceMessage = '';
  StreamSubscription<SystemSettingsModel>? _settingsSub;
  bool _blogLoading = true;
  bool _blogLoadingMore = false;
  int _blogPage = 1;
  int _blogTotal = 0;
  String? _citiesError;

  // ── Section filters — client-side, reuse data already fetched ────────────
  String? _cityRegionFilter; // null = All
  String? _blogCategoryFilter; // null = All

  // ── Scroll ────────────────────────────────────────────────────────────────
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  // Scroll-to section keys
  final _citiesKey = GlobalKey();
  final _blogKey = GlobalKey();

  // ── Hero animation ────────────────────────────────────────────────────────
  late AnimationController _heroCtrl;
  late Animation<double> _heroFade;
  // FIX: was Animation<<Offset>
  late Animation<Offset> _heroSlide;

  // ── Hero ambient motion — slow background zoom + bouncing scroll cue ──────
  late AnimationController _kenBurnsCtrl;
  late Animation<double> _kenBurnsScale;
  late AnimationController _scrollCueCtrl;
  late Animation<double> _scrollCueOffset;

  // ── Hero search — focus requested from the mobile menu's "Search" item ───
  final FocusNode _heroSearchFocusNode = FocusNode();

  // ── Section reveal ────────────────────────────────────────────────────────
  late AnimationController _revealCtrl;
  late Animation<double> _revealFade;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollCtrl.offset);
    });

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    // FIX: was Tween<<Offset>
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));

    _revealCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _revealFade = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeIn);

    _kenBurnsCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat(reverse: true);
    _kenBurnsScale = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _kenBurnsCtrl, curve: Curves.easeInOut));

    _scrollCueCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _scrollCueOffset = Tween<double>(begin: 0.0, end: 8.0).animate(
        CurvedAnimation(parent: _scrollCueCtrl, curve: Curves.easeInOut));

    _heroCtrl.forward();
    _loadAll();
    PageViewService.recordVisit();
    AnalyticsService.logScreenView('LandingPage');
    _settingsSub = SystemSettingsService.stream().listen((s) {
      if (mounted) {
        setState(() {
          _maintenanceMode = s.maintenanceMode;
          _maintenanceMessage = s.maintenanceMessage;
        });
      }
    });

    // ── Listen for email-link sign-in completions ─────────────────────────
    emailLinkResultNotifier.addListener(_onEmailLinkResult);
  }

  void _onEmailLinkResult() {
    final result = emailLinkResultNotifier.value;
    if (result != null && result.isSuccess && mounted) {
      _loadAuthState();
    }
  }

  Future<void> _loadAll() async {
    _loadCities();
    _loadBlog();
    _loadCategories();
    _loadFeaturedPlaces();
    _loadAuthState();
  }

  Future<void> _loadFeaturedPlaces() async {
    try {
      final places = await _LandingApi.fetchFeaturedPlaces();
      if (mounted) setState(() => _featuredPlaces = places);
    } catch (_) {
      // Decorative section — fail silently and just don't show it.
    }
  }

  Future<void> _loadAuthState() async {
    final token = await ApiClient.getAccessToken();
    if (!mounted) return;
    final wasLoggedIn = _isLoggedIn;
    final nowLoggedIn = token != null && token.isNotEmpty;
    setState(() => _isLoggedIn = nowLoggedIn);

    // FIX: clear stale last-section localStorage keys on logout so a future
    // user on the same browser does not inherit stale navigation state.
    if (!nowLoggedIn) {
      try {
        html.window.localStorage.remove(_kLastSectionKey);
        html.window.localStorage.remove(_kLastCityPayload);
      } catch (_) {/* localStorage blocked — silently ignore */}
    }

    // On a fresh login, resume the last section the user visited.
    if (!wasLoggedIn && nowLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resumeLastSection();
      });
    }

    // ── Role check from Firebase "Users" collection ───────────────────────
    if (nowLoggedIn) {
      _log.d(
          'LandingPage._loadAuthState: authenticated session detected — starting role check');
      await _checkAdminRole();
    } else {
      _log.d('LandingPage._loadAuthState: no session — clearing admin gate');
      if (mounted) {
        setState(() {
          _isAdmin = false;
          _userRole = null;
        });
      }
    }
  }

  /// Fetches the user's `role` from Firestore `Users/{uid}` and updates
  /// [_isAdmin] / [_userRole]. Called automatically after every auth state
  /// refresh (login, resume, lifecycle change).
  ///
  /// FIX: removed unreliable ApiClient.getUserId() fallback. Firestore uses
  /// Firebase Auth UIDs as document keys; the API userId may be a different
  /// format (e.g. MongoDB ObjectId). If Firebase Auth is not ready yet, we
  /// defer rather than query with a potentially wrong ID.
  Future<void> _checkAdminRole() async {
    try {
      final userId = FirebaseService.currentUser?.uid;

      if (userId == null || userId.isEmpty) {
        _log.d(
            'LandingPage._checkAdminRole: Firebase Auth not ready — deferring role check');
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _userRole = null;
          });
        }
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();
      final role = doc.data()?['role'] as String?;
      final normalizedRole =
          role == null ? null : RbacService.normalizeRole(role);
      final isAdmin =
          normalizedRole != null && RbacService.isAdminRole(normalizedRole);

      _log.i(
          'LandingPage._checkAdminRole: userId=$userId, role=$role, isAdmin=$isAdmin');

      if (mounted) {
        setState(() {
          _userRole = normalizedRole;
          _isAdmin = isAdmin;
        });
      }
    } catch (e, st) {
      _log.e('LandingPage._checkAdminRole: failed to fetch role',
          error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _isAdmin = false;
          _userRole = null;
        });
      }
    }
  }

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
      // Best-effort — if City_details can't be read, cities still show in
      // whatever order the API returned them in.
      Map<String, CityDetailsModel> details = const {};
      try {
        details = await CityDetailsService.getAll();
      } catch (_) {}
      final sorted = CityDetailsService.sortByDetails(
          cities, details, (c) => c.id, (c) => c.name);
      if (mounted) {
        setState(() {
          _cities = sorted;
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
      final result = await _LandingApi.fetchBlogPosts(limit: 6, page: 1);
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
    _loadFeaturedBlogSlugs();
  }

  Future<void> _loadFeaturedBlogSlugs() async {
    try {
      final all = await BlogPostDetailsService.getAll();
      if (mounted) {
        setState(() => _featuredBlogSlugs =
            all.values.where((d) => d.isFeatured).map((d) => d.slug).toSet());
      }
    } catch (_) {
      // Decorative sort — fail silently.
    }
  }

  Future<void> _loadMoreBlog() async {
    if (_blogLoadingMore) return;
    final nextPage = _blogPage + 1;
    setState(() => _blogLoadingMore = true);
    try {
      final result = await _LandingApi.fetchBlogPosts(limit: 6, page: nextPage);
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
    _saveLastSection('city', cityJson: {
      'id': city.id,
      'name': city.name,
    });
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

  // ── Featured place navigation ─────────────────────────────────────────────
  // PlaceDetailsScreen expects a full CityModel/CategoryModel (it only reads
  // .name off either), but a featured place can belong to any city/category
  // across the whole platform. Resolve against what's already cached
  // (_cities, _cachedCategories); fall back to a minimal model built from
  // the place's own embedded city map / categoryLinks when the match isn't
  // in cache yet (e.g. cities still loading).
  CityModel _cityForPlace(PlaceModel place) {
    final cached = _cities.where((c) => c.id == place.cityId).firstOrNull;
    if (cached != null) return cached;
    return CityModel.fromJson({
      ...?place.city,
      'id': place.cityId,
      'name': place.cityName.isNotEmpty ? place.cityName : 'Resort City',
    });
  }

  CategoryModel? _findCategoryById(List<CategoryModel> tree, String id) {
    for (final c in tree) {
      if (c.id == id) return c;
      final inChildren = _findCategoryById(c.children, id);
      if (inChildren != null) return inChildren;
    }
    return null;
  }

  CategoryModel _categoryForPlace(PlaceModel place) {
    if (place.categoryLinks.isEmpty) {
      return const CategoryModel(
          id: '',
          name: '',
          slug: '',
          isActive: false,
          children: [],
          sortOrder: 0);
    }
    final link = place.categoryLinks.first;
    return _findCategoryById(_cachedCategories, link.categoryId) ??
        CategoryModel(
          id: link.categoryId,
          name: link.categoryName,
          slug: link.categorySlug,
          isActive: true,
          children: const [],
          sortOrder: 0,
        );
  }

  void _goToFeaturedPlace(PlaceModel place) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => PlaceDetailsScreen(
          city: _cityForPlace(place),
          category: _categoryForPlace(place),
          place: place,
        ),
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
          // FIX: was Tween<<Offset>
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  // ── Focus the inline hero search field ────────────────────────────────────
  // Search now lives inline in the hero (not a popup) — reached from the
  // mobile menu's "Search" item by scrolling back to the top and focusing it.
  void _focusHeroSearch() {
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _heroSearchFocusNode.requestFocus();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    emailLinkResultNotifier.removeListener(_onEmailLinkResult);
    _scrollCtrl.dispose();
    _heroCtrl.dispose();
    _revealCtrl.dispose();
    _kenBurnsCtrl.dispose();
    _scrollCueCtrl.dispose();
    _heroSearchFocusNode.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadAuthState();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Maintenance mode blocks tourists only — admins still need to get in to
    // turn it back off, and MainAdmin-only screens already gate themselves.
    if (_maintenanceMode && !_isAdmin) {
      return _MaintenancePage(message: _maintenanceMessage);
    }

    final w = MediaQuery.of(context).size.width;
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: RC.navy,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              SliverToBoxAdapter(child: _hero(w)),
              SliverToBoxAdapter(child: _featuredPlacesSection(w)),
              SliverToBoxAdapter(child: _citiesSection(w)),
              SliverToBoxAdapter(child: _blogSection(w)),
              SliverToBoxAdapter(child: _statsSection(w)),
              SliverToBoxAdapter(child: _footer(w)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PalmnaziNavBar(
              heroOpacity: navOpacity,
              onDestinationsTap: () => _scrollToKey(_citiesKey),
              onCategoriesTap: _openCategoriesOverlay,
              onBlogTap: () => _scrollToKey(_blogKey),
              onSearchTap: _focusHeroSearch,
              onLogoTap: _isAdmin ? _goToAdminWithAuthCheck : null,
            ),
          ),
        ],
      ),
    );
  }

  void _goToAccount() async {
    _saveLastSection('account');
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const AccountScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
    if (mounted) _loadAuthState();
  }

  // ── Footer: Company links ─────────────────────────────────────────────────
  void _goToAbout() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const AboutScreen()));

  void _goToContact() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ContactScreen()));

  void _goToCareers() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const CareersScreen()));

  // ── Footer: Legal links ────────────────────────────────────────────────────
  void _goToPrivacyPolicy() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const StaticPageScreen(
            slug: 'privacy-policy',
            fallbackTitle: 'Privacy Policy',
            fallbackLastUpdated: 'July 2026',
            fallbackSections: [
              StaticInfoSection(
                heading: 'What We Collect',
                body:
                    'When you create an account or make a booking, we collect the '
                    'information you provide directly — name, email, phone number, '
                    'and payment method details needed to process a booking. We '
                    'also collect basic usage data (pages visited, searches made) '
                    'to improve the platform.',
              ),
              StaticInfoSection(
                heading: 'How We Use It',
                body:
                    'Your information is used to create and manage your bookings, '
                    'communicate with you about your trips, and improve the places '
                    'and experiences we surface to you. We do not sell your '
                    'personal information to third parties.',
              ),
              StaticInfoSection(
                heading: 'Sharing With Place Operators',
                body:
                    'When you make a booking, the relevant details (your name and '
                    'contact information, booking dates) are shared with the '
                    'place you booked so they can fulfil your reservation.',
              ),
              StaticInfoSection(
                heading: 'Your Choices',
                body:
                    'You can review, update, or request deletion of your account '
                    'information at any time from your Account page, or by '
                    'contacting us directly.',
              ),
              StaticInfoSection(
                heading: 'Contact',
                body:
                    'Questions about this policy can be sent through our Contact '
                    'Us page.',
              ),
            ],
          ),
        ),
      );

  void _goToTermsOfService() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const StaticPageScreen(
            slug: 'terms-of-service',
            fallbackTitle: 'Terms of Service',
            fallbackLastUpdated: 'July 2026',
            fallbackSections: [
              StaticInfoSection(
                heading: 'Using Palmnazi',
                body: 'Palmnazi Resort Cities connects travellers with resort '
                    'destinations, places, and experiences across Africa. By '
                    'creating an account or making a booking, you agree to '
                    'provide accurate information and use the platform lawfully.',
              ),
              StaticInfoSection(
                heading: 'Bookings & Payments',
                body: 'Bookings are requests sent to the relevant place — '
                    'confirmation, pricing, and cancellation terms are set by '
                    'that place and shown to you before you confirm. Payment '
                    'methods available depend on what each place has enabled.',
              ),
              StaticInfoSection(
                heading: 'Account Responsibility',
                body:
                    'You are responsible for keeping your account credentials '
                    'secure and for all activity under your account.',
              ),
              StaticInfoSection(
                heading: 'Changes to These Terms',
                body: 'We may update these terms from time to time as the '
                    'platform grows; continued use after an update means you '
                    'accept the revised terms.',
              ),
            ],
          ),
        ),
      );

  void _goToCookiePolicy() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const StaticPageScreen(
            slug: 'cookie-policy',
            fallbackTitle: 'Cookie Policy',
            fallbackLastUpdated: 'July 2026',
            fallbackSections: [
              StaticInfoSection(
                heading: 'What Cookies Are Used For',
                body:
                    'On the web, Palmnazi uses local browser storage to keep you '
                    'signed in between visits and to remember where you left off '
                    '(such as the resort city you were browsing) so you can '
                    'resume smoothly after signing in.',
              ),
              StaticInfoSection(
                heading: 'No Third-Party Ad Tracking',
                body:
                    "We don't use advertising or cross-site tracking cookies. "
                    'Storage is used strictly to make the app work.',
              ),
              StaticInfoSection(
                heading: 'Managing Storage',
                body: 'You can clear your browser\'s local storage at any time '
                    'from your browser settings; this will sign you out and '
                    'reset any remembered navigation state.',
              ),
            ],
          ),
        ),
      );

  // ── Last-section persistence helpers ─────────────────────────────────────
  static void _saveLastSection(String section,
      {Map<String, dynamic>? cityJson}) {
    try {
      html.window.localStorage[_kLastSectionKey] = section;
      if (cityJson != null) {
        html.window.localStorage[_kLastCityPayload] = jsonEncode(cityJson);
      } else {
        html.window.localStorage.remove(_kLastCityPayload);
      }
    } catch (_) {/* localStorage blocked — silently ignore */}
  }

  void _resumeLastSection() {
    String? section;
    String? cityPayload;
    try {
      section = html.window.localStorage[_kLastSectionKey];
      cityPayload = html.window.localStorage[_kLastCityPayload];
    } catch (_) {
      return;
    }

    if (section == null || section.isEmpty) return;

    // Clear before navigating so a crashed navigate doesn't loop.
    try {
      html.window.localStorage.remove(_kLastSectionKey);
      html.window.localStorage.remove(_kLastCityPayload);
    } catch (_) {}

    if (section == 'account') {
      _goToAccount();
    } else if (section == 'city' && cityPayload != null) {
      try {
        final raw = jsonDecode(cityPayload) as Map<String, dynamic>;
        final cityId = raw['id'] as String?;
        if (cityId == null) return;

        final city = _cities.cast<CityModel?>().firstWhere(
              (c) => c?.id == cityId,
              orElse: () => null,
            );
        if (city != null) {
          _goToCity(city);
        }
      } catch (_) {}
    }
  }

  // ── Auth-gated admin navigation ──────────────────────────────────────────
  Future<void> _goToAdminWithAuthCheck() async {
    if (!_isAdmin) {
      _log.d(
          'LandingPage._goToAdminWithAuthCheck: blocked non-admin access attempt. role=$_userRole');
      return;
    }

    final accessToken = await ApiClient.getAccessToken();
    final isLoggedIn = accessToken != null && accessToken.isNotEmpty;

    if (isLoggedIn) {
      if (!mounted) return;
      _log.i(
          'LandingPage._goToAdminWithAuthCheck: admin access granted — navigating to AdminDashboard');
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, anim, __) => const AdminDashboard(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 320),
        ),
      );
      if (mounted) _loadAuthState();
    } else {
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

      final newToken = await ApiClient.getAccessToken();
      if (!mounted) return;

      // FIX: was `_loadAuthState()` (fire-and-forget). Must be awaited so that
      // _checkAdminRole() completes and _isAdmin is updated before we read it.
      await _loadAuthState();
      if (!mounted) return;

      if (newToken != null && newToken.isNotEmpty) {
        if (_isAdmin) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, anim, __) => const AdminDashboard(),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 320),
            ),
          );
        } else {
          _log.w(
              'LandingPage._goToAdminWithAuthCheck: user logged in but is not admin — blocking admin navigation');
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HERO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _hero(double w) {
    final viewport = MediaQuery.of(context).size;
    final isMobile = w < 600;
    final isTablet = w >= 600 && w < 1024;
    final isShort = viewport.height < 560;
    final hPad = isMobile ? 20.0 : (isTablet ? 36.0 : 48.0);

    final heroHeight = isShort
        ? math.max(440.0, viewport.height * 0.94)
        : (isMobile ? 700.0 : (isTablet ? 740.0 : 800.0));

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // ── Slow Ken-Burns background zoom ──────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _kenBurnsScale,
              builder: (_, child) =>
                  Transform.scale(scale: _kenBurnsScale.value, child: child),
              child: Image.asset(
                'assets/images/homepage.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: RC.heroGrad),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99121F2E),
                    Color(0xB31C2E42),
                    Color(0xE0121F2E),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DotGridPainter(color: RC.gold.withValues(alpha: 0.03)),
            ),
          ),
          Positioned(
              top: -100,
              right: -60,
              child: _glow(340, RC.gold.withValues(alpha: 0.09))),
          Positioned(
              bottom: 30,
              left: -50,
              child: _glow(260, RC.teal.withValues(alpha: 0.05))),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    hPad, isMobile ? 90 : 110, hPad, isShort ? 16 : 28),
                // A SingleChildScrollView is a structural guarantee against
                // RenderFlex overflow on any extreme aspect ratio (short
                // landscape phones, resized desktop windows) rather than
                // relying purely on font/padding tuning to always fit.
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _heroFade,
                        child: SlideTransition(
                          position: _heroSlide,
                          child: _tagPill(
                              '✦  For Every Trip, Every Traveller', RC.gold),
                        ),
                      ),
                      SizedBox(height: isShort ? 16 : 26),
                      // Search moved to the top of the hero, right under the
                      // tag pill, so it's the first interactive thing a
                      // visitor sees rather than buried below the copy.
                      FadeTransition(
                        opacity: _heroFade,
                        child: _HeroSearch(
                          isMobile: isMobile,
                          width: w,
                          focusNode: _heroSearchFocusNode,
                          onOpenCategories: _openCategoriesOverlay,
                        ),
                      ),
                      SizedBox(height: isShort ? 20 : 34),
                      FadeTransition(
                        opacity: _heroFade,
                        child: SlideTransition(
                          position: _heroSlide,
                          child: _RotatingHeadline(
                            fontSize: isMobile ? 36 : (isTablet ? 48 : 62),
                          ),
                        ),
                      ),
                      if (!isShort) ...[
                        const SizedBox(height: 16),
                        FadeTransition(
                          opacity: _heroFade,
                          child: _TypewriterTagline(
                            fontSize: isMobile ? 15 : 18,
                          ),
                        ),
                      ],
                      if (!isShort) ...[
                        const SizedBox(height: 18),
                        FadeTransition(
                          opacity: _heroFade,
                          child: _heroAudienceBadges(),
                        ),
                      ],
                      if (!isShort) ...[
                        const SizedBox(height: 26),
                        FadeTransition(
                          opacity: _heroFade,
                          child: _heroQuickChips(),
                        ),
                      ],
                      if (isTablet || (!isMobile && !isShort)) ...[
                        const SizedBox(height: 28),
                        FadeTransition(
                          opacity: _heroFade,
                          child: _heroTrustStrip(),
                        ),
                      ],
                      SizedBox(height: isShort ? 14 : 26),
                      FadeTransition(
                        opacity: _heroFade,
                        child: _heroScrollCue(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroQuickChips() {
    final chips = [
      (Icons.location_city_outlined, 'Destinations'),
      (Icons.category_outlined, TourismLabels.categoryPlural),
      (Icons.hotel_outlined, 'Stays'),
      (Icons.groups_outlined, 'Meetings & Events'),
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
                  } else {
                    // Stays / Meetings & Events / Dining / Services all
                    // resolve to "browse by type" — the categories overlay
                    // is where every one of those is actually filterable.
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
                    Icon(c.$1, size: 14, color: RC.gold),
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

  // ── Audience badges — explicitly names who this platform is for, so a
  // business/group traveller doesn't have to guess whether they belong here.
  Widget _heroAudienceBadges() {
    const audiences = [
      'Leisure',
      'Business',
      'Groups',
      'Meetings & Events',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: audiences
          .map((label) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: RC.gold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: RC.gold.withValues(alpha: 0.30)),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ))
          .toList(),
    );
  }

  // ── Inline trust-stat strip — same figures used in _statsSection below ───
  Widget _heroTrustStrip() {
    final count = _cities.isEmpty ? '10' : '${_cities.length}';
    final items = [
      ('$count+', 'Resort Cities'),
      ('500+', 'Curated ${TourismLabels.placePlural}'),
      ('4.9★', 'Avg. Rating'),
      ('20K+', 'Guests Hosted'),
    ];
    return Wrap(
      spacing: 26,
      runSpacing: 10,
      children: items
          .map((it) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.$1,
                      style: const TextStyle(
                          color: RC.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text(it.$2,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12)),
                ],
              ))
          .toList(),
    );
  }

  // ── Scroll-cue affordance — bounces gently, tap-through to Destinations ──
  Widget _heroScrollCue() {
    return GestureDetector(
      onTap: () => _scrollToKey(_citiesKey),
      child: AnimatedBuilder(
        animation: _scrollCueOffset,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _scrollCueOffset.value),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('section_explore_resort_cities'),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: RC.gold.withValues(alpha: 0.85), size: 22),
          ],
        ),
      ),
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
  // FEATURED PLACES SECTION — admin-promoted businesses (PlaceModel.isFeatured)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _featuredPlacesSection(double w) {
    if (_featuredPlaces.isEmpty) return const SizedBox.shrink();

    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;
    const cardW = 260.0;
    const cardH = 300.0;

    return Container(
      color: RC.deepBlue,
      padding: EdgeInsets.fromLTRB(hPad, 56, hPad, 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('HANDPICKED', RC.gold),
              const SizedBox(height: 12),
              Text(
                'Featured Places',
                style: TextStyle(
                  color: RC.textPri,
                  fontSize: isMobile ? 26 : 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Promoted stays, dining and experiences our admins are '
                'highlighting right now.',
                style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: cardH,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _featuredPlaces.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 18),
                  itemBuilder: (_, i) => SizedBox(
                    width: cardW,
                    child: _FeaturedPlaceCard(
                      place: _featuredPlaces[i],
                      onTap: () => _goToFeaturedPlace(_featuredPlaces[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              _sectionLabel('DESTINATIONS', RC.gold),
              const SizedBox(height: 12),
              Text(
                'Explore Resort Cities',
                style: TextStyle(
                  color: RC.textPri,
                  fontSize: isMobile ? 28 : 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Handpicked resort destinations for every kind of trip — leisure escapes, team retreats, and everything in between.',
                style: TextStyle(color: RC.textSec, fontSize: 15, height: 1.6),
              ),
              if (_cities.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildCityRegionFilter(),
              ],
              const SizedBox(height: 32),
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
        Icon(Icons.cloud_off_rounded, color: RC.textMute, size: 48),
        const SizedBox(height: 14),
        Text(context.tr('empty_destinations_error'),
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
        Icon(Icons.location_city_outlined, color: RC.textMute, size: 56),
        const SizedBox(height: 16),
        Text(context.tr('empty_destinations_none'),
            style: TextStyle(color: RC.textSec, fontSize: 15)),
      ]));
    }

    final filtered = _filteredCities;
    if (filtered.isEmpty) {
      return Center(
          child: Column(children: [
        Icon(Icons.filter_alt_off_outlined, color: RC.textMute, size: 48),
        const SizedBox(height: 14),
        Text('No resort cities in "$_cityRegionFilter" yet',
            style: TextStyle(color: RC.textSec, fontSize: 15)),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _cityRegionFilter = null),
          child:
              const Text('Show all regions', style: TextStyle(color: RC.gold)),
        ),
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
            filtered.length,
            (i) => SizedBox(
                  width: cardW,
                  child: FadeTransition(
                    opacity: _revealFade,
                    child: _CityCard(
                        city: filtered[i], onTap: () => _goToCity(filtered[i])),
                  ),
                )),
      );
    });
  }

  List<CityModel> get _filteredCities => _cityRegionFilter == null
      ? _cities
      : _cities.where((c) => c.region == _cityRegionFilter).toList();

  Widget _buildCityRegionFilter() {
    final regions = _cities
        .map((c) => c.region)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (regions.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'All',
            selected: _cityRegionFilter == null,
            onTap: () => setState(() => _cityRegionFilter = null),
          ),
          const SizedBox(width: 8),
          ...regions.map((r) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: r,
                  selected: _cityRegionFilter == r,
                  onTap: () => setState(() => _cityRegionFilter = r),
                ),
              )),
        ],
      ),
    );
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
                            color: RC.textPri,
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
                          style: TextStyle(
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
                      label: Text(context.tr('section_load_more'),
                          style: const TextStyle(color: RC.teal, fontSize: 13)),
                    ),
                  ],
                ],
              ),
              if (_blogPosts.isNotEmpty) ...[
                const SizedBox(height: 22),
                _buildBlogCategoryFilter(),
              ],
              const SizedBox(height: 30),
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
                          style: TextStyle(color: RC.textMute, fontSize: 12),
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
        Icon(Icons.article_outlined, color: RC.textMute, size: 48),
        const SizedBox(height: 12),
        Text('No blog posts yet.', style: TextStyle(color: RC.textSec)),
        const SizedBox(height: 6),
        Text('Check back soon for travel guides and inspiration.',
            style: TextStyle(color: RC.textMute, fontSize: 13)),
      ]));
    }
    final filtered = _filteredBlogPosts;
    if (filtered.isEmpty) {
      return Center(
          child: Column(children: [
        Icon(Icons.filter_alt_off_outlined, color: RC.textMute, size: 44),
        const SizedBox(height: 12),
        Text('No articles tagged "$_blogCategoryFilter" yet',
            style: TextStyle(color: RC.textSec, fontSize: 14)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _blogCategoryFilter = null),
          child:
              const Text('Show all articles', style: TextStyle(color: RC.gold)),
        ),
      ]));
    }
    return LayoutBuilder(builder: (_, constraints) {
      final cols = isMobile ? 1 : (w < 1024 ? 2 : 3);
      const gap = 20.0;
      final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: filtered
            .map((post) => SizedBox(
                  width: cardW,
                  child: _BlogCard(post: post),
                ))
            .toList(),
      );
    });
  }

  List<BlogPost> get _filteredBlogPosts {
    final base = _blogCategoryFilter == null
        ? _blogPosts
        : _blogPosts
            .where((p) => p.categories.contains(_blogCategoryFilter))
            .toList();
    if (_featuredBlogSlugs.isEmpty) return base;
    // Featured posts first; original order preserved within each group.
    final indexed = base.asMap().entries.toList()
      ..sort((a, b) {
        final af = _featuredBlogSlugs.contains(a.value.slug) ? 1 : 0;
        final bf = _featuredBlogSlugs.contains(b.value.slug) ? 1 : 0;
        return af != bf ? bf.compareTo(af) : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Widget _buildBlogCategoryFilter() {
    final categories = _blogPosts.expand((p) => p.categories).toSet().toList()
      ..sort();
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'All',
            selected: _blogCategoryFilter == null,
            onTap: () => setState(() => _blogCategoryFilter = null),
          ),
          const SizedBox(width: 8),
          ...categories.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: c,
                  selected: _blogCategoryFilter == c,
                  onTap: () => setState(() => _blogCategoryFilter = c),
                ),
              )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _statsSection(double w) {
    final isMobile = w < 600;
    final hPad = isMobile ? 20.0 : 48.0;
    final count = _cities.isEmpty ? '10' : '${_cities.length}';

    final items = [
      (Icons.location_city_rounded, '$count+', 'Resort Cities', RC.teal),
      (
        Icons.place_rounded,
        '500+',
        'Curated ${TourismLabels.placePlural}',
        RC.gold
      ),
      (Icons.star_rounded, '4.9★', 'Avg. Rating', RC.coral),
      (Icons.people_alt_rounded, '20K+', 'Guests Hosted', RC.emerald),
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

    final exploreLinks = [
      ('Resort Cities', () => _scrollToKey(_citiesKey)),
      (TourismLabels.categoryPlural, _openCategoriesOverlay),
      ('All ${TourismLabels.placePlural}', _openCategoriesOverlay),
      ('Blog', () => _scrollToKey(_blogKey)),
    ];
    final companyLinks = [
      ('About Us', _goToAbout),
      ('Contact Us', _goToContact),
      ('Careers', _goToCareers),
    ];
    final legalLinksMobile = [
      ('Privacy Policy', _goToPrivacyPolicy),
      ('Terms of Service', _goToTermsOfService),
    ];
    final legalLinksDesktop = [
      ('Privacy Policy', _goToPrivacyPolicy),
      ('Terms of Service', _goToTermsOfService),
      ('Cookie Policy', _goToCookiePolicy),
    ];

    return Container(
      color: const Color(0xFF0E1826),
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
                          _footerLinks(
                              context.tr('footer_explore'), exploreLinks),
                          const SizedBox(height: 28),
                          _footerLinks('Company', companyLinks),
                          const SizedBox(height: 28),
                          _footerLinks('Legal', legalLinksMobile),
                        ])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(flex: 2, child: _footerBrand()),
                          const SizedBox(width: 40),
                          Expanded(
                              child: _footerLinks(
                                  context.tr('footer_explore'), exploreLinks)),
                          const SizedBox(width: 24),
                          Expanded(
                              child: _footerLinks('Company', companyLinks)),
                          const SizedBox(width: 24),
                          Expanded(
                              child: _footerLinks('Legal', legalLinksDesktop)),
                        ]),
              const SizedBox(height: 40),
              Divider(color: Colors.white.withValues(alpha: 0.07)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                        '© 2026 Palmnazi Resort Cities. All rights reserved.',
                        style: TextStyle(color: RC.textMute, fontSize: 12)),
                  ),
                  if (!isMobile)
                    Text(context.tr('footer_made_with_love'),
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
          Text(
            context.tr('footer_tagline'),
            style: TextStyle(color: RC.textSec, fontSize: 13, height: 1.7),
          ),
        ],
      );

  Widget _footerLinks(String heading, List<(String, VoidCallback)> links) =>
      Column(
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
                child: _FooterLink(label: l.$1, onTap: l.$2),
              )),
        ],
      );

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
// _FilterChip — shared "All"/value filter pill used by the Resort Cities
// region filter and the Blog category filter.
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? RC.gold.withValues(alpha: 0.16) : RC.overlay(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? RC.gold.withValues(alpha: 0.70) : RC.overlay(0.15),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? RC.gold : RC.textSec,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FooterLink — footer nav item with a gold hover shift (desktop feedback).
// ─────────────────────────────────────────────────────────────────────────────
class _FooterLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _hovered ? RC.gold : RC.textSec,
            fontSize: 13,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RotatingHeadline — "Find Your Perfect" stays fixed; the second line cycles
// through a few destination-style words with a fade/slide transition.
// ─────────────────────────────────────────────────────────────────────────────
class _RotatingHeadline extends StatefulWidget {
  final double fontSize;
  const _RotatingHeadline({required this.fontSize});

  @override
  State<_RotatingHeadline> createState() => _RotatingHeadlineState();
}

class _RotatingHeadlineState extends State<_RotatingHeadline> {
  static const _words = [
    'Escape',
    'Adventure',
    'Retreat',
    'Venue',
    'Getaway',
    'Offsite'
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _words.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.bold,
      height: 1.1,
      letterSpacing: -0.8,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Find Your Perfect', style: style.copyWith(color: Colors.white)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: ShaderMask(
            key: ValueKey(_index),
            shaderCallback: (b) =>
                const LinearGradient(colors: [RC.gold, RC.goldMid])
                    .createShader(b),
            child: Text(_words[_index],
                style: style.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TypewriterTagline — types out one of a few taglines, pauses, then moves
// on to the next (no delete/backspace, just a clean cut to the next line).
// ─────────────────────────────────────────────────────────────────────────────
class _TypewriterTagline extends StatefulWidget {
  final double fontSize;
  const _TypewriterTagline({required this.fontSize});

  @override
  State<_TypewriterTagline> createState() => _TypewriterTaglineState();
}

class _TypewriterTaglineState extends State<_TypewriterTagline> {
  static const _lines = [
    'Handpicked resort cities across Africa, for leisure and business alike.',
    'From luxury stays to boardrooms — plan every trip in one place.',
    'Team retreats, group meetings, or solo getaways — all simplified here.',
  ];
  int _lineIndex = 0;
  int _charCount = 0;
  Timer? _typeTimer;
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _typeTimer?.cancel();
    _charCount = 0;
    _typeTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final full = _lines[_lineIndex];
      if (_charCount >= full.length) {
        timer.cancel();
        _pauseTimer = Timer(const Duration(milliseconds: 2200), () {
          if (!mounted) return;
          setState(() => _lineIndex = (_lineIndex + 1) % _lines.length);
          _startTyping();
        });
        return;
      }
      setState(() => _charCount++);
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = _lines[_lineIndex];
    final shown = full.substring(0, _charCount);
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: widget.fontSize,
          height: 1.6,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
        ),
        children: [
          TextSpan(text: shown),
          TextSpan(
            text: '|',
            style: TextStyle(
                color: RC.gold.withValues(alpha: 0.85),
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CountUpNumber — animates from 0 up to the value's leading numeric portion
// once when first built (e.g. "500+" counts up to 500 then shows "500+";
// "4.9★" counts up with one decimal then shows "4.9★"). No extra dependency
// (no visibility-detector) — relies on SliverToBoxAdapter children only being
// built once the viewport is about to need them, which approximates
// "animates in as you scroll to it" closely enough for a stat strip.
// ─────────────────────────────────────────────────────────────────────────────
class _CountUpNumber extends StatefulWidget {
  final String value;
  final Color color;
  const _CountUpNumber({required this.value, required this.color});

  @override
  State<_CountUpNumber> createState() => _CountUpNumberState();
}

class _CountUpNumberState extends State<_CountUpNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  double _target = 0;
  String _suffix = '';
  int _decimals = 0;

  @override
  void initState() {
    super.initState();
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(widget.value);
    if (match != null) {
      _target = double.tryParse(match.group(1)!) ?? 0;
      _suffix = widget.value.substring(match.end);
      _decimals = match.group(2) != null ? match.group(2)!.length - 1 : 0;
    } else {
      _suffix = widget.value;
    }
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final current = _target * _anim.value;
        final text = _decimals > 0
            ? current.toStringAsFixed(_decimals)
            : current.round().toString();
        return Text(
          '$text$_suffix',
          style: TextStyle(
              color: widget.color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.1),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatCard
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)
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
            child: _CountUpNumber(value: value, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: RC.textSec, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchDialog
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSearch extends StatefulWidget {
  final bool isMobile;
  final double width;
  final FocusNode focusNode;
  final VoidCallback onOpenCategories;

  const _HeroSearch({
    required this.isMobile,
    required this.width,
    required this.focusNode,
    required this.onOpenCategories,
  });

  @override
  State<_HeroSearch> createState() => _HeroSearchState();
}

class _HeroSearchState extends State<_HeroSearch> {
  final _ctrl = TextEditingController();
  final _layerLink = LayerLink();
  Timer? _debounce;
  int _requestId = 0;
  OverlayEntry? _overlayEntry;

  // null = show results across every type (the default, live-search mode).
  // Non-null = the tourist tapped a filter chip to narrow an already-fetched
  // result set — this never triggers a new network call.
  _SearchType? _filter;

  bool _loading = false;
  bool _searched = false;
  List<_SearchResult> _allResults = [];
  String? _error;

  static const _labels = {
    _SearchType.city: ('City', Icons.location_city_outlined),
    _SearchType.place: (TourismLabels.placeSingular, Icons.place_outlined),
    _SearchType.category: (
      TourismLabels.categorySingular,
      Icons.category_outlined
    ),
    _SearchType.blog: ('Blog', Icons.article_outlined),
  };

  double get _fieldWidth =>
      widget.isMobile ? widget.width - 40 : math.min(widget.width - 96, 560.0);

  List<_SearchResult> get _visibleResults => _filter == null
      ? _allResults
      : _allResults.where((r) => r.type == _filter).toList();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _debounce?.cancel();
    _removeOverlay();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {}); // refresh the field's focus-driven border highlight
    if (widget.focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _allResults = [];
        _searched = false;
        _loading = false;
        _error = null;
      });
      _updateOverlay();
      return;
    }
    setState(() => _loading = true);
    _updateOverlay();
    _debounce = Timer(const Duration(milliseconds: 400), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    final myRequestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    _updateOverlay();
    try {
      // Every type is searched concurrently so the panel shows a single,
      // unified live result list — the filter chips below just narrow what's
      // already been fetched, they don't trigger another round-trip.
      // Each branch has its own catchError so one failing type (e.g. a
      // search param unsupported server-side, or a CORS failure on web)
      // degrades to an empty list for that type instead of failing the
      // whole search.
      final results = await Future.wait([
        _searchTypeSafely(q, _SearchType.city),
        _searchTypeSafely(q, _SearchType.place),
        _searchTypeSafely(q, _SearchType.category),
        _searchTypeSafely(q, _SearchType.blog),
      ]);
      // A newer keystroke's request may have already landed — ignore a
      // stale, slower response so it can't clobber fresher results.
      if (myRequestId != _requestId || !mounted) return;
      setState(() {
        _allResults = results.expand((r) => r).toList();
        _loading = false;
        _searched = true;
      });
      _updateOverlay();
    } catch (e, st) {
      developer.log('Unexpected failure running search for "$q"',
          name: 'LandingSearch', error: e, stackTrace: st);
      if (myRequestId != _requestId || !mounted) return;
      setState(() {
        _error = 'Search failed. Please try again.';
        _loading = false;
        _searched = true;
      });
      _updateOverlay();
    }
  }

  Future<List<_SearchResult>> _searchTypeSafely(
      String q, _SearchType type) async {
    try {
      return await _LandingApi.search(q, type);
    } catch (e, st) {
      developer.log('Search failed for type=$type, query="$q"',
          name: 'LandingSearch', error: e, stackTrace: st);
      return const [];
    }
  }

  // ── Anchored overlay (replaces the old popup Dialog) ──────────────────────
  void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _buildOverlayContent());
    overlay.insert(_overlayEntry!);
  }

  void _updateOverlay() => _overlayEntry?.markNeedsBuild();

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _closeAndUnfocus() {
    widget.focusNode.unfocus();
    _removeOverlay();
  }

  Widget _buildOverlayContent() {
    return Positioned(
      width: _fieldWidth,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 62),
        child: TapRegion(
          groupId: 'hero-search',
          onTapOutside: (_) => _closeAndUnfocus(),
          child: Material(
            color: Colors.transparent,
            child: _buildPanel(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: 'hero-search',
      child: CompositedTransformTarget(
        link: _layerLink,
        child: _buildField(),
      ),
    );
  }

  Widget _buildField() {
    final focused = widget.focusNode.hasFocus;
    return Container(
      width: _fieldWidth,
      padding: EdgeInsets.symmetric(horizontal: widget.isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: RC.deepBlue.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
            color: RC.gold.withValues(alpha: focused ? 0.60 : 0.32),
            width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6)),
          BoxShadow(color: RC.gold.withValues(alpha: 0.10), blurRadius: 24),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: RC.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: widget.focusNode,
              onChanged: _onQueryChanged,
              style: TextStyle(color: RC.textPri, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.isMobile
                    ? 'Search destinations…'
                    : 'Search cities, ${TourismLabels.placePlural.toLowerCase()}, ${TourismLabels.categoryPlural.toLowerCase()}…',
                hintStyle: TextStyle(color: RC.textSec, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(color: RC.gold, strokeWidth: 2),
              ),
            )
          else if (_ctrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _ctrl.clear();
                _onQueryChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close_rounded, color: RC.textMute, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 440),
      decoration: BoxDecoration(
        color: RC.deepBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RC.gold.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 30,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_allResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [null, ..._SearchType.values].map((t) {
                    final selected = t == _filter;
                    final count = t == null
                        ? _allResults.length
                        : _allResults.where((r) => r.type == t).length;
                    if (t != null && count == 0) return const SizedBox.shrink();
                    final label = t == null ? 'All' : _labels[t]!.$1;
                    final icon =
                        t == null ? Icons.apps_rounded : _labels[t]!.$2;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _filter = t);
                          _updateOverlay();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected
                                ? RC.gold.withValues(alpha: 0.15)
                                : RC.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? RC.gold.withValues(alpha: 0.50)
                                  : RC.overlay(0.06),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon,
                                  size: 13,
                                  color: selected ? RC.gold : RC.textMute),
                              const SizedBox(width: 5),
                              Text('$label ($count)',
                                  style: TextStyle(
                                    color: selected ? RC.gold : RC.textMute,
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          Flexible(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (!_searched && !_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_rounded,
                color: RC.textMute.withValues(alpha: 0.5), size: 40),
            const SizedBox(height: 10),
            Text(
                'Type to search across cities, ${TourismLabels.placePlural.toLowerCase()} and ${TourismLabels.categoryPlural.toLowerCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(color: RC.textMute, fontSize: 13)),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(color: RC.gold, strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: RC.coral, size: 32),
          const SizedBox(height: 10),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: RC.textSec, fontSize: 13)),
        ]),
      );
    }
    final visible = _visibleResults;
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              color: RC.textMute.withValues(alpha: 0.6), size: 40),
          const SizedBox(height: 10),
          Text(
            'No results found for "${_ctrl.text.trim()}"',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: RC.textSec, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different spelling or search term.',
            style: TextStyle(color: RC.textMute, fontSize: 12),
          ),
        ]),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      itemCount: visible.length,
      separatorBuilder: (_, __) => Divider(color: RC.overlay(0.05), height: 1),
      itemBuilder: (_, i) {
        final r = visible[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: _resultIcon(r),
          title: Text(r.name,
              style: TextStyle(
                  color: RC.textPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          subtitle: r.subtitle != null && r.subtitle!.isNotEmpty
              ? Text(r.subtitle!,
                  style: TextStyle(color: RC.textMute, fontSize: 11))
              : null,
          trailing: Icon(Icons.arrow_forward_ios_rounded,
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
    final color = t == _SearchType.blog ? RC.teal : RC.gold;
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
    _closeAndUnfocus();
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
        // The place search result only carries a lean map (id/name/embedded
        // city), not the full PlaceModel + CategoryModel that
        // PlaceDetailsScreen needs — so the honest landing spot is that
        // attraction's city page, where the tourist can drill in themselves.
        final cityJson = (r.raw is Map<String, dynamic>)
            ? (r.raw as Map<String, dynamic>)['city']
            : null;
        if (cityJson is Map<String, dynamic>) {
          try {
            final city = CityModel.fromJson(cityJson);
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, anim, __) => ResortCityScreen(city: city),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: const Duration(milliseconds: 350),
              ),
            );
            return;
          } catch (_) {
            // Fall through to the categories overlay below.
          }
        }
        widget.onOpenCategories();
      case _SearchType.category:
        widget.onOpenCategories();
      case _SearchType.blog:
        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PublicCategoriesOverlay
// ─────────────────────────────────────────────────────────────────────────────
class _PublicCategoriesOverlay extends StatefulWidget {
  // FIX: was List<<CategoryModel>
  final List<CategoryModel> preloaded;
  const _PublicCategoriesOverlay({this.preloaded = const []});

  @override
  State<_PublicCategoriesOverlay> createState() =>
      _PublicCategoriesOverlayState();
}

class _PublicCategoriesOverlayState extends State<_PublicCategoriesOverlay> {
  // FIX: was List<<CategoryModel>
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
      _roots = List.of(widget.preloaded);
      _loading = false;
      if (_roots.length <= 6) _expanded.addAll(_roots.map((r) => r.id));
    } else {
      _fetch();
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

  // FIX: was List<<CategoryModel>
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
          icon: Icon(Icons.close_rounded, color: RC.textSec),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TourismLabels.categoryPlural,
                style: TextStyle(
                    color: RC.textPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text('Browse all ${TourismLabels.categoryPlural}',
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
                style: TextStyle(color: RC.textPri, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Filter categories…',
                  hintStyle: TextStyle(color: RC.textMute, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: RC.teal, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
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
        Icon(Icons.cloud_off_rounded, color: RC.textMute, size: 48),
        const SizedBox(height: 14),
        Text('Could not load categories', style: TextStyle(color: RC.textSec)),
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
          style: TextStyle(color: RC.textSec, fontSize: 14),
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
// _RootCategoryTile
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
        border: Border.all(color: RC.overlay(0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: root.children.isNotEmpty ? () => onToggle(root.id) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
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
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(root.name,
                        style: TextStyle(
                            color: RC.textPri,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (root.description != null &&
                        root.description!.isNotEmpty)
                      Text(root.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: RC.textMute, fontSize: 11)),
                  ],
                )),
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
          if (expanded && root.children.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: RC.overlay(0.06))),
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
                              : Icon(Icons.subdirectory_arrow_right_rounded,
                                  color: RC.textMute, size: 14),
                          title: Text(child.name,
                              style:
                                  TextStyle(color: RC.textSec, fontSize: 13)),
                          subtitle: child.placeLinksCount > 0
                              ? Text('${child.placeLinksCount} places',
                                  style: TextStyle(
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
// _CityCard
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Featured place card — compact horizontal-strip card for _featuredPlacesSection
// ─────────────────────────────────────────────────────────────────────────────
class _FeaturedPlaceCard extends StatefulWidget {
  final PlaceModel place;
  final VoidCallback onTap;
  const _FeaturedPlaceCard({required this.place, required this.onTap});

  @override
  State<_FeaturedPlaceCard> createState() => _FeaturedPlaceCardState();
}

class _FeaturedPlaceCardState extends State<_FeaturedPlaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final categoryName =
        p.categoryLinks.isNotEmpty ? p.categoryLinks.first.categoryName : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? RC.gold.withValues(alpha: 0.20)
                    : Colors.black.withValues(alpha: 0.35),
                blurRadius: _hovered ? 24 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: (p.coverImage ?? '').isNotEmpty
                      ? Image.network(p.coverImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeFallback())
                      : _placeFallback(),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.90),
                        ],
                        stops: const [0.30, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: RC.gold.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded,
                          size: 12, color: Colors.black87),
                      const SizedBox(width: 3),
                      Text(context.tr('section_featured'),
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        if (p.cityName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            const Icon(Icons.location_on_outlined,
                                size: 11, color: RC.teal),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(p.cityName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: RC.textSec, fontSize: 11.5)),
                            ),
                          ]),
                        ],
                        if (categoryName != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(categoryName,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10.5)),
                          ),
                        ],
                      ],
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

  Widget _placeFallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RC.tealDark, RC.navy],
          ),
        ),
        child: Center(
          child: Icon(Icons.storefront_rounded,
              size: 56, color: RC.teal.withValues(alpha: 0.25)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Maintenance page — shown to tourists when SystemSettings.maintenanceMode
// is on (see AdminSettingsScreen). Admins sign in from here to turn it off.
// ─────────────────────────────────────────────────────────────────────────────
class _MaintenancePage extends StatelessWidget {
  final String message;
  const _MaintenancePage({required this.message});

  @override
  Widget build(BuildContext context) {
    final display = message.trim().isNotEmpty
        ? message.trim()
        : "We're carrying out scheduled maintenance — please check back shortly.";
    return Scaffold(
      backgroundColor: RC.navy,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.build_circle_outlined, size: 64, color: RC.gold),
              const SizedBox(height: 20),
              Text(context.tr('section_under_maintenance'),
                  style: TextStyle(
                      color: RC.textPri,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(display,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: RC.textSec, fontSize: 14, height: 1.5)),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthScreen(isLogin: true))),
                icon: Icon(Icons.admin_panel_settings_outlined,
                    color: RC.textMute, size: 16),
                label: Text(context.tr('section_admin_sign_in'),
                    style: TextStyle(color: RC.textMute, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                      ? RC.gold.withValues(alpha: 0.20)
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
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.circle,
                              size: 6, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(context.tr('section_open'),
                              style: const TextStyle(
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
                                  style: TextStyle(
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
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(context.tr('footer_explore'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.arrow_forward_rounded,
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
        decoration: BoxDecoration(
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
// _BlogCard
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BlogPostDetailScreen(slug: post.slug)),
        ),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            decoration: BoxDecoration(
              color: RC.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RC.overlay(0.07)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20), blurRadius: 12)
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
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
                          style: TextStyle(
                              color: RC.textPri,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Text(post.excerpt,
                          style: TextStyle(
                              color: RC.textSec, fontSize: 12, height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 14),
                      if (post.formattedDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 11, color: RC.textMute),
                            const SizedBox(width: 4),
                            Text(post.formattedDate,
                                style: TextStyle(
                                    color: RC.textMute, fontSize: 11)),
                            if (post.cityName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.location_on_outlined,
                                  size: 11, color: RC.textMute),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(post.cityName,
                                    style: TextStyle(
                                        color: RC.textMute, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                        ),
                      Row(children: [
                        Icon(Icons.person_outline_rounded,
                            size: 13, color: RC.textMute),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(post.authorName,
                                style:
                                    TextStyle(color: RC.textMute, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                        if (post.readingTimeMinutes != null) ...[
                          Icon(Icons.schedule_rounded,
                              size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.readingTimeMinutes}m',
                              style:
                                  TextStyle(color: RC.textMute, fontSize: 11)),
                        ],
                        if (post.views != null && post.views! > 0) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.visibility_outlined,
                              size: 12, color: RC.textMute),
                          const SizedBox(width: 3),
                          Text('${post.views}',
                              style:
                                  TextStyle(color: RC.textMute, fontSize: 11)),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _SkeletonBox
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
            border: Border.all(color: RC.overlay(0.05)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DotGridPainter
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
