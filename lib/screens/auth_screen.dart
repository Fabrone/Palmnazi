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
// All methods are static. HTTP calls go through ApiClient so that
// base-URL changes only ever require editing api_client.dart.
//
// Firebase mirrors are called after every successful API operation so that
// Firebase Auth + Firestore stay in sync.  Firebase failures are non-blocking.
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
  // Firebase mirror: creates a Firebase Auth account + Firestore document.
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
        // ── Firebase mirror (non-blocking) ─────────────────────────────────
        _log.i('🔐 AuthService.register: Step 4 — Mirroring to Firebase');
        FirebaseService.registerMirror(
          email:    email.trim(),
          password: password,
        ).catchError((e) {
          _log.w('⚠️ AuthService.register: Firebase mirror failed (non-blocking): $e');
        });

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
  //
  // Firebase mirror: signs into Firebase Auth; returns MfaResult which the
  // caller (auth screen) uses to decide whether to show the MFA OTP dialog.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    _log.i('🔑 AuthService.login: ━━━ START ━━━');
    _log.d('🔑 AuthService.login: Email → $email | Password len → ${password.length} chars');

    // ── Step 1: API call ───────────────────────────────────────────────────
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

    _log.d('🔑 AuthService.login:   Status : ${response.statusCode}');
    _log.d('🔑 AuthService.login:   Body   : ${response.body}');

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
        _log.i('✅ AuthService.login: Parsed user: $user');

        // Persist API session
        await ApiClient.saveSession(
          accessToken:  accessToken,
          refreshToken: refreshToken,
          userId:       user.id,
          email:        user.email,
          roles:        user.roles,
        );

        // ── Firebase mirror ─────────────────────────────────────────────────
        _log.i('🔑 AuthService.login: Mirroring to Firebase');
        final mfaResult = await FirebaseService.loginMirror(
          email:    email.trim(),
          password: password,
        );

        _log.i('✅ AuthService.login: ━━━ LOGIN COMPLETE ━━━');
        return LoginResult.success(
          message:   'Welcome back!',
          user:      user,
          mfaResult: mfaResult,
        );

      case 400:
        _log.w('⚠️ AuthService.login: 400 — ${body['error'] ?? body['message']} | body: $body');
        return LoginResult.failure('Please enter both email and password.');

      case 401:
        _log.w('⚠️ AuthService.login: 401 — ${body['error'] ?? body['message']} | body: $body');
        return LoginResult.failure('Incorrect email or password. Please try again.');

      case 403:
        _log.w('⚠️ AuthService.login: 403 — ${body['error'] ?? body['message']} | body: $body');
        return LoginResult.failure('Your account is inactive. Please contact support.');

      case 404:
        _log.w('⚠️ AuthService.login: 404 — ${body['error'] ?? body['message']} | body: $body');
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
  // Firebase mirror: signs into Firebase with the same Google idToken so we
  // don't trigger a second account picker.
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> googleSignIn() async {
    _log.i('🌐 AuthService.googleSignIn: ━━━ START ━━━');

    try {
      // ── Step 1–4: Google native flow ──────────────────────────────────────
      final gsi = GoogleSignIn.instance;
      await gsi.initialize(serverClientId: AppConfig.googleWebClientId);

      if (!gsi.supportsAuthenticate()) {
        return AuthResult.failure('Google Sign-In is not supported on this platform.');
      }

      final GoogleSignInAccount googleUser = await gsi.authenticate(
        scopeHint: ['email', 'profile'],
      );
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        _log.e('❌ AuthService.googleSignIn: idToken is null');
        return AuthResult.failure('Could not retrieve Google credentials. Please try again.');
      }
      _log.i('🌐 AuthService.googleSignIn: idToken obtained (${idToken.length} chars)');

      // ── Step 5: POST idToken to backend ──────────────────────────────────
      dynamic response;
      try {
        response = await ApiClient.post(
          ApiEndpoints.googleAuth,
          body: {'idToken': idToken},
        );
      } on Exception catch (e, st) {
        _log.e(
          '❌ AuthService.googleSignIn: HTTP exception',
          error: e, stackTrace: st,
        );
        return AuthResult.failure(ApiClient.friendlyNetworkError(e));
      }

      _log.d('🌐 AuthService.googleSignIn:   Status : ${response.statusCode}');
      _log.d('🌐 AuthService.googleSignIn:   Body   : ${response.body}');

      final body = ApiClient.parseBody(response);

      switch (response.statusCode) {
        case 200:
        case 201:
          final accessToken  = body['accessToken']  as String?;
          final refreshToken = body['refreshToken'] as String?;
          final userJson     = body['user']          as Map<String, dynamic>?;

          if (accessToken == null || refreshToken == null || userJson == null) {
            _log.e('❌ AuthService.googleSignIn: Missing fields in 200 response | body: $body');
            return AuthResult.failure('Google Sign-In failed. Please try again.');
          }

          final user = AppUser.fromJson(userJson);

          await ApiClient.saveSession(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            userId:       user.id,
            email:        user.email,
            roles:        user.roles,
          );

          // ── Firebase mirror (non-blocking) ──────────────────────────────
          FirebaseService.googleSignInMirror(idToken: idToken).catchError((e) {
            _log.w('⚠️ AuthService.googleSignIn: Firebase mirror failed (non-blocking): $e');
          });

          _log.i('✅ AuthService.googleSignIn: ━━━ GOOGLE AUTH COMPLETE ━━━');
          return AuthResult.success(
            message: 'Signed in with Google successfully!',
            user:    user,
          );

        case 400:
          return AuthResult.failure('Google Sign-In failed. Please try again.');

        case 401:
          return AuthResult.failure('Google credentials are invalid. Please try again.');

        case 402:
        case 403:
          final errMsg = (body['error'] ?? body['message'] ?? '').toString().toLowerCase();
          if (errMsg.contains('inactive')) {
            return AuthResult.failure('Your account is inactive. Please contact support.');
          }
          return AuthResult.failure('Google email not verified. Please verify your Google account first.');

        default:
          _log.e('❌ AuthService.googleSignIn: Unhandled ${response.statusCode} | body: $body');
          return AuthResult.failure('Something went wrong. Please try again.');
      }
    } on GoogleSignInException catch (e, st) {
      _log.e(
        '❌ AuthService.googleSignIn: GoogleSignInException | code: ${e.code.name}',
        error: e, stackTrace: st,
      );
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return AuthResult.failure('Google Sign-In was cancelled.');
      }
      return AuthResult.failure('Google Sign-In failed. Please try again.');
    } catch (e, st) {
      _log.e('❌ AuthService.googleSignIn: Unexpected exception', error: e, stackTrace: st);
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

    // ── Firebase sign-out (non-blocking) ────────────────────────────────────
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

      case 500:
        return AuthResult.failure('Something went wrong. Please try again later.');

      default:
        return AuthResult.failure('Something went wrong. Please try again later.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN RESULT MODEL
//
// Extends AuthResult with the Firebase MfaResult so the UI can decide
// whether to show the MFA OTP dialog immediately after login.
// ─────────────────────────────────────────────────────────────────────────────
class LoginResult {
  final bool      isSuccess;
  final String    message;
  final AppUser?  user;
  final MfaResult? mfaResult;

  LoginResult._({
    required this.isSuccess,
    required this.message,
    this.user,
    this.mfaResult,
  });

  factory LoginResult.success({
    required String    message,
    AppUser?           user,
    required MfaResult mfaResult,
  }) => LoginResult._(isSuccess: true,  message: message, user: user, mfaResult: mfaResult);

  factory LoginResult.failure(String message) =>
      LoginResult._(isSuccess: false, message: message);
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
  // Tab controller: 0=Login, 1=Sign Up, 2=Email Link
  late TabController _tabController;

  final _loginFormKey  = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final _emailLinkFormKey = GlobalKey<FormState>();

  // ── Login controllers ─────────────────────────────────────────────────────
  final _loginEmailController    = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // ── Sign-up controllers ───────────────────────────────────────────────────
  final _signUpEmailController           = TextEditingController();
  final _signUpPasswordController        = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();

  // ── Email Link controller ─────────────────────────────────────────────────
  final _emailLinkController = TextEditingController();

  bool _obscureLoginPassword   = true;
  bool _obscureSignUpPassword  = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading              = false;

  // Email Link state
  bool _emailLinkSent = false;

  @override
  void initState() {
    super.initState();
    _log.i('🖥️ AuthScreen: ━━━ SCREEN INITIALIZED ━━━');
    _tabController = TabController(
      length: 3,
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
    _emailLinkController.dispose();
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

    // ── Check if Firebase MFA is required ────────────────────────────────────
    final mfa = result.mfaResult;
    if (mfa != null && mfa.requiresMfa && mfa.resolver != null) {
      _log.i('🖥️ AuthScreen._handleLogin: MFA required — showing OTP dialog');
      await _showMfaVerificationDialog(resolver: mfa.resolver!);
      return; // Navigation handled inside the dialog
    }

    // ── Offer optional MFA enrollment ────────────────────────────────────────
    final fbUser = FirebaseService.currentUser;
    if (fbUser != null && !(await FirebaseService.isMfaEnrolled())) {
      _log.i('🖥️ AuthScreen._handleLogin: User has no MFA — showing enrollment offer');
      _navigateToLanding();
      // Show enrollment offer after navigation so the user lands first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMfaEnrollmentOffer();
      });
      return;
    }

    _navigateToLanding();
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
      _log.i('🖥️ AuthScreen._handleGoogleSignIn: ✅ Google sign-in succeeded');
      _navigateToLanding();
    } else {
      _showMessage(result);
    }
  }

  Future<void> _handleEmailLinkSend() async {
    if (!_emailLinkFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailLinkController.text.trim();
    _log.i('🖥️ AuthScreen._handleEmailLinkSend: Sending link to $email');

    final result = await FirebaseService.sendSignInLink(email: email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSent) {
      setState(() => _emailLinkSent = true);
      _showMessage(AuthResult.success(
        message: 'Sign-in link sent! Check your inbox and tap the link.',
      ));
    } else {
      _showMessage(AuthResult.failure(
        result.errorMessage ?? 'Could not send link. Please try again.',
      ));
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

  // ── MFA Verification Dialog (shown when Firebase requires OTP at login) ────

  Future<void> _showMfaVerificationDialog({
    required dynamic resolver, // MultiFactorResolver
  }) async {
    _log.i('🖥️ AuthScreen._showMfaVerificationDialog: Opening');

    // Step 1: start MFA verification → sends SMS
    final session = BuildableMfaSession();
    setState(() => _isLoading = true);

    final startResult = await FirebaseService.startMfaVerification(
      resolver: resolver,
      session:  session,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!startResult.isSuccess) {
      _showMessage(AuthResult.failure(startResult.errorMessage ?? 'Could not send SMS.'));
      return;
    }

    // Step 2: collect OTP from user
    final otpController  = TextEditingController();
    final otpFormKey     = GlobalKey<FormState>();
    bool  dialogLoading  = false;
    String? verificationId = startResult.verificationId;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E3A5F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFF14FFEC)),
              const SizedBox(width: 10),
              const Text(
                'Two-Factor Auth',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Form(
            key: otpFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A verification code was sent to ${startResult.maskedPhoneNumber}.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !dialogLoading,
                  style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 8),
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
                  ),
                  validator: (v) {
                    if (v == null || v.length < 4) return 'Enter the code from your SMS';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogLoading ? null : () => Navigator.pop(dialogCtx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            ),
            ElevatedButton(
              onPressed: dialogLoading
                  ? null
                  : () async {
                      if (!otpFormKey.currentState!.validate()) return;
                      setDialogState(() => dialogLoading = true);

                      final verifyResult = await FirebaseService.completeMfaVerification(
                        resolver:       resolver,
                        verificationId: verificationId!,
                        otpCode:        otpController.text.trim(),
                      );

                      if (!ctx.mounted) return;
                      setDialogState(() => dialogLoading = false);

                      if (verifyResult.isSuccess) {
                        Navigator.pop(dialogCtx);
                        if (mounted) _navigateToLanding();
                      } else {
                        Navigator.pop(dialogCtx);
                        if (mounted) {
                          _showMessage(AuthResult.failure(
                            verifyResult.errorMessage ?? 'Verification failed.',
                          ));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14FFEC),
                foregroundColor: const Color(0xFF1E3A5F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: dialogLoading
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)),
                    )
                  : const Text('Verify', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── MFA Enrollment Offer (shown once after login if not enrolled) ──────────

  void _showMfaEnrollmentOffer() {
    showDialog(
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
          'Enable two-factor authentication (SMS) for extra security. '
          'You can set this up now or later in your account settings.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Maybe Later', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showMfaEnrollmentSheet();
            },
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
  }

  // ── MFA Enrollment Bottom Sheet ───────────────────────────────────────────

  void _showMfaEnrollmentSheet() {
    _log.i('🖥️ AuthScreen._showMfaEnrollmentSheet: Opening');
    final phoneController  = TextEditingController();
    final otpController    = TextEditingController();
    final phoneFormKey     = GlobalKey<FormState>();
    final otpFormKey       = GlobalKey<FormState>();
    bool  sheetLoading     = false;
    String? verificationId;

    showModalBottomSheet(
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
                    decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 24),

                const Row(
                  children: [
                    Icon(Icons.phone_android_outlined, color: Color(0xFF14FFEC), size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Enable SMS Verification',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your phone number to receive a one-time code.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Phase 1: phone input
                if (verificationId == null) ...[
                  Form(
                    key: phoneFormKey,
                    child: _buildTextField(
                      controller: phoneController,
                      label: 'Phone Number (e.g. +254712345678)',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your phone number';
                        if (!v.trim().startsWith('+')) return 'Include country code e.g. +254…';
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
                              if (!phoneFormKey.currentState!.validate()) return;
                              setSheetState(() => sheetLoading = true);

                              final session = BuildableMfaSession();
                              final result = await FirebaseService.startMfaEnrollment(
                                phoneNumber: phoneController.text.trim(),
                                session:     session,
                              );

                              setSheetState(() => sheetLoading = false);

                              if (result.isSuccess && result.verificationId != null) {
                                setSheetState(() => verificationId = result.verificationId);
                              } else {
                                if (!sheetCtx.mounted) return;
                                Navigator.pop(sheetCtx);
                                _showMessage(AuthResult.failure(
                                  result.errorMessage ?? 'Could not send SMS.',
                                ));
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
                          : const Text('Send Code', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],

                // Phase 2: OTP input
                if (verificationId != null) ...[
                  Text(
                    'Enter the 6-digit code sent to ${phoneController.text.trim()}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 10),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 8),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 4) return 'Enter the verification code';
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

                              final result = await FirebaseService.completeMfaEnrollment(
                                verificationId: verificationId!,
                                otpCode:        otpController.text.trim(),
                              );

                              if (!sheetCtx.mounted) return;
                              setSheetState(() => sheetLoading = false);
                              Navigator.pop(sheetCtx);

                              _showMessage(result.isSuccess
                                  ? AuthResult.success(message: '🔒 MFA enabled! Your account is now more secure.')
                                  : AuthResult.failure(result.errorMessage ?? 'MFA setup failed.'));
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
                          : const Text('Confirm & Enable MFA', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                    child: Text('Skip for now', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
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
                                    color: const Color(0xFF14FFEC).withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.landscape, size: 40, color: Colors.white),
                            ),
                            const SizedBox(height: 24),

                            // ── Brand name: PALMNAZI RC ──────────────────────
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

                            // Tab bar — 3 tabs
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
                                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                tabs: const [
                                  Tab(text: 'Login'),
                                  Tab(text: 'Sign Up'),
                                  Tab(text: 'Link'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Tab views
                            SizedBox(
                              height: 480,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildLoginForm(),
                                  _buildSignUpForm(),
                                  _buildEmailLinkForm(),
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

          // Login button
          _buildPrimaryButton(label: 'Login', onPressed: _handleLogin),
          const SizedBox(height: 12),

          // Forgot password
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

  // ── Email Link (Passwordless) Form ────────────────────────────────────────

  Widget _buildEmailLinkForm() {
    if (_emailLinkSent) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
            ),
            child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'Check Your Inbox',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'A sign-in link has been sent to\n${_emailLinkController.text.trim()}\n\n'
            'Tap the link in your email to sign in instantly — no password needed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => setState(() => _emailLinkSent = false),
            icon: const Icon(Icons.refresh, color: Color(0xFF14FFEC), size: 18),
            label: const Text('Send to a different email', style: TextStyle(color: Color(0xFF14FFEC))),
          ),
        ],
      );
    }

    return Form(
      key: _emailLinkFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.link_outlined, color: Color(0xFF14FFEC), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No password needed. Enter your email and we\'ll send a magic sign-in link.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildTextField(
            controller: _emailLinkController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 24),

          _buildPrimaryButton(
            label: 'Send Sign-In Link',
            onPressed: _handleEmailLinkSend,
            icon: Icons.send_outlined,
          ),
          const SizedBox(height: 20),
          _buildDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(label: 'Continue with Google'),
        ],
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
                      // Handle bar
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