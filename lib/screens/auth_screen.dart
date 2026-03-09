import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/screens/reset_password_screen.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED LOGGER
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

// ─────────────────────────────────────────────────────────────────────────────
// APP USER MODEL
//
// Represents the authenticated user as returned by the backend after login.
//
// API shape (from /api/auth/login and /api/auth/google):
// {
//   "user": {
//     "id":    "user_id_here",
//     "email": "user@example.com",
//     "roles": ["tourist"]
//   }
// }
//
// NOTE: The backend does NOT return name or phone at login time.
//       Those fields, if needed, must be fetched separately via GET /api/auth/me.
// ─────────────────────────────────────────────────────────────────────────────
class AppUser {
  final String       id;
  final String       email;
  final List<String> roles;

  AppUser({
    required this.id,
    required this.email,
    required this.roles,
  });

  /// Parse from the nested "user" object in the login / Google-auth response.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id:    json['id']    as String? ?? '',
      email: json['email'] as String? ?? '',
      roles: (json['roles'] as List<dynamic>? ?? [])
          .map((r) => r.toString())
          .toList(),
    );
  }

  /// Convenience: primary role (first entry) or "user" if none.
  String get primaryRole => roles.isNotEmpty ? roles.first : 'user';

  @override
  String toString() =>
      'AppUser(id: $id, email: $email, roles: $roles)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH RESULT MODEL
//
// message  — always a clean, user-facing string shown in the UI.
// All technical detail is logged to the terminal via _log before this is set.
// ─────────────────────────────────────────────────────────────────────────────
class AuthResult {
  final bool     isSuccess;
  final String   message;
  final AppUser? user;

  AuthResult._({required this.isSuccess, required this.message, this.user});

  factory AuthResult.success({required String message, AppUser? user}) =>
      AuthResult._(isSuccess: true,  message: message, user: user);

  factory AuthResult.failure(String message) =>
      AuthResult._(isSuccess: false, message: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH SERVICE
//
// All methods are static.  HTTP calls go through ApiClient so that
// base-URL changes only ever require editing api_client.dart.
//
// Endpoints used (from ApiEndpoints):
//   register       POST /api/auth/register
//   login          POST /api/auth/login
//   googleAuth     POST /api/auth/google
//   logout         POST /api/auth/logout
//   forgotPassword POST /api/auth/forgot-password
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER
  //
  // POST /api/auth/register
  // Body    : { email, password }
  // 200 OK  : { success: true }
  // 400     : { error: "Missing fields" }
  // 409     : { error: "Email already in use" }
  //
  // On success the user is NOT logged in automatically — they are redirected
  // to the Login tab so they authenticate and receive tokens.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    _log.i('🔐 AuthService.register: ━━━ START ━━━');
    _log.d('🔐 AuthService.register: Email → $email | Password len → ${password.length} chars');

    // ── Step 1: Send request ───────────────────────────────────────────────
    _log.i('🔐 AuthService.register: Step 1 — Sending POST to ${ApiEndpoints.url(ApiEndpoints.register)}');
    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.register,
        body: {
          'email':    email.trim(),
          'password': password,
        },
      );
      _log.i('🔐 AuthService.register: Step 1 ✓ — Response received');
    } on Exception catch (e, st) {
      _log.e(
        '❌ AuthService.register: Step 1 FAILED — Network exception\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    // ── Step 2: Log raw response ───────────────────────────────────────────
    _log.d('🔐 AuthService.register: Step 2 — Raw response:');
    _log.d('🔐 AuthService.register:   Status : ${response.statusCode}');
    _log.d('🔐 AuthService.register:   Body   : ${response.body}');

    final body = ApiClient.parseBody(response);
    _log.d('🔐 AuthService.register: Step 2 ✓ — Parsed body: $body');

    // ── Step 3: Handle status codes ────────────────────────────────────────
    _log.d('🔐 AuthService.register: Step 3 — Handling status ${response.statusCode}');
    switch (response.statusCode) {
      case 200:
      case 201:
        // Backend returns { "success": true } — no user data in this response.
        // The user must log in separately to receive tokens.
        _log.i('✅ AuthService.register: ━━━ REGISTRATION COMPLETE ━━━');
        return AuthResult.success(
          message: 'Account created! Please log in.',
        );

      case 400:
        final msg = body['error'] ?? body['message'] ?? 'Missing required fields.';
        _log.w('⚠️ AuthService.register: 400 Bad Request — $msg | full body: $body');
        return AuthResult.failure('Please fill in all required fields correctly.');

      case 409:
        final msg = body['error'] ?? body['message'] ?? 'Email conflict.';
        _log.w('⚠️ AuthService.register: 409 Conflict — $msg | full body: $body');
        return AuthResult.failure('This email is already registered. Try logging in.');

      case 500:
        _log.e('❌ AuthService.register: 500 Internal Server Error | body: $body');
        return AuthResult.failure('Server error. Please try again later.');

      default:
        _log.e(
          '❌ AuthService.register: Unhandled status ${response.statusCode} | body: $body',
        );
        return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGIN
  //
  // POST /api/auth/login
  // Body    : { email, password }
  // 200 OK  : { accessToken, refreshToken, user: { id, email, roles[] } }
  // 400     : { error: "Email and password are required" }
  // 401     : { error: "Incorrect password" }
  // 403     : { error: "User is inactive" }
  // 404     : { error: "User not found" }
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    _log.i('🔑 AuthService.login: ━━━ START ━━━');
    _log.d('🔑 AuthService.login: Email → $email | Password len → ${password.length} chars');

    // ── Step 1: Send request ───────────────────────────────────────────────
    _log.i('🔑 AuthService.login: Step 1 — Sending POST to ${ApiEndpoints.url(ApiEndpoints.login)}');
    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.login,
        body: {
          'email':    email.trim(),
          'password': password,
        },
      );
      _log.i('🔑 AuthService.login: Step 1 ✓ — Response received');
    } on Exception catch (e, st) {
      _log.e(
        '❌ AuthService.login: Step 1 FAILED — Network exception\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    // ── Step 2: Log raw response ───────────────────────────────────────────
    _log.d('🔑 AuthService.login: Step 2 — Raw response:');
    _log.d('🔑 AuthService.login:   Status : ${response.statusCode}');
    _log.d('🔑 AuthService.login:   Body   : ${response.body}');

    final body = ApiClient.parseBody(response);
    _log.d('🔑 AuthService.login: Step 2 ✓ — Parsed body: $body');

    // ── Step 3: Handle status codes ────────────────────────────────────────
    _log.d('🔑 AuthService.login: Step 3 — Handling status ${response.statusCode}');
    switch (response.statusCode) {
      case 200:
      case 201:
        // Extract tokens from root of response body
        final accessToken  = body['accessToken']  as String?;
        final refreshToken = body['refreshToken'] as String?;
        final userJson     = body['user']          as Map<String, dynamic>?;

        if (accessToken == null || refreshToken == null || userJson == null) {
          _log.e(
            '❌ AuthService.login: Missing fields in 200 response\n'
            '   accessToken  : $accessToken\n'
            '   refreshToken : $refreshToken\n'
            '   user         : $userJson\n'
            '   Full body    : $body',
          );
          return AuthResult.failure('Login failed. Please try again.');
        }

        final user = AppUser.fromJson(userJson);
        _log.i('✅ AuthService.login: Step 3 — Parsed user: $user');

        // Persist tokens + user info to secure storage
        await ApiClient.saveSession(
          accessToken:  accessToken,
          refreshToken: refreshToken,
          userId:       user.id,
          email:        user.email,
          roles:        user.roles,
        );

        _log.i('✅ AuthService.login: ━━━ LOGIN COMPLETE ━━━');
        return AuthResult.success(
          message: 'Welcome back!',
          user:    user,
        );

      case 400:
        final msg = body['error'] ?? body['message'] ?? 'Missing fields.';
        _log.w('⚠️ AuthService.login: 400 Bad Request — $msg | body: $body');
        return AuthResult.failure('Please enter both email and password.');

      case 401:
        final msg = body['error'] ?? body['message'] ?? 'Incorrect password.';
        _log.w('⚠️ AuthService.login: 401 Unauthorized — $msg | body: $body');
        return AuthResult.failure('Incorrect email or password. Please try again.');

      case 403:
        final msg = body['error'] ?? body['message'] ?? 'Account inactive.';
        _log.w('⚠️ AuthService.login: 403 Forbidden — $msg | body: $body');
        return AuthResult.failure('Your account is inactive. Please contact support.');

      case 404:
        final msg = body['error'] ?? body['message'] ?? 'User not found.';
        _log.w('⚠️ AuthService.login: 404 Not Found — $msg | body: $body');
        return AuthResult.failure('No account found with this email address.');

      case 500:
        _log.e('❌ AuthService.login: 500 Server Error | body: $body');
        return AuthResult.failure('Server error. Please try again later.');

      default:
        _log.e(
          '❌ AuthService.login: Unhandled status ${response.statusCode} | body: $body',
        );
        return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  //
  // 1. Obtain idToken from Google Sign-In (native flow).
  // 2. POST /api/auth/google  Body: { idToken }
  // 3. Response: same shape as /login  { accessToken, refreshToken, user }
  //
  // 200 OK  : { accessToken, refreshToken, user: { id, email, roles[] } }
  // 400     : { error: "Missing token" }
  // 401     : { error: "Invalid Google token" }
  // 402     : { error: "Google email not verified" | "User inactive" }
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> googleSignIn() async {
    _log.i('🌐 AuthService.googleSignIn: ━━━ START ━━━');
    _log.d('🌐 AuthService.googleSignIn: Target → ${ApiEndpoints.url(ApiEndpoints.googleAuth)}');

    try {
      // ── Step 1: Initialize GoogleSignIn (v7 singleton) ───────────────────
      _log.i('🌐 AuthService.googleSignIn: Step 1 — Initializing GoogleSignIn.instance');
      final gsi = GoogleSignIn.instance;
      await gsi.initialize(serverClientId: AppConfig.googleWebClientId);
      _log.i('🌐 AuthService.googleSignIn: Step 1 ✓ — Initialized');

      // ── Step 2: Check platform support ──────────────────────────────────
      final supported = gsi.supportsAuthenticate();
      _log.d('🌐 AuthService.googleSignIn: Step 2 — supportsAuthenticate() = $supported');
      if (!supported) {
        _log.w('⚠️ AuthService.googleSignIn: Step 2 — Platform not supported');
        return AuthResult.failure('Google Sign-In is not supported on this platform.');
      }

      // ── Step 3: Launch Google account picker ─────────────────────────────
      _log.i('🌐 AuthService.googleSignIn: Step 3 — Launching account picker');
      final GoogleSignInAccount googleUser = await gsi.authenticate(
        scopeHint: ['email', 'profile'],
      );
      _log.i('🌐 AuthService.googleSignIn: Step 3 ✓ — Account selected: ${googleUser.email}');

      // ── Step 4: Retrieve ID token ────────────────────────────────────────
      _log.i('🌐 AuthService.googleSignIn: Step 4 — Retrieving ID token (sync in v7)');
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        _log.e(
          '❌ AuthService.googleSignIn: Step 4 FAILED — idToken is null.\n'
          '   Check that googleWebClientId in AppConfig is the correct Web Client ID.',
        );
        return AuthResult.failure(
          'Could not retrieve Google credentials. Please try again.',
        );
      }
      _log.i('🌐 AuthService.googleSignIn: Step 4 ✓ — idToken obtained (${idToken.length} chars)');

      // ── Step 5: POST idToken to backend ─────────────────────────────────
      _log.i('🌐 AuthService.googleSignIn: Step 5 — Sending idToken to backend');
      dynamic response;
      try {
        response = await ApiClient.post(
          ApiEndpoints.googleAuth,
          body: {'idToken': idToken},
        );
        _log.i('🌐 AuthService.googleSignIn: Step 5 ✓ — Backend responded');
      } on Exception catch (e, st) {
        _log.e(
          '❌ AuthService.googleSignIn: Step 5 FAILED — HTTP exception\n'
          '   Type    : ${e.runtimeType}\n'
          '   Message : $e',
          error: e, stackTrace: st,
        );
        return AuthResult.failure(ApiClient.friendlyNetworkError(e));
      }

      // ── Step 6: Log and parse response ───────────────────────────────────
      _log.d('🌐 AuthService.googleSignIn: Step 6 — Raw response:');
      _log.d('🌐 AuthService.googleSignIn:   Status : ${response.statusCode}');
      _log.d('🌐 AuthService.googleSignIn:   Body   : ${response.body}');

      final body = ApiClient.parseBody(response);
      _log.d('🌐 AuthService.googleSignIn: Step 6 ✓ — Parsed body: $body');

      // ── Step 7: Handle status codes ──────────────────────────────────────
      _log.d('🌐 AuthService.googleSignIn: Step 7 — Handling status ${response.statusCode}');
      switch (response.statusCode) {
        case 200:
        case 201:
          final accessToken  = body['accessToken']  as String?;
          final refreshToken = body['refreshToken'] as String?;
          final userJson     = body['user']          as Map<String, dynamic>?;

          if (accessToken == null || refreshToken == null || userJson == null) {
            _log.e(
              '❌ AuthService.googleSignIn: Missing fields in 200 response\n'
              '   Full body: $body',
            );
            return AuthResult.failure('Google Sign-In failed. Please try again.');
          }

          final user = AppUser.fromJson(userJson);
          _log.i('✅ AuthService.googleSignIn: Step 7 — Parsed user: $user');

          await ApiClient.saveSession(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            userId:       user.id,
            email:        user.email,
            roles:        user.roles,
          );

          _log.i('✅ AuthService.googleSignIn: ━━━ GOOGLE AUTH COMPLETE ━━━');
          return AuthResult.success(
            message: 'Signed in with Google successfully!',
            user:    user,
          );

        case 400:
          _log.w('⚠️ AuthService.googleSignIn: 400 — Missing/bad token | body: $body');
          return AuthResult.failure('Google Sign-In failed. Please try again.');

        case 401:
          _log.w('⚠️ AuthService.googleSignIn: 401 — Invalid token | body: $body');
          return AuthResult.failure('Google credentials are invalid. Please try again.');

        case 402:
        case 403:
          final errMsg =
              (body['error'] ?? body['message'] ?? '').toString().toLowerCase();
          _log.w(
            '⚠️ AuthService.googleSignIn: ${response.statusCode} — $errMsg | body: $body',
          );
          if (errMsg.contains('inactive')) {
            return AuthResult.failure(
              'Your account is inactive. Please contact support.',
            );
          }
          return AuthResult.failure(
            'Google email not verified. Please verify your Google account first.',
          );

        default:
          _log.e(
            '❌ AuthService.googleSignIn: Unhandled ${response.statusCode} | body: $body',
          );
          return AuthResult.failure('Something went wrong. Please try again.');
      }
    } on GoogleSignInException catch (e, st) {
      _log.e(
        '❌ AuthService.googleSignIn: GoogleSignInException\n'
        '   Code        : ${e.code.name}\n'
        '   Description : ${e.description}',
        error: e, stackTrace: st,
      );
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        _log.i('🌐 AuthService.googleSignIn: User cancelled the flow');
        return AuthResult.failure('Google Sign-In was cancelled.');
      }
      return AuthResult.failure('Google Sign-In failed. Please try again.');
    } catch (e, st) {
      _log.e(
        '❌ AuthService.googleSignIn: Unexpected exception\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  //
  // POST /api/auth/logout  (authenticated)
  // Body    : { refreshTokenId }   ← the stored refreshToken value
  // 200 OK  : { success: true }
  //
  // Always clears local session regardless of server response,
  // so the user cannot get stuck in a logged-in state on the device.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> logout() async {
    _log.i('🚪 AuthService.logout: ━━━ START ━━━');

    final refreshToken = await ApiClient.getRefreshToken();

    if (refreshToken != null) {
      _log.i('🚪 AuthService.logout: Revoking refresh token on server');
      try {
        final response = await ApiClient.authPost(
          ApiEndpoints.logout,
          body: {'refreshTokenId': refreshToken},
        );
        _log.d(
          '🚪 AuthService.logout: Server responded ${response.statusCode} | '
          'body: ${response.body}',
        );
        if (response.statusCode == 200) {
          _log.i('🚪 AuthService.logout: ✓ Server confirmed token revocation');
        } else {
          _log.w(
            '⚠️ AuthService.logout: Server returned ${response.statusCode} '
            '— proceeding to clear local session anyway',
          );
        }
      } on Exception catch (e) {
        _log.w(
          '⚠️ AuthService.logout: Could not reach server ($e) '
          '— clearing local session anyway',
        );
      }
    } else {
      _log.w('⚠️ AuthService.logout: No refresh token stored — skipping server call');
    }

    await ApiClient.clearSession();
    _log.i('🚪 AuthService.logout: ━━━ LOGOUT COMPLETE ━━━');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORGOT PASSWORD
  //
  // POST /api/auth/forgot-password
  // Body    : { email }
  // 200 OK  : { message: "If account exists, reset email sent." }
  // 500     : { message: "Something went wrong." }
  //
  // The backend sends a reset link to the user's inbox if the email exists.
  // We always display a neutral message to avoid account-enumeration attacks.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> forgotPassword({required String email}) async {
    _log.i('🔒 AuthService.forgotPassword: ━━━ START ━━━');
    _log.d(
      '🔒 AuthService.forgotPassword: '
      'URL → ${ApiEndpoints.url(ApiEndpoints.forgotPassword)} | Email → $email',
    );

    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.forgotPassword,
        body: {'email': email.trim()},
      );
      _log.i('🔒 AuthService.forgotPassword: Response received');
    } on Exception catch (e, st) {
      _log.e(
        '❌ AuthService.forgotPassword: HTTP FAILED\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    _log.d('🔒 AuthService.forgotPassword: Status → ${response.statusCode}');
    _log.d('🔒 AuthService.forgotPassword: Body   → ${response.body}');

    final body = ApiClient.parseBody(response);

    if (response.statusCode == 200 || response.statusCode == 204) {
      _log.i('✅ AuthService.forgotPassword: ━━━ RESET EMAIL SENT ━━━');
      // Always show a neutral message (prevents account enumeration)
      return AuthResult.success(
        message: 'If that email is registered, a reset link has been sent. '
                 'Check your inbox and spam folder.',
      );
    }

    switch (response.statusCode) {
      case 400:
        _log.w('⚠️ AuthService.forgotPassword: 400 — ${body['message'] ?? body['error']}');
        return AuthResult.failure('Please enter a valid email address.');

      case 404:
        // Still return neutral success to prevent account enumeration
        _log.w('⚠️ AuthService.forgotPassword: 404 — email not registered, returning neutral');
        return AuthResult.success(
          message: 'If that email is registered, a reset link has been sent. '
                   'Check your inbox and spam folder.',
        );

      case 429:
        _log.w('⚠️ AuthService.forgotPassword: 429 — Rate limited');
        return AuthResult.failure(
          'Too many attempts. Please wait a few minutes and try again.',
        );

      case 500:
        _log.e('❌ AuthService.forgotPassword: 500 — ${body['message'] ?? body['error']}');
        return AuthResult.failure('Something went wrong. Please try again later.');

      default:
        _log.e(
          '❌ AuthService.forgotPassword: Unhandled ${response.statusCode} | body: $body',
        );
        return AuthResult.failure('Something went wrong. Please try again later.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  final bool isLogin;
  const AuthScreen({super.key, required this.isLogin});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _loginFormKey  = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  // ── Login controllers ─────────────────────────────────────────────────────
  final _loginEmailController    = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // ── Sign-up controllers ───────────────────────────────────────────────────
  // NOTE: The register endpoint only accepts email + password.
  // Name and phone are not collected at registration.
  final _signUpEmailController           = TextEditingController();
  final _signUpPasswordController        = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();

  bool _obscureLoginPassword   = true;
  bool _obscureSignUpPassword  = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading              = false;

  @override
  void initState() {
    super.initState();
    _log.i('🖥️ AuthScreen: ━━━ SCREEN INITIALIZED ━━━');
    _log.d('🖥️ AuthScreen: Initial tab → ${widget.isLogin ? "Login (0)" : "Sign Up (1)"}');
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isLogin ? 0 : 1,
    );
    _tabController.addListener(() {
      _log.d(
        '🖥️ AuthScreen: Tab changed → '
        '${_tabController.index == 0 ? "Login" : "Sign Up"}',
      );
    });
  }

  @override
  void dispose() {
    _log.i('🧹 AuthScreen: Disposing resources');
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    super.dispose();
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    _log.d('🖥️ AuthScreen._handleLogin: Login button pressed');
    if (!_loginFormKey.currentState!.validate()) {
      _log.w('⚠️ AuthScreen._handleLogin: Form validation FAILED');
      return;
    }
    _log.i(
      '🖥️ AuthScreen._handleLogin: Form validated ✓ | '
      'email → ${_loginEmailController.text.trim()}',
    );

    setState(() => _isLoading = true);

    final result = await AuthService.login(
      email:    _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _log.i(
      '🖥️ AuthScreen._handleLogin: Result → '
      'isSuccess: ${result.isSuccess} | "${result.message}"',
    );
    _showMessage(result);

    if (result.isSuccess) {
      _log.i('🖥️ AuthScreen._handleLogin: ✅ Navigating to LandingPage');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    }
  }

  Future<void> _handleRegister() async {
    _log.d('🖥️ AuthScreen._handleRegister: Sign Up button pressed');
    if (!_signUpFormKey.currentState!.validate()) {
      _log.w('⚠️ AuthScreen._handleRegister: Form validation FAILED');
      return;
    }
    _log.i(
      '🖥️ AuthScreen._handleRegister: Form validated ✓ | '
      'email → ${_signUpEmailController.text.trim()}',
    );

    setState(() => _isLoading = true);

    final result = await AuthService.register(
      email:    _signUpEmailController.text.trim(),
      password: _signUpPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _log.i(
      '🖥️ AuthScreen._handleRegister: Result → '
      'isSuccess: ${result.isSuccess} | "${result.message}"',
    );
    _showMessage(result);

    if (result.isSuccess) {
      // Pre-fill login email and switch tab so the user can log in immediately.
      _loginEmailController.text = _signUpEmailController.text.trim();
      _tabController.animateTo(0);
      _log.i('🖥️ AuthScreen._handleRegister: ✅ Switched to Login tab');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    _log.i('🖥️ AuthScreen._handleGoogleSignIn: Google button pressed');
    setState(() => _isLoading = true);

    final result = await AuthService.googleSignIn();

    if (!mounted) return;
    setState(() => _isLoading = false);

    _log.i(
      '🖥️ AuthScreen._handleGoogleSignIn: Result → '
      'isSuccess: ${result.isSuccess} | "${result.message}"',
    );
    _showMessage(result);

    if (result.isSuccess) {
      _log.i('🖥️ AuthScreen._handleGoogleSignIn: ✅ Navigating to LandingPage');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    }
  }

  // ── Message Display ───────────────────────────────────────────────────────

  void _showMessage(AuthResult result) {
    _log.d('🖥️ AuthScreen._showMessage: "${result.message}"');
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.isSuccess
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: result.isSuccess
            ? const Color(0xFF0D7377)
            : const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: result.isSuccess ? 3 : 5),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _log.d('🖥️ AuthScreen: build() called');
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A1128),
                  Color(0xFF1E3A5F),
                  Color(0xFF0D7377),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF14FFEC),
                  strokeWidth: 3,
                ),
              ),
            ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Back button row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                _log.d('🖥️ AuthScreen: Back button pressed');
                                Navigator.pop(context);
                              },
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Card
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.landscape,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // App name
                            Text(
                              'PALMNAZI',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Resort Cities',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Tab bar
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF14FFEC),
                                      Color(0xFF0D7377),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                indicatorSize: TabBarIndicatorSize.tab,
                                dividerColor: Colors.transparent,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white70,
                                tabs: const [
                                  Tab(text: 'Login'),
                                  Tab(text: 'Sign Up'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Tab views
                            // Height is sufficient for both forms.
                            // Login  : email + password + button + forgot + divider + google
                            // Sign Up: email + password + confirm + button + divider + google
                            SizedBox(
                              height: 420,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildLoginForm(),
                                  _buildSignUpForm(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Login Form ────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _buildTextField(
            controller: _loginEmailController,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPasswordController,
            label: 'Password',
            icon: Icons.lock_outlined,
            obscureText: _obscureLoginPassword,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please enter your password' : null,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureLoginPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white70,
              ),
              onPressed: () =>
                  setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
          ),
          const SizedBox(height: 24),

          // Login button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14FFEC),
                foregroundColor: const Color(0xFF1E3A5F),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1E3A5F),
                      ),
                    )
                  : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Forgot password
          TextButton(
            onPressed: _isLoading ? null : _showForgotPasswordSheet,
            child: Text(
              'Forgot Password?',
              style: TextStyle(
                color: const Color(0xFF14FFEC).withValues(alpha: 0.9),
              ),
            ),
          ),

          // Navigate directly to ResetPasswordScreen for users who already
          // have a reset code from their email.
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    _log.d(
                      '🖥️ AuthScreen: '
                      '"Have a reset code?" pressed — navigating to ResetPasswordScreen',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ResetPasswordScreen(),
                      ),
                    );
                  },
            child: Text(
              'Have a reset code? Set new password →',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _buildDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(label: 'Continue with Google'),
        ],
      ),
    );
  }

  // ── Sign-Up Form ──────────────────────────────────────────────────────────
  //
  // The register API endpoint accepts only { email, password }.
  // Name and phone are not part of the registration flow.

  Widget _buildSignUpForm() {
    return Form(
      key: _signUpFormKey,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildTextField(
              controller: _signUpEmailController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _signUpPasswordController,
              label: 'Password',
              icon: Icons.lock_outlined,
              obscureText: _obscureSignUpPassword,
              validator: _passwordValidator,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSignUpPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => setState(
                  () => _obscureSignUpPassword = !_obscureSignUpPassword,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _signUpConfirmPasswordController,
              label: 'Confirm Password',
              icon: Icons.lock_outlined,
              obscureText: _obscureConfirmPassword,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _signUpPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Create account button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14FFEC),
                  foregroundColor: const Color(0xFF1E3A5F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1E3A5F),
                        ),
                      )
                    : const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _buildDivider(),
            const SizedBox(height: 16),
            _buildGoogleButton(label: 'Sign up with Google'),
          ],
        ),
      ),
    );
  }

  // ── Shared Widgets ────────────────────────────────────────────────────────

  Widget _buildGoogleButton({required String label}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: const Icon(Icons.g_mobiledata, size: 28),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.5),
            width: 2,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: !_isLoading,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: const Color(0xFF14FFEC)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCF6679), width: 2),
        ),
        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
      ),
      validator: validator ??
          (value) {
            if (value == null || value.isEmpty) return 'Please enter $label';
            return null;
          },
    );
  }

  // ── Forgot Password Sheet ─────────────────────────────────────────────────

  void _showForgotPasswordSheet() {
    _log.i('🖥️ AuthScreen._showForgotPasswordSheet: Opening sheet');
    _log.d(
      '🖥️ AuthScreen._showForgotPasswordSheet: '
      'Pre-filling email → ${_loginEmailController.text.trim()}',
    );

    final forgotEmailController = TextEditingController(
      text: _loginEmailController.text.trim(),
    );
    final forgotFormKey = GlobalKey<FormState>();
    bool sheetLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
                child: Form(
                  key: forgotFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Header row
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                              ),
                            ),
                            child: const Icon(
                              Icons.lock_reset_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset Password',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                "We'll send a reset link to your email",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Email field
                      TextFormField(
                        controller: forgotEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        enabled: !sheetLoading,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            color: Color(0xFF14FFEC),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF14FFEC),
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFCF6679),
                              width: 1.5,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFCF6679),
                              width: 2,
                            ),
                          ),
                          errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter your email';
                          }
                          final reg = RegExp(
                              r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
                          if (!reg.hasMatch(v.trim())) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Info hint
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF14FFEC).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                const Color(0xFF14FFEC).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF14FFEC),
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Check your spam/junk folder if the email doesn't arrive within a few minutes.",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: sheetLoading
                                  ? null
                                  : () {
                                      _log.d(
                                        '🖥️ AuthScreen: Forgot password sheet — Cancel',
                                      );
                                      Navigator.pop(sheetContext);
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: sheetLoading
                                  ? null
                                  : () async {
                                      _log.i(
                                        '🖥️ AuthScreen: Forgot password — Send Reset Link pressed',
                                      );
                                      if (!forgotFormKey.currentState!
                                          .validate()) {
                                        _log.w(
                                          '⚠️ AuthScreen: Forgot password form FAILED',
                                        );
                                        return;
                                      }
                                      setSheetState(() => sheetLoading = true);

                                      final result =
                                          await AuthService.forgotPassword(
                                        email: forgotEmailController.text
                                            .trim(),
                                      );

                                      setSheetState(
                                          () => sheetLoading = false);
                                      _log.i(
                                        '🖥️ AuthScreen: Forgot password result → '
                                        'isSuccess: ${result.isSuccess} | "${result.message}"',
                                      );

                                      if (!sheetContext.mounted) return;
                                      Navigator.pop(sheetContext);

                                      if (!mounted) return;
                                      _showMessage(result);

                                      // If the email was sent successfully,
                                      // take the user straight to the reset
                                      // screen so they can enter their code
                                      // as soon as it arrives in their inbox.
                                      if (result.isSuccess) {
                                        _log.i(
                                          '🖥️ AuthScreen: Forgot password succeeded — '
                                          'navigating to ResetPasswordScreen',
                                        );
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ResetPasswordScreen(),
                                          ),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14FFEC),
                                foregroundColor: const Color(0xFF1E3A5F),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: sheetLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF1E3A5F),
                                      ),
                                    )
                                  : const Text(
                                      'Send Reset Link',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Validators ────────────────────────────────────────────────────────────

  String? _emailValidator(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Please enter a password';
    // Backend requires minimum 8 characters (per /api/auth/resetpassword docs)
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }
}