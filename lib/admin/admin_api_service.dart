import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTE: This service uses ApiClient.authPatch for all PATCH calls.
// If that method does not yet exist in api_client.dart, add it alongside
// authPut — identical implementation but with method: 'PATCH'.
//
// NOTE v2.0: unlinkPlaceCategories uses DELETE with a JSON body.
// Ensure ApiClient.authDelete accepts an optional `body` parameter, e.g.
//
//   static Future<http.Response> authDelete(String path,
//       {Map<String, dynamic>? body}) async { ... }
//
// NOTE v3.0 (Blog): authGetWithParams already handles query params as a Map.
// All new blog filter/search params are passed via queryParams.
// ─────────────────────────────────────────────────────────────────────────────

final Logger _adminLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// All backend endpoint strings — single source of truth
// ─────────────────────────────────────────────────────────────────────────────
abstract class _Ep {
  // Cities
  static const String cities = '/api/cities';
  static String cityById(String id) => '/api/cities/$id';

  // Categories  (global, no city scope)
  static const String categories = '/api/categories';
  static String categoryById(String id) => '/api/categories/$id';
  static String deleteCategory(String id, {bool cascade = false}) =>
      '/api/categories/$id${cascade ? '?cascade=true' : ''}';

  // Places — core CRUD
  static const String places = '/api/places';
  static String placeById(String id) => '/api/places/$id';
  static String placeLocation(String id) => '/api/places/$id/location';
  static String placeContact(String id) => '/api/places/$id/contact';
  static String placeAttributes(String id) => '/api/places/$id/attributes';
  static String placeMedia(String id) => '/api/places/$id/media';
  static String placeBooking(String id) => '/api/places/$id/booking';
  static String placeCategories(String id) => '/api/places/$id/categories';
  static String placeValidate(String id) => '/api/places/$id/submit';
  static String placeSubmit(String id) => '/api/places/$id/submit';

  // Accommodation
  static String placeRooms(String placeId) => '/api/places/$placeId/rooms';
  static String roomById(String roomId) => '/api/rooms/$roomId';

  // Dining
  static String placeMenuSections(String placeId) =>
      '/api/places/$placeId/menu-sections';
  static String placeMenuItems(String placeId) =>
      '/api/places/$placeId/menu-items';
  static String menuItemById(String itemId) => '/api/menu-items/$itemId';

  // Entertainment
  static String placeShows(String placeId) => '/api/places/$placeId/shows';
  static String placePerformances(String placeId) =>
      '/api/places/$placeId/performances';
  static String performanceById(String perfId) =>
      '/api/performances/$perfId';

  // Cultural
  static String placeExhibitions(String placeId) =>
      '/api/places/$placeId/exhibitions';
  static String placeArtifacts(String placeId) =>
      '/api/places/$placeId/artifacts';

  // Dashboard
  static const String adminStats = '/api/stats';

  // ── Blog ─────────────────────────────────────────────────────────────────
  static const String blog       = '/api/blog';
  static const String blogSearch = '/api/blog/search';
  static const String blogDrafts = '/api/blog/drafts';

  static String blogBySlug(String slug)        => '/api/blog/$slug';
  static String blogHardDelete(String slug)    => '/api/blog/$slug?hard=true';
  static String blogViews(String slug)         => '/api/blog/$slug/views';
  static String blogLike(String slug)          => '/api/blog/$slug/like';
  static String blogComments(String slug)      => '/api/blog/$slug/comments';

  // Filter endpoints (public-facing but also useful for admin)
  static const String blogByCategory = '/api/blog/categories';
  static const String blogByTag      = '/api/blog/tags';
  static String blogByAuthor(String authorId) => '/api/blog/author/$authorId';
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminApiException
// ─────────────────────────────────────────────────────────────────────────────
class AdminApiException implements Exception {
  final int? statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  const AdminApiException({
    required this.message,
    this.statusCode,
    this.errors,
  });

  String? fieldError(String field) {
    // Format 1: POST 400 — Zod-style nested errors
    final v = errors?[field];
    if (v is List && v.isNotEmpty) return v.first.toString();
    if (v is Map) {
      final errs = v['_errors'];
      if (errs is List && errs.isNotEmpty) return errs.first.toString();
    }
    if (v is String) return v;

    // Format 2: PUT 400 — flat fieldErrors wrapper
    final fieldErrors = errors?['fieldErrors'];
    if (fieldErrors is Map) {
      final fe = fieldErrors[field];
      if (fe is List && fe.isNotEmpty) return fe.first.toString();
      if (fe is String) return fe;
    }

    return null;
  }

  @override
  String toString() =>
      'AdminApiException(${statusCode != null ? "$statusCode " : ""}$message)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminApiService
// ─────────────────────────────────────────────────────────────────────────────
class AdminApiService {

  // ── Response unwrapping helpers ──────────────────────────────────────────

  Map<String, dynamic> _unwrapObject(
      http.Response response, String method, String endpoint) {
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
      return body;
    }
    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  List<dynamic> _unwrapList(
      http.Response response, String method, String endpoint) {
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'];
      if (data is List) return data;
      for (final key in [
        'places', 'categories', 'rooms',
        'posts', 'drafts',
        'comments',
        'shows', 'performances',
        'exhibitions', 'artifacts',
        'menuSections', 'menuItems',
      ]) {
        if (data is Map && data.containsKey(key)) return data[key] as List;
        if (body.containsKey(key)) return body[key] as List;
      }
      return [];
    }
    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  void _unwrapDelete(
      http.Response response, String method, String endpoint) {
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = ApiClient.parseBody(response);
    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  Never _throwFromBody(Map<String, dynamic> body, int statusCode,
      String method, String endpoint) {
    final errors  = body['errors'] as Map<String, dynamic>?;
    final message = body['message'] as String? ??
        body['error'] as String? ??
        (errors != null
            ? 'Validation failed — check the highlighted fields'
            : 'Request failed ($statusCode)');
    _adminLog.e(
      '❌ [AdminApiService] $method $endpoint → $statusCode\n'
      '   message: $message'
      '${errors != null ? "\n   errors: $errors" : ""}',
    );
    throw AdminApiException(
        statusCode: statusCode, message: message, errors: errors);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESORT CITIES
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<CityModel>> getCities({Map<String, String>? filters}) async {
    _adminLog.i('🏙️  [AdminApiService] GET cities  filters=$filters');
    final response = await ApiClient.authGetWithParams(
      _Ep.cities,
      queryParams: filters,
    );
    final list = _unwrapList(response, 'GET', _Ep.cities);
    return list
        .map((e) => CityModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CityModel> getCityById(String id) async {
    final ep = _Ep.cityById(id);
    final response = await ApiClient.authGet(ep);
    return CityModel.fromJson(_unwrapObject(response, 'GET', ep));
  }

  Future<CityModel> createCity(Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createCity  payload=$payload');
    final response = await ApiClient.authPost(_Ep.cities, body: payload);
    return CityModel.fromJson(_unwrapObject(response, 'POST', _Ep.cities));
  }

  Future<CityModel> updateCity(String id, Map<String, dynamic> payload) async {
    final ep = _Ep.cityById(id);
    final response = await ApiClient.authPut(ep, body: payload);
    return CityModel.fromJson(_unwrapObject(response, 'PUT', ep));
  }

  Future<void> deleteCity(String id) async {
    final ep = _Ep.cityById(id);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CATEGORIES
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<CategoryModel>> getCategories({
    bool? isActive,
    String? parentId,
    bool includeChildren = false,
  }) async {
    _adminLog.i('📂 [AdminApiService] GET categories');
    final params = <String, String>{};
    if (isActive != null) params['isActive'] = isActive.toString();
    if (parentId != null) params['parentId'] = parentId;
    if (includeChildren) params['includeChildren'] = 'true';

    final response = await ApiClient.authGetWithParams(
      _Ep.categories,
      queryParams: params.isEmpty ? null : params,
    );
    final list = _unwrapList(response, 'GET', _Ep.categories);
    return list
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CategoryModel>> getCategoryTree() async {
    final all = await getCategories(includeChildren: true);
    return all.where((c) => c.isRoot).toList();
  }

  Future<CategoryModel> createCategory(Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createCategory  payload=$payload');
    final response = await ApiClient.authPost(_Ep.categories, body: payload);
    return CategoryModel.fromJson(
        _unwrapObject(response, 'POST', _Ep.categories));
  }

  Future<CategoryModel> createSubcategory(
      String parentId, Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createSubcategory  parentId=$parentId');
    final merged = {...payload, 'parentId': parentId};
    final response = await ApiClient.authPost(_Ep.categories, body: merged);
    return CategoryModel.fromJson(
        _unwrapObject(response, 'POST', _Ep.categories));
  }

  Future<CategoryModel> updateCategory(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PUT updateCategory  id=$id');
    final ep = _Ep.categoryById(id);
    final response = await ApiClient.authPut(ep, body: payload);
    return CategoryModel.fromJson(_unwrapObject(response, 'PUT', ep));
  }

  Future<void> deleteCategory(String id, {bool cascade = false}) async {
    final ep = _Ep.deleteCategory(id, cascade: cascade);
    _adminLog.i('🗑️  [AdminApiService] DELETE category  id=$id  cascade=$cascade');
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLACES — 11-step progressive creation workflow
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<PlaceModel>> getPlaces({
    String? cityId,
    String? categoryId,
    String? status,
    String? search,
    String? taxonomy,
    bool? isBookable,
    bool includeAttributes = false,
    int page = 1,
    int limit = 20,
  }) async {
    _adminLog.i('📍 [AdminApiService] GET places  cityId=$cityId');
    final params = <String, String>{};
    if (cityId != null) params['cityId'] = cityId;
    if (categoryId != null) params['categoryId'] = categoryId;
    if (status != null) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (taxonomy != null) params['taxonomy'] = taxonomy;
    if (isBookable != null) params['isBookable'] = isBookable.toString();
    if (includeAttributes) params['includeAttributes'] = 'true';
    params['page'] = page.toString();
    params['limit'] = limit.toString();

    final response = await ApiClient.authGetWithParams(
      _Ep.places,
      queryParams: params,
    );
    final body = ApiClient.parseBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'];
      List<dynamic> list;
      if (data is Map && data['places'] is List) {
        list = data['places'] as List;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      return list
          .map((e) => PlaceModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwFromBody(body, response.statusCode, 'GET', _Ep.places);
  }

  Future<PlaceModel> getPlaceById(String id) async {
    final ep = _Ep.placeById(id);
    final response = await ApiClient.authGet(ep);
    return PlaceModel.fromJson(_unwrapObject(response, 'GET', ep));
  }

  Future<PlaceModel> createPlaceDraft({
    required String name,
    required String cityId,
    required String primaryCategory,
    String? ownerId,
  }) async {
    _adminLog.i('➕ [AdminApiService] POST createPlaceDraft  name=$name  cityId=$cityId');
    final payload = <String, dynamic>{
      'name': name,
      'cityId': cityId,
      'primaryCategory': primaryCategory,
      if (ownerId != null) 'ownerId': ownerId,
    };
    final response = await ApiClient.authPost(_Ep.places, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'POST', _Ep.places));
  }

  Future<PlaceModel> updatePlaceBasicInfo(
      String id, Map<String, dynamic> payload) async {
    final ep = _Ep.placeById(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> updatePlaceLocation(
      String id, Map<String, dynamic> payload) async {
    final ep = _Ep.placeLocation(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> updatePlaceContact(
      String id, Map<String, dynamic> payload) async {
    final ep = _Ep.placeContact(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> updatePlaceAttributes(
      String id, Map<String, dynamic> attributes) async {
    final ep = _Ep.placeAttributes(id);
    final response =
        await ApiClient.authPatch(ep, body: {'attributes': attributes});
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> updatePlaceMedia(
      String id, {
      required String? coverImage,
      required List<Map<String, dynamic>> images,
    }) async {
    final ep = _Ep.placeMedia(id);
    final payload = <String, dynamic>{
      if (coverImage != null && coverImage.isNotEmpty) 'coverImage': coverImage,
      'images': images,
    };
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> updatePlaceBooking(
      String id, Map<String, dynamic> payload) async {
    final ep = _Ep.placeBooking(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  Future<PlaceModel> linkPlaceCategories(
      String id,
      List<String> categoryIds, {
      bool replaceMode = false,
  }) async {
    final ep = replaceMode
        ? '${_Ep.placeCategories(id)}?mode=replace'
        : _Ep.placeCategories(id);
    final response =
        await ApiClient.authPut(ep, body: {'categoryIds': categoryIds});
    return PlaceModel.fromJson(_unwrapObject(response, 'PUT', ep));
  }

  Future<PlaceModel> unlinkPlaceCategories(
      String id, List<String> categoryIds) async {
    final ep = _Ep.placeCategories(id);
    final response = await ApiClient.authDelete(ep, body: {'categoryIds': categoryIds});
    return PlaceModel.fromJson(_unwrapObject(response, 'DELETE', ep));
  }

  Future<PlaceValidationResult> validatePlace(String id) async {
    final ep = _Ep.placeValidate(id);
    final response = await ApiClient.authGet(ep);
    return PlaceValidationResult.fromJson(_unwrapObject(response, 'GET', ep));
  }

  Future<PlaceModel> submitPlace(String id) async {
    final ep = _Ep.placeSubmit(id);
    final response = await ApiClient.authPost(ep, body: {});
    return PlaceModel.fromJson(_unwrapObject(response, 'POST', ep));
  }

  Future<void> deletePlaceById(String id) async {
    final ep = _Ep.placeById(id);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ── Accommodation ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRooms(String placeId) async {
    final ep = _Ep.placeRooms(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> createRooms(
      String placeId, List<Map<String, dynamic>> rooms) async {
    final ep = _Ep.placeRooms(placeId);
    final response = await ApiClient.authPost(ep, body: {'rooms': rooms});
    final list = _unwrapList(response, 'POST', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateRoom(
      String roomId, Map<String, dynamic> payload) async {
    final ep = _Ep.roomById(roomId);
    return _unwrapObject(
        await ApiClient.authPatch(ep, body: payload), 'PATCH', ep);
  }

  Future<void> deleteRoom(String roomId) async {
    final ep = _Ep.roomById(roomId);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ── Dining ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMenuSections(String placeId) async {
    final ep = _Ep.placeMenuSections(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createMenuSections(
      String placeId, List<Map<String, dynamic>> sections) async {
    final ep = _Ep.placeMenuSections(placeId);
    await ApiClient.authPost(ep, body: {'sections': sections});
  }

  Future<List<Map<String, dynamic>>> getMenuItems(String placeId) async {
    final ep = _Ep.placeMenuItems(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createMenuItems(
      String placeId, List<Map<String, dynamic>> items) async {
    final ep = _Ep.placeMenuItems(placeId);
    await ApiClient.authPost(ep, body: {'menuItems': items});
  }

  Future<Map<String, dynamic>> updateMenuItem(
      String itemId, Map<String, dynamic> payload) async {
    final ep = _Ep.menuItemById(itemId);
    return _unwrapObject(
        await ApiClient.authPatch(ep, body: payload), 'PATCH', ep);
  }

  Future<void> deleteMenuItem(String itemId) async {
    final ep = _Ep.menuItemById(itemId);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ── Entertainment ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getShows(String placeId) async {
    final ep = _Ep.placeShows(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createShows(
      String placeId, List<Map<String, dynamic>> shows) async {
    final ep = _Ep.placeShows(placeId);
    await ApiClient.authPost(ep, body: {'shows': shows});
  }

  Future<List<Map<String, dynamic>>> getPerformances(String placeId) async {
    final ep = _Ep.placePerformances(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createPerformances(
      String placeId, List<Map<String, dynamic>> performances) async {
    final ep = _Ep.placePerformances(placeId);
    await ApiClient.authPost(ep, body: {'performances': performances});
  }

  Future<Map<String, dynamic>> updatePerformance(
      String perfId, Map<String, dynamic> payload) async {
    final ep = _Ep.performanceById(perfId);
    return _unwrapObject(
        await ApiClient.authPatch(ep, body: payload), 'PATCH', ep);
  }

  // ── Cultural ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExhibitions(String placeId) async {
    final ep = _Ep.placeExhibitions(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createExhibitions(
      String placeId, List<Map<String, dynamic>> exhibitions) async {
    final ep = _Ep.placeExhibitions(placeId);
    await ApiClient.authPost(ep, body: {'exhibitions': exhibitions});
  }

  Future<List<Map<String, dynamic>>> getArtifacts(String placeId) async {
    final ep = _Ep.placeArtifacts(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createArtifacts(
      String placeId, List<Map<String, dynamic>> artifacts) async {
    final ep = _Ep.placeArtifacts(placeId);
    await ApiClient.authPost(ep, body: {'artifacts': artifacts});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD STATS
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getDashboardStats() async {
    _adminLog.i('📊 [AdminApiService] GET adminStats');
    const requestedKeys =
        'cities_total,places_total,places_active,places_pending,users_total';
    final response = await ApiClient.authGetWithParams(
      _Ep.adminStats,
      queryParams: {'keys': requestedKeys},
    );
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ GET ${_Ep.adminStats}  →  ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final statsList = body['stats'];
      if (statsList is List) {
        return {
          for (final item in statsList)
            if (item is Map<String, dynamic> && item['key'] is String)
              item['key'] as String: item['value'],
        };
      }
      return {};
    }
    _throwFromBody(body, response.statusCode, 'GET', _Ep.adminStats);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BLOG — Full implementation
  //
  // Implemented endpoints:
  //   GET    /api/blog                      getBlogPosts()
  //   GET    /api/blog/search?q=            searchBlogPosts()
  //   GET    /api/blog/{slug}               getBlogPostBySlug()
  //   POST   /api/blog                      createBlogPost()
  //   PATCH  /api/blog/{slug}               updateBlogPost()
  //   DELETE /api/blog/{slug}               deleteBlogPost()      (soft)
  //   DELETE /api/blog/{slug}?hard=true     deleteBlogPostHard()  (permanent)
  //   GET    /api/blog/drafts               getBlogDrafts()
  //   POST   /api/blog/{slug}/views         trackBlogView()
  //   POST   /api/blog/{slug}/like          likeBlogPost()
  //   GET    /api/blog/{slug}/comments      getBlogComments()
  //   POST   /api/blog/{slug}/comments      addBlogComment()
  //   GET    /api/blog/categories?slug=     getBlogPostsByCategory()
  //   GET    /api/blog/tags?slug=           getBlogPostsByTag()
  //   GET    /api/blog/author/{authorId}    getBlogPostsByAuthor()
  // ══════════════════════════════════════════════════════════════════════════

  // ── List / Search ──────────────────────────────────────────────────────────

  /// List posts with full filter support.
  /// When [query] is provided the search endpoint is used instead of the
  /// list endpoint, and status/category/tag filters are ignored by the server
  /// (the search API only accepts page/limit).
  Future<Map<String, dynamic>> getBlogPosts({
    int    page    = 1,
    int    limit   = 20,
    String? status,
    String? category,
    String? tag,
    String? cityId,
    String? authorId,
    bool?   featured,
    String? sortBy,   // publishedAt | title | updatedAt
    String? order,    // asc | desc
  }) async {
    _adminLog.i('📰 [AdminApiService] GET blog  page=$page  status=$status  '
        'category=$category  tag=$tag');
    final params = <String, String>{
      'page':  '$page',
      'limit': '$limit',
      if (status   != null) 'status':   status,
      if (category != null) 'category': category,
      if (tag      != null) 'tag':      tag,
      if (cityId   != null) 'cityId':   cityId,
      if (authorId != null) 'authorId': authorId,
      if (featured != null) 'featured': featured.toString(),
      if (sortBy   != null) 'sortBy':   sortBy,
      if (order    != null) 'order':    order,
    };
    final response = await ApiClient.authGetWithParams(
      _Ep.blog,
      queryParams: params,
    );
    return _parseBlogListResponse(response, 'GET', _Ep.blog, page);
  }

  /// Full-text search across posts.
  /// Returns the same shape as [getBlogPosts] for easy interop.
  Future<Map<String, dynamic>> searchBlogPosts(
    String query, {
    int page  = 1,
    int limit = 20,
  }) async {
    _adminLog.i('🔍 [AdminApiService] GET blog/search  q=$query  page=$page');
    final response = await ApiClient.authGetWithParams(
      _Ep.blogSearch,
      queryParams: {
        'q':     Uri.encodeQueryComponent(query),
        'page':  '$page',
        'limit': '$limit',
      },
    );
    return _parseBlogListResponse(response, 'GET', _Ep.blogSearch, page);
  }

  /// Shared response parser for all blog list/search endpoints.
  Map<String, dynamic> _parseBlogListResponse(
      http.Response response, String method, String ep, int page) {
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ $method $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final posts      = (body['posts'] as List? ?? []).cast<Map<String, dynamic>>();
      final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
      return {
        'posts':      posts,
        'page':       pagination['page']       ?? page,
        'total':      pagination['total']      ?? posts.length,
        'totalPages': pagination['totalPages'] ?? 1,
        'query':      body['query'],   // present on search responses only
      };
    }
    _throwFromBody(body, response.statusCode, method, ep);
  }

  // ── Filter endpoints ───────────────────────────────────────────────────────

  /// Posts filtered by category slug  —  GET /api/blog/categories?slug=…
  Future<Map<String, dynamic>> getBlogPostsByCategory(
    String categorySlug, {
    int page  = 1,
    int limit = 20,
  }) async {
    _adminLog.i('📂 [AdminApiService] GET blog/categories  slug=$categorySlug');
    final response = await ApiClient.authGetWithParams(
      _Ep.blogByCategory,
      queryParams: {'slug': categorySlug, 'page': '$page', 'limit': '$limit'},
    );
    return _parseBlogListResponse(
        response, 'GET', _Ep.blogByCategory, page);
  }

  /// Posts filtered by tag slug  —  GET /api/blog/tags?slug=…
  Future<Map<String, dynamic>> getBlogPostsByTag(
    String tagSlug, {
    int page  = 1,
    int limit = 20,
  }) async {
    _adminLog.i('🏷️  [AdminApiService] GET blog/tags  slug=$tagSlug');
    final response = await ApiClient.authGetWithParams(
      _Ep.blogByTag,
      queryParams: {'slug': tagSlug, 'page': '$page', 'limit': '$limit'},
    );
    return _parseBlogListResponse(response, 'GET', _Ep.blogByTag, page);
  }

  /// Posts by a specific author  —  GET /api/blog/author/{authorId}
  /// Returns { author: {...}, posts: [...], pagination: {...} }
  Future<Map<String, dynamic>> getBlogPostsByAuthor(
    String authorId, {
    int page  = 1,
    int limit = 20,
  }) async {
    _adminLog.i('👤 [AdminApiService] GET blog/author  authorId=$authorId');
    final ep = _Ep.blogByAuthor(authorId);
    final response = await ApiClient.authGetWithParams(
      ep,
      queryParams: {'page': '$page', 'limit': '$limit'},
    );
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ GET $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final posts      = (body['posts'] as List? ?? []).cast<Map<String, dynamic>>();
      final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
      return {
        'author':     body['author'],
        'posts':      posts,
        'page':       pagination['page']       ?? page,
        'total':      pagination['total']      ?? posts.length,
        'totalPages': pagination['totalPages'] ?? 1,
      };
    }
    _throwFromBody(body, response.statusCode, 'GET', ep);
  }

  // ── Single post ────────────────────────────────────────────────────────────

  /// Fetch a single post's full detail (content, meta, comments, etc.).
  /// Always call this before opening the edit compose screen so the full
  /// HTML content is available — the list endpoint omits the content field.
  Future<Map<String, dynamic>> getBlogPostBySlug(String slug) async {
    _adminLog.i('📄 [AdminApiService] GET blog/$slug');
    final ep       = _Ep.blogBySlug(slug);
    final response = await ApiClient.authGet(ep);
    final body     = ApiClient.parseBody(response);
    _adminLog.d('   ↳ GET $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Response shape: { post: {...}, relatedPlaces: [...], similarPosts: [...] }
      final post = body['post'] ?? body['data'] ?? body;
      return post as Map<String, dynamic>;
    }
    _throwFromBody(body, response.statusCode, 'GET', ep);
  }

  // ── Create / Update / Delete ───────────────────────────────────────────────

  Future<Map<String, dynamic>> createBlogPost(
      Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createBlogPost  title=${payload['title']}');
    const ep       = _Ep.blog;
    final response = await ApiClient.authPost(ep, body: payload);
    final body     = ApiClient.parseBody(response);
    _adminLog.d('   ↳ POST $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final post = body['post'] ?? body['data'] ?? body;
      return post as Map<String, dynamic>;
    }
    _throwFromBody(body, response.statusCode, 'POST', ep);
  }

  Future<Map<String, dynamic>> updateBlogPost(
      String slug, Map<String, dynamic> payload) async {
    _adminLog.i('✏️ [AdminApiService] PATCH updateBlogPost  slug=$slug');
    final ep       = _Ep.blogBySlug(slug);
    final response = await ApiClient.authPatch(ep, body: payload);
    final body     = ApiClient.parseBody(response);
    _adminLog.d('   ↳ PATCH $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final post = body['post'] ?? body['data'] ?? body;
      return post as Map<String, dynamic>;
    }
    _throwFromBody(body, response.statusCode, 'PATCH', ep);
  }

  /// Soft delete — the post is archived and can be restored by the backend team.
  Future<void> deleteBlogPost(String slug) async {
    _adminLog.i('🗑️ [AdminApiService] DELETE blog (soft)  slug=$slug');
    final ep = _Ep.blogBySlug(slug);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  /// Hard (permanent) delete — irreversible. Admin only.
  Future<void> deleteBlogPostHard(String slug) async {
    _adminLog.i('💥 [AdminApiService] DELETE blog (hard)  slug=$slug');
    final ep = _Ep.blogHardDelete(slug);
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ── Drafts ─────────────────────────────────────────────────────────────────

  /// Returns the current admin user's own drafts only.
  /// Useful for a personal "My Drafts" section distinct from the global list.
  Future<List<Map<String, dynamic>>> getBlogDrafts() async {
    _adminLog.i('📝 [AdminApiService] GET blog drafts');
    const ep       = _Ep.blogDrafts;
    final response = await ApiClient.authGet(ep);
    final body     = ApiClient.parseBody(response);
    _adminLog.d('   ↳ GET $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (body['drafts'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    _throwFromBody(body, response.statusCode, 'GET', ep);
  }

  // ── Engagement ─────────────────────────────────────────────────────────────

  /// Track a page view. Call this when a post detail screen opens.
  /// Returns the new total view count.
  Future<int> trackBlogView(String slug) async {
    _adminLog.d('👁️  [AdminApiService] POST blog/views  slug=$slug');
    final ep       = _Ep.blogViews(slug);
    final response = await ApiClient.authPost(ep, body: {});
    final body     = ApiClient.parseBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (body['views'] as num?)?.toInt() ?? 0;
    }
    _throwFromBody(body, response.statusCode, 'POST', ep);
  }

  /// Toggle a like on a post. Returns the new total like count.
  Future<int> likeBlogPost(String slug) async {
    _adminLog.i('❤️  [AdminApiService] POST blog/like  slug=$slug');
    final ep       = _Ep.blogLike(slug);
    final response = await ApiClient.authPost(ep, body: {});
    final body     = ApiClient.parseBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (body['likes'] as num?)?.toInt() ?? 0;
    }
    _throwFromBody(body, response.statusCode, 'POST', ep);
  }

  // ── Comments ───────────────────────────────────────────────────────────────

  /// Fetch paginated comments for a post, including nested replies.
  /// Returns { comments: [...], page, total, totalPages }.
  Future<Map<String, dynamic>> getBlogComments(
    String slug, {
    int page  = 1,
    int limit = 20,
  }) async {
    _adminLog.i('💬 [AdminApiService] GET blog/comments  slug=$slug  page=$page');
    final ep       = _Ep.blogComments(slug);
    final response = await ApiClient.authGetWithParams(
      ep,
      queryParams: {'page': '$page', 'limit': '$limit'},
    );
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ GET $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final comments   = (body['comments'] as List? ?? []).cast<Map<String, dynamic>>();
      final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
      return {
        'comments':   comments,
        'page':       pagination['page']       ?? page,
        'total':      pagination['total']      ?? comments.length,
        'totalPages': pagination['totalPages'] ?? 1,
      };
    }
    _throwFromBody(body, response.statusCode, 'GET', ep);
  }

  /// Add a top-level comment or reply to an existing comment.
  /// [parentId] — provide to make this a reply; omit for a root comment.
  /// Returns the newly created comment object.
  Future<Map<String, dynamic>> addBlogComment(
    String slug,
    String content, {
    String? parentId,
  }) async {
    _adminLog.i('💬 [AdminApiService] POST blog/comments  slug=$slug  '
        'isReply=${parentId != null}');
    final ep      = _Ep.blogComments(slug);
    final payload = <String, dynamic>{
      'content': content,
      if (parentId != null) 'parentId': parentId,
    };
    final response = await ApiClient.authPost(ep, body: payload);
    final body     = ApiClient.parseBody(response);
    _adminLog.d('   ↳ POST $ep  →  ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (body['comment'] ?? body['data'] ?? body)
          as Map<String, dynamic>;
    }
    _throwFromBody(body, response.statusCode, 'POST', ep);
  }
}