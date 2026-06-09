import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html show window;// web-only: used for last-section storage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/screens/reset_password_screen.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_email_link_service.dart';
import 'package:palmnazi/services/firebase_mfa_service.dart';
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
  /// Firebase UID — primary key for ALL system operations and the document ID
  /// in the Firestore `Users` collection.
  final String firebaseUid;

  /// Backend API's own user ID (_id from MongoDB). Stored as `apiId` on the
  /// Firestore document so both systems can be cross-referenced.
  final String apiId;

  final String email;

  /// Single role string — Firestore is the source of truth.
  /// Possible values: 'Tourist' (default) | 'Admin' | 'MainAdmin'
  final String role;

  final bool   mfaEnabled;
  final String provider;   // 'email' | 'google'

  AppUser({
    required this.firebaseUid,
    required this.apiId,
    required this.email,
    required this.role,
    this.mfaEnabled = false,
    this.provider   = 'email',
  });

  /// Constructs from a Firebase UID plus the backend API response JSON.
  /// [roleOverride] should be supplied from Firestore whenever available —
  /// Firestore is the single source of truth for role.
  factory AppUser.fromApiJson({
    required String              firebaseUid,
    required Map<String, dynamic> json,
    String?                      roleOverride,
  }) {
    return AppUser(
      firebaseUid: firebaseUid,
      apiId:       json['_id']      as String?
                ?? json['id']       as String? ?? '',
      email:       json['email']    as String? ?? '',
      role:        roleOverride
                ?? json['role']     as String?
                ?? 'Tourist',
      mfaEnabled:  json['mfaEnabled'] as bool?   ?? false,
      provider:    json['provider']   as String? ?? 'email',
    );
  }

  /// Exposes role as a list — used by [ApiClient.saveSession] which expects
  /// [List<String>] for backward compatibility with the roles storage key.
  List<String> get roles => [role];

  String get primaryRole => role.isNotEmpty ? role : 'Tourist';

  bool get isTourist   => role == 'Tourist';
  bool get isAdmin     => role == 'Admin' || role == 'MainAdmin';
  bool get isMainAdmin => role == 'MainAdmin';

  @override
  String toString() =>
      'AppUser(uid: $firebaseUid, apiId: $apiId, email: $email, role: $role)';
}

// ─────────────────────────────────────────────────────────────────────────────
// USER FIRESTORE STORE
// Owns all reads and writes to the `Users` collection.
// Document ID = Firebase UID so every query is an O(1) point-read.
// ─────────────────────────────────────────────────────────────────────────────
class _UserStore {
  _UserStore._();

  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('Users');

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _col.doc(uid);

  // ── Called once on email/password registration ────────────────────────────
  // Sets role to 'Tourist' — always. Admin promotion is a separate admin-side
  // operation that updates the role field directly in Firestore.
  static Future<void> createUser({
    required String firebaseUid,
    required String email,
    required String apiId,
    required String provider,
  }) =>
      _doc(firebaseUid).set({
        'email':       email,
        'provider':    provider,
        'role':        'Tourist',                  // ← default, always
        'apiId':       apiId,
        'mfaEnabled':  false,
        'createdAt':   FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });

  // ── Called on Google Sign-In ──────────────────────────────────────────────
  // If the document doesn't exist yet → creates it (new Google user).
  // If it already exists → only refreshes lastLoginAt and syncs apiId.
  // Role is NEVER overwritten here — admin controls it.
  static Future<void> upsertGoogleUser({
    required String firebaseUid,
    required String email,
    required String apiId,
  }) async {
    final ref  = _doc(firebaseUid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'email':       email,
        'provider':    'google',
        'role':        'Tourist',                  // ← default for new Google users
        'apiId':       apiId,
        'mfaEnabled':  false,
        'createdAt':   FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update({
        'apiId':       apiId,                      // keep in sync with backend
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Called on every login ─────────────────────────────────────────────────
  // Stamps lastLoginAt and returns the current role from Firestore.
  static Future<String> touchAndGetRole(String firebaseUid) async {
    final ref = _doc(firebaseUid);
    await ref.update({'lastLoginAt': FieldValue.serverTimestamp()});
    final snap = await ref.get();
    return snap.data()?['role'] as String? ?? 'Tourist';
  }

  // ── Role-only read (used after Google upsert) ─────────────────────────────
  static Future<String> getRole(String firebaseUid) async {
    final snap = await _doc(firebaseUid).get();
    return snap.data()?['role'] as String? ?? 'Tourist';
  }
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
      AuthResult._(isSuccess: true, message: message, user: user);

  factory AuthResult.failure(String message) =>
      AuthResult._(isSuccess: false, message: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN RESULT MODEL
// ─────────────────────────────────────────────────────────────────────────────
class LoginResult {
  final bool                    isSuccess;
  final String                  message;
  final AppUser?                user;
  final fb.MultiFactorResolver? mfaResolver;

  LoginResult._({
    required this.isSuccess,
    required this.message,
    this.user,
    this.mfaResolver,
  });

  factory LoginResult.success({
    required String message,
    AppUser? user,
    fb.MultiFactorResolver? mfaResolver,
  }) =>
      LoginResult._(
        isSuccess:   true,
        message:     message,
        user:        user,
        mfaResolver: mfaResolver,
      );

  factory LoginResult.failure(String message) =>
      LoginResult._(isSuccess: false, message: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH SERVICE — Dual Auth (Firebase + API) — FINAL
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {
  static String? _lastRefreshTokenId;

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    _log.i('🔐 AuthService.register: ━━━ START ━━━');

    // ── Step 1: Firebase — create auth user + send verification email ────────
    fb.User? firebaseUser;
    try {
      final credential = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      firebaseUser = credential.user;
      if (firebaseUser != null) {
        await firebaseUser.sendEmailVerification();
        _log.i('✅ Firebase user created (uid: ${firebaseUser.uid})');
      }
    } on fb.FirebaseAuthException catch (e) {
      _log.e('❌ Firebase register failed', error: e);
      return AuthResult.failure(_mapFirebaseError(e));
    } catch (e) {
      _log.e('❌ Unexpected Firebase register error', error: e);
      return AuthResult.failure('Registration failed. Please try again.');
    }

    if (firebaseUser == null) {
      return AuthResult.failure('Registration failed. Please try again.');
    }

    // ── Step 2: API — create backend user record ─────────────────────────────
    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.register,
        body: {
          'email':    email.trim(),
          'password': password,
          'provider': 'email',
        },
      );
    } on Exception catch (e, st) {
      _log.e('❌ AuthService.register: API network error', error: e, stackTrace: st);
      // Roll back Firebase user so auth state stays consistent
      await firebaseUser.delete().catchError((_) {});
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    // Roll back Firebase user if the API rejected the registration
    if (response.statusCode != 200 && response.statusCode != 201) {
      await firebaseUser.delete().catchError((_) {});
      switch (response.statusCode) {
        case 400: return AuthResult.failure('Please fill in all required fields correctly.');
        case 409: return AuthResult.failure('This email is already registered. Try logging in.');
        case 500: return AuthResult.failure('Server error. Please try again later.');
        default:  return AuthResult.failure('Something went wrong. Please try again.');
      }
    }

    // ── Step 3: Extract apiId from API response ──────────────────────────────
    final body     = ApiClient.parseBody(response);
    final userJson = body['user'] as Map<String, dynamic>? ?? {};
    final apiId    = userJson['_id'] as String?
                  ?? userJson['id']  as String? ?? '';

    // ── Step 4: Firestore — create Users/{firebaseUid} document ─────────────
    // role is always 'Tourist' on registration.
    // Admin promotion is handled separately on the admin side.
    try {
      await _UserStore.createUser(
        firebaseUid: firebaseUser.uid,
        email:       email.trim(),
        apiId:       apiId,
        provider:    'email',
      );
      _log.i('✅ Firestore Users/${firebaseUser.uid} created — role: Tourist | apiId: $apiId');
    } catch (e) {
      _log.e('❌ Firestore write failed after registration', error: e);
      // Non-fatal — user can still log in; doc can be rebuilt on first login
    }

    // ── Step 5: Persist session if the API returned tokens ───────────────────
    final accessToken  = body['accessToken']  as String?;
    final refreshToken = body['refreshToken'] as String?;
    if (accessToken != null && refreshToken != null) {
      await ApiClient.saveSession(
        firebaseUid:  firebaseUser.uid,
        accessToken:  accessToken,
        refreshToken: refreshToken,
        apiId:        apiId,
        email:        email.trim(),
        roles:        ['Tourist'], userId: '',
      );
      _log.i('✅ Session persisted for uid: ${firebaseUser.uid}');
    }

    return AuthResult.success(
      message: 'Account created! A verification link has been sent to '
               '$email — tap it to verify your address, then log in.',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGIN — Dual Auth
  // ══════════════════════════════════════════════════════════════════════════
  static Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    _log.i('🔑 AuthService.login: ━━━ START ━━━');

    // ── Step 1: Firebase sign-in — establishes Firebase session + gets UID ───
    fb.UserCredential? firebaseCred;
    try {
      firebaseCred = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _log.i('✅ Firebase sign-in OK (uid: ${firebaseCred.user?.uid})');
    } on fb.FirebaseAuthException catch (e) {
      _log.e('❌ Firebase login failed', error: e);
      return LoginResult.failure(_mapFirebaseError(e));
    } catch (e) {
      _log.e('❌ Unexpected Firebase login error', error: e);
      return LoginResult.failure('Sign-in failed. Please try again.');
    }

    final firebaseUid = firebaseCred.user?.uid ?? '';

    // ── Step 2: API login — get JWT tokens ───────────────────────────────────
    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.login,
        body: {'email': email.trim(), 'password': password},
      );
    } on Exception catch (e, st) {
      _log.e('❌ AuthService.login: API network error', error: e, stackTrace: st);
      await fb.FirebaseAuth.instance.signOut();
      return LoginResult.failure(ApiClient.friendlyNetworkError(e));
    }

    final body = ApiClient.parseBody(response);

    switch (response.statusCode) {
      case 200:
      case 201:
        final accessToken    = body['accessToken']    as String?;
        final refreshToken   = body['refreshToken']   as String?;
        final refreshTokenId = body['refreshTokenId'] as String?;
        final userJson       = body['user']           as Map<String, dynamic>?;

        if (accessToken == null || refreshToken == null || userJson == null) {
          await fb.FirebaseAuth.instance.signOut();
          return LoginResult.failure('Login failed. Please try again.');
        }

        final apiId = userJson['_id'] as String?
                   ?? userJson['id']  as String? ?? '';

        _lastRefreshTokenId = refreshTokenId;

        // ── Step 3: Firestore — stamp lastLoginAt, read current role ─────────
        // Firestore is the source of truth for role. Admin may have updated it
        // since the last login — always read fresh.
        String role = 'Tourist';
        try {
          role = await _UserStore.touchAndGetRole(firebaseUid);
          _log.i('✅ Firestore updated — role: $role | uid: $firebaseUid');
        } catch (e) {
          _log.w('⚠️ Firestore touch failed — defaulting to Tourist: $e');
        }

        final user = AppUser.fromApiJson(
          firebaseUid:  firebaseUid,
          json:         userJson,
          roleOverride: role,
        );

        // ── Step 4: Persist full session ─────────────────────────────────────
        await ApiClient.saveSession(
          firebaseUid:  firebaseUid,
          accessToken:  accessToken,
          refreshToken: refreshToken,
          apiId:        apiId,
          email:        user.email,
          roles:        user.roles, userId: '',
        );

        return LoginResult.success(message: 'Welcome back!', user: user);

      case 400:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('Please enter both email and password.');
      case 401:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('Incorrect email or password. Please try again.');
      case 403:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('Your account is inactive. Please contact support.');
      case 404:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('No account found with this email address.');
      case 500:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('Server error. Please try again later.');
      default:
        await fb.FirebaseAuth.instance.signOut();
        return LoginResult.failure('Something went wrong. Please try again.');
    }
  }

  // Firebase error mapper
  static String _mapFirebaseError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
        return 'Incorrect email or password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'Your account is inactive. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> googleSignIn() async {
    _log.i('🌐 AuthService.googleSignIn: ━━━ START ━━━');

    try {
      final gsi = GoogleSignIn.instance;
      await gsi.initialize(serverClientId: AppConfig.googleWebClientId);

      if (!gsi.supportsAuthenticate()) {
        return AuthResult.failure('Google Sign-In is not supported on this platform.');
      }

      final GoogleSignInAccount  googleUser = await gsi.authenticate(scopeHint: ['email', 'profile']);
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        return AuthResult.failure('Could not retrieve Google credentials. Please try again.');
      }

      // ── Step 1: API Google auth — get JWT tokens + apiId ──────────────────
      dynamic response;
      try {
        response = await ApiClient.post(
          ApiEndpoints.googleAuth,
          body: {'idToken': idToken},
        );
      } on Exception catch (e) {
        return AuthResult.failure(ApiClient.friendlyNetworkError(e));
      }

      final body = ApiClient.parseBody(response);

      switch (response.statusCode) {
        case 200:
        case 201:
          final accessToken  = body['accessToken']  as String?;
          final refreshToken = body['refreshToken'] as String?;
          final userJson     = body['user']         as Map<String, dynamic>?;

          if (accessToken == null || refreshToken == null || userJson == null) {
            return AuthResult.failure('Google Sign-In failed. Please try again.');
          }

          final apiId = userJson['_id'] as String?
                     ?? userJson['id']  as String? ?? '';
          final email = userJson['email'] as String? ?? '';

          // ── Step 2: Firebase — sign in with Google credential to get UID ──
          // Firebase UID is the Firestore document key — required for Firestore writes.
          String firebaseUid = '';
          try {
            final fbCredential = fb.GoogleAuthProvider.credential(idToken: idToken);
            final fbResult     = await fb.FirebaseAuth.instance
                .signInWithCredential(fbCredential);
            firebaseUid = fbResult.user?.uid ?? '';
            _log.i('✅ Firebase Google sign-in OK (uid: $firebaseUid)');
          } catch (e) {
            // Fall back to any UID the API may have returned
            firebaseUid = userJson['firebaseUid'] as String? ?? '';
            _log.w('⚠️ Firebase Google sign-in failed — falling back: $e');
          }

          // ── Step 3: Firestore — upsert Users/{firebaseUid} ────────────────
          // New user  → creates doc with role: Tourist
          // Returning → updates lastLoginAt + syncs apiId; role is untouched
          String role = 'Tourist';
          if (firebaseUid.isNotEmpty) {
            try {
              await _UserStore.upsertGoogleUser(
                firebaseUid: firebaseUid,
                email:       email,
                apiId:       apiId,
              );
              role = await _UserStore.getRole(firebaseUid);
              _log.i('✅ Firestore upsert OK — uid: $firebaseUid | role: $role');
            } catch (e) {
              _log.w('⚠️ Firestore upsert failed: $e');
            }
          }

          final user = AppUser.fromApiJson(
            firebaseUid:  firebaseUid,
            json:         userJson,
            roleOverride: role,
          );

          // ── Step 4: Persist session ────────────────────────────────────────
          await ApiClient.saveSession(
            firebaseUid:  firebaseUid,
            accessToken:  accessToken,
            refreshToken: refreshToken,
            apiId:        apiId,
            email:        user.email,
            roles:        user.roles, userId: '',
          );

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
          return AuthResult.failure(
              'Google email not verified. Please verify your Google account first.');
        default:
          return AuthResult.failure('Something went wrong. Please try again.');
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return AuthResult.failure('Google Sign-In was cancelled.');
      }
      return AuthResult.failure('Google Sign-In failed. Please try again.');
    } catch (e) {
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> logout() async {
    _log.i('🚪 AuthService.logout: ━━━ START ━━━');

    final tokenId = _lastRefreshTokenId;
    _lastRefreshTokenId = null;
    if (tokenId != null) {
      // Fire-and-forget: wrap in async closure so error handling uses
      // a plain try/catch and avoids the catchError return-type constraint.
      () async {
        try {
          await ApiClient.authPost(
            ApiEndpoints.logout,
            body: {'refreshTokenId': tokenId},
          );
        } catch (e) {
          _log.d('🚪 AuthService.logout: revoke token failed (non-blocking): $e');
        }
      }();
    }

    await ApiClient.clearSession();

    // Clear the last-section pointer so a fresh login starts at the landing page.
    try {
      html.window.localStorage.remove('pn_last_section');
      html.window.localStorage.remove('pn_last_city_json');
    } catch (_) {/* localStorage not available — silently ignore */}

    // Firebase sign-out removed: login no longer signs the user into Firebase,
    // so there is no Firebase session to clear. Only the API session token and
    // the localStorage section-pointer need to be wiped on logout.

    _log.i('🚪 AuthService.logout: ━━━ LOGOUT COMPLETE ━━━');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORGOT PASSWORD
  // ══════════════════════════════════════════════════════════════════════════
  static Future<AuthResult> forgotPassword({required String email}) async {
    dynamic response;
    try {
      response = await ApiClient.post(
        ApiEndpoints.forgotPassword,
        body: {'email': email.trim()},
      );
    } on Exception catch (e) {
      return AuthResult.failure(ApiClient.friendlyNetworkError(e));
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      return AuthResult.success(
        message: 'If that email is registered, a reset link has been sent. '
                 'Check your inbox and spam folder.',
      );
    }

    switch (response.statusCode) {
      case 400: return AuthResult.failure('Please enter a valid email address.');
      case 404: return AuthResult.success(
        message: 'If that email is registered, a reset link has been sent.',
      );
      case 429: return AuthResult.failure(
          'Too many attempts. Please wait a few minutes and try again.');
      default:  return AuthResult.failure('Something went wrong. Please try again later.');
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
  // ── Tab controller (0=Login, 1=Sign Up, 2=Passwordless) ──────────────────
  late TabController _tabController;

  final _loginFormKey  = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  final _loginEmailController            = TextEditingController();
  final _loginPasswordController         = TextEditingController();
  final _signUpEmailController           = TextEditingController();
  final _signUpPasswordController        = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();

  // ── Passwordless sign-in state ────────────────────────────────────────────
  final _magicEmailController = TextEditingController();
  final _magicFormKey         = GlobalKey<FormState>();
  bool  _magicLinkSent        = false;

  bool _obscureLoginPassword   = true;
  bool _obscureSignUpPassword  = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading              = false;

  @override
  void initState() {
    super.initState();
    _log.i('🖥️ AuthScreen: ━━━ SCREEN INITIALIZED ━━━');
    _tabController = TabController(
      length: 3,                              // ← was 2, now 3
      vsync: this,
      initialIndex: widget.isLogin ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    _magicEmailController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HANDLE LOGIN
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await AuthService.login(
      email:    _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.isSuccess) {
      _showMessage(AuthResult.failure(result.message));
      return;
    }

    if (result.mfaResolver != null) {
      final verified = await _showMfaLoginChallenge(resolver: result.mfaResolver!);
      if (!mounted) return;
      if (verified) {
        _navigateToLanding();
      } else {
        await AuthService.logout();
        if (mounted) _showMessage(AuthResult.failure('Sign in cancelled. Please try again.'));
      }
    } else {
      _navigateToLanding();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showMfaEnrollmentOffer();
      });
    }
  }

  Future<void> _handleRegister() async {
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
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final result = await AuthService.googleSignIn();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      _navigateToLanding();
    } else {
      _showMessage(result);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HANDLE PASSWORDLESS SIGN-IN (email magic link)
  //
  // Flow:
  //   1. User enters email → tap "Send Sign-In Link".
  //   2. FirebaseEmailLinkService.sendSignInLink(purpose=signIn) is called.
  //   3. User receives email and taps the link.
  //   4. The deep-link handler in main.dart calls
  //      FirebaseEmailLinkService.handleIncomingLink(link) which calls
  //      completeSignIn() → signs the user into Firebase.
  //   5. The emailLinkResultNotifier (ValueNotifier in main.dart) fires.
  //   6. The UI in this screen listens and navigates to landing.
  //
  // The screen also shows a manual "I have a link" option for cases where
  // deep-links are not yet configured (useful during development).
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _handleSendMagicLink() async {
    if (!_magicFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await FirebaseEmailLinkService.sendSignInLink(
      email:   _magicEmailController.text.trim(),
      purpose: EmailLinkPurpose.signIn,
    );

    if (!mounted) return;
    setState(() {
      _isLoading    = false;
      _magicLinkSent = result.isSuccess;
    });

    _showMessage(result.isSuccess
        ? AuthResult.success(message: result.message)
        : AuthResult.failure(result.message));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HANDLE INCOMING EMAIL LINK (called by main.dart notifier listener)
  //
  // Wire this up in main.dart like so:
  //
  //   // In your top-level widget / MaterialApp builder:
  //   emailLinkResultNotifier.addListener(() {
  //     final result = emailLinkResultNotifier.value;
  //     if (result != null && result.isSuccess) {
  //       // If AuthScreen is in the stack, pop to it:
  //       navigatorKey.currentState?.pushAndRemoveUntil(
  //         MaterialPageRoute(builder: (_) => const LandingPage()),
  //         (r) => false,
  //       );
  //     }
  //   });
  // ══════════════════════════════════════════════════════════════════════════

  // ── Navigation helper ─────────────────────────────────────────────────────
  // Always push-and-remove so LandingPage is guaranteed to be the root,
  // regardless of how many AuthScreen instances are in the stack (e.g. the
  // session-expiry re-push or the zone-crash double-push seen in logs).
  // LandingPage._goToSignIn() awaits the push and calls _loadAuthState()
  // on return — because we pop-to-root here that await resolves correctly.
  void _navigateToLanding() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const LandingPage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 320),
      ),
      (route) => false,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA LOGIN CHALLENGE  (mandatory, non-dismissible)
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> _showMfaLoginChallenge({
    required fb.MultiFactorResolver resolver,
  }) async {
    final hint = resolver.hints.isNotEmpty ? resolver.hints.first : null;
    final maskedPhone = (hint is fb.PhoneMultiFactorInfo)
        ? _maskPhone(hint.phoneNumber)
        : 'your phone';

    final otpController = TextEditingController();
    final otpFormKey    = GlobalKey<FormState>();
    bool  sheetLoading  = true;
    bool  smsSent       = false;
    bool  verified      = false;
    String? sendErrorMsg;
    String? verificationId;

    final resultCompleter = Completer<bool>();

    if (!mounted) return false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setS) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!sheetCtx.mounted || smsSent || sendErrorMsg != null) return;
              if (!sheetLoading) return;

              final r = await FirebaseMfaService.startSignInChallenge(
                resolver: resolver,
                onCodeSent: (vId, _) {
                  verificationId = vId;
                  if (sheetCtx.mounted) setS(() { sheetLoading = false; smsSent = true; });
                },
                onFailed: (e) {
                  if (sheetCtx.mounted) {
                    setS(() {
                    sheetLoading = false;
                    sendErrorMsg = FirebaseMfaService.mapAuthErrorPublic(e);
                  });
                  }
                },
              );

              if (!r.isSuccess && sheetCtx.mounted && sheetLoading) {
                setS(() { sheetLoading = false; sendErrorMsg = r.message; });
              }
            });

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                    Center(child: Container(
                      width: 44, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    )),
                    const SizedBox(height: 24),
                    const Row(children: [
                      Icon(Icons.phone_android_rounded, color: Color(0xFF14FFEC), size: 28),
                      SizedBox(width: 12),
                      Expanded(child: Text('Two-Factor Verification',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 8),
                    if (sheetLoading)
                      Row(children: [
                        const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF14FFEC))),
                        const SizedBox(width: 10),
                        Text('Sending SMS to $maskedPhone…',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
                      ])
                    else if (sendErrorMsg != null)
                      Text('Could not send code: $sendErrorMsg\nTap "Resend code" below to try again.',
                          style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13, height: 1.4))
                    else
                      Text('Enter the 6-digit code sent to $maskedPhone.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4)),
                    const SizedBox(height: 24),
                    if (!sheetLoading) ...[
                      Form(
                        key: otpFormKey,
                        child: TextFormField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6, autofocus: smsSent,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 12),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            counterText: '', hintText: '• • • • • •',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 20, letterSpacing: 8),
                            filled: true, fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2)),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
                            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFCF6679), width: 2)),
                            errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                          ),
                          validator: (v) => (v == null || v.trim().length != 6)
                              ? 'Please enter the full 6-digit code' : null,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (!smsSent || verificationId == null) ? null : () async {
                            if (!otpFormKey.currentState!.validate()) return;
                            setS(() => sheetLoading = true);
                            final vResult = await FirebaseMfaService.resolveSignIn(
                              resolver: resolver, verificationId: verificationId!,
                              smsCode: otpController.text.trim(),
                            );
                            if (!sheetCtx.mounted) return;
                            if (vResult.isSuccess) {
                              verified = true;
                              Navigator.pop(sheetCtx);
                            } else {
                              setS(() => sheetLoading = false);
                              if (mounted) _showMessage(AuthResult.failure(vResult.message));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14FFEC),
                            foregroundColor: const Color(0xFF1E3A5F),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: sheetLoading
                              ? const SizedBox(height: 20, width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                              : const Text('Verify & Sign In',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(child: TextButton.icon(
                        onPressed: sheetLoading ? null : () async {
                          setS(() { sheetLoading = true; smsSent = false; sendErrorMsg = null; verificationId = null; });
                          await FirebaseMfaService.startSignInChallenge(
                            resolver: resolver,
                            onCodeSent: (vId, _) {
                              verificationId = vId;
                              if (sheetCtx.mounted) setS(() { sheetLoading = false; smsSent = true; });
                              if (mounted) _showMessage(AuthResult.success(message: 'A new code has been sent to $maskedPhone.'));
                            },
                            onFailed: (e) {
                              if (sheetCtx.mounted) {
                                setS(() {
                                sheetLoading = false;
                                sendErrorMsg = FirebaseMfaService.mapAuthErrorPublic(e);
                              });
                              }
                            },
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, color: Color(0xFF14FFEC), size: 16),
                        label: const Text('Resend code', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
                      )),
                    ],
                    const SizedBox(height: 16),
                    Center(child: TextButton(
                      onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                      child: Text('Cancel Sign In',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                    )),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).then((_) {
      if (!resultCompleter.isCompleted) resultCompleter.complete(verified);
    });

    return resultCompleter.future;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA ENROLLMENT OFFER
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showMfaEnrollmentOffer() async {
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A5F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.security_outlined, color: Color(0xFF14FFEC)),
          SizedBox(width: 10),
          Text('Secure Your Account',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          'Add phone two-factor authentication for extra security. '
          'Enable it any time from your account settings.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Maybe Later', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showMfaEnrollmentSheet();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14FFEC),
              foregroundColor: const Color(0xFF1E3A5F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Enable Now', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFA ENROLLMENT SHEET
  //
  // CHANGED: the "email not verified" guard now offers to resend the
  // verification email link instead of just showing an error and stopping.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showMfaEnrollmentSheet() async {
    final emailVerified = await FirebaseService.reloadAndCheckEmailVerified();
    if (!emailVerified) {
      if (!mounted) return;
      // ── Offer to resend the verification link ─────────────────────────────
      await _showEmailNotVerifiedDialog();
      return;
    }

    final phoneController  = TextEditingController();
    final otpController    = TextEditingController();
    final phoneFormKey     = GlobalKey<FormState>();
    final otpFormKey       = GlobalKey<FormState>();
    bool  sheetLoading     = false;
    bool  smsSent          = false;
    String? verificationId;

    if (!mounted) return;

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
                begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                Center(child: Container(
                  width: 44, height: 4,
                  decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 24),
                Row(children: [
                  const Icon(Icons.phone_android_rounded, color: Color(0xFF14FFEC), size: 28),
                  const SizedBox(width: 12),
                  Text(smsSent ? 'Enter Verification Code' : 'Enable Phone Two-Factor Auth',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Text(
                  smsSent
                      ? 'Enter the 6-digit code sent to ${_maskPhone(phoneController.text)}.'
                      : 'Enter your phone number with country code (e.g. +254 712 345 678).',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),

                // Phase 1: phone number
                if (!smsSent) ...[
                  Form(
                    key: phoneFormKey,
                    child: TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: !sheetLoading,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Phone Number', hintText: '+254 712 345 678',
                        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF14FFEC)),
                        filled: true, fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
                        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter your phone number';
                        if (!v.trim().startsWith('+')) return 'Include country code (e.g. +254…)';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: sheetLoading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(sheetLoading ? 'Sending…' : 'Send Code'),
                      onPressed: sheetLoading ? null : () async {
                        if (!phoneFormKey.currentState!.validate()) return;
                        setSheetState(() => sheetLoading = true);
                        final session = await FirebaseMfaService.getMultiFactorSession();
                        if (session == null) {
                          if (sheetCtx.mounted) { setSheetState(() => sheetLoading = false); Navigator.pop(sheetCtx); }
                          if (mounted) _showMessage(AuthResult.failure('Session expired. Please sign in again.'));
                          return;
                        }
                        await FirebaseMfaService.startEnrollment(
                          phoneNumber: phoneController.text.trim(),
                          session: session,
                          onCodeSent: (vId, _) {
                            verificationId = vId;
                            if (sheetCtx.mounted) setSheetState(() { sheetLoading = false; smsSent = true; });
                          },
                          onFailed: (e) {
                            if (sheetCtx.mounted) { setSheetState(() => sheetLoading = false); Navigator.pop(sheetCtx); }
                            if (mounted) _showMessage(AuthResult.failure(FirebaseMfaService.mapAuthErrorPublic(e)));
                          },
                        );
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

                // Phase 2: SMS code entry
                if (smsSent) ...[
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6, autofocus: true, enabled: !sheetLoading,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 10),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '', hintText: '------',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 8),
                        filled: true, fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
                        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                      ),
                      validator: (v) => (v == null || v.trim().length != 6)
                          ? 'Please enter the full 6-digit code' : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (sheetLoading || verificationId == null) ? null : () async {
                        if (!otpFormKey.currentState!.validate()) return;
                        setSheetState(() => sheetLoading = true);
                        final r = await FirebaseMfaService.completeEnrollment(
                          verificationId: verificationId!, smsCode: otpController.text.trim(),
                        );
                        if (!sheetCtx.mounted) return;
                        setSheetState(() => sheetLoading = false);
                        Navigator.pop(sheetCtx);
                        if (mounted) {
                          _showMessage(r.isSuccess
                            ? AuthResult.success(message: r.message)
                            : AuthResult.failure(r.message));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: sheetLoading
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                          : const Text('Confirm & Enable MFA', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: TextButton.icon(
                    onPressed: sheetLoading ? null : () => setSheetState(() {
                      smsSent = false; verificationId = null; otpController.clear();
                    }),
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF14FFEC), size: 16),
                    label: const Text('Change phone number', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
                  )),
                ],

                const SizedBox(height: 8),
                Center(child: TextButton(
                  onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                  child: Text('Skip for now', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EMAIL NOT VERIFIED DIALOG
  //
  // NEW: shown when the user tries to enroll MFA but hasn't verified email.
  // Offers to resend the verification link via FirebaseEmailLinkService.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showEmailNotVerifiedDialog() async {
    if (!mounted) return;

    // Firebase Auth persistence is NONE on web, so currentUser?.email is null
    // after an API-only login.  Fall back to the email stored in the API session.
    final firebaseEmail = fb.FirebaseAuth.instance.currentUser?.email;
    final email = (firebaseEmail != null && firebaseEmail.isNotEmpty)
        ? firebaseEmail
        : (await ApiClient.getEmail() ?? '');

    // Guard: ApiClient.getEmail() is async — the widget may have been disposed
    // while it was awaited.  Using context after any await without this check
    // triggers use_build_context_synchronously (dart diagnostic line 1069).
    // The earlier `if (!mounted) return` at the top of this method only
    // protects usage up to the first await; every subsequent await needs its
    // own guard before context is accessed again.
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool sending = false;
        bool sent    = false;

        return StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E3A5F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.mark_email_unread_outlined, color: Color(0xFF14FFEC)),
            SizedBox(width: 10),
            Expanded(child: Text('Verify Your Email First',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phone two-factor authentication requires a verified email address. '
                'Please verify $email before enabling MFA.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5),
              ),
              if (sent) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF14FFEC), size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Verification link sent! Check your inbox and tap the link.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.4))),
                  ]),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: Text('Close', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            ),
            if (!sent)
              ElevatedButton.icon(
                icon: sending
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(sending ? 'Sending…' : 'Resend Verification Link'),
                onPressed: sending ? null : () async {
                  setD(() => sending = true);
                  // Pass the email explicitly — Firebase currentUser is null
                  // with Persistence.NONE and API-only auth.
                  final ok = await FirebaseService.sendEmailVerificationLink(
                    emailOverride: email,
                  );
                  setD(() { sending = false; sent = ok; });
                  if (!ok && ctx2.mounted) {
                    Navigator.pop(ctx2);
                    if (mounted) _showMessage(AuthResult.failure('Could not send verification link. Please try again.'));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14FFEC),
                  foregroundColor: const Color(0xFF1E3A5F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ));
      },
    );
  }

  // ── Message Display ───────────────────────────────────────────────────────
  void _showMessage(AuthResult result) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(result.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(result.message,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: result.isSuccess ? const Color(0xFF0D7377) : const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: result.isSuccess ? 3 : 5),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF0A1128), Color(0xFF1E3A5F), Color(0xFF0D7377)],
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF14FFEC), strokeWidth: 3),
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    IconButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ]),
                ),

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
                          boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 5)],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                    color: const Color(0xFF14FFEC).withValues(alpha: 0.5),
                                    blurRadius: 20, spreadRadius: 5)]),
                              child: ClipOval(child: Image.asset('assets/images/logo.png',
                                width: 80, height: 80, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80, height: 80,
                                  decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.travel_explore_rounded, size: 40, color: Colors.white),
                                ),
                              )),
                            ),
                            const SizedBox(height: 24),
                            Text('PALMNAZI RC',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontSize: 30, fontWeight: FontWeight.bold,
                                    letterSpacing: 2, color: Colors.white)),
                            const SizedBox(height: 8),
                            Text('Resort Cities',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, letterSpacing: 3)),
                            const SizedBox(height: 32),

                            // ── Tab bar: Login | Sign Up | Magic Link ──────
                            Container(
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(30)),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                                    borderRadius: BorderRadius.circular(30)),
                                indicatorSize: TabBarIndicatorSize.tab,
                                dividerColor: Colors.transparent,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white70,
                                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                tabs: const [
                                  Tab(text: 'Login'),
                                  Tab(text: 'Sign Up'),
                                  Tab(icon: Icon(Icons.link_rounded, size: 18), text: 'Magic Link'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // ── Tab views ─────────────────────────────────
                            SizedBox(
                              height: 440,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildLoginForm(),
                                  _buildSignUpForm(),
                                  _buildMagicLinkForm(),   // ← NEW
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

  // ── Login Form ─────────────────────────────────────────────────────────────
  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _buildTextField(
            controller: _loginEmailController, label: 'Email',
            icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPasswordController, label: 'Password',
            icon: Icons.lock_outlined, obscureText: _obscureLoginPassword,
            validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password' : null,
            suffixIcon: IconButton(
              icon: Icon(_obscureLoginPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white70),
              onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton(label: 'Login', onPressed: _handleLogin),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : _showForgotPasswordSheet,
            child: Text('Forgot Password?',
                style: TextStyle(color: const Color(0xFF14FFEC).withValues(alpha: 0.9))),
          ),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ResetPasswordScreen())),
            child: Text('Have a reset code? Set new password →',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          ),
          const SizedBox(height: 4),
          _buildDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(label: 'Continue with Google'),
        ],
      ),
    );
  }

  // ── Sign-Up Form ───────────────────────────────────────────────────────────
  Widget _buildSignUpForm() {
    return Form(
      key: _signUpFormKey,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildTextField(
              controller: _signUpEmailController, label: 'Email',
              icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _signUpPasswordController, label: 'Password',
              icon: Icons.lock_outlined, obscureText: _obscureSignUpPassword,
              validator: _passwordValidator,
              suffixIcon: IconButton(
                icon: Icon(_obscureSignUpPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white70),
                onPressed: () => setState(() => _obscureSignUpPassword = !_obscureSignUpPassword),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _signUpConfirmPasswordController, label: 'Confirm Password',
              icon: Icons.lock_outlined, obscureText: _obscureConfirmPassword,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _signUpPasswordController.text) return 'Passwords do not match';
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white70),
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

  // ── Magic Link (Passwordless) Form ─────────────────────────────────────────
  // NEW: tab 2 — passwordless sign-in via email link.
  Widget _buildMagicLinkForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF14FFEC), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'No password needed. Enter your email and we\'ll send a '
                'one-tap sign-in link. Tapping it also verifies your email address.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 24),

          if (!_magicLinkSent) ...[
            Form(
              key: _magicFormKey,
              child: _buildTextField(
                controller: _magicEmailController, label: 'Email Address',
                icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
            ),
            const SizedBox(height: 24),
            _buildPrimaryButton(
              label: 'Send Sign-In Link',
              icon: Icons.send_rounded,
              onPressed: _handleSendMagicLink,
            ),
          ] else ...[
            // Sent state — show confirmation and allow resend
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D7377).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0D7377).withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.mark_email_read_outlined, color: Color(0xFF14FFEC), size: 40),
                  const SizedBox(height: 12),
                  const Text('Link sent!', style: TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Check your inbox for ${_magicEmailController.text.trim()}. '
                    'Tap the link in the email to sign in — no password needed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Color(0xFF14FFEC), size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'The link opens this app directly. If it asks for your email, '
                        'enter ${_magicEmailController.text.trim()}.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, height: 1.4),
                      )),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Resend button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Resend Link'),
                onPressed: _isLoading ? null : () {
                  setState(() => _magicLinkSent = false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF14FFEC),
                  side: const BorderSide(color: Color(0xFF14FFEC)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _buildDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(label: 'Continue with Google'),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => _tabController.animateTo(0),
              child: Text('Use password instead →',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ────────────────────────────────────────────────────────
  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
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
            ? const SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
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
    return Row(children: [
      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: Colors.white.withValues(alpha: 0.6)))),
      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
    ]);
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
      controller: controller, obscureText: obscureText,
      keyboardType: keyboardType, enabled: !_isLoading,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: const Color(0xFF14FFEC)),
        suffixIcon: suffixIcon, filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 2)),
        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
      ),
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) return 'Please enter $label';
        return null;
      },
    );
  }

  // ── Forgot Password Sheet ─────────────────────────────────────────────────
  void _showForgotPasswordSheet() {
    final forgotEmailController = TextEditingController(text: _loginEmailController.text.trim());
    final forgotFormKey = GlobalKey<FormState>();
    bool sheetLoading = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)]),
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
                  Center(child: Container(width: 44, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: const BoxDecoration(shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)])),
                      child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Reset Password',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("We'll send a reset link to your email",
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                    ]),
                  ]),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: forgotEmailController, keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white), enabled: !sheetLoading,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF14FFEC)),
                      filled: true, fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 2)),
                      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
                      errorStyle: const TextStyle(color: Color(0xFFCF6679)),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please enter your email';
                      if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(v.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: ElevatedButton(
                      onPressed: sheetLoading ? null : () async {
                        if (!forgotFormKey.currentState!.validate()) return;
                        setSheetState(() => sheetLoading = true);
                        final result = await AuthService.forgotPassword(email: forgotEmailController.text.trim());
                        setSheetState(() => sheetLoading = false);
                        if (!sheetCtx.mounted) return;
                        Navigator.pop(sheetCtx);
                        if (!mounted) return;
                        _showMessage(result);
                        if (result.isSuccess) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: sheetLoading
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                          : const Text('Send Reset Link',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Validators ────────────────────────────────────────────────────────────
  String? _emailValidator(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Please enter a password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static String _maskPhone(String? phone) {
    if (phone == null || phone.length < 6) return 'your phone';
    return '${phone.substring(0, phone.length - 4)}****';
  }
}