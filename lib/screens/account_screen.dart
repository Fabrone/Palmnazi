import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/screens/auth_screen.dart';   // AppUser, AuthService
import 'package:palmnazi/screens/landing_page.dart';  // RC colour tokens + LandingPage
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logger (shared across this file)
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
// AccountScreen
// ─────────────────────────────────────────────────────────────────────────────
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // ── Data state ─────────────────────────────────────────────────────────────
  String?       _email;
  String?       _userId;
  List<String>  _roles       = [];
  bool          _emailVerified = false;
  // API-backed MFA flag — true when the backend reports mfaEnabled: true.
  // Loaded via GET /api/auth/me so it always reflects the authoritative state.
  bool          _mfaEnabled  = false;

  // ── Loading flags ──────────────────────────────────────────────────────────
  bool _loading       = true;
  bool _actionLoading = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loaders
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // ── API session (stored by ApiClient.saveSession) ─────────────────────
      final email  = await ApiClient.getEmail();
      final userId = await ApiClient.getUserId();
      final roles  = await ApiClient.getRoles();

      // ── MFA status from GET /api/auth/me ──────────────────────────────────
      bool mfaEnabled = false;
      try {
        final meResp = await ApiClient.authGet(ApiEndpoints.me);
        if (meResp.statusCode == 200) {
          final meBody = ApiClient.parseBody(meResp);
          // Accept either top-level or nested under "user"
          final userMap = (meBody['user'] as Map<String, dynamic>?) ?? meBody;
          mfaEnabled = (userMap['mfaEnabled'] as bool?) ?? false;
        }
      } catch (e) {
        _log.w('⚠️ AccountScreen._loadUserInfo: Could not fetch /me for MFA status: $e');
      }

      // ── Firebase — reload for emailVerified ───────────────────────────────
      final fbUser = FirebaseService.currentUser;
      if (fbUser != null) {
        try { await fbUser.reload(); } catch (_) {}
      }
      final emailVerified = FirebaseService.currentUser?.emailVerified ?? false;

      _log.i(
        '📱 AccountScreen._loadUserInfo: '
        'email=$email | verified=$emailVerified | mfaEnabled=$mfaEnabled',
      );

      if (mounted) {
        setState(() {
          _email         = email;
          _userId        = userId;
          _roles         = roles;
          _emailVerified = emailVerified;
          _mfaEnabled    = mfaEnabled;
          _loading       = false;
        });
      }
    } catch (e, st) {
      _log.e('❌ AccountScreen._loadUserInfo: Error', error: e, stackTrace: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MFA handlers
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the two-phase email OTP enrollment sheet.
  /// After the sheet closes, reloads user info to refresh the MFA badge.
  Future<void> _handleEnableMfa() async {
    await _showMfaEnrollmentSheet();
    if (mounted) await _loadUserInfo();
  }

  /// Confirms then disables MFA via the API.
  Future<void> _handleDisableMfa() async {
    final confirm = await _confirmDialog(
      icon: Icons.no_encryption_gmailerrorred_rounded,
      iconColor: RC.coral,
      title: 'Disable Email MFA?',
      body: 'This removes the email OTP two-factor step from your account. '
            'You can re-enable it at any time from this screen.',
      confirmLabel: 'Disable',
      confirmColor: RC.coral,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    _log.i('📱 AccountScreen._handleDisableMfa: Calling mfaDisable endpoint');

    try {
      final response = await ApiClient.authPost(
        ApiEndpoints.mfaDisable,
        body: {'email': _email ?? ''},
      );
      final body = ApiClient.parseBody(response);

      if (!mounted) return;
      setState(() => _actionLoading = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _log.i('✅ AccountScreen._handleDisableMfa: MFA disabled');
        _snack('Email MFA has been disabled.', ok: true);
        await _loadUserInfo();
      } else {
        final msg = body['error'] ?? body['message'] ?? 'Could not disable MFA.';
        _log.w('⚠️ AccountScreen._handleDisableMfa: ${response.statusCode} — $msg');
        _snack('Could not disable MFA. Please try again.', ok: false);
      }
    } catch (e) {
      if (mounted) setState(() => _actionLoading = false);
      _log.e('❌ AccountScreen._handleDisableMfa: Exception — $e');
      _snack(ApiClient.friendlyNetworkError(e), ok: false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Email OTP MFA Enrollment Sheet
  //
  // Two-phase, API-backed — mirrors the implementation in auth_screen.dart:
  //   Phase 1 — POST /api/auth/mfa/send-otp   → dispatches OTP to user's email
  //   Phase 2 — POST /api/auth/mfa/verify-otp → verifies code and enables MFA
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showMfaEnrollmentSheet() async {
    final email = _email ?? '';
    if (email.isEmpty) {
      _snack('No email address found. Please sign in again.', ok: false);
      return;
    }

    _log.i('📱 AccountScreen._showMfaEnrollmentSheet: Opening for $email');

    final otpController = TextEditingController();
    final otpFormKey    = GlobalKey<FormState>();
    bool  sheetLoading  = false;
    bool  otpSent       = false; // false = phase 1, true = phase 2

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 24),

                Row(children: [
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
                ]),
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

                // ── Phase 1: Send OTP ───────────────────────────────────────
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
                              setS(() => sheetLoading = true);
                              _log.i('📱 MfaEnrollmentSheet: Sending OTP to $email');

                              final result = await AuthService.mfaSendOtp(email: email);
                              setS(() => sheetLoading = false);

                              if (result.isSuccess) {
                                _log.i('📱 MfaEnrollmentSheet: OTP sent — advancing to phase 2');
                                setS(() => otpSent = true);
                              } else {
                                _log.w('📱 MfaEnrollmentSheet: OTP send failed — ${result.message}');
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                if (mounted) _snack(result.message, ok: false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                // ── Phase 2: Verify OTP ─────────────────────────────────────
                if (otpSent) ...[
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !sheetLoading,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF14FFEC), width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFCF6679), width: 1.5),
                        ),
                        errorStyle:
                            const TextStyle(color: Color(0xFFCF6679)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 4) {
                          return 'Enter the code from your email';
                        }
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
                              setS(() => sheetLoading = true);
                              _log.i('📱 MfaEnrollmentSheet: Verifying OTP');

                              final result = await AuthService.mfaVerifyOtp(
                                email: email,
                                otp:   otpController.text.trim(),
                              );

                              if (!sheetCtx.mounted) return;
                              setS(() => sheetLoading = false);
                              Navigator.pop(sheetCtx);
                              if (!mounted) return;

                              _log.i(
                                '📱 MfaEnrollmentSheet: Verify result — '
                                'isSuccess=${result.isSuccess}',
                              );
                              _snack(result.message, ok: result.isSuccess);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: sheetLoading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF1E3A5F)),
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
                              setS(() => sheetLoading = true);
                              _log.i('📱 MfaEnrollmentSheet: Re-sending OTP');
                              await AuthService.mfaSendOtp(email: email);
                              setS(() => sheetLoading = false);
                              if (mounted) {
                                _snack(
                                  'A new code has been sent to $email.',
                                  ok: true,
                                );
                              }
                            },
                      icon: const Icon(Icons.refresh_rounded,
                          color: Color(0xFF14FFEC), size: 16),
                      label: const Text(
                        'Resend code',
                        style: TextStyle(
                            color: Color(0xFF14FFEC), fontSize: 13),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: sheetLoading
                        ? null
                        : () => Navigator.pop(sheetCtx),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Sign-out handler
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleSignOut() async {
    final confirm = await _confirmDialog(
      icon: Icons.logout_rounded,
      iconColor: RC.coral,
      title: 'Sign Out?',
      body: 'You will be signed out of your account on this device.',
      confirmLabel: 'Sign Out',
      confirmColor: RC.coral,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    await AuthService.logout();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RC.navy,
      body: CustomScrollView(
        slivers: [
          _appBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF14FFEC)),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _profileCard()),
            SliverToBoxAdapter(child: _securitySection()),
            SliverToBoxAdapter(child: _signOutBtn()),
            const SliverToBoxAdapter(child: SizedBox(height: 56)),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // App bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _appBar() => SliverAppBar(
        backgroundColor: RC.navy,
        expandedHeight: 148,
        pinned: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: RC.teal),
            onPressed: _loading ? null : _loadUserInfo,
            tooltip: 'Refresh',
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
          title: const Text(
            'My Account',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold),
          ),
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF071829), Color(0xFF0B2135)],
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.only(right: 24, bottom: 56, top: 60),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF14FFEC)
                              .withValues(alpha: 0.30),
                          blurRadius: 20)
                    ],
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Profile card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _profileCard() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Email ──────────────────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _iconCircle(Icons.email_outlined, RC.teal),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Email'),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text(
                            _email ?? '—',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (_email == null) return;
                            Clipboard.setData(ClipboardData(text: _email!));
                            _snack('Email copied!', ok: true);
                          },
                          child: const Icon(Icons.copy_rounded,
                              size: 14, color: RC.textMute),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      _emailVerifiedBadge(),
                    ],
                  ),
                ),
              ]),

              const _Divider(),

              // ── Roles ──────────────────────────────────────────────────
              Row(children: [
                _iconCircle(Icons.badge_outlined, RC.gold),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Roles'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _roles.map((r) => _roleBadge(r)).toList(),
                      ),
                    ],
                  ),
                ),
              ]),

              const _Divider(),

              // ── User ID ────────────────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                _iconCircle(Icons.fingerprint_rounded, RC.teal),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('User ID'),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text(
                            _userId ?? '—',
                            style: const TextStyle(
                                color: RC.textSec,
                                fontSize: 11,
                                fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (_userId == null) return;
                            Clipboard.setData(
                                ClipboardData(text: _userId!));
                            _snack('User ID copied!', ok: true);
                          },
                          child: const Icon(Icons.copy_rounded,
                              size: 14, color: RC.textMute),
                        ),
                      ]),
                    ],
                  ),
                ),
              ]),
            ],
          ),
        ),
      );

  Widget _emailVerifiedBadge() {
    final ok    = _emailVerified;
    final color = ok ? RC.emerald : RC.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          ok ? 'Email Verified' : 'Email Not Verified',
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  Widget _roleBadge(String role) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: RC.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RC.gold.withValues(alpha: 0.30)),
        ),
        child: Text(
          role.toUpperCase(),
          style: const TextStyle(
              color: RC.gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Security section
  // ─────────────────────────────────────────────────────────────────────────
  Widget _securitySection() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                'SECURITY',
                style: TextStyle(
                    color: RC.textMute,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4),
              ),
            ),
            Container(
              decoration: _cardDecoration(),
              // Single tile — email OTP MFA only
              child: _emailOtpMfaTile(),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Email OTP MFA tile
  // Replaces the old SMS MFA + email-link tiles.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _emailOtpMfaTile() => ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: _iconCircle(
          Icons.email_outlined,
          _mfaEnabled ? RC.emerald : RC.teal,
        ),
        title: const Text(
          'Email Two-Factor Auth',
          style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _mfaEnabled
              ? 'Enabled — a code is sent to your email at each login'
              : 'Disabled — adds an email OTP verification step at login',
          style: const TextStyle(color: RC.textMute, fontSize: 12),
        ),
        trailing: _actionLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF14FFEC)))
            : Switch.adaptive(
                value: _mfaEnabled,
                onChanged: (enable) async {
                  enable
                      ? await _handleEnableMfa()
                      : await _handleDisableMfa();
                },
                activeThumbColor: RC.emerald,
                inactiveThumbColor: RC.textMute,
                inactiveTrackColor: RC.textMute.withValues(alpha: 0.28),
              ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Sign-out button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _signOutBtn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: _handleSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: RC.coral,
              side: const BorderSide(color: RC.coral),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor:
          ok ? const Color(0xFF0D7377) : const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: ok ? 3 : 5),
    ));
  }

  Future<bool?> _confirmDialog({
    required IconData icon,
    required Color    iconColor,
    required String   title,
    required String   body,
    required String   confirmLabel,
    required Color    confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A5F),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          body,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Small reusable pieces ─────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: RC.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      );

  Widget _iconCircle(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: RC.textMute, fontSize: 11, letterSpacing: 0.5),
      );

  Widget _sheetContainer({required Widget child}) => Container(
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
        child: child,
      );

  Widget _sheetHandle() => Center(
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2)),
        ),
      );

}

// ─────────────────────────────────────────────────────────────────────────────
// Thin divider widget
// ─────────────────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(
        color: Color(0xFF1A3550),
        height: 1,
      );
}