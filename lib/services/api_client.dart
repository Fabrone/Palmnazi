import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── MFA (Email OTP) ──────────────────────────────────────────────────────

  /// Send a one-time passcode to the authenticated user's email address.
  /// POST  Auth: Bearer required
  /// Body: { email }
  /// 200 OK: { message: "OTP sent" }
  static const String mfaSendOtp = '/api/auth/mfa/send-otp';

  /// Verify the OTP the user received and enable / confirm MFA.
  /// POST  Auth: Bearer required
  /// Body: { email, otp }
  /// 200 OK: { message: "MFA verified", mfaEnabled: true }
  static const String mfaVerifyOtp = '/api/auth/mfa/verify-otp';

  /// Verify an OTP as the second factor during login (step-up auth).
  /// POST  Auth: Bearer required
  /// Body: { email, otp }
  /// 200 OK: { accessToken, refreshToken, user }
  static const String mfaLoginVerify = '/api/auth/mfa/login-verify';

  /// Disable MFA for the authenticated user.
  /// POST  Auth: Bearer required
  /// Body: { email }
  /// 200 OK: { message: "MFA disabled", mfaEnabled: false }
  static const String mfaDisable = '/api/auth/mfa/disable';

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
// STORAGE KEYS
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

  /// All keys managed by the session store (used for clear operations).
  static const List<String> all = [
    accessToken,
    refreshToken,
    userId,
    userEmail,
    userRoles,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION STORE
//
// WHY NOT flutter_secure_storage:
//   On Flutter Web, flutter_secure_storage uses IndexedDB + WebCrypto. The
//   underlying write operations dispatch detached JS Promises that can throw
//   OperationError directly into Dart's root zone — bypassing all try/catch —
//   causing widget disposal while _handleLogin() is still executing. The
//   `if (!mounted) return` guard then fires and navigation never happens
//   (same root cause as the Firebase Auth IndexedDB issue documented in
//   firebase_session_service.dart).
//
// WHY shared_preferences:
//   On web, shared_preferences writes to window.localStorage synchronously at
//   the JS layer. No Promises, no WebCrypto, no IndexedDB, no OperationError.
//   On iOS/Android, it uses NSUserDefaults / SharedPreferences — both are
//   reliable and well-tested.
//
// WHY the in-memory cache:
//   Even though shared_preferences is fast, an in-memory Map guarantees that
//   getAccessToken() returns the just-saved value INSTANTLY after saveSession()
//   — even during the same microtask cycle. This eliminates the race between
//   saveSession() completing and the subsequent _loadAuthState() read in
//   LandingPage.initState().
// ─────────────────────────────────────────────────────────────────────────────
class _SessionStore {
  _SessionStore._();

  // Primary source of truth at runtime. Populated on every write and on
  // the first read (lazy cache warm-up). Cleared on clearSession().
  static final Map<String, String> _mem = {};

  // Lazy-initialized SharedPreferences instance. Created once on first use.
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Optional: call from main.dart before routing to pre-fill _mem ─────────
  //
  // This is not strictly required but eliminates any cold-start I/O on the
  // very first ApiClient.isLoggedIn / getAccessToken() call.
  //
  //   void main() async {
  //     WidgetsFlutterBinding.ensureInitialized();
  //     await _SessionStore.prime();   // ← warm up cache
  //     ...
  //   }
  static Future<void> prime() async {
    try {
      final p = await _instance;
      for (final key in StorageKeys.all) {
        final v = p.getString(key);
        if (v != null) _mem[key] = v;
      }
      _apiLog.d('💾 _SessionStore.prime: Cache warmed — ${_mem.length} key(s) loaded');
    } catch (e) {
      _apiLog.w('⚠️ _SessionStore.prime: Could not warm cache: $e');
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  static Future<String?> read(String key) async {
    // Memory hit — no I/O at all
    if (_mem.containsKey(key)) return _mem[key];

    // Cold start / cache miss — read from SharedPreferences and cache the result
    try {
      final p = await _instance;
      final v = p.getString(key);
      if (v != null) _mem[key] = v;
      return v;
    } catch (e) {
      _apiLog.w('⚠️ _SessionStore.read($key) failed: $e');
      return null;
    }
  }

  static Future<void> writeAll(Map<String, String> entries) async {
    // Apply all writes to memory immediately
    _mem.addAll(entries);

    try {
      final p = await _instance;
      for (final kv in entries.entries) {
        await p.setString(kv.key, kv.value);
      }
    } catch (e) {
      _apiLog.w('⚠️ _SessionStore.writeAll persist failed: $e');
    }
  }

  // ── Delete one ────────────────────────────────────────────────────────────


  // ── Delete all session keys ───────────────────────────────────────────────

  static Future<void> deleteAll() async {
    _mem.clear();
    try {
      final p = await _instance;
      for (final key in StorageKeys.all) {
        await p.remove(key);
      }
    } catch (e) {
      _apiLog.w('⚠️ _SessionStore.deleteAll failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// API CLIENT
// ─────────────────────────────────────────────────────────────────────────────
class ApiClient {
  ApiClient._();

  static const Duration _timeout = Duration(seconds: 20);

  // ── Session-Expired Callback ─────────────────────────────
  static void Function()? onSessionExpired;

  // ── Optional startup warm-up ─────────────────────────────────────────────
  //
  // Call once in main() after WidgetsFlutterBinding.ensureInitialized():
  //
  //   await ApiClient.primeSessionCache();
  //
  // This pre-loads any persisted session into the in-memory cache so that
  // the very first isLoggedIn / getAccessToken() call is instant.
  static Future<void> primeSessionCache() => _SessionStore.prime();

  // ── Token / Session Accessors ────────────────────────────

  static Future<String?> getAccessToken()  async =>
      _SessionStore.read(StorageKeys.accessToken);

  static Future<String?> getRefreshToken() async =>
      _SessionStore.read(StorageKeys.refreshToken);

  static Future<String?> getUserId()       async =>
      _SessionStore.read(StorageKeys.userId);

  static Future<String?> getUserEmail()    async =>
      _SessionStore.read(StorageKeys.userEmail);

  /// Alias for [getUserEmail] — used by AccountScreen and other callers
  /// that refer to the session email as `getEmail()`.
  static Future<String?> getEmail() => getUserEmail();

  /// Returns roles as a List. Empty list when no session exists.
  static Future<List<String>> getUserRoles() async {
    final raw = await _SessionStore.read(StorageKeys.userRoles);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',');
  }

  /// Alias for [getUserRoles] — used by AccountScreen and other callers
  /// that refer to the session roles as `getRoles()`.
  static Future<List<String>> getRoles() => getUserRoles();

  /// True when a valid access token is currently stored.
  static Future<bool> get isLoggedIn async =>
      (await getAccessToken()) != null;

  // ── Session Persistence ───────────────────────────────────────────────────

  /// Persist tokens and user info after any successful login.
  ///
  /// The in-memory cache inside _SessionStore is written synchronously before
  /// any I/O, so getAccessToken() called immediately after saveSession()
  /// returns the correct token without any async delay.
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    required List<String> roles,
  }) async {
    _apiLog.d('💾 ApiClient.saveSession: Persisting session');
    try {
      await _SessionStore.writeAll({
        StorageKeys.accessToken:  accessToken,
        StorageKeys.refreshToken: refreshToken,
        StorageKeys.userId:       userId,
        StorageKeys.userEmail:    email,
        StorageKeys.userRoles:    roles.join(','),
      });
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

  /// Wipe all stored session data. Call on logout or confirmed session expiry.
  static Future<void> clearSession() async {
    _apiLog.i('🚪 ApiClient.clearSession: Deleting all session entries');
    await _SessionStore.deleteAll();
    _apiLog.i('🚪 ApiClient.clearSession: ✓ Session cleared');
  }

  // ── HTTP Headers ──────────────────────────────────────────────────────────

  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  static Future<Map<String, String>> get _authHeaders async {
    // getAccessToken() returns from in-memory cache — no I/O after first login
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Public HTTP Helpers ───────────────────────────────────────────────────

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

    var response = await _doAuthGet(endpoint);

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

  /// Authenticated DELETE with automatic 401 recovery.
  ///
  /// An optional [body] may be supplied for endpoints that require a JSON
  /// payload on DELETE (e.g. bulk-unlink operations). When omitted the
  /// request is sent with no body.
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

        await _SessionStore.writeAll({
          StorageKeys.accessToken:  newAccessToken,
          StorageKeys.refreshToken: newRefreshToken ?? refreshToken,
        });

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

    if (msg.contains('operationerror')) {
      _apiLog.e(
        '🌐 ApiClient: OperationError on web — almost certainly a CORS issue.\n'
        '   The backend must return Access-Control-Allow-Origin headers for '
        '${AppConfig.baseUrl}\n'
        '   Check DevTools → Network → look for a blocked OPTIONS preflight.',
      );
      return 'Request blocked by browser security policy. '
          'The server may need CORS headers configured. '
          'Please contact support or try the mobile app.';
    }

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

  static Future<http.Response> _doAuthGet(String endpoint) async {
    final uri     = Uri.parse(ApiEndpoints.url(endpoint));
    final headers = await _authHeaders;
    return http.get(uri, headers: headers).timeout(_timeout);
  }

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