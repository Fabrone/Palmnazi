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
// HOW URLS WORK IN THIS PROJECT:
//   Full URL = baseUrl + endpoint path
//   e.g.  https://pnrcapi.vercel.app  +  /api/auth/login
//       = https://pnrcapi.vercel.app/api/auth/login
//
// To switch to local development:
//   1. Comment out the live baseUrl line.
//   2. Uncomment the localhost line and set your port number.
//
// ── CORS — REQUIRED FOR FLUTTER WEB ─────────────────────────────────────────
//
// Flutter Web runs inside a browser. Every HTTP request is routed through the
// browser's fetch() API, which enforces the Same-Origin Policy. Before sending
// a POST/PUT/DELETE (or any request with a custom header like Authorization)
// the browser sends an OPTIONS preflight. If the backend does not reply with
// the correct Access-Control headers the browser aborts the request and the
// Dart http package throws: ClientException: Failed to fetch.
//
// ADD THIS TO YOUR NODE.JS BACKEND (index.js / server.js / app.js):
//
//   const cors = require('cors');          // npm install cors
//
//   app.use(cors({
//     origin: '*',                         // replace '*' with your exact
//                                          // deployed domain in production
//     methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
//     allowedHeaders: ['Content-Type', 'Authorization'],
//     credentials: false,                  // set true only if using cookies
//   }));
//
//   // Handle preflight for every route
//   app.options('*', cors());
//
// If you are on Vercel and your backend is a Next.js API route, add this to
// each route handler instead:
//
//   res.setHeader('Access-Control-Allow-Origin', '*');
//   res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
//   res.setHeader('Access-Control-Allow-Headers', 'Content-Type,Authorization');
//   if (req.method === 'OPTIONS') { res.status(200).end(); return; }
//
// ─────────────────────────────────────────────────────────────────────────────
class AppConfig {
  AppConfig._();

  // ── Live / testing environment ───────────────
  static const String baseUrl = 'https://pnrcapi.vercel.app';

  // ── Local development (uncomment to use) ─────
  // static const String baseUrl = 'http://localhost:3000';

  // ── Google Sign-In ───────────────────────────
  // Replace with your actual Web Client ID from Google Cloud Console.
  static const String googleWebClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
}

// ─────────────────────────────────────────────────────────────────────────────
// API ENDPOINTS
//
// All paths are relative to AppConfig.baseUrl.
// Every endpoint begins with /api/ as required by the backend.
// Use ApiEndpoints.url(path) to get the full absolute URL.
//
// ── Adding new endpoints ─────────────────────────────────────────────────────
// As each backend section is ready (cities, channels, places), add its
// constant here.  Every screen imports this file and uses the constant —
// never a raw string.  Changing a URL only ever requires editing one line here.
// ─────────────────────────────────────────────────────────────────────────────
class ApiEndpoints {
  ApiEndpoints._();

  // ── Authentication ───────────────────────────────────────────────────────

  /// Register a new account.
  /// POST  Body: { email, password }
  static const String register = '/api/auth/register';

  /// Log in with email + password.
  /// POST  Body: { email, password }
  /// Returns: { accessToken, refreshToken, user }
  static const String login = '/api/auth/login';

  /// Log in / register via Google.
  /// POST  Body: { idToken }
  /// Returns: { accessToken, refreshToken, user }
  static const String googleAuth = '/api/auth/google';

  /// Revoke a refresh token (logout).
  /// POST  Body: { refreshTokenId }  ← the stored refreshToken value
  /// Auth: Bearer required
  static const String logout = '/api/auth/logout';

  /// Rotate an expired access token.
  /// POST  Body: { userId, refreshToken }
  /// Returns: { accessToken, refreshToken }
  static const String refresh = '/api/auth/refresh';

  /// Get the currently authenticated user's profile.
  /// GET   Auth: Bearer required
  /// Returns: { user: { sub, email, roles[], permissions[], iat, exp } }
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

  // ── Resort Cities  (uncomment when backend is ready) ────────────────────
  // static const String cities   = '/api/cities';
  // static const String channels = '/api/channels';
  // static const String places   = '/api/places';

  // ────────────────────────────────────────────────────────────────────────
  /// Build the absolute URL for a given endpoint path.
  ///
  /// Every HTTP call should use this so that switching environments
  /// (live vs local) only ever requires changing [AppConfig.baseUrl].
  // ────────────────────────────────────────────────────────────────────────
  static String url(String endpoint) => '${AppConfig.baseUrl}$endpoint';
}

// ─────────────────────────────────────────────────────────────────────────────
// SECURE STORAGE KEYS
//
// Every key used with FlutterSecureStorage is declared here.
// Never write raw strings when reading or writing to storage.
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

// ─────────────────────────────────────────────────────────────────────────────
// API CLIENT
//
// Central HTTP helper used by every service class in the app.
//
// Public surface:
//   post()               — unauthenticated POST
//   authPost()           — authenticated POST  (auto-refresh on 401)
//   authGet()            — authenticated GET   (auto-refresh on 401)
//   saveSession()        — persist tokens + user info after login
//   clearSession()       — wipe storage on logout or hard-expired session
//   refreshAccessToken() — rotate the access + refresh token pair
//
// ── 401 Auto-Refresh Behaviour ───────────────────────────────────────────────
//
// When authPost() or authGet() receives a 401 from the server:
//   1. refreshAccessToken() is called automatically behind the scenes.
//   2. If the refresh succeeds, the original request is retried once
//      with the new token.  The caller never notices the recovery.
//   3. If the refresh also fails (expired, revoked, or network error),
//      clearSession() is called and [onSessionExpired] fires so the
//      app can navigate the user back to the login screen.
//
// ── Registering the Expiry Callback ─────────────────────────────────────────
//
// Do this once in main.dart (or wherever you hold your NavigatorKey)
// after the key is available:
//
//   final navigatorKey = GlobalKey<NavigatorState>();
//
//   void main() {
//     WidgetsFlutterBinding.ensureInitialized();
//     ApiClient.onSessionExpired = () {
//       navigatorKey.currentState?.pushAndRemoveUntil(
//         MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)),
//         (route) => false,
//       );
//     };
//     runApp(MyApp(navigatorKey: navigatorKey));
//   }
// ─────────────────────────────────────────────────────────────────────────────
class ApiClient {
  ApiClient._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const Duration _timeout = Duration(seconds: 20);

  // ── Session-Expired Callback ──────────────────────────────────────────────
  //
  // Register once at app start-up (see class-level docs above).
  // Fires only when a session is confirmed unrecoverable — i.e. both the
  // original request and the post-refresh retry returned 401.
  static void Function()? onSessionExpired;

  // ── Token / Session Accessors ─────────────────────────────────────────────

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

  // ── Public HTTP Helpers ───────────────────────────────────────────────────

  /// Unauthenticated POST.
  ///
  /// Use for endpoints that do not require a Bearer token:
  /// register, login, forgot-password, reset-password.
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
  ///
  /// The Bearer token is attached from storage automatically.
  /// On 401 the token is refreshed and the request is retried once.
  /// If the retry also fails the session is cleared and
  /// [onSessionExpired] fires.
  ///
  /// Use for: logout, change-password, and any future protected POSTs.
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
  ///
  /// Same 401-refresh-retry logic as [authPost].
  /// Use for: GET /api/auth/me and any future protected GETs.
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

  // ── Token Refresh ─────────────────────────────────────────────────────────

  /// Rotate the access + refresh token pair using the stored refresh token.
  ///
  /// Returns [true] on success.  New tokens are written to storage so the
  /// next authPost / authGet call carries the updated token automatically.
  ///
  /// Endpoint : POST /api/auth/refresh
  /// Body     : { userId, refreshToken }
  /// 200 OK   : { accessToken, refreshToken }  (old refresh token revoked)
  /// 401      : Invalid refresh token
  /// 403      : User inactive
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

    // ── CORS / browser fetch failure ────────────────────────────────────────
    // On Flutter Web every request goes through the browser's fetch() API.
    // When the backend is missing CORS headers the browser blocks the request
    // and dart:html reports it as a generic "Failed to fetch" ClientException
    // with NO status code — indistinguishable from a real network outage at
    // the Dart level.  We detect it here so we can surface a meaningful message
    // instead of "Check your internet connection."
    //
    // Root cause: the backend at pnrcapi.vercel.app must return:
    //   Access-Control-Allow-Origin: *   (or your app's exact origin)
    //   Access-Control-Allow-Methods: GET, POST, OPTIONS
    //   Access-Control-Allow-Headers: Content-Type, Authorization
    // on every response, including the preflight OPTIONS response.
    // See the backend fix snippet in api_client.dart comments below.
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

  /// Clear the session and fire [onSessionExpired].
  ///
  /// Called only after a confirmed, unrecoverable 401 — i.e. both the
  /// original request and the post-refresh retry returned 401.
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