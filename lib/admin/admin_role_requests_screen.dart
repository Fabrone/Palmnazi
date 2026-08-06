import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/audit_log_service.dart';
import 'package:palmnazi/services/rbac_service.dart';
import 'package:palmnazi/widgets/place_search_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logger
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
// AdminRoleRequestsScreen
//
// Visible only to MainAdmin (routing guard lives in AdminDashboard).
// Streams the entire AdminRequests collection ordered by newest first.
//
// Actions (MainAdmin only — MainAdmin is the sole role that can assign or
// revoke roles):
//   Approve — picks CityManager | ContentAdmin | MainAdmin role; batch-writes
//             to AdminRequests AND Users/{firebaseUid} in a single Firestore
//             commit.
//   Deny    — optional free-text reason; updates AdminRequests only.
//   Revoke  — resets an already-accepted request back to denied and strips
//             the role from Users/{firebaseUid}.
// ─────────────────────────────────────────────────────────────────────────────
class AdminRoleRequestsScreen extends StatefulWidget {
  const AdminRoleRequestsScreen({super.key});

  @override
  State<AdminRoleRequestsScreen> createState() =>
      _AdminRoleRequestsScreenState();
}

class _AdminRoleRequestsScreenState extends State<AdminRoleRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<AdminRequest> _requests = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;
  final Set<String> _actioning = {}; // request IDs currently awaiting a write

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
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
          _requests =
              snap.docs.map((d) => AdminRequest.fromFirestore(d)).toList();
          _loading = false;
          _error = null;
        });
      },
      onError: (Object e) {
        _log.e('❌ [AdminRoleRequestsScreen] stream error', error: e);
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      },
    );
  }

  // ── Filtered list for the active tab ──────────────────────────────────────
  List<AdminRequest> get _visible {
    switch (_tabs.index) {
      case 1:
        return _requests.where((r) => r.isPending).toList();
      case 2:
        return _requests.where((r) => r.isAccepted).toList();
      case 3:
        return _requests.where((r) => r.isDenied).toList();
      default:
        return _requests;
    }
  }

  int get _pendingCount => _requests.where((r) => r.isPending).length;
  int get _acceptedCount => _requests.where((r) => r.isAccepted).length;
  int get _deniedCount => _requests.where((r) => r.isDenied).length;

  // ── Approve ────────────────────────────────────────────────────────────────
  Future<void> _onApprove(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack(context.tr('admin_role_requests_error_approve_missing_uid'),
          ok: false);
      return;
    }

    final approvedAsMsg = context.tr('admin_role_requests_snack_approved_as');
    final approveFailedMsg =
        context.tr('admin_role_requests_error_approve_failed');

    final role = await _showApproveSheet(req);
    if (role == null || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      final me = FirebaseAuth.instance.currentUser;
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      // 1. Update the AdminRequests document
      batch.update(
        FirebaseFirestore.instance.collection('AdminRequests').doc(req.id),
        {
          'status': 'accepted',
          'grantedRole': role,
          'respondedAt': now,
          'respondedBy': me?.uid ?? '',
          'respondedByEmail': me?.email ?? '',
          // Clear any previous denial reason
          'denialReason': FieldValue.delete(),
        },
      );

      // 2. Elevate the user's role in the Users collection. City Manager and
      // Content Admin are both scoped to the place they requested; MainAdmin
      // isn't scoped to any single place, so its managedPlaceId is cleared.
      final isPlaceScoped = RbacService.isPlaceScopedRole(role);
      batch.update(
        FirebaseFirestore.instance.collection('Users').doc(req.firebaseUid),
        {
          'role': role,
          'managedPlaceId': isPlaceScoped ? req.placeId : '',
          'managedPlaceName': isPlaceScoped ? req.placeName : '',
          'managedCityId': isPlaceScoped ? req.cityId : '',
          'managedCityName': isPlaceScoped ? req.cityName : '',
        },
      );

      await batch.commit();
      final roleLabel = RbacService.roleLabel(role);
      AuditLogService.log(
          action: 'role_grant',
          module: 'Role',
          targetId: req.firebaseUid,
          targetLabel: req.userEmail,
          details: 'Granted $roleLabel');
      _log.i(
          '✅ [AdminRoleRequestsScreen] Approved ${req.userEmail} as $roleLabel');
      if (mounted) {
        _snack('${req.userEmail} $approvedAsMsg $roleLabel.', ok: true);
      }
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Approve failed', error: e);
      if (mounted) _snack(approveFailedMsg, ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Deny ───────────────────────────────────────────────────────────────────
  Future<void> _onDeny(AdminRequest req) async {
    final requestFromMsg = context.tr('admin_role_requests_snack_request_from');
    final declinedSuffix =
        context.tr('admin_role_requests_snack_declined_suffix');
    final denyFailedMsg = context.tr('admin_role_requests_error_deny_failed');

    final reason = await _showDenySheet(req);
    if (reason == null || !mounted) return; // null = sheet dismissed

    setState(() => _actioning.add(req.id));
    try {
      final me = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('AdminRequests')
          .doc(req.id)
          .update({
        'status': 'denied',
        if (reason.trim().isNotEmpty) 'denialReason': reason.trim(),
        'respondedAt': Timestamp.now(),
        'respondedBy': me?.uid ?? '',
        'respondedByEmail': me?.email ?? '',
        // Clear any previous granted role
        'grantedRole': FieldValue.delete(),
      });
      _log.i('✅ [AdminRoleRequestsScreen] Denied ${req.userEmail}');
      if (mounted) {
        _snack('$requestFromMsg ${req.userEmail} $declinedSuffix', ok: false);
      }
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Deny failed', error: e);
      if (mounted) _snack(denyFailedMsg, ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Revoke (accepted → Tourist) ────────────────────────────────────────────
  Future<void> _onRevoke(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack(context.tr('admin_role_requests_error_revoke_missing_uid'),
          ok: false);
      return;
    }

    final revokedPrefixMsg =
        context.tr('admin_role_requests_snack_role_revoked_prefix');
    final revokeFailedMsg =
        context.tr('admin_role_requests_error_revoke_failed');

    final confirm = await _confirmDialog(
      icon: Icons.remove_moderator_rounded,
      iconColor: AdC.orange,
      title: context.tr('admin_role_requests_revoke_confirm_title'),
      body: '${context.tr('admin_role_requests_revoke_confirm_body_prefix')} '
          '${RbacService.roleLabel(req.grantedRole ?? RbacService.roleCityManager)} '
          '${context.tr('admin_role_requests_revoke_confirm_body_middle')} '
          '${req.userEmail} '
          '${context.tr('admin_role_requests_revoke_confirm_body_suffix')}',
      confirmLabel: context.tr('admin_role_requests_confirm_revoke'),
      confirmColor: AdC.orange,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      final me = FirebaseAuth.instance.currentUser;
      final batch = FirebaseFirestore.instance.batch();

      // Mark the request as denied / revoked
      batch.update(
        FirebaseFirestore.instance.collection('AdminRequests').doc(req.id),
        {
          'status': 'denied',
          'denialReason': 'Role revoked by administrator.',
          'grantedRole': FieldValue.delete(),
          'respondedAt': Timestamp.now(),
          'respondedBy': me?.uid ?? '',
          'respondedByEmail': me?.email ?? '',
        },
      );

      // Reset the user's role to Tourist and clear their place assignment
      batch.update(
        FirebaseFirestore.instance.collection('Users').doc(req.firebaseUid),
        {
          'role': 'Tourist',
          'managedPlaceId': '',
          'managedPlaceName': '',
          'managedCityId': '',
          'managedCityName': '',
        },
      );

      await batch.commit();
      AuditLogService.log(
          action: 'role_revoke',
          module: 'Role',
          targetId: req.firebaseUid,
          targetLabel: req.userEmail);
      _log.i('✅ [AdminRoleRequestsScreen] Revoked role for ${req.userEmail}');
      if (mounted) {
        _snack('$revokedPrefixMsg ${req.userEmail}.', ok: false);
      }
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Revoke failed', error: e);
      if (mounted) _snack(revokeFailedMsg, ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Delete (denied requests only) ──────────────────────────────────────────
  Future<void> _onDelete(AdminRequest req) async {
    final requestFromMsg = context.tr('admin_role_requests_snack_request_from');
    final deletedSuffix =
        context.tr('admin_role_requests_snack_deleted_suffix');
    final deleteFailedMsg =
        context.tr('admin_role_requests_error_delete_failed');

    final confirm = await _confirmDialog(
      icon: Icons.delete_outline_rounded,
      iconColor: AdC.red,
      title: context.tr('admin_role_requests_delete_confirm_title'),
      body: '${context.tr('admin_role_requests_delete_confirm_body_prefix')} '
          '${req.userEmail}. '
          '${context.tr('admin_role_requests_delete_confirm_body_suffix')}',
      confirmLabel: context.tr('common_delete'),
      confirmColor: AdC.red,
    );
    if (confirm != true || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      await FirebaseFirestore.instance
          .collection('AdminRequests')
          .doc(req.id)
          .delete();
      AuditLogService.log(
          action: 'role_request_delete',
          module: 'Role',
          targetId: req.firebaseUid,
          targetLabel: req.userEmail);
      _log.i(
          '✅ [AdminRoleRequestsScreen] Deleted denied request from ${req.userEmail}');
      if (mounted) {
        _snack('$requestFromMsg ${req.userEmail} $deletedSuffix', ok: true);
      }
    } catch (e) {
      _log.e('❌ [AdminRoleRequestsScreen] Delete failed', error: e);
      if (mounted) _snack(deleteFailedMsg, ok: false);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Switch role (accepted requests only) ───────────────────────────────────
  Future<void> _onSwitchRole(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack(context.tr('admin_role_requests_error_switch_missing_uid'),
          ok: false);
      return;
    }
    final currentRole = req.grantedRole ?? RbacService.roleCityManager;
    final newRole = await _showSwitchRoleSheet(req, currentRole);
    if (newRole == null || !mounted || newRole == currentRole) return;

    String placeId = req.placeId;
    String placeName = req.placeName;
    String cityId = req.cityId;
    String cityName = req.cityName;

    // Switching into a place-scoped role with no place on file yet (e.g. a
    // MainAdmin being moved down to City Manager / Content Admin) requires
    // picking one before we can write a valid scope.
    if (RbacService.isPlaceScopedRole(newRole) && placeId.isEmpty) {
      final picked = await showPlaceSearchPicker(context);
      if (picked == null || !mounted) return;
      placeId = picked.id;
      placeName = picked.name;
      cityId = picked.cityId;
      cityName = picked.cityName;
    }

    setState(() => _actioning.add(req.id));
    try {
      final me = FirebaseAuth.instance.currentUser;
      final result = await RbacService.switchGrantedRole(
        requestId: req.id,
        targetFirebaseUid: req.firebaseUid,
        newRole: newRole,
        respondedBy: me?.uid ?? '',
        respondedByEmail: me?.email ?? '',
        placeId: placeId,
        placeName: placeName,
        cityId: cityId,
        cityName: cityName,
      );
      if (result.isSuccess) {
        AuditLogService.log(
            action: 'role_switch',
            module: 'Role',
            targetId: req.firebaseUid,
            targetLabel: req.userEmail,
            details:
                'Switched from ${RbacService.roleLabel(currentRole)} to ${RbacService.roleLabel(newRole)}');
        _log.i(
            '✅ [AdminRoleRequestsScreen] Switched ${req.userEmail} to ${RbacService.roleLabel(newRole)}');
      } else {
        _log.e(
            '❌ [AdminRoleRequestsScreen] Switch role failed: ${result.message}');
      }
      if (mounted) _snack(result.message, ok: result.isSuccess);
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  // ── Reassign place (accepted City Manager / Content Admin requests only) ──
  Future<void> _onReassignPlace(AdminRequest req) async {
    if (req.firebaseUid.isEmpty) {
      _snack(context.tr('admin_role_requests_error_reassign_missing_uid'),
          ok: false);
      return;
    }
    final picked = await showPlaceSearchPicker(context);
    if (picked == null || !mounted) return;

    setState(() => _actioning.add(req.id));
    try {
      final result = await RbacService.reassignManagedPlace(
        targetFirebaseUid: req.firebaseUid,
        placeId: picked.id,
        placeName: picked.name,
        cityId: picked.cityId,
        cityName: picked.cityName,
      );
      if (mounted) _snack(result.message, ok: result.isSuccess);
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
          total: _requests.length,
          pending: _pendingCount,
          accepted: _acceptedCount,
          denied: _deniedCount,
        ),
        _buildTabBar(context),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AdC.teal))
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _subscribe)
                  : _buildList(),
        ),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final allLabel = context.tr('category_subcat_all');
    final pendingLabel = context.tr('admin_role_requests_tab_pending');
    final approvedLabel = context.tr('admin_role_requests_tab_approved');
    final deniedLabel = context.tr('admin_role_requests_tab_denied');
    return Container(
      color: AdC.surface,
      child: TabBar(
        controller: _tabs,
        indicatorColor: AdC.teal,
        labelColor: AdC.teal,
        unselectedLabelColor: AdC.textMute,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        tabs: [
          Tab(text: allLabel),
          Tab(
              text: _pendingCount > 0
                  ? '$pendingLabel ($_pendingCount)'
                  : pendingLabel),
          Tab(
              text: _acceptedCount > 0
                  ? '$approvedLabel ($_acceptedCount)'
                  : approvedLabel),
          Tab(
              text: _deniedCount > 0
                  ? '$deniedLabel ($_deniedCount)'
                  : deniedLabel),
        ],
      ),
    );
  }

  Widget _buildList() {
    final items = _visible;
    if (items.isEmpty) return _EmptyState(tabIndex: _tabs.index);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _RequestCard(
        request: items[i],
        isActioning: _actioning.contains(items[i].id),
        onApprove: () => _onApprove(items[i]),
        onDeny: () => _onDeny(items[i]),
        onRevoke: () => _onRevoke(items[i]),
        onReassignPlace: () => _onReassignPlace(items[i]),
        onSwitchRole: () => _onSwitchRole(items[i]),
        onDelete: () => _onDelete(items[i]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Approve Bottom Sheet — role selector
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showApproveSheet(AdminRequest req) {
    String selected = RbacService.roleCityManager;

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
                    color: AdC.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_user_rounded,
                      color: AdC.green, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('admin_role_requests_approve_sheet_title'),
                        style: TextStyle(
                            color: AdC.textPri,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text(req.userEmail,
                        style: TextStyle(color: AdC.textMute, fontSize: 12),
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
                  color: AdC.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdC.green.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${context.tr('admin_role_requests_approve_sheet_notice_prefix')} '
                  '${req.userEmail}\'s '
                  '${context.tr('admin_role_requests_approve_sheet_notice_suffix')}',
                  style:
                      TextStyle(color: AdC.textSec, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              Text(context.tr('admin_role_requests_select_role_to_grant'),
                  style: TextStyle(
                      color: AdC.textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              _RoleOption(
                role: RbacService.roleCityManager,
                description:
                    context.tr('admin_role_requests_role_desc_city_manager'),
                isSelected: selected == RbacService.roleCityManager,
                onTap: () => setS(() => selected = RbacService.roleCityManager),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                role: RbacService.roleContentAdmin,
                description:
                    context.tr('admin_role_requests_role_desc_content_admin'),
                isSelected: selected == RbacService.roleContentAdmin,
                onTap: () =>
                    setS(() => selected = RbacService.roleContentAdmin),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                role: RbacService.roleMainAdmin,
                description:
                    context.tr('admin_role_requests_role_desc_main_admin'),
                isSelected: selected == RbacService.roleMainAdmin,
                onTap: () => setS(() => selected = RbacService.roleMainAdmin),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                      '${context.tr('admin_role_requests_approve_as_prefix')} ${RbacService.roleLabel(selected)}'),
                  onPressed: () => Navigator.pop(ctx, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdC.green,
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
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('common_cancel'),
                        style: TextStyle(color: AdC.textMute)),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Switch Role Bottom Sheet — role selector for an already-accepted user
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _showSwitchRoleSheet(AdminRequest req, String currentRole) {
    String selected = currentRole;

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
                    color: AdC.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded,
                      color: AdC.teal, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('admin_role_requests_switch_sheet_title'),
                        style: TextStyle(
                            color: AdC.textPri,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text(req.userEmail,
                        style: TextStyle(color: AdC.textMute, fontSize: 12),
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
                  color: AdC.teal.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdC.teal.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${context.tr('admin_role_requests_switch_sheet_notice_currently_prefix')} '
                  '${RbacService.roleLabel(currentRole)}. '
                  '${context.tr('admin_role_requests_switch_sheet_notice_suffix')} '
                  '${req.userEmail}\'s '
                  '${context.tr('admin_role_requests_switch_sheet_notice_suffix2')}',
                  style:
                      TextStyle(color: AdC.textSec, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              Text(context.tr('admin_role_requests_select_new_role'),
                  style: TextStyle(
                      color: AdC.textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              _RoleOption(
                role: RbacService.roleCityManager,
                description:
                    context.tr('admin_role_requests_role_desc_city_manager'),
                isSelected: selected == RbacService.roleCityManager,
                onTap: () => setS(() => selected = RbacService.roleCityManager),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                role: RbacService.roleContentAdmin,
                description:
                    context.tr('admin_role_requests_role_desc_content_admin'),
                isSelected: selected == RbacService.roleContentAdmin,
                onTap: () =>
                    setS(() => selected = RbacService.roleContentAdmin),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                role: RbacService.roleMainAdmin,
                description:
                    context.tr('admin_role_requests_role_desc_main_admin'),
                isSelected: selected == RbacService.roleMainAdmin,
                onTap: () => setS(() => selected = RbacService.roleMainAdmin),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(selected == currentRole
                      ? context.tr('admin_role_requests_select_different_role')
                      : '${context.tr('admin_role_requests_switch_to_prefix')} ${RbacService.roleLabel(selected)}'),
                  onPressed: selected == currentRole
                      ? null
                      : () => Navigator.pop(ctx, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdC.teal,
                    foregroundColor: const Color(0xFF0A1128),
                    disabledBackgroundColor: AdC.teal.withValues(alpha: 0.25),
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
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('common_cancel'),
                        style: TextStyle(color: AdC.textMute)),
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
                    color: AdC.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cancel_rounded,
                      color: AdC.red, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('admin_role_requests_deny_sheet_title'),
                        style: TextStyle(
                            color: AdC.textPri,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text(req.userEmail,
                        style: TextStyle(color: AdC.textMute, fontSize: 12),
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
                  color: AdC.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdC.red.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${context.tr('admin_role_requests_deny_sheet_notice_prefix')} '
                  '"${req.facilityName}" '
                  '${context.tr('admin_role_requests_deny_sheet_notice_suffix')}',
                  style:
                      TextStyle(color: AdC.textSec, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              // Reason field
              Text(context.tr('admin_role_requests_reason_for_denial'),
                  style: TextStyle(
                      color: AdC.textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 3,
                style: TextStyle(color: AdC.textPri, fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.tr('admin_role_requests_reason_hint'),
                  hintStyle: TextStyle(color: AdC.textMute, fontSize: 13),
                  filled: true,
                  fillColor: AdC.overlay(0.06),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AdC.overlay(0.15))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AdC.red, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.do_not_disturb_rounded, size: 18),
                  label: Text(
                      context.tr('admin_role_requests_btn_decline_request')),
                  // Return the reason text (may be empty); null = cancel
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdC.red,
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
                    onPressed: () =>
                        Navigator.pop(ctx), // null → caller treats as cancel
                    child: Text(context.tr('common_cancel'),
                        style: TextStyle(color: AdC.textMute)),
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
    required Color iconColor,
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdC.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Flexible(
                child: Text(title,
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 16,
                        fontWeight: FontWeight.bold))),
          ]),
          content: Text(body,
              style: TextStyle(color: AdC.textSec, fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('common_cancel'),
                  style: TextStyle(color: AdC.textSec)),
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

  // ── Snack ──────────────────────────────────────────────────────────────────
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
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
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
          color: AdC.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AdC.overlay(0.15)),
        ),
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
        child: child,
      );

  Widget _sheetHandle() => Center(
          child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
            color: AdC.overlay(0.3), borderRadius: BorderRadius.circular(2)),
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
          color: AdC.surface,
          border: Border(bottom: BorderSide(color: AdC.overlay(0.12))),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _StatPill(
                label: context.tr('admin_role_requests_stat_total'),
                count: total,
                color: AdC.textMute),
            _StatPill(
                label: context.tr('admin_role_requests_tab_pending'),
                count: pending,
                color: AdC.orange),
            _StatPill(
                label: context.tr('admin_role_requests_tab_approved'),
                count: accepted,
                color: AdC.green),
            _StatPill(
                label: context.tr('admin_role_requests_tab_denied'),
                count: denied,
                color: AdC.red),
          ],
        ),
      );
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatPill(
      {required this.label, required this.count, required this.color});

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
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$label: $count',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Request Card
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final AdminRequest request;
  final bool isActioning;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onRevoke;
  final VoidCallback onReassignPlace;
  final VoidCallback onSwitchRole;
  final VoidCallback onDelete;

  const _RequestCard({
    required this.request,
    required this.isActioning,
    required this.onApprove,
    required this.onDeny,
    required this.onRevoke,
    required this.onReassignPlace,
    required this.onSwitchRole,
    required this.onDelete,
  });

  // Status-driven theming
  Color get _statusColor {
    if (request.isPending) return AdC.orange;
    if (request.isAccepted) return AdC.green;
    return AdC.red;
  }

  String _statusLabel(BuildContext context) {
    if (request.isPending) {
      return context.tr('admin_role_requests_status_pending');
    }
    if (request.isAccepted) {
      return context.tr('admin_role_requests_status_approved');
    }
    return context.tr('admin_role_requests_status_declined');
  }

  IconData get _statusIcon {
    if (request.isPending) return Icons.hourglass_top_rounded;
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
          color: AdC.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.userEmail,
                      style: TextStyle(
                          color: AdC.textPri,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    request.placeName.isNotEmpty
                        ? '${request.placeName} · ${request.cityName}'
                        : request.facilityName,
                    style: TextStyle(color: AdC.textMute, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: _statusColor.withValues(alpha: 0.35)),
                ),
                child: Text(_statusLabel(context),
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
            ]),

            const SizedBox(height: 14),
            Divider(color: AdC.overlay(0.12), height: 1),
            const SizedBox(height: 14),

            // ── Services ──────────────────────────────────────────────────
            if (request.servicesOffered.isNotEmpty) ...[
              Text(context.tr('admin_role_requests_services_offered'),
                  style: TextStyle(
                      color: AdC.textMute,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: request.servicesOffered
                    .map((s) => _ServiceTag(label: s))
                    .toList(),
              ),
              const SizedBox(height: 14),
            ],

            // ── Meta row ──────────────────────────────────────────────────
            Wrap(spacing: 14, runSpacing: 4, children: [
              _Meta(Icons.schedule_rounded,
                  '${context.tr('admin_role_requests_meta_submitted_prefix')} ${_fmt(request.createdAt)}'),
              if (request.respondedAt != null)
                _Meta(
                  request.isAccepted
                      ? Icons.check_circle_outline_rounded
                      : Icons.block_rounded,
                  '${request.isAccepted ? context.tr('admin_role_requests_tab_approved') : context.tr('admin_role_requests_tab_denied')}: ${_fmt(request.respondedAt)}',
                ),
              if (request.respondedByEmail != null)
                _Meta(Icons.admin_panel_settings_rounded,
                    '${context.tr('admin_role_requests_meta_by_prefix')} ${request.respondedByEmail}'),
              if (request.grantedRole != null)
                _Meta(Icons.badge_rounded,
                    '${context.tr('admin_role_requests_meta_role_prefix')} ${RbacService.roleLabel(request.grantedRole!)}'),
            ]),

            // ── Denial reason box ─────────────────────────────────────────
            if (request.isDenied && request.denialReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AdC.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdC.red.withValues(alpha: 0.22)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 13, color: AdC.red),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                        '${context.tr('admin_role_requests_reason_prefix')} ${request.denialReason}',
                        style: const TextStyle(
                            color: AdC.red, fontSize: 11, height: 1.4),
                      )),
                    ]),
              ),
            ],

            // ── Action buttons ────────────────────────────────────────────
            if (request.isPending ||
                request.isAccepted ||
                request.isDenied) ...[
              const SizedBox(height: 14),
              Divider(color: AdC.overlay(0.12), height: 1),
              const SizedBox(height: 12),
              if (isActioning)
                const Center(
                    child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AdC.teal),
                ))
              else if (request.isPending)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label:
                          Text(context.tr('admin_role_requests_btn_decline')),
                      onPressed: onDeny,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdC.red,
                        side: BorderSide(color: AdC.red.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 14),
                      label:
                          Text(context.tr('admin_role_requests_btn_approve')),
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdC.green,
                        foregroundColor: const Color(0xFF0A1128),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ])
              else if (request.isAccepted)
                Column(
                  children: [
                    if (RbacService.isPlaceScopedRole(
                        request.grantedRole ?? ''))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_location_alt_rounded,
                                size: 14),
                            label: Text(context
                                .tr('admin_role_requests_btn_reassign_place')),
                            onPressed: onReassignPlace,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdC.teal,
                              side: BorderSide(
                                  color: AdC.teal.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              textStyle: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                          label: Text(context
                              .tr('admin_role_requests_btn_switch_role')),
                          onPressed: onSwitchRole,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdC.teal,
                            side: BorderSide(
                                color: AdC.teal.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.remove_moderator_rounded,
                              size: 14),
                          label: Text(context
                              .tr('admin_role_requests_btn_revoke_role')),
                          onPressed: onRevoke,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdC.orange,
                            side: BorderSide(
                                color: AdC.orange.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                )
              else if (request.isDenied)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                      label: Text(context.tr('common_delete')),
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdC.red,
                        side: BorderSide(color: AdC.red.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.replay_rounded, size: 14),
                      label:
                          Text(context.tr('admin_role_requests_btn_reapprove')),
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdC.green,
                        foregroundColor: const Color(0xFF0A1128),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
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
          color: AdC.teal.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AdC.teal.withValues(alpha: 0.22)),
        ),
        child:
            Text(label, style: const TextStyle(color: AdC.teal, fontSize: 11)),
      );
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AdC.textMute),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: AdC.textMute, fontSize: 11)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Option — radio-style selector inside the approve sheet
// ─────────────────────────────────────────────────────────────────────────────
class _RoleOption extends StatelessWidget {
  final String role;
  final String description;
  final bool isSelected;
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
                ? AdC.green.withValues(alpha: 0.10)
                : AdC.overlay(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AdC.green.withValues(alpha: 0.50)
                  : AdC.overlay(0.12),
            ),
          ),
          child: Row(children: [
            // Radio dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AdC.green.withValues(alpha: 0.20)
                    : Colors.transparent,
                border: Border.all(
                    color: isSelected ? AdC.green : AdC.textMute, width: 1.5),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 10, color: AdC.green)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(RbacService.roleLabel(role),
                    style: TextStyle(
                        color: isSelected ? AdC.green : AdC.textPri,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        color: AdC.textMute, fontSize: 11, height: 1.4)),
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

  static const _icons = [
    Icons.inbox_rounded,
    Icons.hourglass_empty_rounded,
    Icons.verified_rounded,
    Icons.remove_circle_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.tr('admin_role_requests_empty_all'),
      context.tr('admin_role_requests_empty_pending'),
      context.tr('admin_role_requests_empty_approved'),
      context.tr('admin_role_requests_empty_declined'),
    ];
    final label = tabIndex < labels.length
        ? labels[tabIndex]
        : context.tr('admin_role_requests_empty_all');
    final icon =
        tabIndex < _icons.length ? _icons[tabIndex] : Icons.inbox_rounded;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: AdC.overlay(0.12)),
        const SizedBox(height: 16),
        Text('${context.tr('admin_role_requests_empty_prefix')} $label',
            style: TextStyle(
                color: AdC.textMute,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text(context.tr('admin_role_requests_empty_body'),
            style: TextStyle(color: AdC.textMute, fontSize: 12)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error View
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: AdC.red),
            const SizedBox(height: 16),
            Text(context.tr('admin_role_requests_error_load_title'),
                style: TextStyle(
                    color: AdC.textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(color: AdC.textMute, fontSize: 11),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(context.tr('common_retry')),
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdC.teal,
                foregroundColor: const Color(0xFF0A1128),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
        ),
      );
}
