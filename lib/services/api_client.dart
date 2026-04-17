import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED LOGGER
// ─────────────────────────────────────────────────────────────────────────────
final Logger _apiLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// APP CONFIGURATION
//
// ─────────────────────────────────────────────────────────────────────────────
class AppConfig {
  AppConfig._();

  // ── Live / testing environment ───────────────
  static const String baseUrl = 'https://pnrcapi.vercel.app';

  // ── Local development (uncomment to use) ─────
  static const String googleWebClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
}

// ─────────────────────────────────────────────────────────────────────────────
// API ENDPOINTS
// ─────────────────────────────────────────────────────────────────────────────
class ApiEndpoints {
  ApiEndpoints._();

  // ── Authentication ───────────────────────────────────────────────────────

  /// Register a new account.
  /// POST  Body: { email, password }
  static const String register = '/api/auth/register';

  /// Log in with email + password.
  static const String login = '/api/auth/login';

  /// Log in / register via Google.
  static const String googleAuth = '/api/auth/google';

  /// Revoke a refresh token (logout).
  static const String logout = '/api/auth/logout';

  /// Rotate an expired access token.
  static const String refresh = '/api/auth/refresh';

  /// Get the currently authenticated user's profile.
  static const String me = '/api/auth/me';

  /// Send a password-reset email.
  /// POST  Body: { email }
  static const String forgotPassword = '/api/auth/forgot-password';

  /// Validate a reset token and set a new password.
  /// POST  Body: { token, newPassword }
  static const String resetPassword = '/api/auth/reset-password';

  /// Change password while authenticated.
  /// POST  Body: { newPassword }  Auth: Bearer required
  static const String changePassword = '/api/auth/resetpassword';

  // ── Resort Cities ────────────────────────────────────────────────────────

  /// List all cities, or filter with query params e.g. ?country=Kenya&isActive=true
  /// GET   Auth: Bearer required
  static const String cities = '/api/cities';

  /// Create a new resort city.
  /// POST  Body: { name, country, region, slug, latitude, longitude,
  ///              coverImage, description, isActive }
  /// Auth: Bearer + admin role required
  static const String createCity = '/api/cities';

  /// Fetch a single city by its database ID.
  /// GET   Auth: Bearer required
  static String cityById(String id) => '/api/cities/$id';

  /// Partial-update a city.  Only send the fields that changed.
  /// PUT   Auth: Bearer + admin role required
  static String updateCity(String id) => '/api/cities/$id';

  /// Permanently delete a city and all nested channels/places.
  /// DELETE  Auth: Bearer + admin role required
  static String deleteCity(String id) => '/api/cities/$id';

  // ── Channels ─────────────────────────────────────────────────────────────

  /// List all channels for a city.
  /// GET   Auth: Bearer required
  static String channels(String cityId) => '/api/cities/$cityId/channels';

  /// Create a channel inside a city.
  /// POST  Auth: Bearer + admin role required
  static String createChannel(String cityId) =>
      '/api/cities/$cityId/channels';

  /// Update or delete a specific channel.
  /// PUT / DELETE  Auth: Bearer + admin role required
  static String channelById(String cityId, String channelId) =>
      '/api/cities/$cityId/channels/$channelId';

  // ── Places ────────────────────────────────────────────────────────────────

  /// List all places in a channel. Supports filters as query params.
  /// GET   Auth: Bearer required
  static String places(String cityId, String channelId) =>
      '/api/cities/$cityId/channels/$channelId/places';

  /// Create a place inside a channel.
  /// POST  Auth: Bearer + admin role required
  static String createPlace(String cityId, String channelId) =>
      '/api/cities/$cityId/channels/$channelId/places';

  /// Update or delete a specific place.
  /// PUT / DELETE  Auth: Bearer + admin role required
  static String placeById(String cityId, String channelId, String placeId) =>
      '/api/cities/$cityId/channels/$channelId/places/$placeId';

  // ── Admin Dashboard ──────────────────────
  static const String adminStats = '/api/admin/stats';

  // ────────────────────────────────────────────────────────────────────────
  /// Build the absolute URL for a given endpoint path.
  // ────────────────────────────────────────────────────────────────────────
  static String url(String endpoint) => '${AppConfig.baseUrl}$endpoint';
}

// ─────────────────────────────────────────────────────────────────────────────
// SECURE STORAGE KEYS
// ─────────────────────────────────────────────────────────────────────────────
class StorageKeys {
  StorageKeys._();

  // ── Auth tokens ──────────────────────────────
  static const String accessToken  = 'access_token';
  static const String refreshToken = 'refresh_token';

  // ── User profile ─────────────────────────────
  static const String userId    = 'user_id';
  static const String userEmail = 'user_email';

  /// Roles stored as a comma-separated string.
  /// e.g. "tourist,admin"  — read back with storedValue.split(',')
  static const String userRoles = 'user_roles';
}

// ───────────────────────────────────────────────────────────
// API CLIENT
class ApiClient {
  ApiClient._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const Duration _timeout = Duration(seconds: 20);

  // ── Session-Expired Callback ─────────────────────────────
  static void Function()? onSessionExpired;

  // ── Token / Session Accessors ────────────────────────────

  static Future<String?> getAccessToken()  async =>
      _storage.read(key: StorageKeys.accessToken);

  static Future<String?> getRefreshToken() async =>
      _storage.read(key: StorageKeys.refreshToken);

  static Future<String?> getUserId()       async =>
      _storage.read(key: StorageKeys.userId);

  static Future<String?> getUserEmail()    async =>
      _storage.read(key: StorageKeys.userEmail);

  /// Returns roles as a List.  Empty list when no session exists.
  static Future<List<String>> getUserRoles() async {
    final raw = await _storage.read(key: StorageKeys.userRoles);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',');
  }

  /// True when a valid access token is currently stored.
  static Future<bool> get isLoggedIn async =>
      (await getAccessToken()) != null;

  // ── Session Persistence ───────────────────────────────────────────────────

  /// Persist tokens and user info to secure storage after any successful login.
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    required List<String> roles,
  }) async {
    _apiLog.d('💾 ApiClient.saveSession: Persisting session to secure storage');
    try {
      await Future.wait([
        _storage.write(key: StorageKeys.accessToken,  value: accessToken),
        _storage.write(key: StorageKeys.refreshToken, value: refreshToken),
        _storage.write(key: StorageKeys.userId,       value: userId),
        _storage.write(key: StorageKeys.userEmail,    value: email),
        _storage.write(key: StorageKeys.userRoles,    value: roles.join(',')),
      ]);
      _apiLog.i(
        '💾 ApiClient.saveSession: ✓ Session saved\n'
        '   userId : $userId\n'
        '   email  : $email\n'
        '   roles  : $roles',
      );
    } catch (e, st) {
      _apiLog.e('❌ ApiClient.saveSession: Failed', error: e, stackTrace: st);
    }
  }

  /// Wipe all stored session data.  Call on logout or confirmed session expiry.
  static Future<void> clearSession() async {
    _apiLog.i('🚪 ApiClient.clearSession: Deleting all secure storage entries');
    await _storage.deleteAll();
    _apiLog.i('🚪 ApiClient.clearSession: ✓ Session cleared');
  }

  // ── HTTP Headers ──────────────────────────────────────────────────────────

  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  static Future<Map<String, String>> get _authHeaders async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Public HTTP Helpers ───────────────────────────
  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(ApiEndpoints.url(endpoint));
    _apiLog.d('📤 ApiClient.post ──► $uri');
    if (body != null) _apiLog.d('   body: $body');

    return http
        .post(
          uri,
          headers: _jsonHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
  }

  /// Authenticated POST with automatic 401 recovery.
  static Future<http.Response> authPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    _apiLog.d('📤 ApiClient.authPost ──► ${ApiEndpoints.url(endpoint)}');
    if (body != null) _apiLog.d('   body: $body');

    // First attempt
    var response = await _doAuthPost(endpoint, body: body);

    // 401 recovery
    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authPost: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i('🔄 ApiClient.authPost: Refresh succeeded — retrying $endpoint');
        response = await _doAuthPost(endpoint, body: body);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authPost: Still 401 after retry on $endpoint — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authPost: Token refresh failed for $endpoint — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  /// Authenticated GET with automatic 401 recovery.
  static Future<http.Response> authGet(String endpoint) async {
    _apiLog.d('📥 ApiClient.authGet ──► ${ApiEndpoints.url(endpoint)}');

    // First attempt
    var response = await _doAuthGet(endpoint);

    // 401 recovery
    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authGet: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i('🔄 ApiClient.authGet: Refresh succeeded — retrying $endpoint');
        response = await _doAuthGet(endpoint);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authGet: Still 401 after retry on $endpoint — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authGet: Token refresh failed for $endpoint — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  /// Authenticated PUT with automatic 401 recovery.
  static Future<http.Response> authPut(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    _apiLog.d('📝 ApiClient.authPut ──► ${ApiEndpoints.url(endpoint)}');
    if (body != null) _apiLog.d('   body: $body');

    var response = await _doAuthPut(endpoint, body: body);

    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authPut: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i('🔄 ApiClient.authPut: Refresh succeeded — retrying $endpoint');
        response = await _doAuthPut(endpoint, body: body);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authPut: Still 401 after retry on $endpoint — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authPut: Token refresh failed for $endpoint — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  /// Authenticated PATCH with automatic 401 recovery.
  /// Used by AdminApiService for all progressive place update endpoints:
  /// PATCH /api/places/:id, /location, /contact, /attributes, /media, /booking
  static Future<http.Response> authPatch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    _apiLog.d('📝 ApiClient.authPatch ──► ${ApiEndpoints.url(endpoint)}');
    if (body != null) _apiLog.d('   body: $body');

    var response = await _doAuthPatch(endpoint, body: body);

    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authPatch: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i('🔄 ApiClient.authPatch: Refresh succeeded — retrying $endpoint');
        response = await _doAuthPatch(endpoint, body: body);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authPatch: Still 401 after retry on $endpoint — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authPatch: Token refresh failed for $endpoint — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  /// Use for: DELETE /api/cities/:id and any other protected deletes.
  /// An optional [body] may be supplied for endpoints that require a JSON
  /// payload on DELETE (e.g. bulk-unlink operations). When omitted the
  /// request is sent with no body, preserving backward-compatibility with
  /// all existing call-sites.
  static Future<http.Response> authDelete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    _apiLog.d('🗑️  ApiClient.authDelete ──► ${ApiEndpoints.url(endpoint)}');
    if (body != null) _apiLog.d('   body: $body');

    var response = await _doAuthDelete(endpoint, body: body);

    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authDelete: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i(
            '🔄 ApiClient.authDelete: Refresh succeeded — retrying $endpoint');
        response = await _doAuthDelete(endpoint, body: body);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authDelete: Still 401 after retry on $endpoint — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authDelete: Token refresh failed for $endpoint — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  /// Authenticated GET with query parameters and automatic 401 recovery.

  /// [queryParams] are appended to the URL automatically.
  static Future<http.Response> authGetWithParams(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    final baseUri = Uri.parse(ApiEndpoints.url(endpoint));
    final uri = (queryParams != null && queryParams.isNotEmpty)
        ? baseUri.replace(queryParameters: queryParams)
        : baseUri;

    _apiLog.d('📥 ApiClient.authGetWithParams ──► $uri');

    final headers = await _authHeaders;
    var response = await http.get(uri, headers: headers).timeout(_timeout);

    if (response.statusCode == 401) {
      _apiLog.w(
        '⚠️ ApiClient.authGetWithParams: 401 on $endpoint — '
        'attempting token refresh before retry',
      );
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        _apiLog.i(
            '🔄 ApiClient.authGetWithParams: Refresh succeeded — retrying');
        final newHeaders = await _authHeaders;
        response =
            await http.get(uri, headers: newHeaders).timeout(_timeout);

        if (response.statusCode == 401) {
          _apiLog.e(
            '❌ ApiClient.authGetWithParams: Still 401 after retry — '
            'session is unrecoverable',
          );
          await _handleSessionExpired();
        }
      } else {
        _apiLog.e(
          '❌ ApiClient.authGetWithParams: Token refresh failed — '
          'session is unrecoverable',
        );
        await _handleSessionExpired();
      }
    }

    return response;
  }

  // ── Token Refresh ─────────────────────────────────────────────────────────

  static Future<bool> refreshAccessToken() async {
    _apiLog.i('🔄 ApiClient.refreshAccessToken: ━━━ START ━━━');

    final userId       = await getUserId();
    final refreshToken = await getRefreshToken();

    if (userId == null || refreshToken == null) {
      _apiLog.w(
        '⚠️ ApiClient.refreshAccessToken: '
        'No stored userId or refreshToken — cannot refresh',
      );
      return false;
    }

    _apiLog.d(
      '🔄 ApiClient.refreshAccessToken: Sending refresh for userId: $userId',
    );

    http.Response response;
    try {
      response = await post(
        ApiEndpoints.refresh,
        body: {'userId': userId, 'refreshToken': refreshToken},
      );
    } on Exception catch (e) {
      _apiLog.e('❌ ApiClient.refreshAccessToken: HTTP exception — $e');
      return false;
    }

    _apiLog.d(
      '🔄 ApiClient.refreshAccessToken: '
      'Response status: ${response.statusCode}',
    );

    if (response.statusCode == 200) {
      try {
        final data = parseBody(response);
        final newAccessToken = data['accessToken'] as String?;
        // Handle the capitalisation inconsistency in the API docs.
        final newRefreshToken =
            (data['refreshToken'] ?? data['Refreshtoken']) as String?;

        if (newAccessToken == null) {
          _apiLog.e(
            '❌ ApiClient.refreshAccessToken: '
            'accessToken missing in response body: $data',
          );
          return false;
        }

        await Future.wait([
          _storage.write(
              key: StorageKeys.accessToken, value: newAccessToken),
          _storage.write(
              key: StorageKeys.refreshToken,
              value: newRefreshToken ?? refreshToken),
        ]);

        _apiLog.i(
          '✅ ApiClient.refreshAccessToken: ✓ Tokens rotated successfully',
        );
        return true;
      } catch (e) {
        _apiLog.e(
          '❌ ApiClient.refreshAccessToken: '
          'Failed to parse response — $e',
        );
        return false;
      }
    }

    _apiLog.w(
      '⚠️ ApiClient.refreshAccessToken: '
      'Refresh rejected — status ${response.statusCode} | '
      'body: ${response.body}',
    );
    return false;
  }

  // ── JSON Parsing Helper ───────────────────────────────────────────────────

  /// Safely decode a JSON response body.
  /// Returns an empty map if the body is empty or unparseable.
  static Map<String, dynamic> parseBody(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      _apiLog.w(
        '⚠️ ApiClient.parseBody: Could not parse JSON. '
        'Raw body: ${response.body}',
      );
      return {};
    }
  }

  // ── Network Error Helper ──────────────────────────────────────────────────

  /// Convert low-level network exceptions into human-readable messages.
  static String friendlyNetworkError(Object e) {
    final msg = e.toString().toLowerCase();

    if (kIsWeb && msg.contains('failed to fetch')) {
      _apiLog.e(
        '🌐 ApiClient: CORS or network error on web.'

        '   The browser blocked the request — most likely the backend is missing Access-Control-Allow-Origin headers.'

        '   Check the browser DevTools → Network tab → look for a failed OPTIONS preflight request to confirm.',
      );
      return 'Request blocked by browser security policy. '
          'The server may need CORS headers configured. '
          'Please contact support or try the mobile app.';
    }

    // ── Standard network errors ──────────────────────────────────────────────
    if (msg.contains('socketexception')    ||
        msg.contains('failed to fetch')    ||
        msg.contains('connection refused') ||
        msg.contains('clientexception')) {
      return 'Cannot connect to server. Check your internet connection.';
    }
    if (msg.contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }
    if (msg.contains('tlsexception') || msg.contains('handshake')) {
      return 'Secure connection failed. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  /// Internal authenticated POST — no retry logic.
  /// Called by [authPost] which owns the 401-recovery logic.
  static Future<http.Response> _doAuthPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
  }

  /// Internal authenticated GET — no retry logic.
  /// Called by [authGet] which owns the 401-recovery logic.
  static Future<http.Response> _doAuthGet(String endpoint) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http.get(uri, headers: headers).timeout(_timeout);
  }

  /// Internal authenticated PUT — no retry logic.
  /// Called by [authPut] which owns the 401-recovery logic.
  static Future<http.Response> _doAuthPut(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http
        .put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
  }

  /// Internal authenticated PATCH — no retry logic.
  /// Called by [authPatch] which owns the 401-recovery logic.
  static Future<http.Response> _doAuthPatch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http
        .patch(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
  }

  /// Internal authenticated DELETE — no retry logic.
  /// Called by [authDelete] which owns the 401-recovery logic.
  static Future<http.Response> _doAuthDelete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http
        .delete(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
  }

  /// Clear the session and fire [onSessionExpired].

  static Future<void> _handleSessionExpired() async {
    await clearSession();
    if (onSessionExpired != null) {
      _apiLog.i(
        '🚨 ApiClient._handleSessionExpired: '
        'Firing onSessionExpired → app should navigate to login',
      );
      onSessionExpired!();
    } else {
      _apiLog.w(
        '⚠️ ApiClient._handleSessionExpired: onSessionExpired is null.\n'
        '   Register it in main.dart to enable automatic redirect:\n'
        '   ApiClient.onSessionExpired = () { navigatorKey... };',
      );
    }
  }
}