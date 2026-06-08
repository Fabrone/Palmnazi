import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html show window, StorageEvent; // web-only: cross-tab verification
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_mfa_service.dart';
import 'package:palmnazi/services/firebase_service.dart';
import 'package:palmnazi/services/notification_service.dart';
import 'package:palmnazi/services/rbac_service.dart';

final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0, errorMethodCount: 8, lineLength: 100, colors: true, printEmojis: true,
  ),
);

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String?       _email;
  String?       _firebaseUid;
  // ignore: unused_field
  String?       _userId;
  bool          _emailVerified = false;
  bool          _mfaEnabled    = false;

  String?        _firestoreRole;
  AdminRequest?  _adminRequest;

  bool _loading       = true;
  bool _actionLoading = false;

  StreamSubscription<String>?        _roleSub;
  StreamSubscription<AdminRequest?>? _requestSub;

  // ── Cross-tab email verification listeners ────────────
  StreamSubscription<dynamic>?       _authStateSub;
  StreamSubscription<html.StorageEvent>? _storageSub;
  Timer?                             _verificationTimer;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    _requestSub?.cancel();
    _cancelVerificationListeners(); // stop auth / storage / timer listeners
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loader
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadUserInfo() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final email  = await ApiClient.getEmail();
      final userId = await ApiClient.getUserId();

      final fbUid      = FirebaseService.currentUser?.uid;
      final mfaEnabled = await FirebaseMfaService.isPhoneMfaEnrolled();

      final fbUser = FirebaseService.currentUser;
      if (fbUser != null) {
        try { await fbUser.reload(); } catch (_) {}
      }

      // Primary check: Firebase Auth (works when user is signed into Firebase).
      bool emailVerified = FirebaseService.currentUser?.emailVerified ?? false;

      // Fallback check: localStorage signal
      if (!emailVerified && kIsWeb) {
        try {
          final storedEmail =
              html.window.localStorage['pn_verified_email'] ?? '';
          if (storedEmail.isNotEmpty &&
              storedEmail == (email ?? '').toLowerCase().trim()) {
            emailVerified = true;
            _log.d('AccountScreen: emailVerified via localStorage signal');
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _email         = email;
          _firebaseUid   = fbUid;
          _userId        = userId;
          _emailVerified = emailVerified;
          _mfaEnabled    = mfaEnabled;
          _loading       = false;
        });
      }

      if (fbUid != null) _startRbacListeners(fbUid);

      // Start real-time cross-tab listeners when email is not yet verified.
      // They cancel themselves automatically once verification is detected.
      if (!emailVerified) {
        _cancelVerificationListeners();
        _listenForVerification(email);
      } else {
        _cancelVerificationListeners(); // verified — no need to keep listeners
      }
    } catch (e, st) {
      _log.e('❌ AccountScreen._loadUserInfo', error: e, stackTrace: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startRbacListeners(String userId) {
    _roleSub?.cancel();
    _requestSub?.cancel();

    _roleSub = RbacService.userRoleStream(userId).listen(
      (role) { if (mounted) setState(() => _firestoreRole = role); },
      onError: (e) => _log.w('⚠️ AccountScreen: role stream error — $e'),
    );
    _requestSub = RbacService.userRequestStream(userId).listen(
      (req) { if (mounted) setState(() => _adminRequest = req); },
      onError: (e) => _log.w('⚠️ AccountScreen: request stream error — $e'),
    );
    NotificationService.startUserRequestListener(userId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cross-tab email verification detection
  // ────────────────────────────────────────────────────────────
  void _listenForVerification(String? userEmail) {
    // 1. Firebase auth-state stream (cross-tab via IndexedDB)
    _authStateSub = FirebaseService.authStateChanges.listen((fbUser) {
      if (!mounted || _emailVerified) return;
      if (fbUser?.emailVerified == true) {
        _log.d('AccountScreen: emailVerified via authStateChanges');
        setState(() => _emailVerified = true);
        _cancelVerificationListeners();
      }
    });

    // 2. localStorage storage event (same-origin cross-tab signal)
    if (kIsWeb) {
      _storageSub = html.window.onStorage
          .listen((html.StorageEvent event) {
        if (!mounted || _emailVerified) return;
        if (event.key == 'pn_verified_email') {
          final incoming = event.newValue ?? '';
          if (incoming.isNotEmpty &&
              incoming == (userEmail ?? '').toLowerCase().trim()) {
            _log.d('AccountScreen: emailVerified via storage event');
            setState(() => _emailVerified = true);
            _cancelVerificationListeners();
          }
        }
      });
    }

    // 3. Polling fallback (every 6 s)
    _verificationTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) async {
        if (!mounted || _emailVerified) {
          _cancelVerificationListeners();
          return;
        }

        // Check localStorage first — cheap, synchronous
        if (kIsWeb) {
          try {
            final stored =
                html.window.localStorage['pn_verified_email'] ?? '';
            if (stored.isNotEmpty &&
                stored == (userEmail ?? '').toLowerCase().trim()) {
              if (mounted) {
                _log.d('AccountScreen: emailVerified via poll localStorage');
                setState(() => _emailVerified = true);
              }
              _cancelVerificationListeners();
              return;
            }
          } catch (_) {}
        }

        // Firebase reload fallback
        final verified = await FirebaseService.reloadAndCheckEmailVerified();
        if (verified && mounted) {
          _log.d('AccountScreen: emailVerified via poll Firebase reload');
          setState(() => _emailVerified = true);
          _cancelVerificationListeners();
        }
      },
    );
  }

  void _cancelVerificationListeners() {
    _authStateSub?.cancel();
    _authStateSub = null;
    _storageSub?.cancel();
    _storageSub = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Role helpers
  // ─────────────────────────────────────────────────────────────────────────
  // Role is sourced exclusively from the Firestore Users collection
  // (streamed via RbacService.userRoleStream → _firestoreRole).
  // The API-fetched _roles list is intentionally NOT used as a fallback here
  // so that any stale or mismatched API value never overrides the Firestore truth.
  String get _effectiveRole => _firestoreRole ?? 'Tourist';
  bool get _isTourist => _effectiveRole == 'Tourist';
  bool get _isAdmin   => _effectiveRole == 'Admin' || _effectiveRole == 'MainAdmin';

  // ─────────────────────────────────────────────────────────────────────────
  // Admin Role Request
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleRequestAdminRole() async {
    if (_firebaseUid == null || _email == null) return;
    await _showAdminRequestSheet();
  }

  Future<void> _showAdminRequestSheet() async {
    final facilityCtrl  = TextEditingController();
    final serviceCtrl   = TextEditingController();
    final formKey       = GlobalKey<FormState>();
    final List<String>  services      = [];
    bool                agreedToTerms = false;
    bool                sheetLoading  = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetContainer(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const SizedBox(height: 24),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: Color(0xFFFF9800), size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Request Admin Access',
                            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('Complete the form below to apply',
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'Your request will be reviewed by a Main Administrator. '
                      'You will receive a notification when a decision is made.',
                      style: TextStyle(color: Color(0xFFFF9800), fontSize: 12, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Hotel / Place / Facility Name *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: facilityCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: _inputDecoration(hint: 'e.g. Sarova Whitesands Beach Resort',
                              icon: Icons.business_rounded),
                          validator: (v) => (v == null || v.trim().length < 3)
                              ? 'Please enter the facility name' : null,
                        ),
                        const SizedBox(height: 20),
                        _fieldLabel('Services Offered *'),
                        const SizedBox(height: 4),
                        Text('Add each service and press the + button or Enter.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextFormField(
                            controller: serviceCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: _inputDecoration(hint: 'e.g. Spa & Wellness', icon: Icons.room_service_rounded),
                            onFieldSubmitted: (v) {
                              final s = v.trim();
                              if (s.isNotEmpty && !services.contains(s)) {
                                setS(() => services.add(s)); serviceCtrl.clear();
                              }
                            },
                          )),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              final s = serviceCtrl.text.trim();
                              if (s.isNotEmpty && !services.contains(s)) {
                                setS(() => services.add(s)); serviceCtrl.clear();
                              }
                            },
                            child: Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFF14FFEC).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.35)),
                              ),
                              child: const Icon(Icons.add_rounded, color: Color(0xFF14FFEC), size: 22),
                            ),
                          ),
                        ]),
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 6,
                              children: services.map((s) => _serviceChipRemovable(s,
                                  onRemove: () => setS(() => services.remove(s)))).toList()),
                        ],
                        if (services.isEmpty)
                          Padding(padding: const EdgeInsets.only(top: 6),
                              child: Text('At least one service is required.',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11))),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: () => setS(() => agreedToTerms = !agreedToTerms),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: agreedToTerms ? const Color(0xFF14FFEC).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: agreedToTerms ? const Color(0xFF14FFEC) : Colors.white38, width: 1.5),
                              ),
                              child: agreedToTerms
                                  ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF14FFEC))
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(child: Text(
                              'I confirm that the information provided is accurate and '
                              'I agree to the Terms & Conditions for admin access on this platform.',
                              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                            )),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: sheetLoading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A1128)))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(sheetLoading ? 'Submitting…' : 'Submit Request'),
                      onPressed: sheetLoading ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        if (services.isEmpty) { if (mounted) _snack('Please add at least one service.', ok: false); return; }
                        if (!agreedToTerms) { if (mounted) _snack('Please agree to the Terms & Conditions.', ok: false); return; }
                        setS(() => sheetLoading = true);
                        final result = await RbacService.submitAdminRequest(
                          userId: _firebaseUid!, userEmail: _email!,
                          facilityName: facilityCtrl.text.trim(), servicesOffered: List.from(services),
                        );
                        if (!sheetCtx.mounted) return;
                        setS(() => sheetLoading = false);
                        Navigator.pop(sheetCtx);
                        if (mounted) _snack(result.message, ok: result.isSuccess);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC), foregroundColor: const Color(0xFF0A1128),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: TextButton(
                    onPressed: sheetLoading ? null : () => Navigator.pop(sheetCtx),
                    child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MFA handlers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleEnableMfa() async {
    await _showMfaEnrollmentSheet();
    if (mounted) await _loadUserInfo();
  }

  Future<void> _handleDisableMfa() async {
    final confirm = await _confirmDialog(
      icon: Icons.no_encryption_gmailerrorred_rounded, iconColor: RC.coral,
      title: 'Disable Phone MFA?',
      body: 'This removes the phone SMS two-factor step from your account. '
            'You can re-enable it at any time from this screen.',
      confirmLabel: 'Disable', confirmColor: RC.coral,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final factors = await FirebaseMfaService.fetchEnrolledFactors();
      if (factors.isEmpty) {
        if (mounted) setState(() => _actionLoading = false);
        _snack('No enrolled MFA factor found.', ok: false);
        return;
      }
      final result = await FirebaseMfaService.unenrollFactor(factors.first);
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (result.isSuccess) {
        _snack(result.message, ok: true);
        await _loadUserInfo();
      } else {
        _snack(result.message, ok: false);
      }
    } catch (e) {
      if (mounted) setState(() => _actionLoading = false);
      _snack('Could not disable MFA. Please try again.', ok: false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MFA Enrollment Sheet
  //
  // CHANGED: the "not verified" guard now calls _showEmailNotVerifiedSheet()
  // which offers to resend a verification link instead of just showing a
  // snack and stopping.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showMfaEnrollmentSheet() async {
    final emailVerified = await FirebaseService.reloadAndCheckEmailVerified();
    if (!emailVerified) {
      if (!mounted) return;
      await _showEmailNotVerifiedSheet();
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
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
                  const Icon(Icons.phone_android_rounded, color: Color(0xFF14FFEC), size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    smsSent ? 'Enter Verification Code' : 'Enable Phone Two-Factor Auth',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  )),
                ]),
                const SizedBox(height: 8),
                Text(
                  smsSent
                      ? 'Enter the 6-digit code sent to your phone.'
                      : 'Enter your phone number with country code (e.g. +254 712 345 678).',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),

                // Phase 1 — phone number
                if (!smsSent) ...[
                  Form(
                    key: phoneFormKey,
                    child: TextFormField(
                      controller: phoneController, keyboardType: TextInputType.phone,
                      enabled: !sheetLoading, style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(hint: '+254 712 345 678', icon: Icons.phone_outlined),
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
                        setS(() => sheetLoading = true);
                        final session = await FirebaseMfaService.getMultiFactorSession();
                        if (session == null) {
                          if (sheetCtx.mounted) { setS(() => sheetLoading = false); Navigator.pop(sheetCtx); }
                          if (mounted) _snack('Session expired. Please sign in again.', ok: false);
                          return;
                        }
                        await FirebaseMfaService.startEnrollment(
                          phoneNumber: phoneController.text.trim(), session: session,
                          onCodeSent: (vId, _) {
                            verificationId = vId;
                            if (sheetCtx.mounted) setS(() { sheetLoading = false; smsSent = true; });
                          },
                          onFailed: (e) {
                            if (sheetCtx.mounted) { setS(() => sheetLoading = false); Navigator.pop(sheetCtx); }
                            if (mounted) _snack(FirebaseMfaService.mapAuthErrorPublic(e), ok: false);
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC), foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                // Phase 2 — SMS code entry
                if (smsSent) ...[
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController, keyboardType: TextInputType.number,
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
                        setS(() => sheetLoading = true);
                        final r = await FirebaseMfaService.completeEnrollment(
                          verificationId: verificationId!, smsCode: otpController.text.trim(),
                        );
                        if (!sheetCtx.mounted) return;
                        setS(() => sheetLoading = false);
                        Navigator.pop(sheetCtx);
                        if (mounted) _snack(r.message, ok: r.isSuccess);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC), foregroundColor: const Color(0xFF1E3A5F),
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
                    onPressed: sheetLoading ? null : () => setS(() {
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

  // ─────────────────────────────────────────────────────────────────────────
  // Email Not Verified Sheet (shown when MFA enrollment is blocked)
  //
  // NEW: replaces the plain snack error with an actionable bottom sheet
  // that lets the user resend the verification link on the spot.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showEmailNotVerifiedSheet() async {
    if (!mounted) return;

    bool sending = false;
    bool sent    = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setS) => _sheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 24),

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCF6679).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.mark_email_unread_outlined, color: Color(0xFFCF6679), size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email Not Verified',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Verify your email to enable Phone MFA',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                )),
              ]),
              const SizedBox(height: 20),

              // Explanation
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFCF6679).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCF6679).withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Firebase requires a verified email address before you can enroll '
                  'phone two-factor authentication. We\'ll send a verification link to '
                  '${_email ?? 'your email address'}. Tap the link to verify and then '
                  'come back to enable MFA.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 20),

              // Success state
              if (sent) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF14FFEC), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Verification link sent! Check your inbox for ${_email ?? 'your email'} '
                      'and tap the link. Then return here and tap ⟳ Refresh.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Send / Resend button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: sending
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A5F)))
                      : Icon(sent ? Icons.refresh_rounded : Icons.send_rounded, size: 18),
                  label: Text(sending ? 'Sending…' : sent ? 'Resend Link' : 'Send Verification Link'),
                  onPressed: sending ? null : () async {
                    setS(() => sending = true);
                    final ok = await FirebaseService.sendEmailVerificationLink(emailOverride: _email);
                    setS(() { sending = false; sent = ok; });
                    if (!ok && mounted) {
                      _snack('Could not send verification link. Please try again.', ok: false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14FFEC), foregroundColor: const Color(0xFF1E3A5F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: Text('Close', style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
                ),
              ),
            ],
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
      icon: Icons.logout_rounded, iconColor: RC.coral,
      title: 'Sign Out?',
      body: 'You will be signed out of your account on this device.',
      confirmLabel: 'Sign Out', confirmColor: RC.coral,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    await NotificationService.stopAllListeners();
    await AuthService.logout();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LandingPage()), (route) => false);
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
              child: Center(child: CircularProgressIndicator(color: Color(0xFF14FFEC))),
            )
          else ...[
            SliverToBoxAdapter(child: _profileCard()),
            SliverToBoxAdapter(child: _securitySection()),
            if (_isTourist || (_adminRequest != null && !_isAdmin))
              SliverToBoxAdapter(child: _adminAccessSection()),
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
        backgroundColor: RC.navy, expandedHeight: 148, pinned: true, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: RC.teal),
            onPressed: _loading ? null : _loadUserInfo, tooltip: 'Refresh',
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
          title: const Text('My Account',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF071829), Color(0xFF0B2135)]),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 24, bottom: 56, top: 60),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF14FFEC).withValues(alpha: 0.30), blurRadius: 20)],
                  ),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Profile card
  //
  // CHANGED: the "Email Not Verified" badge is now tappable — tapping it
  // shows the email-not-verified sheet with the resend action.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _profileCard() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _iconCircle(Icons.email_outlined, RC.teal),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Email'),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Text(_email ?? '—',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (_email == null) return;
                          Clipboard.setData(ClipboardData(text: _email!));
                          _snack('Email copied!', ok: true);
                        },
                        child: const Icon(Icons.copy_rounded, size: 14, color: RC.textMute),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    // ── Tappable verification badge ──────────────────────
                    GestureDetector(
                      onTap: _emailVerified
                          ? null                          // already verified, no action
                          : _showEmailNotVerifiedSheet,  // prompt resend
                      child: _emailVerifiedBadge(),
                    ),
                    // Show a small hint below the badge when not verified
                    if (!_emailVerified) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _showEmailNotVerifiedSheet,
                        child: Text(
                          'Tap to resend verification link →',
                          style: TextStyle(
                              color: const Color(0xFFCF6679).withValues(alpha: 0.7),
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                )),
              ]),
              const SizedBox(height: 20),
              const _Divider(),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _iconCircle(Icons.badge_outlined, RC.gold),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Role'),
                    const SizedBox(height: 12),
                    _roleBadge(_effectiveRole),
                  ],
                )),
              ]),
            ],
          ),
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
              child: Text('SECURITY',
                  style: TextStyle(color: RC.textMute, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            ),
            Container(
              decoration: _cardDecoration(),
              child: _phoneMfaTile(),
            ),
          ],
        ),
      );

  Widget _phoneMfaTile() => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: _iconCircle(Icons.phone_android_rounded, _mfaEnabled ? RC.emerald : RC.teal),
        title: const Text('Phone Two-Factor Auth',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(
          _mfaEnabled
              ? 'Enabled — an SMS code is required at each sign-in'
              : 'Disabled — adds a phone SMS verification step at sign-in',
          style: const TextStyle(color: RC.textMute, fontSize: 12),
        ),
        trailing: _actionLoading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF14FFEC)))
            : Switch.adaptive(
                value: _mfaEnabled,
                onChanged: (enable) async {
                  enable ? await _handleEnableMfa() : await _handleDisableMfa();
                },
                activeThumbColor: RC.emerald,
                inactiveThumbColor: RC.textMute,
                inactiveTrackColor: RC.textMute.withValues(alpha: 0.28),
              ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Admin Access section
  // ─────────────────────────────────────────────────────────────────────────
  Widget _adminAccessSection() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 14),
              child: Text('ADMIN ACCESS',
                  style: TextStyle(color: RC.textMute, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            ),
            Container(decoration: _cardDecoration(), child: _adminRequestTile()),
          ],
        ),
      );

  Widget _adminRequestTile() {
    final req = _adminRequest;
    if (req == null) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _iconCircle(Icons.admin_panel_settings_rounded, const Color(0xFFFF9800)),
        title: const Text('Request Admin Role',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: const Text('Apply to manage places, content and more.',
            style: TextStyle(color: RC.textMute, fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: _handleRequestAdminRole,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800).withValues(alpha: 0.15),
            foregroundColor: const Color(0xFFFF9800), elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFFF9800), width: 1)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: const Text('Apply'),
        ),
      );
    }
    if (req.isPending) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _iconCircle(Icons.hourglass_top_rounded, const Color(0xFFFF9800)),
        title: const Text('Admin Request Pending',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text('Submitted for ${req.facilityName}', style: const TextStyle(color: RC.textMute, fontSize: 12)),
          const SizedBox(height: 6),
          _requestStatusBadge('UNDER REVIEW', const Color(0xFFFF9800)),
        ]),
        isThreeLine: true,
      );
    }
    if (req.isAccepted) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _iconCircle(Icons.verified_rounded, RC.emerald),
        title: Text('${req.grantedRole ?? 'Admin'} Role Granted',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text('Your request for ${req.facilityName} was approved.',
              style: const TextStyle(color: RC.textMute, fontSize: 12)),
          const SizedBox(height: 6),
          _requestStatusBadge('APPROVED', RC.emerald),
        ]),
        isThreeLine: true,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _iconCircle(Icons.cancel_outlined, RC.coral),
        title: const Text('Request Declined',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          if (req.denialReason != null)
            Text('Reason: ${req.denialReason}',
                style: const TextStyle(color: RC.textMute, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          _requestStatusBadge('DECLINED', RC.coral),
        ]),
        isThreeLine: true,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Submit a New Request'),
          onPressed: _handleRequestAdminRole,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF9800),
            side: const BorderSide(color: Color(0xFFFF9800), width: 1),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        )),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign-out button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _signOutBtn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            onPressed: _handleSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: RC.coral, side: const BorderSide(color: RC.coral),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers / small widgets
  // ─────────────────────────────────────────────────────────────────────────
  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: ok ? const Color(0xFF0D7377) : const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: ok ? 3 : 5),
    ));
  }

  Future<bool?> _confirmDialog({
    required IconData icon, required Color iconColor,
    required String title, required String body,
    required String confirmLabel, required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A5F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: iconColor), const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: Text(body,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

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
        Icon(ok ? Icons.verified_rounded : Icons.warning_amber_rounded, size: 11, color: color),
        const SizedBox(width: 4),
        Text(ok ? 'Email Verified' : 'Email Not Verified',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        if (!ok) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 11, color: color.withValues(alpha: 0.7)),
        ],
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
        child: Text(role.toUpperCase(),
            style: const TextStyle(color: RC.gold, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _requestStatusBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
      );

  Widget _serviceChipRemovable(String label, {required VoidCallback onRemove}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Color(0xFF14FFEC), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(onTap: onRemove,
              child: const Icon(Icons.close_rounded, size: 13, color: Color(0xFF14FFEC))),
        ]),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: RC.surface, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      );

  Widget _iconCircle(IconData icon, Color color) => Container(
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: RC.textMute, fontSize: 11, letterSpacing: 0.5));

  Widget _fieldLabel(String text) => Text(text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600));

  InputDecoration _inputDecoration({required String hint, required IconData icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true, fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF14FFEC), width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5)),
        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _sheetContainer({required Widget child}) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
        child: child,
      );

  Widget _sheetHandle() => Center(child: Container(
        width: 44, height: 4,
        decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
      ));
}

// ─────────────────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Color(0xFF1A3550), height: 1);
}