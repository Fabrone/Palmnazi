import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';
//import 'package:palmnazi/services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:palmnazi/services/rbac_service.dart';
import 'package:palmnazi/services/api_client.dart'; // for getEmail only

// ─────────────────────────────────────────────────────────────────────────────
// AdminRoleRequestsScreen
//
// Accessible from the Admin Dashboard sidebar / quick actions (index 5).
// Only MainAdmin users ever land on this screen (enforced by dashboard gate).
//
// Shows all PENDING admin role requests in a scrollable card list.
// Each card exposes:
//   • Requester email, facility name, services offered, submission date
//   • [Accept] button  → role-picker sheet → batch write in RbacService
//   • [Deny]   button  → denial-reason sheet → update in RbacService
// ─────────────────────────────────────────────────────────────────────────────

final Logger _log = Logger(
  printer: PrettyPrinter(
      methodCount: 0, errorMethodCount: 8,
      lineLength: 100, colors: true, printEmojis: true),
);

class AdminRoleRequestsScreen extends StatefulWidget {
  const AdminRoleRequestsScreen({super.key});

  @override
  State<AdminRoleRequestsScreen> createState() =>
      _AdminRoleRequestsScreenState();
}

class _AdminRoleRequestsScreenState extends State<AdminRoleRequestsScreen> {
  // ── Admin identity (needed for respondedBy fields) ─────────────────────────
  String? _adminUid;
  String? _adminEmail;

  // ── Tab: 0 = Pending, 1 = Responded ──────────────────────────────────────
  int _tab = 0;

  // ── Per-card action loading state ─────────────────────────────────────────
  final Set<String> _actioning = {};

  @override
  void initState() {
    super.initState();
    _loadAdminIdentity();
  }

  Future<void> _loadAdminIdentity() async {
    // _adminUid must be the Firebase Auth uid — RbacService.acceptRequest writes
    // it into AdminRequests.respondedBy and the security rules use Firebase uid
    // as the identity anchor.  ApiClient.getUserId() returns the custom API id
    // which is a different value and must NOT be used as the Firestore identity.
    _adminUid   = FirebaseAuth.instance.currentUser?.uid;
    _adminEmail = await ApiClient.getEmail();
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCEPT flow — shows role picker bottom sheet
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleAccept(AdminRequest req) async {
    final chosen = await _showRolePickerSheet(req);
    if (chosen == null || !mounted) return;

    setState(() => _actioning.add(req.id));

    final result = await RbacService.acceptRequest(
      requestId:          req.id,
      targetUserId:       req.userId,
      targetFirebaseUid:  req.firebaseUid,   // Firebase uid — document key in Users
      grantedRole:        chosen,
      respondedBy:        _adminUid      ?? '',
      respondedByEmail:   _adminEmail    ?? '',
    );

    if (!mounted) return;
    setState(() => _actioning.remove(req.id));

    _snack(result.message, ok: result.isSuccess);

    if (result.isSuccess) {
      _log.i('✅ AdminRoleRequestsScreen: Accepted → $chosen for ${req.userEmail}');
      // Trigger notification for the requester
      // (NotificationService picks it up via their Firestore listener)
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DENY flow — shows denial reason sheet
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleDeny(AdminRequest req) async {
    final reason = await _showDenialReasonSheet(req);
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() => _actioning.add(req.id));

    final result = await RbacService.denyRequest(
      requestId:        req.id,
      respondedBy:      _adminUid    ?? '',
      respondedByEmail: _adminEmail  ?? '',
      reason:           reason.trim(),
    );

    if (!mounted) return;
    setState(() => _actioning.remove(req.id));

    _snack(result.message, ok: result.isSuccess);
    if (result.isSuccess) {
      _log.i('✅ AdminRoleRequestsScreen: Denied — reason=$reason');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Role picker sheet
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showRolePickerSheet(AdminRequest req) async {
    String selectedRole = 'Admin';

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

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Color(0xFF14FFEC), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Grant Admin Role',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      Text(req.userEmail,
                          style: const TextStyle(
                              color: Color(0xFF14FFEC), fontSize: 12)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Select the role to assign to this user. '
                'MainAdmin can manage all role requests; Admin has standard admin access.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.5),
              ),
              const SizedBox(height: 24),

              // Role options
              ...[
                ('Admin',     Icons.shield_outlined,           const Color(0xFF2196F3),
                 'Standard admin: manage places, blog and content.'),
                ('MainAdmin', Icons.admin_panel_settings_rounded, const Color(0xFFFF9800),
                 'Full control: all admin powers + role management.'),
              ].map((t) => _roleOption(
                    label:       t.$1,
                    icon:        t.$2,
                    color:       t.$3,
                    description: t.$4,
                    selected:    selectedRole == t.$1,
                    onTap:       () => setS(() => selectedRole = t.$1),
                  )),

              const SizedBox(height: 28),

              // Confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text('Grant $selectedRole Role'),
                  onPressed: () => Navigator.pop(ctx, selectedRole),
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
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Denial reason sheet
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showDenialReasonSheet(AdminRequest req) async {
    final ctrl    = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _sheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 24),

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCF6679).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cancel_outlined,
                      color: Color(0xFFCF6679), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deny Request',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      Text(req.userEmail,
                          style: const TextStyle(
                              color: Color(0xFFCF6679), fontSize: 12)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              Form(
                key: formKey,
                child: TextFormField(
                  controller: ctrl,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'State your reason for declining this request…',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 13),
                    filled:     true,
                    fillColor:  Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFCF6679), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFCF6679), width: 1.5),
                    ),
                    errorStyle:
                        const TextStyle(color: Color(0xFFCF6679)),
                  ),
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Please provide a clear reason (at least 10 characters).'
                      : null,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Decline Request'),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(ctx, ctrl.text.trim());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCF6679),
                    foregroundColor: Colors.white,
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
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tab bar ─────────────────────────────────────────────────────────
        _buildTabBar(),
        // ── Content ─────────────────────────────────────────────────────────
        Expanded(
          child: _tab == 0
              ? _buildPendingList()
              : _buildRespondedList(),
        ),
      ],
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return StreamBuilder<int>(
      stream: RbacService.pendingRequestsCountStream(),
      builder: (ctx, snap) {
        final pendingCount = snap.data ?? 0;
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(children: [
            _tabButton(
              label: 'Pending',
              count: pendingCount,
              active: _tab == 0,
              activeColor: const Color(0xFFFF9800),
              onTap: () => setState(() => _tab = 0),
            ),
            _tabButton(
              label: 'Responded',
              count: null,
              active: _tab == 1,
              activeColor: const Color(0xFF14FFEC),
              onTap: () => setState(() => _tab = 1),
            ),
          ]),
        );
      },
    );
  }

  Widget _tabButton({
    required String    label,
    required int?      count,
    required bool      active,
    required Color     activeColor,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: active
                  ? Border.all(color: activeColor.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active ? activeColor : Colors.white38,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  // ── Pending list ──────────────────────────────────────────────────────────
  Widget _buildPendingList() {
    return StreamBuilder<List<AdminRequest>>(
      stream: RbacService.pendingRequestsStream(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF14FFEC)));
        }
        final requests = snap.data ?? [];
        if (requests.isEmpty) return _emptyState('No pending requests', Icons.inbox_rounded);
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => _RequestCard(
            request:    requests[i],
            isActioning: _actioning.contains(requests[i].id),
            onAccept:   () => _handleAccept(requests[i]),
            onDeny:     () => _handleDeny(requests[i]),
          ),
        );
      },
    );
  }

  // ── Responded list (accepted + denied) ───────────────────────────────────
  Widget _buildRespondedList() {
    final responded = FirebaseFirestore.instance
        .collection('AdminRequests')
        .where('status', whereIn: ['accepted', 'denied'])
        .orderBy('respondedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => AdminRequest.fromFirestore(d)).toList());

    return StreamBuilder<List<AdminRequest>>(
      stream: responded,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF14FFEC)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _emptyState('No responded requests yet', Icons.history_rounded);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => _RespondedCard(request: list[i]),
        );
      },
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyState(String text, IconData icon) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white12),
            const SizedBox(height: 16),
            Text(text,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: ok ? 3 : 5),
      ));
  }

  Widget _roleOption({
    required String       label,
    required IconData     icon,
    required Color        color,
    required String       description,
    required bool         selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: selected ? color : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.radio_button_checked_rounded,
                  color: color, size: 20)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: Colors.white24, size: 20),
          ]),
        ),
      );

  Widget _sheetContainer({required Widget child}) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3A5F), Color(0xFF0A1128)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
        child: child,
      );

  Widget _sheetHandle() => Center(
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending Request Card
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final AdminRequest  request;
  final bool          isActioning;
  final VoidCallback  onAccept;
  final VoidCallback  onDeny;

  const _RequestCard({
    required this.request,
    required this.isActioning,
    required this.onAccept,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFF9800).withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────────
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
              ),
              child: Center(
                child: Text(
                  request.userEmail.isNotEmpty
                      ? request.userEmail[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.userEmail,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    _formatDate(request.createdAt),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            _statusBadge('PENDING', const Color(0xFFFF9800)),
          ]),

          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),

          // ── Facility ────────────────────────────────────────────────────
          _infoRow(Icons.business_rounded, 'Facility',
              request.facilityName, const Color(0xFF14FFEC)),

          const SizedBox(height: 12),

          // ── Services ────────────────────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.room_service_rounded,
                size: 15, color: Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Services Offered',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: request.servicesOffered
                        .map((s) => _serviceChip(s))
                        .toList(),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Actions ─────────────────────────────────────────────────────
          if (isActioning)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF14FFEC)),
              ),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Deny'),
                  onPressed: onDeny,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCF6679),
                    side: const BorderSide(
                        color: Color(0xFFCF6679), width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 16),
                  label: const Text('Accept'),
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14FFEC),
                    foregroundColor: const Color(0xFF0A1128),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color iconColor) =>
      Row(children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      ]);

  Widget _serviceChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF14FFEC),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _statusBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      );

  String _formatDate(DateTime dt) {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} · '
        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Responded Request Card (read-only history)
// ─────────────────────────────────────────────────────────────────────────────
class _RespondedCard extends StatelessWidget {
  final AdminRequest request;
  const _RespondedCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final isAccepted = request.isAccepted;
    final color = isAccepted ? const Color(0xFF14FFEC) : const Color(0xFFCF6679);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(
                isAccepted ? Icons.check_rounded : Icons.close_rounded,
                color: color, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.userEmail,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(request.facilityName,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            _badge(isAccepted
                ? (request.grantedRole ?? 'Admin').toUpperCase()
                : 'DENIED', color),
          ]),
          if (!isAccepted && request.denialReason != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFCF6679).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFCF6679).withValues(alpha: 0.2)),
              ),
              child: Text(
                'Reason: ${request.denialReason}',
                style: const TextStyle(
                    color: Color(0xFFCF6679), fontSize: 12, height: 1.4),
              ),
            ),
          ],
          if (request.respondedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Responded ${_formatDate(request.respondedAt!)} by ${request.respondedByEmail ?? '—'}',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      );

  String _formatDate(DateTime dt) {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}