import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared logger for AdminApiService.
//
// Uses identical PrettyPrinter config to the logger in api_client.dart so all
// HTTP output appears in the same format in the terminal during testing.
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
// AdminApiException
//
// Thrown by [AdminApiService] on any non-2xx backend response.
// Callers can inspect [errors] for per-field validation messages
// returned in backend 400 responses:
//   { "status": "error", "errors": { "name": ["Required field"] } }
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

  /// Returns the first validation message for [field], or null.
  String? fieldError(String field) {
    final v = errors?[field];
    if (v is List && v.isNotEmpty) return v.first.toString();
    if (v is String) return v;
    return null;
  }

  @override
  String toString() =>
      'AdminApiException(${statusCode != null ? "$statusCode " : ""}$message)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminApiService
//
// All CRUD operations for the admin console.
//
// Deliberately uses the same [ApiClient] static methods already used by the
// rest of the app — no second HTTP client, no second token store.
// Every admin call therefore gets:
//   • Bearer token injected from FlutterSecureStorage automatically
//   • 401 → refresh → retry behaviour transparently
//   • onSessionExpired callback if the session is unrecoverable
// ─────────────────────────────────────────────────────────────────────────────
class AdminApiService {

  // ── Internal response-unwrapping helpers ──────────────────────────────────

  /// Unwrap a single-object backend response envelope.
  /// Backend shape: { "status": "success", "data": { … } }
  Map<String, dynamic> _unwrapObject(
    http.Response response,
    String method,
    String endpoint,
  ) {
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
      // Some endpoints may embed fields at the top level — fall back gracefully
      return body;
    }

    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  /// Unwrap a list-type backend response envelope.
  /// Backend shape: { "status": "success", "data": [ … ] }
  List<dynamic> _unwrapList(
    http.Response response,
    String method,
    String endpoint,
  ) {
    final body = ApiClient.parseBody(response);
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'];
      if (data is List) return data;
      return [];
    }

    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  /// Unwrap a DELETE response that only carries a message (no data).
  /// Backend shape: { "status": "success", "message": "City deleted successfully" }
  void _unwrapDelete(
    http.Response response,
    String method,
    String endpoint,
  ) {
    _adminLog.d('   ↳ $method $endpoint  →  ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final body = ApiClient.parseBody(response);
    _throwFromBody(body, response.statusCode, method, endpoint);
  }

  /// Extract error info from the body and throw [AdminApiException].
  Never _throwFromBody(
    Map<String, dynamic> body,
    int statusCode,
    String method,
    String endpoint,
  ) {
    final message = body['message'] as String? ??
        body['error'] as String? ??
        'Request failed ($statusCode)';

    final errors = body['errors'] as Map<String, dynamic>?;

    _adminLog.e(
      '❌ [AdminApiService] $method $endpoint  →  $statusCode\n'
      '   message : $message'
      '${errors != null ? "\n   errors  : $errors" : ""}',
    );

    throw AdminApiException(
      statusCode: statusCode,
      message: message,
      errors: errors,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // RESORT CITIES
  //   GET    /api/cities              → getCities()
  //   GET    /api/cities/:id          → getCityById()
  //   POST   /api/cities              → createCity()
  //   PUT    /api/cities/:id          → updateCity()
  //   DELETE /api/cities/:id          → deleteCity()
  // ════════════════════════════════════════════════════════════════════════════

  /// Fetch all resort cities.
  ///
  /// Pass [filters] to narrow results, e.g.:
  ///   {'country': 'Kenya', 'isActive': 'true'}
  /// These map directly to the query string: ?country=Kenya&isActive=true
  Future<List<CityModel>> getCities({
    Map<String, String>? filters,
  }) async {
    _adminLog.i(
      '🏙️  [AdminApiService] GET cities'
      '${filters != null && filters.isNotEmpty ? "  filters=$filters" : ""}',
    );

    final response = await ApiClient.authGetWithParams(
      ApiEndpoints.cities,
      queryParams: filters,
    );

    final list = _unwrapList(response, 'GET', ApiEndpoints.cities);
    final cities = list
        .map((e) => CityModel.fromJson(e as Map<String, dynamic>))
        .toList();

    _adminLog.i('✅ [AdminApiService] getCities  →  ${cities.length} cities');
    return cities;
  }

  /// Fetch a single city by its ID.
  Future<CityModel> getCityById(String id) async {
    _adminLog.i('🏙️  [AdminApiService] GET city  id=$id');

    final endpoint = ApiEndpoints.cityById(id);
    final response = await ApiClient.authGet(endpoint);

    final data = _unwrapObject(response, 'GET', endpoint);
    final city = CityModel.fromJson(data);

    _adminLog.i('✅ [AdminApiService] getCityById  →  "${city.name}"');
    return city;
  }

  /// Create a new resort city.
  ///
  /// [payload] must include:
  ///   name, country, region, slug, latitude (double), longitude (double),
  ///   coverImage (URL string), description, isActive (bool)
  ///
  /// On a 400 response, [AdminApiException.errors] will contain per-field
  /// messages ready for inline display in the form, e.g.:
  ///   exception.fieldError('name')  →  "Required field"
  Future<CityModel> createCity(Map<String, dynamic> payload) async {
    _adminLog.i('➕ [AdminApiService] POST createCity  payload=$payload');

    final response = await ApiClient.authPost(
      ApiEndpoints.createCity,
      body: payload,
    );

    final data = _unwrapObject(response, 'POST', ApiEndpoints.createCity);
    final city = CityModel.fromJson(data);

    _adminLog.i(
      '✅ [AdminApiService] createCity  →  '
      'id=${city.id}  name="${city.name}"  slug=${city.slug}',
    );
    return city;
  }

  /// Partially update a city.
  ///
  /// Only the fields present in [payload] are changed on the backend.
  /// Common partial-update patterns:
  ///   updateCity(id, {'isActive': false})          // toggle visibility
  ///   updateCity(id, {'name': 'Nairobi City'})     // rename
  Future<CityModel> updateCity(
    String id,
    Map<String, dynamic> payload,
  ) async {
    _adminLog.i(
        '✏️  [AdminApiService] PUT updateCity  id=$id  payload=$payload');

    final endpoint = ApiEndpoints.updateCity(id);
    final response = await ApiClient.authPut(endpoint, body: payload);

    final data = _unwrapObject(response, 'PUT', endpoint);
    final city = CityModel.fromJson(data);

    _adminLog.i(
      '✅ [AdminApiService] updateCity  →  '
      'id=${city.id}  name="${city.name}"  isActive=${city.isActive}',
    );
    return city;
  }

  /// Permanently delete a city and all its nested channels and places.
  Future<void> deleteCity(String id) async {
    _adminLog.i('🗑️  [AdminApiService] DELETE city  id=$id');

    final endpoint = ApiEndpoints.deleteCity(id);
    final response = await ApiClient.authDelete(endpoint);

    _unwrapDelete(response, 'DELETE', endpoint);

    _adminLog.i('✅ [AdminApiService] deleteCity  →  id=$id deleted');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CHANNELS  — endpoints defined; full backend docs to be confirmed
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<ChannelItem>> getChannels(
      String cityId) async {
    _adminLog.i('📂 [AdminApiService] GET channels  cityId=$cityId');
    final endpoint = ApiEndpoints.channels(cityId);
    final response = await ApiClient.authGet(endpoint);
    final list = _unwrapList(response, 'GET', endpoint);
    final channels = list
        .map((e) => ChannelItem.fromJson(e as Map<String, dynamic>))
        .toList();
    _adminLog.i(
        '✅ [AdminApiService] getChannels  →  ${channels.length} channels');
    return channels;
  }

  Future<Map<String, dynamic>> createChannel(
      String cityId, Map<String, dynamic> payload) async {
    _adminLog.i(
        '➕ [AdminApiService] POST createChannel  cityId=$cityId  payload=$payload');
    final endpoint = ApiEndpoints.createChannel(cityId);
    final response = await ApiClient.authPost(endpoint, body: payload);
    final data = _unwrapObject(response, 'POST', endpoint);
    _adminLog.i('✅ [AdminApiService] createChannel  →  done');
    return data;
  }

  Future<Map<String, dynamic>> updateChannel(
      String cityId, String channelId, Map<String, dynamic> payload) async {
    _adminLog.i(
        '✏️  [AdminApiService] PUT updateChannel  channelId=$channelId  payload=$payload');
    final endpoint = ApiEndpoints.channelById(cityId, channelId);
    final response = await ApiClient.authPut(endpoint, body: payload);
    final data = _unwrapObject(response, 'PUT', endpoint);
    _adminLog.i(
        '✅ [AdminApiService] updateChannel  →  channelId=$channelId');
    return data;
  }

  Future<void> deleteChannel(
      String cityId, String channelId) async {
    _adminLog.i(
        '🗑️  [AdminApiService] DELETE channel  channelId=$channelId');
    final endpoint = ApiEndpoints.channelById(cityId, channelId);
    final response = await ApiClient.authDelete(endpoint);
    _unwrapDelete(response, 'DELETE', endpoint);
    _adminLog.i(
        '✅ [AdminApiService] deleteChannel  →  channelId=$channelId');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PLACES  — endpoints defined; full backend docs to be confirmed
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<PlaceItem>> getPlaces(
      String cityId, String channelId) async {
    _adminLog.i(
        '📍 [AdminApiService] GET places  cityId=$cityId  channelId=$channelId');
    final endpoint = ApiEndpoints.places(cityId, channelId);
    final response = await ApiClient.authGet(endpoint);
    final list = _unwrapList(response, 'GET', endpoint);
    final places = list
        .map((e) => PlaceItem.fromJson(e as Map<String, dynamic>))
        .toList();
    _adminLog.i(
        '✅ [AdminApiService] getPlaces  →  ${places.length} places');
    return places;
  }

  Future<Map<String, dynamic>> createPlace(
      String cityId, String channelId, Map<String, dynamic> payload) async {
    _adminLog.i(
        '➕ [AdminApiService] POST createPlace  channelId=$channelId  payload=$payload');
    final endpoint = ApiEndpoints.createPlace(cityId, channelId);
    final response = await ApiClient.authPost(endpoint, body: payload);
    final data = _unwrapObject(response, 'POST', endpoint);
    _adminLog.i('✅ [AdminApiService] createPlace  →  done');
    return data;
  }

  Future<Map<String, dynamic>> updatePlace(
    String cityId,
    String channelId,
    String placeId,
    Map<String, dynamic> payload,
  ) async {
    _adminLog.i(
        '✏️  [AdminApiService] PUT updatePlace  placeId=$placeId  payload=$payload');
    final endpoint = ApiEndpoints.placeById(cityId, channelId, placeId);
    final response = await ApiClient.authPut(endpoint, body: payload);
    final data = _unwrapObject(response, 'PUT', endpoint);
    _adminLog.i(
        '✅ [AdminApiService] updatePlace  →  placeId=$placeId');
    return data;
  }

  Future<void> deletePlace(
      String cityId, String channelId, String placeId) async {
    _adminLog.i('🗑️  [AdminApiService] DELETE place  placeId=$placeId');
    final endpoint = ApiEndpoints.placeById(cityId, channelId, placeId);
    final response = await ApiClient.authDelete(endpoint);
    _unwrapDelete(response, 'DELETE', endpoint);
    _adminLog.i('✅ [AdminApiService] deletePlace  →  placeId=$placeId');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DASHBOARD STATS  —  GET /api/admin/stats
  // ════════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getDashboardStats() async {
    _adminLog.i('📊 [AdminApiService] GET adminStats');

    final response = await ApiClient.authGet(ApiEndpoints.adminStats);
    final data = _unwrapObject(response, 'GET', ApiEndpoints.adminStats);

    _adminLog.i('✅ [AdminApiService] getDashboardStats  →  $data');
    return data;
  }
}