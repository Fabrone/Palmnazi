import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logger
// ─────────────────────────────────────────────────────────────────────────────
final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0, errorMethodCount: 8, lineLength: 100,
    colors: true, printEmojis: true,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Palette — matches admin_dashboard.dart
// ─────────────────────────────────────────────────────────────────────────────
const _kSurface = Color(0xFF111827);
const _kTeal    = Color(0xFF14FFEC);
const _kOrange  = Color(0xFFFF9800);
const _kGreen   = Color(0xFF00C853);
const _kRed     = Color(0xFFCF6679);

// ─────────────────────────────────────────────────────────────────────────────
// AdminRoleRequestsScreen
//
// Visible only to MainAdmin (routing guard lives in AdminDashboard).
// Streams the entire AdminRequests collection ordered by newest first.
//
// Actions (MainAdmin only):
//   Approve — picks Admin | MainAdmin role; batch-writes to AdminRequests
//             AND Users/{firebaseUid} in a single Firestore commit.
//   Deny    — optional free-text reason; updates AdminRequests only.
//   Revoke  — resets an already-accepted request back to denied and strips
//             the role from Users/{firebaseUid}.
// ─────────────────────────────────────────────────────────────────────────────
class AdminRoleRequestsScreen extends StatefulWidget {
  const AdminRoleRequestsScreen({super.key});

  @override
  State<AdminRoleRequestsScreen> createState() => _AdminRoleRequestsScreenState();
}

class _AdminRoleRequestsScreenState extends State<AdminRoleRequestsScreen>
    with SingleTickerProviderStateMixin {

  late TabController       _tabs;
  List<AdminRequest>       _requests  = [];
  bool                     _loading   = true;
  String?                  _error;
  StreamSubscription?      _sub;
  final Set<String>        _actioning = {};   // request IDs currently awaiting a write

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _subscribe();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _sub?.cancel();
    super.dispose();
  }

  // ── Firestore real-time stream ─────────────────────────────────────────────
  void _subscribe() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('AdminRequests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _requests = snap.docs
              .map((d) => AdminRequest.fromFirestore(d))
              .toList();
          _loading = false;
          _error   = null;
        });
      },
      onError: (Object e) {
        _log.e('❌ [AdminRoleRequestsScreen] stream error', error: e);
        if (mounted) setState(() { _loading = false; _error = e.toString(); });
      },
    );
  }

  // ── Filtered list for the active tab ──────────────────────────────────────
  List<AdminRequest> get _visible {
    switch (_tabs.index) {
      case 1:  return _requests.where((r) => r.isPending).toList();
      case 2:  return _requests.where((r) => r.isAccepted).toList();
      case 3:  return _requests.where((r) => r.isDenied).toList();
      default: return _requests;
    }
  }

  int get _pendingCount  => _requests.where((r) => r.isPending).length;
  int get _acceptedCount => _requests.where((r) => r.isAccepted).length;
  int get _deniedCount   => _requests.where((r) => r.isDenied).length;

  // ── Approve ────────────────────────────────────────────────────────────────
  Future<void> _onApprove(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack('Cannot approve: user Firebase UID is missing from this request.', ok: false);
      return;
    }

    final role = await _showApproveSheet(req);
    if (role == null || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      final me  = FirebaseAuth.instance.currentUser;
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      // 1. Update the AdminRequests document
      batch.update(
        FirebaseFirestore.instance.collection('AdminRequests').doc(req.id),
        {
          'status':           'accepted',
          'grantedRole':      role,
          'respondedAt':      now,
          'respondedBy':      me?.uid  ?? '',
          'respondedByEmail': me?.email ?? '',
          // Clear any previous denial reason
          'denialReason':     FieldValue.delete(),
        },
      );

      // 2. Elevate the user's role in the Users collection
      batch.update(
        FirebaseFirestore.instance.collection('Users').doc(req.firebaseUid),
        {'role': role},
      );

      await batch.commit();
      _log.i('✅ [AdminRoleRequestsScreen] Approved ${req.userEmail} as $role');
      if (mounted) _snack('${req.userEmail} approved as $role.', ok: true);
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Approve failed', error: e);
      if (mounted) _snack('Approval failed. Please try again.', ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Deny ───────────────────────────────────────────────────────────────────
  Future<void> _onDeny(AdminRequest req) async {
    final reason = await _showDenySheet(req);
    if (reason == null || !mounted) return;   // null = sheet dismissed

    setState(() => _actioning.add(req.id));
    try {
      final me = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('AdminRequests')
          .doc(req.id)
          .update({
        'status':           'denied',
        if (reason.trim().isNotEmpty) 'denialReason': reason.trim(),
        'respondedAt':      Timestamp.now(),
        'respondedBy':      me?.uid  ?? '',
        'respondedByEmail': me?.email ?? '',
        // Clear any previous granted role
        'grantedRole':      FieldValue.delete(),
      });
      _log.i('✅ [AdminRoleRequestsScreen] Denied ${req.userEmail}');
      if (mounted) _snack('Request from ${req.userEmail} declined.', ok: false);
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Deny failed', error: e);
      if (mounted) _snack('Action failed. Please try again.', ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Revoke (accepted → Tourist) ────────────────────────────────────────────
  Future<void> _onRevoke(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack('Cannot revoke: user Firebase UID is missing.', ok: false);
      return;
    }

    final confirm = await _confirmDialog(
      icon:         Icons.remove_moderator_rounded,
      iconColor:    _kOrange,
      title:        'Revoke Admin Role?',
      body:         'This will remove the ${req.grantedRole ?? "Admin"} role from '
                    '${req.userEmail} and reset their account to Tourist level. '
                    'They can re-apply at any time.',
      confirmLabel: 'Revoke',
      confirmColor: _kOrange,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      final me  = FirebaseAuth.instance.currentUser;
      final batch = FirebaseFirestore.instance.batch();

      // Mark the request as denied / revoked
      batch.update(
        FirebaseFirestore.instance.collection('AdminRequests').doc(req.id),
        {
          'status':           'denied',
          'denialReason':     'Role revoked by administrator.',
          'grantedRole':      FieldValue.delete(),
          'respondedAt':      Timestamp.now(),
          'respondedBy':      me?.uid  ?? '',
          'respondedByEmail': me?.email ?? '',
        },
      );

      // Reset the user's role to Tourist
      batch.update(
        FirebaseFirestore.instance.collection('Users').doc(req.firebaseUid),
        {'role': 'Tourist'},
      );

      await batch.commit();
      _log.i('✅ [AdminRoleRequestsScreen] Revoked role for ${req.userEmail}');
      if (mounted) _snack('Role revoked for ${req.userEmail}.', ok: false);
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Revoke failed', error: e);
      if (mounted) _snack('Revoke failed. Please try again.', ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryBar(
          total:    _requests.length,
          pending:  _pendingCount,
          accepted: _acceptedCount,
          denied:   _deniedCount,
        ),
        _buildTabBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kTeal))
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _subscribe)
                  : _buildList(),
        ),
      ],
    );
  }

  Widget _buildTabBar() => Container(
        color: _kSurface,
        child: TabBar(
          controller: _tabs,
          indicatorColor:        _kTeal,
          labelColor:            _kTeal,
          unselectedLabelColor:  Colors.white38,
          labelStyle:            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle:  const TextStyle(fontSize: 12),
          tabs: [
            const Tab(text: 'All'),
            Tab(text: _pendingCount  > 0 ? 'Pending ($_pendingCount)'   : 'Pending'),
            Tab(text: _acceptedCount > 0 ? 'Approved ($_acceptedCount)' : 'Approved'),
            Tab(text: _deniedCount   > 0 ? 'Denied ($_deniedCount)'     : 'Denied'),
          ],
        ),
      );

  Widget _buildList() {
    final items = _visible;
    if (items.isEmpty) return _EmptyState(tabIndex: _tabs.index);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _RequestCard(
        request:    items[i],
        isActioning: _actioning.contains(items[i].id),
        onApprove:  () => _onApprove(items[i]),
        onDeny:     () => _onDeny(items[i]),
        onRevoke:   () => _onRevoke(items[i]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Approve Bottom Sheet — role selector
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showApproveSheet(AdminRequest req) {
    String selected = 'Admin';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _sheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 24),

              // Title
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: _kGreen, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Approve Request',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(req.userEmail,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ],
                )),
              ]),
              const SizedBox(height: 16),

              // Info notice
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Approving will grant the selected role and immediately update '
                  '${req.userEmail}\'s access across the platform.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              Text('Select Role to Grant',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              _RoleOption(
                role:        'Admin',
                description: 'Can manage places, listings, blog, and content.',
                isSelected:  selected == 'Admin',
                onTap:       () => setS(() => selected = 'Admin'),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                role:        'MainAdmin',
                description: 'Full system access including user role management.',
                isSelected:  selected == 'MainAdmin',
                onTap:       () => setS(() => selected = 'MainAdmin'),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon:  const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text('Approve as $selected'),
                  onPressed: () => Navigator.pop(ctx, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: const Color(0xFF0A1128),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Deny Bottom Sheet — optional reason field
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showDenySheet(AdminRequest req) {
    final ctrl = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _sheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 24),

              // Title
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cancel_rounded, color: _kRed, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Decline Request',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(req.userEmail,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ],
                )),
              ]),
              const SizedBox(height: 16),

              // Warning notice
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kRed.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'The user will be notified that their admin request for '
                  '"${req.facilityName}" has been declined.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              // Reason field
              Text('Reason for Denial (optional)',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Insufficient supporting documentation.',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kRed, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon:  const Icon(Icons.do_not_disturb_rounded, size: 18),
                  label: const Text('Decline Request'),
                  // Return the reason text (may be empty); null = cancel
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () => Navigator.pop(ctx),    // null → caller treats as cancel
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Confirm dialog ─────────────────────────────────────────────────────────
  Future<bool?> _confirmDialog({
    required IconData icon,
    required Color    iconColor,
    required String   title,
    required String   body,
    required String   confirmLabel,
    required Color    confirmColor,
  }) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E3A5F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Flexible(child: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
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
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  // ── Snack ──────────────────────────────────────────────────────────────────
  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
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

  // ── Sheet helpers ──────────────────────────────────────────────────────────
  Widget _sheetContainer({required Widget child}) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)],
          ),
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
// Summary Bar — live counts at the top of the screen
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryBar extends StatelessWidget {
  final int total, pending, accepted, denied;

  const _SummaryBar({
    required this.total,
    required this.pending,
    required this.accepted,
    required this.denied,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kSurface,
          border: const Border(bottom: BorderSide(color: Color(0xFF1F2937))),
        ),
        child: Wrap(
          spacing: 8, runSpacing: 6,
          children: [
            _StatPill(label: 'Total',    count: total,    color: Colors.white54),
            _StatPill(label: 'Pending',  count: pending,  color: _kOrange),
            _StatPill(label: 'Approved', count: accepted, color: _kGreen),
            _StatPill(label: 'Denied',   count: denied,   color: _kRed),
          ],
        ),
      );
}

class _StatPill extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;

  const _StatPill({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$label: $count',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Request Card
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final AdminRequest request;
  final bool         isActioning;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onRevoke;

  const _RequestCard({
    required this.request,
    required this.isActioning,
    required this.onApprove,
    required this.onDeny,
    required this.onRevoke,
  });

  // Status-driven theming
  Color get _statusColor {
    if (request.isPending)  return _kOrange;
    if (request.isAccepted) return _kGreen;
    return _kRed;
  }

  String get _statusLabel {
    if (request.isPending)  return 'PENDING';
    if (request.isAccepted) return 'APPROVED';
    return 'DECLINED';
  }

  IconData get _statusIcon {
    if (request.isPending)  return Icons.hourglass_top_rounded;
    if (request.isAccepted) return Icons.verified_rounded;
    return Icons.cancel_rounded;
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}  '
        '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ────────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.userEmail,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(request.facilityName,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ],
              )),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.35)),
                ),
                child: Text(_statusLabel,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
            ]),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1F2937), height: 1),
            const SizedBox(height: 14),

            // ── Services ──────────────────────────────────────────────────
            if (request.servicesOffered.isNotEmpty) ...[
              const Text('SERVICES OFFERED',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: request.servicesOffered
                    .map((s) => _ServiceTag(label: s))
                    .toList(),
              ),
              const SizedBox(height: 14),
            ],

            // ── Meta row ──────────────────────────────────────────────────
            Wrap(spacing: 14, runSpacing: 4, children: [
              _Meta(Icons.schedule_rounded, 'Submitted: ${_fmt(request.createdAt)}'),
              if (request.respondedAt != null)
                _Meta(
                  request.isAccepted
                      ? Icons.check_circle_outline_rounded
                      : Icons.block_rounded,
                  '${request.isAccepted ? "Approved" : "Denied"}: ${_fmt(request.respondedAt)}',
                ),
              if (request.respondedByEmail != null)
                _Meta(Icons.admin_panel_settings_rounded,
                    'By: ${request.respondedByEmail}'),
              if (request.grantedRole != null)
                _Meta(Icons.badge_rounded, 'Role: ${request.grantedRole}'),
            ]),

            // ── Denial reason box ─────────────────────────────────────────
            if (request.isDenied && request.denialReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kRed.withValues(alpha: 0.22)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, size: 13, color: _kRed),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Reason: ${request.denialReason}',
                    style: const TextStyle(color: _kRed, fontSize: 11, height: 1.4),
                  )),
                ]),
              ),
            ],

            // ── Action buttons ────────────────────────────────────────────
            if (request.isPending || request.isAccepted) ...[
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF1F2937), height: 1),
              const SizedBox(height: 12),
              if (isActioning)
                const Center(child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kTeal),
                ))
              else if (request.isPending)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon:  const Icon(Icons.close_rounded, size: 14),
                      label: const Text('Decline'),
                      onPressed: onDeny,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: BorderSide(color: _kRed.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon:  const Icon(Icons.check_rounded, size: 14),
                      label: const Text('Approve'),
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: const Color(0xFF0A1128),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ])
              else if (request.isAccepted)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon:  const Icon(Icons.remove_moderator_rounded, size: 14),
                    label: const Text('Revoke Role'),
                    onPressed: onRevoke,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kOrange,
                      side: BorderSide(color: _kOrange.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small supporting widgets
// ─────────────────────────────────────────────────────────────────────────────
class _ServiceTag extends StatelessWidget {
  final String label;
  const _ServiceTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _kTeal.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kTeal.withValues(alpha: 0.22)),
        ),
        child: Text(label,
            style: const TextStyle(color: _kTeal, fontSize: 11)),
      );
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: Colors.white38),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Option — radio-style selector inside the approve sheet
// ─────────────────────────────────────────────────────────────────────────────
class _RoleOption extends StatelessWidget {
  final String       role;
  final String       description;
  final bool         isSelected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.role,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? _kGreen.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? _kGreen.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(children: [
            // Radio dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? _kGreen.withValues(alpha: 0.20)
                    : Colors.transparent,
                border: Border.all(
                    color: isSelected ? _kGreen : Colors.white38, width: 1.5),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 10, color: _kGreen)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role,
                    style: TextStyle(
                        color: isSelected ? _kGreen : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        height: 1.4)),
              ],
            )),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final int tabIndex;
  const _EmptyState({required this.tabIndex});

  static const _labels = ['requests', 'pending requests', 'approved requests', 'declined requests'];
  static const _icons  = [
    Icons.inbox_rounded,
    Icons.hourglass_empty_rounded,
    Icons.verified_rounded,
    Icons.remove_circle_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final label = tabIndex < _labels.length ? _labels[tabIndex] : 'requests';
    final icon  = tabIndex < _icons.length  ? _icons[tabIndex]  : Icons.inbox_rounded;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: Colors.white12),
        const SizedBox(height: 16),
        Text('No $label',
            style: const TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text('They will appear here when submitted.',
            style: TextStyle(color: Colors.white24, fontSize: 12)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error View
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: _kRed),
            const SizedBox(height: 16),
            const Text('Failed to load requests',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(message,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon:  const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                foregroundColor: const Color(0xFF0A1128),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
        ),
      );
}