import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';   // AppUser, AuthService
import 'package:palmnazi/screens/landing_page.dart';  // RC colour tokens + LandingPage
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_mfa_service.dart';
import 'package:palmnazi/services/firebase_service.dart';
import 'package:palmnazi/services/notification_service.dart';
import 'package:palmnazi/services/rbac_service.dart';

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
  List<String>  _roles         = [];
  bool          _emailVerified = false;
  bool          _mfaEnabled    = false;

  // ── RBAC state ─────────────────────────────────────────────────────────────
  String?        _firestoreRole;   // live role from Firestore Users doc
  AdminRequest?  _adminRequest;    // user's most recent request (any status)

  // ── Loading flags ──────────────────────────────────────────────────────────
  bool _loading       = true;
  bool _actionLoading = false;

  // ── Firestore live listeners ───────────────────────────────────────────────
  StreamSubscription<String>?       _roleSub;
  StreamSubscription<AdminRequest?>? _requestSub;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    _requestSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loaders
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final email  = await ApiClient.getEmail();
      final userId = await ApiClient.getUserId();
      final roles  = await ApiClient.getRoles();

      bool mfaEnabled = false;
      try {
        final meResp = await ApiClient.authGet(ApiEndpoints.me);
        if (meResp.statusCode == 200) {
          final meBody = ApiClient.parseBody(meResp);
          final userMap = (meBody['user'] as Map<String, dynamic>?) ?? meBody;
          mfaEnabled = (userMap['mfaEnabled'] as bool?) ?? false;
        }
      } catch (e) {
        _log.w('⚠️ AccountScreen._loadUserInfo: Could not fetch /me for MFA: $e');
      }

      final fbUser = FirebaseService.currentUser;
      if (fbUser != null) {
        try { await fbUser.reload(); } catch (_) {}
      }
      final emailVerified = FirebaseService.currentUser?.emailVerified ?? false;

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

      // ── Start live RBAC listeners ──────────────────────────────────────────
      // IMPORTANT: Firestore security rules require the caller to be signed in
      // via Firebase Auth.  We must wait until a Firebase Auth user is present
      // before opening any Firestore stream, otherwise the SDK sends the
      // request unauthenticated and the rules engine returns
      // [cloud_firestore/permission-denied].
      //
      // FirebaseService.currentUser can be null for a brief window after the
      // custom-API session is restored but before the Firebase Auth mirror
      // completes.  Polling here (max ~3 s) avoids that race without
      // restructuring the entire auth flow.
      // Use the Firebase Auth uid — NOT the custom API userId — as the key
      // for all Firestore operations.  RbacService document paths and security
      // rules both anchor on Firebase uid (request.auth.uid).
      final firebaseUid = FirebaseService.currentUser?.uid;
      if (userId != null && firebaseUid != null) {
        // _waitForFirebaseAuth() already confirmed currentUser is non-null above,
        // but we re-read it here to have the uid value in scope.
        if (mounted) _startRbacListeners(firebaseUid);
      } else if (userId != null) {
        await _waitForFirebaseAuth();
        final fbUid = FirebaseService.currentUser?.uid;
        if (fbUid != null && mounted) _startRbacListeners(fbUid);
      }
    } catch (e, st) {
      _log.e('❌ AccountScreen._loadUserInfo: Error', error: e, stackTrace: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Wait until Firebase Auth has a signed-in user (max 3 s).
  //
  // WHY THIS EXISTS
  // On session restore, the custom-API tokens are loaded from secure storage
  // first (synchronous), then FirebaseSessionService mirrors the sign-in to
  // Firebase Auth (async network call).  There is a short window where
  // ApiClient already has a userId but FirebaseService.currentUser is still
  // null.  Opening a Firestore stream in that window produces a
  // [cloud_firestore/permission-denied] error because the Firebase SDK has
  // no auth token to attach to the request.
  //
  // Polling with a 200 ms tick is cheap and safe: the await only happens
  // once per session, during the _loadUserInfo() call in initState().
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _waitForFirebaseAuth({int maxWaitMs = 3000}) async {
    const tickMs = 200;
    int waited = 0;
    while (FirebaseService.currentUser == null && waited < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
      waited += tickMs;
    }
    if (FirebaseService.currentUser == null) {
      _log.w(
        '⚠️ AccountScreen._waitForFirebaseAuth: Firebase Auth user still null '
        'after ${maxWaitMs}ms — Firestore streams may be denied.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start Firestore listeners for role + request status
  // ─────────────────────────────────────────────────────────────────────────
  // firebaseUid — the Firebase Auth uid (NOT the custom API userId).
  // RbacService uses this as the Firestore document key and the identity
  // anchor checked by security rules.
  void _startRbacListeners(String firebaseUid) {
    _roleSub?.cancel();
    _requestSub?.cancel();

    // Live role listener — reads Users/{firebaseUid}
    _roleSub = RbacService.userRoleStream(firebaseUid).listen(
      (role) {
        if (mounted) setState(() => _firestoreRole = role);
      },
      onError: (e) => _log.w('⚠️ AccountScreen: role stream error — $e'),
    );

    // Live request listener — queries AdminRequests where firebaseUid matches
    _requestSub = RbacService.userRequestStream(firebaseUid).listen(
      (req) {
        if (mounted) setState(() => _adminRequest = req);
      },
      onError: (e) => _log.w('⚠️ AccountScreen: request stream error — $e'),
    );

    // Start notification listener using the Firebase uid, which is what
    // RbacService.userRequestStream() actually queries on internally.
    // (The custom API _userId is irrelevant to the Firestore query.)
    NotificationService.startUserRequestListener(firebaseUid);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Determine effective role (Firestore is authoritative; API roles as fallback)
  //
  // WHY toLowerCase():
  // The custom API JWT returns roles in ALL-CAPS (e.g. "TOURIST", "ADMIN")
  // while Firestore stores them in title-case ("Tourist", "Admin", "MainAdmin").
  // Normalising both sides to lowercase makes the comparison robust regardless
  // of which source is active at any given moment.
  // ─────────────────────────────────────────────────────────────────────────
  String get _effectiveRole =>
      (_firestoreRole ?? (_roles.isNotEmpty ? _roles.first : 'Tourist'))
          .toLowerCase();

  bool get _isTourist => _effectiveRole == 'tourist';
  bool get _isAdmin   => _effectiveRole == 'admin' || _effectiveRole == 'mainadmin';

  // ─────────────────────────────────────────────────────────────────────────
  // Admin Role Request handler — opens the request sheet
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleRequestAdminRole() async {
    if (_userId == null || _email == null) return;
    await _showAdminRequestSheet();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Admin Request bottom sheet (multi-step form)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showAdminRequestSheet() async {
    final facilityCtrl  = TextEditingController();
    final serviceCtrl   = TextEditingController();
    final formKey       = GlobalKey<FormState>();
    final List<String>  services      = [];
    bool                agreedToTerms = false;
    bool                sheetLoading  = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

                  // ── Header ─────────────────────────────────────────────
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Request Admin Access',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                          Text('Complete the form below to apply',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'Your request will be reviewed by a Main Administrator. '
                      'You will receive a notification when a decision is made.',
                      style: TextStyle(
                          color: Color(0xFFFF9800), fontSize: 12, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Form ───────────────────────────────────────────────
                  Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Facility name
                        _fieldLabel('Hotel / Place / Facility Name *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: facilityCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: _inputDecoration(
                            hint: 'e.g. Sarova Whitesands Beach Resort',
                            icon: Icons.business_rounded,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().length < 3)
                                  ? 'Please enter the facility name'
                                  : null,
                        ),
                        const SizedBox(height: 20),

                        // Services offered
                        _fieldLabel('Services Offered *'),
                        const SizedBox(height: 4),
                        Text(
                          'Add each service and press the + button or Enter.',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: serviceCtrl,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                              decoration: _inputDecoration(
                                hint: 'e.g. Spa & Wellness',
                                icon: Icons.room_service_rounded,
                              ),
                              onFieldSubmitted: (v) {
                                final s = v.trim();
                                if (s.isNotEmpty && !services.contains(s)) {
                                  setS(() => services.add(s));
                                  serviceCtrl.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              final s = serviceCtrl.text.trim();
                              if (s.isNotEmpty && !services.contains(s)) {
                                setS(() => services.add(s));
                                serviceCtrl.clear();
                              }
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFF14FFEC)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF14FFEC)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: const Icon(Icons.add_rounded,
                                  color: Color(0xFF14FFEC), size: 22),
                            ),
                          ),
                        ]),
                        // Services chips
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: services
                                .map((s) => _serviceChipRemovable(
                                      s,
                                      onRemove: () => setS(() => services.remove(s)),
                                    ))
                                .toList(),
                          ),
                        ],
                        if (services.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'At least one service is required.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 11),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Terms & Conditions
                        GestureDetector(
                          onTap: () =>
                              setS(() => agreedToTerms = !agreedToTerms),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: agreedToTerms
                                      ? const Color(0xFF14FFEC)
                                          .withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: agreedToTerms
                                        ? const Color(0xFF14FFEC)
                                        : Colors.white38,
                                    width: 1.5,
                                  ),
                                ),
                                child: agreedToTerms
                                    ? const Icon(Icons.check_rounded,
                                        size: 14,
                                        color: Color(0xFF14FFEC))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'I confirm that the information provided is accurate and I agree to the Terms & Conditions for admin access on this platform.',
                                  style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                      height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Submit button ──────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: sheetLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0A1128)),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                          sheetLoading ? 'Submitting…' : 'Submit Request'),
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              // Validate form fields
                              if (!formKey.currentState!.validate()) return;

                              // Validate services
                              if (services.isEmpty) {
                                if (mounted) {
                                  _snack(
                                    'Please add at least one service.',
                                    ok: false,
                                  );
                                }
                                return;
                              }

                              // Validate terms
                              if (!agreedToTerms) {
                                if (mounted) {
                                  _snack(
                                    'Please agree to the Terms & Conditions.',
                                    ok: false,
                                  );
                                }
                                return;
                              }

                              setS(() => sheetLoading = true);

                              final result =
                                  await RbacService.submitAdminRequest(
                                userId:          _userId!,
                                userEmail:       _email!,
                                facilityName:    facilityCtrl.text.trim(),
                                servicesOffered: List.from(services),
                              );

                              if (!sheetCtx.mounted) return;
                              setS(() => sheetLoading = false);
                              Navigator.pop(sheetCtx);

                              if (mounted) {
                                _snack(result.message, ok: result.isSuccess);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF0A1128),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: sheetLoading
                          ? null
                          : () => Navigator.pop(sheetCtx),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MFA handlers (unchanged from original)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleEnableMfa() async {
    await _showMfaEnrollmentSheet();
    if (mounted) await _loadUserInfo();
  }

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

    try {
      final result = await FirebaseMfaService.disableMfa();
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (result.isSuccess) {
        _snack('Email MFA has been disabled.', ok: true);
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
  // Email OTP MFA Enrollment Sheet (unchanged from original)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showMfaEnrollmentSheet() async {
    final email = _email ?? '';
    if (email.isEmpty) {
      _snack('No email address found. Please sign in again.', ok: false);
      return;
    }

    final otpController = TextEditingController();
    final otpFormKey    = GlobalKey<FormState>();
    bool  sheetLoading  = false;
    bool  otpSent       = false;

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
                  const Icon(Icons.email_outlined,
                      color: Color(0xFF14FFEC), size: 28),
                  const SizedBox(width: 12),
                  Text(
                    otpSent ? 'Enter Verification Code' : 'Enable Email MFA',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
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
                      height: 1.4),
                ),
                const SizedBox(height: 24),

                if (!otpSent) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: sheetLoading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF1E3A5F)))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                          sheetLoading ? 'Sending…' : 'Send Code to Email'),
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              setS(() => sheetLoading = true);
                              try {
                                final result =
                                    await FirebaseMfaService.sendOtp(
                                        email: email);
                                if (!sheetCtx.mounted) return;
                                setS(() => sheetLoading = false);
                                if (result.isSuccess) {
                                  setS(() => otpSent = true);
                                } else {
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx);
                                  }
                                  if (mounted) {
                                    _snack(result.message, ok: false);
                                  }
                                }
                              } catch (e) {
                                if (sheetCtx.mounted) {
                                  setS(() => sheetLoading = false);
                                  Navigator.pop(sheetCtx);
                                }
                                if (mounted) {
                                  _snack('Could not send code. Please try again.',
                                      ok: false);
                                }
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

                if (otpSent) ...[
                  Form(
                    key: otpFormKey,
                    child: TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !sheetLoading,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          letterSpacing: 10),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            letterSpacing: 8),
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
                      validator: (v) =>
                          (v == null || v.trim().length < 4)
                              ? 'Enter the code from your email'
                              : null,
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
                              try {
                                final result =
                                    await FirebaseMfaService.verifyOtp(
                                        otp: otpController.text.trim());
                                if (!sheetCtx.mounted) return;
                                setS(() => sheetLoading = false);
                                Navigator.pop(sheetCtx);
                                if (!mounted) return;
                                _snack(result.message, ok: result.isSuccess);
                              } catch (e) {
                                if (sheetCtx.mounted) {
                                  setS(() => sheetLoading = false);
                                  Navigator.pop(sheetCtx);
                                }
                                if (mounted) {
                                  _snack(
                                      'Verification failed. Please try again.',
                                      ok: false);
                                }
                              }
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
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF1E3A5F)))
                          : const Text('Confirm & Enable MFA',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: sheetLoading
                          ? null
                          : () async {
                              setS(() => sheetLoading = true);
                              await FirebaseMfaService.sendOtp(email: email);
                              setS(() => sheetLoading = false);
                              if (mounted) {
                                _snack('A new code has been sent to $email.',
                                    ok: true);
                              }
                            },
                      icon: const Icon(Icons.refresh_rounded,
                          color: Color(0xFF14FFEC), size: 16),
                      label: const Text('Resend code',
                          style: TextStyle(
                              color: Color(0xFF14FFEC), fontSize: 13)),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: sheetLoading
                        ? null
                        : () => Navigator.pop(sheetCtx),
                    child: Text('Skip for now',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13)),
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

    // Stop notification listeners before sign-out
    await NotificationService.stopAllListeners();
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
                  child: CircularProgressIndicator(
                      color: Color(0xFF14FFEC))),
            )
          else ...[
            SliverToBoxAdapter(child: _profileCard()),
            SliverToBoxAdapter(child: _securitySection()),
            // ── Admin Access section (Tourist-only) ───────────────────────
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
  // Admin Access section — shown only for Tourist role users
  // ─────────────────────────────────────────────────────────────────────────
  Widget _adminAccessSection() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                'ADMIN ACCESS',
                style: TextStyle(
                    color: RC.textMute,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4),
              ),
            ),
            Container(
              decoration: _cardDecoration(),
              child: _adminRequestTile(),
            ),
          ],
        ),
      );

  Widget _adminRequestTile() {
    final req = _adminRequest;

    // ── No existing request — show "Request Access" CTA ──────────────────
    if (req == null) {
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _iconCircle(
            Icons.admin_panel_settings_rounded, const Color(0xFFFF9800)),
        title: const Text('Request Admin Role',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: const Text(
          'Apply to manage places, content and more.',
          style: TextStyle(color: RC.textMute, fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: _handleRequestAdminRole,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800).withValues(alpha: 0.15),
            foregroundColor: const Color(0xFFFF9800),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(
                    color: Color(0xFFFF9800), width: 1)),
            textStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: const Text('Apply'),
        ),
      );
    }

    // ── Pending request ───────────────────────────────────────────────────
    if (req.isPending) {
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading:
            _iconCircle(Icons.hourglass_top_rounded, const Color(0xFFFF9800)),
        title: const Text('Admin Request Pending',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Submitted for ${req.facilityName}',
              style: const TextStyle(color: RC.textMute, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _requestStatusBadge('UNDER REVIEW', const Color(0xFFFF9800)),
          ],
        ),
        isThreeLine: true,
      );
    }

    // ── Accepted request ──────────────────────────────────────────────────
    if (req.isAccepted) {
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading:
            _iconCircle(Icons.verified_rounded, RC.emerald),
        title: Text('${req.grantedRole ?? 'Admin'} Role Granted',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Your request for ${req.facilityName} was approved.',
              style: const TextStyle(color: RC.textMute, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _requestStatusBadge('APPROVED', RC.emerald),
          ],
        ),
        isThreeLine: true,
      );
    }

    // ── Denied request — allow re-application ─────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          leading: _iconCircle(Icons.cancel_outlined, RC.coral),
          title: const Text('Request Declined',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              if (req.denialReason != null)
                Text(
                  'Reason: ${req.denialReason}',
                  style: const TextStyle(color: RC.textMute, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              _requestStatusBadge('DECLINED', RC.coral),
            ],
          ),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Submit a New Request'),
              onPressed: _handleRequestAdminRole,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF9800),
                side: const BorderSide(
                    color: Color(0xFFFF9800), width: 1),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // App bar (unchanged from original)
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
              padding: const EdgeInsets.only(right: 24, bottom: 56, top: 60),
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
  // Profile card (unchanged from original)
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
                            Clipboard.setData(
                                ClipboardData(text: _email!));
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
              Row(children: [
                _iconCircle(Icons.badge_outlined, RC.gold),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Role'),
                      const SizedBox(height: 8),
                      _roleBadge(_effectiveRole),
                    ],
                  ),
                ),
              ]),
              const _Divider(),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Security section (unchanged from original)
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
              child: _emailOtpMfaTile(),
            ),
          ],
        ),
      );

  Widget _emailOtpMfaTile() => ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: _iconCircle(
          Icons.email_outlined,
          _mfaEnabled ? RC.emerald : RC.teal,
        ),
        title: const Text('Email Two-Factor Auth',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
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
                inactiveTrackColor:
                    RC.textMute.withValues(alpha: 0.28),
              ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Sign-out button (unchanged from original)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _signOutBtn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign Out',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
        ]),
        content: Text(body,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                height: 1.5)),
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

  // ── Small reusable pieces ──────────────────────────────────────────────────

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
          size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          ok ? 'Email Verified' : 'Email Not Verified',
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
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

  Widget _requestStatusBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6),
        ),
      );

  Widget _serviceChipRemovable(String label,
          {required VoidCallback onRemove}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF14FFEC),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 13, color: Color(0xFF14FFEC)),
          ),
        ]),
      );

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

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: RC.textMute, fontSize: 11, letterSpacing: 0.5));

  Widget _fieldLabel(String text) => Text(text,
      style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w600));

  InputDecoration _inputDecoration({
    required String   hint,
    required IconData icon,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled:    true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFF14FFEC), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFFCF6679), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFCF6679)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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