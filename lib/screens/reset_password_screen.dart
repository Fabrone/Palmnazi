import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGGER
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
// RESET PASSWORD SERVICE
//
// POST /api/auth/reset-password
// Body    : { token, newPassword }
// 200 OK  : { message: "Password reset successful." }
// 400     : { message: "Invalid or expired token." }
//           { message: "Password must be at least 8 characters" }  (implied)
// ─────────────────────────────────────────────────────────────────────────────
class ResetPasswordService {
  // ════════════════════════════════════════════════════════════════════════════
  // RESET PASSWORD
  // ════════════════════════════════════════════════════════════════════════════
  static Future<ResetPasswordResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    _log.i('🔑 ResetPasswordService.resetPassword: ━━━ START ━━━');
    _log.d(
      '🔑 ResetPasswordService.resetPassword: '
      'URL → ${ApiEndpoints.url(ApiEndpoints.resetPassword)} | '
      'token length → ${token.length} | '
      'password length → ${newPassword.length}',
    );

    // ── Step 1: Send request ───────────────────────────────────────────────
    dynamic response;
    try {
      _log.i('🔑 ResetPasswordService.resetPassword: Step 1 — Sending POST');
      response = await ApiClient.post(
        ApiEndpoints.resetPassword,
        body: {
          'token':       token.trim(),
          'newPassword': newPassword,
        },
      );
      _log.i('🔑 ResetPasswordService.resetPassword: Step 1 ✓ — Response received');
    } on Exception catch (e, st) {
      _log.e(
        '❌ ResetPasswordService.resetPassword: Step 1 FAILED\n'
        '   Type    : ${e.runtimeType}\n'
        '   Message : $e',
        error: e, stackTrace: st,
      );
      return ResetPasswordResult.failure(
        ApiClient.friendlyNetworkError(e),
      );
    }

    // ── Step 2: Log raw response ───────────────────────────────────────────
    _log.d('🔑 ResetPasswordService.resetPassword: Step 2 — Raw response:');
    _log.d('🔑 ResetPasswordService.resetPassword:   Status : ${response.statusCode}');
    _log.d('🔑 ResetPasswordService.resetPassword:   Body   : ${response.body}');

    final body = ApiClient.parseBody(response);
    _log.d('🔑 ResetPasswordService.resetPassword: Step 2 ✓ — Parsed: $body');

    // ── Step 3: Handle status codes ────────────────────────────────────────
    switch (response.statusCode) {
      case 200:
        _log.i('✅ ResetPasswordService.resetPassword: ━━━ RESET COMPLETE ━━━');
        return ResetPasswordResult.success(
          message: body['message'] as String? ?? 'Password reset successful.',
        );

      case 400:
        final msg = (body['message'] ?? body['error'] ?? '').toString();
        _log.w('⚠️ ResetPasswordService.resetPassword: 400 — $msg | body: $body');

        // Distinguish token errors from password-strength errors
        if (msg.toLowerCase().contains('token')) {
          return ResetPasswordResult.failure(
            'This reset link has expired or is invalid. '
            'Please request a new one.',
          );
        }
        if (msg.toLowerCase().contains('password')) {
          return ResetPasswordResult.failure(
            'Password must be at least 8 characters.',
          );
        }
        return ResetPasswordResult.failure(
          'Invalid request. Please check your details and try again.',
        );

      case 404:
        _log.w('⚠️ ResetPasswordService.resetPassword: 404 — token not found');
        return ResetPasswordResult.failure(
          'This reset link has expired or is invalid. '
          'Please request a new one.',
        );

      case 500:
        _log.e('❌ ResetPasswordService.resetPassword: 500 | body: $body');
        return ResetPasswordResult.failure(
          'Server error. Please try again later.',
        );

      default:
        _log.e(
          '❌ ResetPasswordService.resetPassword: '
          'Unhandled ${response.statusCode} | body: $body',
        );
        return ResetPasswordResult.failure(
          'Something went wrong. Please try again.',
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESET PASSWORD RESULT
// ─────────────────────────────────────────────────────────────────────────────
class ResetPasswordResult {
  final bool   isSuccess;
  final String message;

  ResetPasswordResult._({required this.isSuccess, required this.message});

  factory ResetPasswordResult.success({required String message}) =>
      ResetPasswordResult._(isSuccess: true,  message: message);

  factory ResetPasswordResult.failure(String message) =>
      ResetPasswordResult._(isSuccess: false, message: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// RESET PASSWORD SCREEN
//
// Navigation: pushed from AuthScreen (after a successful forgot-password email)
// or via a deep link that pre-fills the [initialToken] parameter.
//
// Deep link setup (for future reference):
//   When the user taps the reset link in their email, the app should open
//   this screen with the token pre-filled.  Configure your deep link handler
//   to extract the token query param and pass it as [initialToken]:
//
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => ResetPasswordScreen(
//           initialToken: uri.queryParameters['token'],
//         ),
//       ),
//     );
//
// Three UI states
// ───────────────
//   1. form    — token + new password + confirm fields
//   2. loading — full-screen spinner overlay
//   3. success — confirmation card with "Back to Login" button
// ─────────────────────────────────────────────────────────────────────────────
class ResetPasswordScreen extends StatefulWidget {
  /// Optional: pre-fill the token field (from a deep link or email redirect).
  final String? initialToken;

  const ResetPasswordScreen({
    super.key,
    this.initialToken,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _tokenController;
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword        = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading              = false;
  bool _isSuccess              = false;

  // Animation for the success card entrance
  late AnimationController _successAnimController;
  late Animation<double>   _successFadeAnimation;
  late Animation<Offset>   _successSlideAnimation;

  @override
  void initState() {
    super.initState();
    _log.i('🖥️ ResetPasswordScreen: ━━━ SCREEN INITIALIZED ━━━');

    _tokenController = TextEditingController(
      text: widget.initialToken ?? '',
    );

    if (widget.initialToken != null) {
      _log.d(
        '🖥️ ResetPasswordScreen: '
        'Pre-filled token from parameter (${widget.initialToken!.length} chars)',
      );
    }

    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _successFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimController,
        curve: Curves.easeOut,
      ),
    );

    _successSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end:   Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _successAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _log.i('🧹 ResetPasswordScreen: Disposing resources');
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _successAnimController.dispose();
    super.dispose();
  }

  // ── Handler ───────────────────────────────────────────────────────────────

  Future<void> _handleResetPassword() async {
    _log.d('🖥️ ResetPasswordScreen._handleResetPassword: Submit pressed');

    if (!_formKey.currentState!.validate()) {
      _log.w('⚠️ ResetPasswordScreen: Form validation FAILED');
      return;
    }

    _log.i('🖥️ ResetPasswordScreen: Form validated ✓ — submitting');
    setState(() => _isLoading = true);

    final result = await ResetPasswordService.resetPassword(
      token:       _tokenController.text.trim(),
      newPassword: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _log.i(
      '🖥️ ResetPasswordScreen: Result → '
      'isSuccess: ${result.isSuccess} | "${result.message}"',
    );

    if (result.isSuccess) {
      setState(() => _isSuccess = true);
      _successAnimController.forward();
      _log.i('🖥️ ResetPasswordScreen: ✅ Password reset — showing success state');
    } else {
      _showErrorSnackbar(result.message);
    }
  }

  void _showErrorSnackbar(String message) {
    _log.d('🖥️ ResetPasswordScreen._showErrorSnackbar: "$message"');
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _navigateToLogin() {
    _log.i('🖥️ ResetPasswordScreen: Navigating to AuthScreen (login)');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(isLogin: true),
      ),
      (route) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Background ─────────────────────────────────────────────────
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

          // Subtle diagonal grid overlay (matches AnimatedBackground style)
          CustomPaint(
            painter: _DiagonalGridPainter(),
            size: Size.infinite,
          ),

          // ── Loading overlay ─────────────────────────────────────────────
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF14FFEC),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Resetting your password…',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Main content ────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: _isSuccess
                              ? _buildSuccessState()
                              : _buildFormCard(),
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

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (!_isSuccess)
            IconButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      _log.d('🖥️ ResetPasswordScreen: Back button pressed');
                      Navigator.pop(context);
                    },
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  // ── Form card ─────────────────────────────────────────────────────────────

  Widget _buildFormCard() {
    return Container(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Center(child: _buildHeaderIcon()),
            const SizedBox(height: 28),

            Center(
              child: Column(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF14FFEC), Colors.white],
                    ).createShader(bounds),
                    child: const Text(
                      'Create New Password',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Enter the reset code from your email\nand choose a strong new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // ── Reset token field ───────────────────────────────────────────
            _buildSectionLabel('Reset Code', Icons.vpn_key_outlined),
            const SizedBox(height: 10),
            TextFormField(
              controller: _tokenController,
              enabled: !_isLoading,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
                fontSize: 13,
              ),
              decoration: _fieldDecoration(
                label: 'Paste your reset code here',
                icon: Icons.vpn_key_outlined,
                suffixIcon: _tokenController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() => _tokenController.clear());
                        },
                      )
                    : null,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter the reset code from your email';
                }
                if (v.trim().length < 8) {
                  return 'Reset code appears too short — please check your email';
                }
                return null;
              },
              onChanged: (_) => setState(() {}), // rebuild for clear button
            ),

            // Hint box
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF14FFEC).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF14FFEC),
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Open the reset email we sent you and copy the full '
                      'reset code, then paste it in the field above.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── New password field ──────────────────────────────────────────
            _buildSectionLabel('New Password', Icons.lock_outlined),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !_isLoading,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(
                label: 'Enter new password',
                icon: Icons.lock_outlined,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter a new password';
                if (v.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Confirm password field ──────────────────────────────────────
            _buildSectionLabel('Confirm Password', Icons.lock_outlined),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              enabled: !_isLoading,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(
                label: 'Re-enter new password',
                icon: Icons.lock_outlined,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),

            // ── Password strength bar ───────────────────────────────────────
            const SizedBox(height: 16),
            _buildPasswordStrengthIndicator(_passwordController.text),

            const SizedBox(height: 32),

            // ── Submit button ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleResetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14FFEC),
                  foregroundColor: const Color(0xFF0A1128),
                  disabledBackgroundColor:
                      const Color(0xFF14FFEC).withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF0A1128),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_reset_rounded, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Reset Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Back to login link ──────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: _isLoading ? null : _navigateToLogin,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new,
                      size: 13,
                      color: const Color(0xFF14FFEC).withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Back to Login',
                      style: TextStyle(
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccessState() {
    return FadeTransition(
      opacity: _successFadeAnimation,
      child: SlideTransition(
        position: _successSlideAnimation,
        child: Container(
          key: const ValueKey('success'),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            children: [
              // Animated check icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.45),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF14FFEC), Colors.white],
                ).createShader(bounds),
                child: const Text(
                  'Password Reset!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'Your password has been updated successfully.\n'
                'You can now log in with your new password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              // Back to login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToLogin,
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: const Text(
                    'Back to Login',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14FFEC),
                    foregroundColor: const Color(0xFF0A1128),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Supporting widgets ────────────────────────────────────────────────────

  Widget _buildHeaderIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14FFEC).withValues(alpha: 0.4),
            blurRadius: 25,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(
        Icons.lock_reset_rounded,
        color: Colors.white,
        size: 38,
      ),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF14FFEC)),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.75),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      prefixIcon: Icon(icon, color: const Color(0xFF14FFEC), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
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
    );
  }

  /// Visual password-strength bar shown beneath the new-password field.
  Widget _buildPasswordStrengthIndicator(String password) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = _passwordStrength(password);
    final label    = _strengthLabel(strength);
    final color    = _strengthColor(strength);
    final segments = strength; // 1–4

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segmented bar
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i < segments
                      ? color
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          'Strength: $label',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  int _passwordStrength(String password) {
    if (password.length < 8) return 1;
    int score = 1;
    if (password.length >= 12)                               score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      score++;
    }
    return score.clamp(1, 4);
  }

  String _strengthLabel(int strength) {
    switch (strength) {
      case 1:  return 'Weak';
      case 2:  return 'Fair';
      case 3:  return 'Good';
      default: return 'Strong';
    }
  }

  Color _strengthColor(int strength) {
    switch (strength) {
      case 1:  return const Color(0xFFCF6679);
      case 2:  return const Color(0xFFFFB300);
      case 3:  return const Color(0xFF14FFEC);
      default: return const Color(0xFF00E676);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIAGONAL GRID PAINTER
// Subtle background decoration matching AnimatedBackground's grid style.
// ─────────────────────────────────────────────────────────────────────────────
class _DiagonalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 60.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }

    final dotPaint = Paint()
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        dotPaint.color = const Color(0xFF14FFEC).withValues(alpha: 0.12);
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}