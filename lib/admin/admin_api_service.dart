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
// Ensure ApiClient.authDelete accepts an optional `body` parameter, e.g.:
//
//   static Future<http.Response> authDelete(String path,
//       {Map<String, dynamic>? body}) async { ... }
//
// If authDelete doesn't support body yet, add it alongside the existing
// authPut implementation (change method to 'DELETE' and include body encoding).
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

  // Categories  (replaces channels — global, no city scope)
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
  static const String adminStats = '/api/admin/stats';
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
    final v = errors?[field];
    if (v is List && v.isNotEmpty) return v.first.toString();
    if (v is Map) {
      final errs = v['_errors'];
      if (errs is List && errs.isNotEmpty) return errs.first.toString();
    }
    if (v is String) return v;
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
      // Some list responses wrap in {places:[...], pagination:{...}}
      // NOTE: keep this list in sync with every list endpoint the backend exposes.
      for (final key in [
        'places', 'categories', 'rooms',
        'shows', 'performances',
        'exhibitions', 'artifacts',
        'menuSections', 'menuItems',   // v2.0 — Dining endpoints
      ]) {
        if (data is Map && data.containsKey(key)) {
          return data[key] as List;
        }
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
    final message = body['message'] as String? ??
        body['error'] as String? ??
        'Request failed ($statusCode)';
    final errors = body['errors'] as Map<String, dynamic>?;
    _adminLog.e(
      '❌ [AdminApiService] $method $endpoint → $statusCode\n'
      '   message: $message'
      '${errors != null ? "\n   errors: $errors" : ""}',
    );
    throw AdminApiException(
        statusCode: statusCode, message: message, errors: errors);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESORT CITIES  —  confirmed endpoints unchanged
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
  // CATEGORIES  (previously "Channels")
  //
  // Categories are GLOBAL — not scoped to a city.
  // The hierarchy is: Parent Category → Child Categories (subcategories).
  // Example: "Accommodation" (parent) → "Hotels", "Resorts" (children).
  //
  // Linking a place to a category is done via PUT /api/places/:id/categories.
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch all categories. Use filters to control what's returned:
  ///   isActive:        true/false
  ///   parentId:        specific parent's id — or "null" for root-only
  ///   includeChildren: true  → each parent includes its children array
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

  /// Get all root categories with their children in one call.
  Future<List<CategoryModel>> getCategoryTree() async {
    final all = await getCategories(includeChildren: true);
    // Filter to only root categories — children are embedded inside them
    return all.where((c) => c.isRoot).toList();
  }

  /// Create a root-level category.
  /// Required: name, slug. Optional: icon, description, sortOrder, isActive.
  Future<CategoryModel> createCategory(Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createCategory  payload=$payload');
    final response = await ApiClient.authPost(_Ep.categories, body: payload);
    return CategoryModel.fromJson(
        _unwrapObject(response, 'POST', _Ep.categories));
  }

  /// Create a subcategory by including parentId in the payload.
  Future<CategoryModel> createSubcategory(
      String parentId, Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createSubcategory  parentId=$parentId');
    final merged = {...payload, 'parentId': parentId};
    final response = await ApiClient.authPost(_Ep.categories, body: merged);
    return CategoryModel.fromJson(
        _unwrapObject(response, 'POST', _Ep.categories));
  }

  /// Partial update of a category. Only provided fields are changed.
  Future<CategoryModel> updateCategory(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PUT updateCategory  id=$id');
    final ep = _Ep.categoryById(id);
    final response = await ApiClient.authPut(ep, body: payload);
    return CategoryModel.fromJson(_unwrapObject(response, 'PUT', ep));
  }

  /// Delete a category.
  /// Set cascade=true to also delete all child subcategories.
  Future<void> deleteCategory(String id, {bool cascade = false}) async {
    final ep = _Ep.deleteCategory(id, cascade: cascade);
    _adminLog.i('🗑️  [AdminApiService] DELETE category  id=$id  cascade=$cascade');
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLACES — core 11-step progressive creation workflow
  //
  // The flow:
  //   Step 1  POST /api/places                   → createPlaceDraft()
  //   Step 2  PATCH /api/places/:id              → updatePlaceBasicInfo()
  //   Step 3  PATCH /api/places/:id/location     → updatePlaceLocation()
  //   Step 4  PATCH /api/places/:id/contact      → updatePlaceContact()
  //   Step 5  PATCH /api/places/:id/attributes   → updatePlaceAttributes()
  //   Step 6  (category-specific nested data)
  //   Step 7  PATCH /api/places/:id/media        → updatePlaceMedia()
  //   Step 8  PATCH /api/places/:id/booking      → updatePlaceBooking()
  //   Step 9  PUT   /api/places/:id/categories   → linkPlaceCategories()
  //   Step 10 GET   /api/places/:id/submit       → validatePlace()
  //   Step 11 POST  /api/places/:id/submit       → submitPlace()
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch places with optional filtering.
  ///
  /// [includeAttributes] — v2.0 opt-in flag.  When true the API adds
  /// `attributes`, `contact`, `images`, `description`, `bookingSettings`,
  /// and `searchKeywords` to every list item (heavier payload).
  /// Omit (default false) for lean list screens; use [getPlaceById] for
  /// full detail in the edit wizard.
  Future<List<PlaceModel>> getPlaces({
    String? cityId,
    String? categoryId,
    String? status,
    String? search,
    String? taxonomy,
    bool? isBookable,
    bool includeAttributes = false,   // v2.0 opt-in
    int page = 1,
    int limit = 20,
  }) async {
    _adminLog.i('📍 [AdminApiService] GET places  cityId=$cityId  categoryId=$categoryId  includeAttributes=$includeAttributes');
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
    // Backend wraps list as data.places[...]
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

  /// STEP 1 — Create a minimal draft place record.
  /// Returns the new PlaceModel with status=PENDING and the server-assigned id.
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

  /// STEP 2 — Update basic descriptive info.
  Future<PlaceModel> updatePlaceBasicInfo(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeBasicInfo  id=$id');
    final ep = _Ep.placeById(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 3 — Update address and GPS coordinates.
  Future<PlaceModel> updatePlaceLocation(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeLocation  id=$id');
    final ep = _Ep.placeLocation(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 4 — Update phone, email, website.
  Future<PlaceModel> updatePlaceContact(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeContact  id=$id');
    final ep = _Ep.placeContact(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 5 — Update the flexible JSONB attributes blob.
  /// The attributes object varies by category type (see Place API docs).
  Future<PlaceModel> updatePlaceAttributes(
      String id, Map<String, dynamic> attributes) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeAttributes  id=$id');
    final ep = _Ep.placeAttributes(id);
    final response =
        await ApiClient.authPatch(ep, body: {'attributes': attributes});
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 7 — Update cover image and image gallery.
  Future<PlaceModel> updatePlaceMedia(
      String id, {
      required String? coverImage,
      required List<Map<String, dynamic>> images,
    }) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeMedia  id=$id');
    final ep = _Ep.placeMedia(id);
    final payload = <String, dynamic>{
      if (coverImage != null && coverImage.isNotEmpty) 'coverImage': coverImage,
      'images': images,
    };
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 8 — Configure booking availability and pricing.
  Future<PlaceModel> updatePlaceBooking(
      String id, Map<String, dynamic> payload) async {
    _adminLog.i('✏️  [AdminApiService] PATCH placeBooking  id=$id');
    final ep = _Ep.placeBooking(id);
    final response = await ApiClient.authPatch(ep, body: payload);
    return PlaceModel.fromJson(_unwrapObject(response, 'PATCH', ep));
  }

  /// STEP 9 — Link this place to one or more categories.
  ///
  /// **v2.0 behaviour change — READ THIS.**
  /// The API is now ADDITIVE by default: only the provided categoryIds are
  /// linked; existing links not in the list are left untouched.
  ///
  /// Set [replaceMode] = true to use `?mode=replace` and replicate the old
  /// v1.0 "replace all" behaviour.  You almost always want this when editing
  /// an existing place so that removed categories are properly unlinked.
  ///
  /// For the initial creation wizard pass [replaceMode] = false (additive is
  /// fine — there are no pre-existing links to worry about).
  Future<PlaceModel> linkPlaceCategories(
      String id,
      List<String> categoryIds, {
      bool replaceMode = false,
  }) async {
    _adminLog.i(
        '🔗 [AdminApiService] PUT placeCategories  id=$id  categories=${categoryIds.length}  replaceMode=$replaceMode');
    final ep = replaceMode
        ? '${_Ep.placeCategories(id)}?mode=replace'
        : _Ep.placeCategories(id);
    final response =
        await ApiClient.authPut(ep, body: {'categoryIds': categoryIds});
    return PlaceModel.fromJson(_unwrapObject(response, 'PUT', ep));
  }

  /// Unlink specific categories from a place without touching other links.
  ///
  /// Uses `DELETE /api/places/:id/categories` — new in v2.0.
  /// Returns the updated place after removal.
  ///
  /// Requires ApiClient.authDelete to accept an optional `body` parameter —
  /// see the note at the top of this file.
  Future<PlaceModel> unlinkPlaceCategories(
      String id, List<String> categoryIds) async {
    _adminLog.i(
        '🔓 [AdminApiService] DELETE placeCategories  id=$id  categories=${categoryIds.length}');
    final ep = _Ep.placeCategories(id);
    final response = await ApiClient.authDelete(ep, body: {'categoryIds': categoryIds});
    return PlaceModel.fromJson(_unwrapObject(response, 'DELETE', ep));
  }

  /// STEP 10 — Check if the place has all required fields for submission.
  Future<PlaceValidationResult> validatePlace(String id) async {
    _adminLog.i('🔍 [AdminApiService] GET validatePlace  id=$id');
    final ep = _Ep.placeValidate(id);
    final response = await ApiClient.authGet(ep);
    return PlaceValidationResult.fromJson(_unwrapObject(response, 'GET', ep));
  }

  /// STEP 11 — Submit the place for activation (PENDING → ACTIVE).
  Future<PlaceModel> submitPlace(String id) async {
    _adminLog.i('🚀 [AdminApiService] POST submitPlace  id=$id');
    final ep = _Ep.placeSubmit(id);
    final response = await ApiClient.authPost(ep, body: {});
    return PlaceModel.fromJson(_unwrapObject(response, 'POST', ep));
  }

  /// Permanently delete a place. Will fail if the place has bookings.
  Future<void> deletePlaceById(String id) async {
    final ep = _Ep.placeById(id);
    _adminLog.i('🗑️  [AdminApiService] DELETE place  id=$id');
    _unwrapDelete(await ApiClient.authDelete(ep), 'DELETE', ep);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ACCOMMODATION — Rooms (Step 6 for accommodation-type places)
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRooms(String placeId) async {
    final ep = _Ep.placeRooms(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  /// Creates (or replaces) all rooms for a place.
  Future<List<Map<String, dynamic>>> createRooms(
      String placeId, List<Map<String, dynamic>> rooms) async {
    _adminLog.i('➕ [AdminApiService] POST createRooms  placeId=$placeId  count=${rooms.length}');
    final ep = _Ep.placeRooms(placeId);
    final response =
        await ApiClient.authPost(ep, body: {'rooms': rooms});
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

  // ──────────────────────────────────────────────────────────────────────────
  // DINING — Menu sections & items (Step 6 for dining-type places)
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMenuSections(String placeId) async {
    final ep = _Ep.placeMenuSections(placeId);
    final list = _unwrapList(await ApiClient.authGet(ep), 'GET', ep);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> createMenuSections(
      String placeId, List<Map<String, dynamic>> sections) async {
    _adminLog.i('➕ [AdminApiService] POST createMenuSections  placeId=$placeId');
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
    _adminLog.i('➕ [AdminApiService] POST createMenuItems  placeId=$placeId  count=${items.length}');
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

  // ──────────────────────────────────────────────────────────────────────────
  // ENTERTAINMENT — Shows & performances (Step 6 for entertainment places)
  // ──────────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────────
  // CULTURAL — Exhibitions & artifacts (Step 6 for cultural places)
  // ──────────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────────
  // DASHBOARD STATS
  // ──────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardStats() async {
    _adminLog.i('📊 [AdminApiService] GET adminStats');
    final response = await ApiClient.authGet(_Ep.adminStats);
    return _unwrapObject(response, 'GET', _Ep.adminStats);
  }
}