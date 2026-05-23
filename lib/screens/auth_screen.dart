import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/screens/reset_password_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_service.dart';

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

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id:    json['id']    as String? ?? '',
      email: json['email'] as String? ?? '',
      roles: (json['roles'] as List<dynamic>? ?? [])
          .map((r) => r.toString())
          .toList(),
    );
  }

  String get primaryRole => roles.isNotEmpty ? roles.first : 'user';

  @override
  String toString() =>
      'AppUser(id: $id, email: $email, roles: $roles)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH RESULT MODEL
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
// LOGIN RESULT MODEL
// ─────────────────────────────────────────────────────────────────────────────
class LoginResult {
  final bool     isSuccess;
  final String   message;
  final AppUser? user;

  LoginResult._({
    required this.isSuccess,
    required this.message,
    this.user,
  });

  factory LoginResult.success({required String message, AppUser? user}) =>
      LoginResult._(isSuccess: true, message: message, user: user);

  factory LoginResult.failure(String message) =>
      LoginResult._(isSuccess: false, message: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    _log.i('🔐 AuthService.register: ━━━ START ━━━');
    _log.d('🔐 AuthService.register: Email → $email | Password len → ${password.length} chars');

    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.register,
        body: {
          'email':    email.trim(),
          'password': password,
        },
      );
      _log.i('🔐 AuthService.register: ✓ Response received | status: ${response.statusCode}');
    } on Exception catch (e, st) {
      _log.e(
        '❌ AuthService.register: Network exception\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    final body = ApiClient.parseBody(response);
    _log.d('🔐 AuthService.register: Parsed body: $body');

    switch (response.statusCode) {
      case 200:
      case 201:
        _log.i('🔐 AuthService.register: Mirroring to Firebase (non-blocking)');
        FirebaseService.registerMirror(
          email:    email.trim(),
          password: password,
        ).catchError((e) {
          _log.w('⚠️ AuthService.register: Firebase mirror failed (non-blocking): $e');
        });

        _log.i('✅ AuthService.register: ━━━ REGISTRATION COMPLETE ━━━');
        return AuthResult.success(message: 'Account created! Please log in.');

      case 400:
        final msg = body['error'] ?? body['message'] ?? 'Missing required fields.';
        _log.w('⚠️ AuthService.register: 400 Bad Request — $msg');
        return AuthResult.failure('Please fill in all required fields correctly.');

      case 409:
        final msg = body['error'] ?? body['message'] ?? 'Email conflict.';
        _log.w('⚠️ AuthService.register: 409 Conflict — $msg');
        return AuthResult.failure('This email is already registered. Try logging in.');

      case 500:
        _log.e('❌ AuthService.register: 500 Internal Server Error | body: $body');
        return AuthResult.failure('Server error. Please try again later.');

      default:
        _log.e('❌ AuthService.register: Unhandled status ${response.statusCode} | body: $body');
        return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGIN
  // ══════════════════════════════════════════════════════════════════════════
  static Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    _log.i('🔑 AuthService.login: ━━━ START ━━━');
    _log.d('🔑 AuthService.login: Email → $email | Password len → ${password.length} chars');

    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.login,
        body: {
          'email':    email.trim(),
          'password': password,
        },
      );
    } on Exception catch (e, st) {
      _log.e(
        '❌ AuthService.login: Network exception\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return LoginResult.failure(ApiClient.friendlyNetworkError(e));
    }

    _log.d('🔑 AuthService.login: Status → ${response.statusCode}');
    _log.d('🔑 AuthService.login: Body   → ${response.body}');

    final body = ApiClient.parseBody(response);

    switch (response.statusCode) {
      case 200:
      case 201:
        final accessToken  = body['accessToken']  as String?;
        final refreshToken = body['refreshToken'] as String?;
        final userJson     = body['user']          as Map<String, dynamic>?;

        if (accessToken == null || refreshToken == null || userJson == null) {
          _log.e('❌ AuthService.login: Missing fields in 200 response | body: $body');
          return LoginResult.failure('Login failed. Please try again.');
        }

        final user = AppUser.fromJson(userJson);
        _log.i('✅ AuthService.login: API user parsed: $user');

        await ApiClient.saveSession(
          accessToken:  accessToken,
          refreshToken: refreshToken,
          userId:       user.id,
          email:        user.email,
          roles:        user.roles,
        );

        // ── Firebase mirror (non-blocking, independent log path) ────────────
        _log.i('🔑 AuthService.login [Firebase path]: Mirroring login to Firebase');
        FirebaseService.loginMirror(
          email:    email.trim(),
          password: password,
        ).catchError((e) {
          _log.w('⚠️ AuthService.login [Firebase path]: Mirror failed (non-blocking): $e');
        });

        _log.i('✅ AuthService.login: ━━━ LOGIN COMPLETE ━━━');
        return LoginResult.success(message: 'Welcome back!', user: user);

      case 400:
        _log.w('⚠️ AuthService.login: 400 — ${body['error'] ?? body['message']}');
        return LoginResult.failure('Please enter both email and password.');

      case 401:
        _log.w('⚠️ AuthService.login: 401 — ${body['error'] ?? body['message']}');
        return LoginResult.failure('Incorrect email or password. Please try again.');

      case 403:
        _log.w('⚠️ AuthService.login: 403 — ${body['error'] ?? body['message']}');
        return LoginResult.failure('Your account is inactive. Please contact support.');

      case 404:
        _log.w('⚠️ AuthService.login: 404 — ${body['error'] ?? body['message']}');
        return LoginResult.failure('No account found with this email address.');

      case 500:
        _log.e('❌ AuthService.login: 500 | body: $body');
        return LoginResult.failure('Server error. Please try again later.');

      default:
        _log.e('❌ AuthService.login: Unhandled ${response.statusCode} | body: $body');
        return LoginResult.failure('Something went wrong. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  //
  // Dual-path: API path and Firebase mirror path each have independent
  // log prefixes so they can be traced separately in the console.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> googleSignIn() async {
    _log.i('🌐 AuthService.googleSignIn [API path]: ━━━ START ━━━');

    try {
      // ── Step 1–4: Google native flow ──────────────────────────────────────
      final gsi = GoogleSignIn.instance;
      await gsi.initialize(serverClientId: AppConfig.googleWebClientId);

      if (!gsi.supportsAuthenticate()) {
        _log.e('❌ AuthService.googleSignIn [API path]: platform does not support authenticate()');
        return AuthResult.failure('Google Sign-In is not supported on this platform.');
      }

      final GoogleSignInAccount googleUser = await gsi.authenticate(
        scopeHint: ['email', 'profile'],
      );
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        _log.e('❌ AuthService.googleSignIn [API path]: idToken is null');
        return AuthResult.failure('Could not retrieve Google credentials. Please try again.');
      }
      _log.i('🌐 AuthService.googleSignIn [API path]: idToken obtained (${idToken.length} chars)');

      // ── Step 5: POST idToken to backend ──────────────────────────────────
      dynamic response;
      try {
        response = await ApiClient.post(
          ApiEndpoints.googleAuth,
          body: {'idToken': idToken},
        );
      } on Exception catch (e, st) {
        _log.e(
          '❌ AuthService.googleSignIn [API path]: HTTP exception',
          error: e, stackTrace: st,
        );
        return AuthResult.failure(ApiClient.friendlyNetworkError(e));
      }

      _log.d('🌐 AuthService.googleSignIn [API path]: Status → ${response.statusCode}');
      _log.d('🌐 AuthService.googleSignIn [API path]: Body   → ${response.body}');

      final body = ApiClient.parseBody(response);

      switch (response.statusCode) {
        case 200:
        case 201:
          final accessToken  = body['accessToken']  as String?;
          final refreshToken = body['refreshToken'] as String?;
          final userJson     = body['user']          as Map<String, dynamic>?;

          if (accessToken == null || refreshToken == null || userJson == null) {
            _log.e('❌ AuthService.googleSignIn [API path]: Missing fields in 200 response | body: $body');
            return AuthResult.failure('Google Sign-In failed. Please try again.');
          }

          final user = AppUser.fromJson(userJson);
          _log.i('✅ AuthService.googleSignIn [API path]: User parsed: $user');

          await ApiClient.saveSession(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            userId:       user.id,
            email:        user.email,
            roles:        user.roles,
          );
          _log.i('✅ AuthService.googleSignIn [API path]: Session saved');

          // ── Firebase mirror (independent log path) ───────────────────────
          _log.i('🌐 AuthService.googleSignIn [Firebase path]: Starting mirror with idToken');
          FirebaseService.googleSignInMirror(idToken: idToken).then((_) {
            _log.i('✅ AuthService.googleSignIn [Firebase path]: Mirror completed successfully');
          }).catchError((e) {
            _log.w('⚠️ AuthService.googleSignIn [Firebase path]: Mirror failed (non-blocking): $e');
          });

          _log.i('✅ AuthService.googleSignIn [API path]: ━━━ GOOGLE AUTH COMPLETE ━━━');
          return AuthResult.success(
            message: 'Signed in with Google successfully!',
            user:    user,
          );

        case 400:
          _log.w('⚠️ AuthService.googleSignIn [API path]: 400 | body: $body');
          return AuthResult.failure('Google Sign-In failed. Please try again.');

        case 401:
          _log.w('⚠️ AuthService.googleSignIn [API path]: 401 | body: $body');
          return AuthResult.failure('Google credentials are invalid. Please try again.');

        case 402:
        case 403:
          final errMsg = (body['error'] ?? body['message'] ?? '').toString().toLowerCase();
          _log.w('⚠️ AuthService.googleSignIn [API path]: ${response.statusCode} | $errMsg');
          if (errMsg.contains('inactive')) {
            return AuthResult.failure('Your account is inactive. Please contact support.');
          }
          return AuthResult.failure('Google email not verified. Please verify your Google account first.');

        default:
          _log.e('❌ AuthService.googleSignIn [API path]: Unhandled ${response.statusCode} | body: $body');
          return AuthResult.failure('Something went wrong. Please try again.');
      }
    } on GoogleSignInException catch (e, st) {
      _log.e(
        '❌ AuthService.googleSignIn [API path]: GoogleSignInException | code: ${e.code.name}',
        error: e, stackTrace: st,
      );
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return AuthResult.failure('Google Sign-In was cancelled.');
      }
      return AuthResult.failure('Google Sign-In failed. Please try again.');
    } catch (e, st) {
      _log.e('❌ AuthService.googleSignIn [API path]: Unexpected exception', error: e, stackTrace: st);
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> logout() async {
    _log.i('🚪 AuthService.logout: ━━━ START ━━━');

    final refreshToken = await ApiClient.getRefreshToken();

    if (refreshToken != null) {
      try {
        final response = await ApiClient.authPost(
          ApiEndpoints.logout,
          body: {'refreshTokenId': refreshToken},
        );
        _log.d('🚪 AuthService.logout: Server responded ${response.statusCode}');
      } on Exception catch (e) {
        _log.w('⚠️ AuthService.logout: Could not reach server ($e) — clearing local session anyway');
      }
    }

    await ApiClient.clearSession();

    FirebaseService.signOut().catchError((e) {
      _log.w('⚠️ AuthService.logout: Firebase signOut failed (non-blocking): $e');
    });

    _log.i('🚪 AuthService.logout: ━━━ LOGOUT COMPLETE ━━━');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORGOT PASSWORD
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> forgotPassword({required String email}) async {
    _log.i('🔒 AuthService.forgotPassword: ━━━ START ━━━');

    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.forgotPassword,
        body: {'email': email.trim()},
      );
    } on Exception catch (e, st) {
      _log.e('❌ AuthService.forgotPassword: HTTP FAILED', error: e, stackTrace: st);
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    _log.d('🔒 AuthService.forgotPassword: Status → ${response.statusCode}');

    if (response.statusCode == 200 || response.statusCode == 204) {
      _log.i('✅ AuthService.forgotPassword: ━━━ RESET EMAIL SENT ━━━');
      return AuthResult.success(
        message: 'If that email is registered, a reset link has been sent. '
                 'Check your inbox and spam folder.',
      );
    }

    switch (response.statusCode) {
      case 400:
        return AuthResult.failure('Please enter a valid email address.');
      case 404:
        return AuthResult.success(
          message: 'If that email is registered, a reset link has been sent. '
                   'Check your inbox and spam folder.',
        );
      case 429:
        return AuthResult.failure('Too many attempts. Please wait a few minutes and try again.');
      default:
        return AuthResult.failure('Something went wrong. Please try again later.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA — SEND EMAIL OTP
  //
  // Calls the API to send a one-time code to the authenticated user's email.
  // POST /api/auth/mfa/send-otp   Body: { email }   Auth: Bearer required
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> mfaSendOtp({required String email}) async {
    _log.i('🔐 AuthService.mfaSendOtp: ━━━ START ━━━ | email=$email');
    try {
      final response = await ApiClient.authPost(
        ApiEndpoints.mfaSendOtp,
        body: {'email': email.trim()},
      );
      _log.d('🔐 AuthService.mfaSendOtp: Status → ${response.statusCode}');
      final body = ApiClient.parseBody(response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _log.i('✅ AuthService.mfaSendOtp: OTP dispatched');
        return AuthResult.success(message: 'A verification code has been sent to $email.');
      }
      if (response.statusCode == 429) {
        return AuthResult.failure('Too many requests. Please wait a moment and try again.');
      }
      final msg = body['error'] ?? body['message'] ?? 'Could not send code.';
      _log.w('⚠️ AuthService.mfaSendOtp: ${response.statusCode} — $msg');
      return AuthResult.failure('Could not send verification code. Please try again.');
    } on Exception catch (e, st) {
      _log.e('❌ AuthService.mfaSendOtp: Exception', error: e, stackTrace: st);
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA — VERIFY EMAIL OTP
  //
  // Verifies the OTP entered by the user and enables MFA on their account.
  // POST /api/auth/mfa/verify-otp   Body: { email, otp }   Auth: Bearer required
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> mfaVerifyOtp({
    required String email,
    required String otp,
  }) async {
    _log.i('🔐 AuthService.mfaVerifyOtp: ━━━ START ━━━');
    try {
      final response = await ApiClient.authPost(
        ApiEndpoints.mfaVerifyOtp,
        body: {'email': email.trim(), 'otp': otp.trim()},
      );
      _log.d('🔐 AuthService.mfaVerifyOtp: Status → ${response.statusCode}');
      final body = ApiClient.parseBody(response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _log.i('✅ AuthService.mfaVerifyOtp: OTP verified — MFA enabled');
        return AuthResult.success(message: '🔒 MFA enabled! Your account is now more secure.');
      }
      if (response.statusCode == 400 || response.statusCode == 401) {
        _log.w('⚠️ AuthService.mfaVerifyOtp: Invalid/expired OTP');
        return AuthResult.failure('Incorrect or expired code. Please try again.');
      }
      final msg = body['error'] ?? body['message'] ?? 'Verification failed.';
      _log.w('⚠️ AuthService.mfaVerifyOtp: ${response.statusCode} — $msg');
      return AuthResult.failure('Verification failed. Please try again.');
    } on Exception catch (e, st) {
      _log.e('❌ AuthService.mfaVerifyOtp: Exception', error: e, stackTrace: st);
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
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
  // Tab controller: 0=Login, 1=Sign Up  (email-link tab removed)
  late TabController _tabController;

  final _loginFormKey  = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  // ── Login controllers ─────────────────────────────────────────────────────
  final _loginEmailController    = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // ── Sign-up controllers ───────────────────────────────────────────────────
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
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isLogin ? 0 : 1,
    );
    _tabController.addListener(() {
      _log.d('🖥️ AuthScreen: Tab changed → ${_tabController.index}');
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

    setState(() => _isLoading = true);

    final result = await AuthService.login(
      email:    _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _log.i('🖥️ AuthScreen._handleLogin: isSuccess=${result.isSuccess} | "${result.message}"');

    if (!result.isSuccess) {
      _showMessage(AuthResult.failure(result.message));
      return;
    }

    // ── Offer optional email OTP MFA enrollment ──────────────────────────────
    await _showMfaEnrollmentOffer();
    if (mounted) _navigateToLanding();
  }

  Future<void> _handleRegister() async {
    _log.d('🖥️ AuthScreen._handleRegister: Sign Up button pressed');
    if (!_signUpFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await AuthService.register(
      email:    _signUpEmailController.text.trim(),
      password: _signUpPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _showMessage(result);

    if (result.isSuccess) {
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

    if (result.isSuccess) {
      _log.i('🖥️ AuthScreen._handleGoogleSignIn: ✅ Google sign-in succeeded — navigating');
      _navigateToLanding();
    } else {
      _log.w('🖥️ AuthScreen._handleGoogleSignIn: ✗ ${result.message}');
      _showMessage(result);
    }
  }

  // ── Navigation helper ─────────────────────────────────────────────────────

  void _navigateToLanding() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    }
  }

  // ── MFA Enrollment Offer ──────────────────────────────────────────────────
  //
  // Shown once after login. If the user accepts, opens the email OTP
  // enrollment sheet.  Always awaited before navigating so the caller can
  // safely navigate away afterwards.

  Future<void> _showMfaEnrollmentOffer() async {
    if (!mounted) return;

    final wantsToEnroll = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A5F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security_outlined, color: Color(0xFF14FFEC)),
            SizedBox(width: 10),
            Text(
              'Secure Your Account',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Enable two-factor authentication (email OTP) for extra security. '
          'You can set this up now or later in your account settings.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Maybe Later', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14FFEC),
              foregroundColor: const Color(0xFF1E3A5F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Enable MFA', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (wantsToEnroll == true && mounted) {
      await _showMfaEnrollmentSheet();
    }
  }

  // ── Email OTP MFA Enrollment Sheet ───────────────────────────────────────
  //
  // Flutter-native, API-backed two-phase flow:
  //   Phase 1 — sends the OTP to the user's email via the API.
  //   Phase 2 — user enters the code; the API verifies and enables MFA.

  Future<void> _showMfaEnrollmentSheet() async {
    _log.i('🖥️ AuthScreen._showMfaEnrollmentSheet: Opening');

    final email = _loginEmailController.text.trim();
    final otpController  = TextEditingController();
    final otpFormKey     = GlobalKey<FormState>();
    bool  sheetLoading   = false;
    bool  otpSent        = false; // false = phase 1, true = phase 2

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 44, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    const Icon(Icons.email_outlined, color: Color(0xFF14FFEC), size: 28),
                    const SizedBox(width: 12),
                    Text(
                      otpSent ? 'Enter Verification Code' : 'Enable Email MFA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Text(
                  otpSent
                      ? 'Enter the 6-digit code sent to $email'
                      : 'We will send a one-time code to $email to confirm.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Phase 1: Send OTP button ─────────────────────────────────
                if (!otpSent) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: sheetLoading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1E3A5F),
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(sheetLoading ? 'Sending…' : 'Send Code to Email'),
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              setSheetState(() => sheetLoading = true);
                              _log.i('🖥️ MfaEnrollmentSheet: Sending OTP to $email');

                              final result = await AuthService.mfaSendOtp(email: email);
                              setSheetState(() => sheetLoading = false);

                              if (result.isSuccess) {
                                _log.i('🖥️ MfaEnrollmentSheet: OTP sent — advancing to phase 2');
                                setSheetState(() => otpSent = true);
                              } else {
                                _log.w('🖥️ MfaEnrollmentSheet: OTP send failed — ${result.message}');
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                if (mounted) _showMessage(AuthResult.failure(result.message));
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                // ── Phase 2: OTP input + verify ──────────────────────────────
                if (otpSent) ...[
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !sheetLoading,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 10,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          letterSpacing: 8,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 4) return 'Enter the code from your email';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              if (!otpFormKey.currentState!.validate()) return;
                              setSheetState(() => sheetLoading = true);
                              _log.i('🖥️ MfaEnrollmentSheet: Verifying OTP');

                              final result = await AuthService.mfaVerifyOtp(
                                email: email,
                                otp:   otpController.text.trim(),
                              );

                              if (!sheetCtx.mounted) return;
                              setSheetState(() => sheetLoading = false);
                              Navigator.pop(sheetCtx);
                              if (!mounted) return;

                              _log.i('🖥️ MfaEnrollmentSheet: Verify result — isSuccess=${result.isSuccess}');
                              _showMessage(result.isSuccess
                                  ? AuthResult.success(message: result.message)
                                  : AuthResult.failure(result.message));
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: sheetLoading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1E3A5F),
                              ),
                            )
                          : const Text(
                              'Confirm & Enable MFA',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Resend link
                  Center(
                    child: TextButton.icon(
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              setSheetState(() => sheetLoading = true);
                              _log.i('🖥️ MfaEnrollmentSheet: Re-sending OTP');
                              await AuthService.mfaSendOtp(email: email);
                              setSheetState(() => sheetLoading = false);
                              if (mounted) {
                                _showMessage(AuthResult.success(
                                  message: 'A new code has been sent to $email.',
                                ));
                              }
                            },
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF14FFEC), size: 16),
                      label: const Text(
                        'Resend code',
                        style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
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

  // ── Message Display ───────────────────────────────────────────────────────

  void _showMessage(AuthResult result) {
    _log.d('🖥️ AuthScreen._showMessage: "${result.message}"');
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: result.isSuccess ? const Color(0xFF0D7377) : const Color(0xFFB00020),
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
                child: CircularProgressIndicator(color: Color(0xFF14FFEC), strokeWidth: 3),
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
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF14FFEC).withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 80,
                                    height: 80,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.travel_explore_rounded,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Brand name ───────────────────────────────────
                            Text(
                              'PALMNAZI RC',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontSize: 30,
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

                            // Tab bar — 2 tabs (Login / Sign Up)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                indicatorSize: TabBarIndicatorSize.tab,
                                dividerColor: Colors.transparent,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white70,
                                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                tabs: const [
                                  Tab(text: 'Login'),
                                  Tab(text: 'Sign Up'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Tab views
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
            validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password' : null,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureLoginPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Colors.white70,
              ),
              onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
          ),
          const SizedBox(height: 24),

          _buildPrimaryButton(label: 'Login', onPressed: _handleLogin),
          const SizedBox(height: 12),

          TextButton(
            onPressed: _isLoading ? null : _showForgotPasswordSheet,
            child: Text(
              'Forgot Password?',
              style: TextStyle(color: const Color(0xFF14FFEC).withValues(alpha: 0.9)),
            ),
          ),

          TextButton(
            onPressed: _isLoading
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
                    ),
            child: Text(
              'Have a reset code? Set new password →',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
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
                  _obscureSignUpPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _obscureSignUpPassword = !_obscureSignUpPassword),
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
                if (v != _signUpPasswordController.text) return 'Passwords do not match';
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            const SizedBox(height: 24),

            _buildPrimaryButton(label: 'Create Account', onPressed: _handleRegister),
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

  Widget _buildPrimaryButton({
    required String   label,
    required VoidCallback onPressed,
    IconData?         icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF14FFEC),
          foregroundColor: const Color(0xFF1E3A5F),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleButton({required String label}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: const Icon(Icons.g_mobiledata, size: 28),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          child: Text('OR', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String               label,
    required IconData             icon,
    bool                          obscureText   = false,
    Widget?                       suffixIcon,
    TextInputType?                keyboardType,
    String? Function(String?)?    validator,
  }) {
    return TextFormField(
      controller:   controller,
      obscureText:  obscureText,
      keyboardType: keyboardType,
      enabled:      !_isLoading,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText:  label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: const Color(0xFF14FFEC)),
        suffixIcon: suffixIcon,
        filled:     true,
        fillColor:  Colors.white.withValues(alpha: 0.08),
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
    _log.i('🖥️ AuthScreen._showForgotPasswordSheet: Opening');

    final forgotEmailController = TextEditingController(
      text: _loginEmailController.text.trim(),
    );
    final forgotFormKey = GlobalKey<FormState>();
    bool sheetLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
                child: Form(
                  key: forgotFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44, height: 4,
                          decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset Password',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                "We'll send a reset link to your email",
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      TextFormField(
                        controller: forgotEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        enabled: !sheetLoading,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                          prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF14FFEC)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter your email';
                          final reg = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
                          if (!reg.hasMatch(v.trim())) return 'Please enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF14FFEC), size: 16),
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

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                      if (!forgotFormKey.currentState!.validate()) return;
                                      setSheetState(() => sheetLoading = true);

                                      final result = await AuthService.forgotPassword(
                                        email: forgotEmailController.text.trim(),
                                      );

                                      setSheetState(() => sheetLoading = false);
                                      if (!sheetCtx.mounted) return;
                                      Navigator.pop(sheetCtx);
                                      if (!mounted) return;
                                      _showMessage(result);

                                      if (result.isSuccess) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14FFEC),
                                foregroundColor: const Color(0xFF1E3A5F),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: sheetLoading
                                  ? const SizedBox(
                                      height: 20, width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)),
                                    )
                                  : const Text(
                                      'Send Reset Link',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }
}