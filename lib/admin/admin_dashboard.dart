import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_resort_cities_screen.dart';
import 'package:palmnazi/admin/admin_categories_screen.dart';
import 'package:palmnazi/admin/admin_places_screen.dart';
import 'package:palmnazi/admin/admin_blog_list_screen.dart';
import 'package:palmnazi/admin/admin_role_requests_screen.dart';
import 'package:palmnazi/admin/admin_payment_methods_screen.dart';
import 'package:palmnazi/admin/admin_bookings_screen.dart';
import 'package:palmnazi/admin/admin_contact_messages_screen.dart';
import 'package:palmnazi/admin/admin_reports_screen.dart';
import 'package:palmnazi/admin/admin_settings_screen.dart';
import 'package:palmnazi/admin/admin_static_pages_screen.dart';
import 'package:palmnazi/admin/admin_audit_log_screen.dart';
import 'package:palmnazi/admin/place_admin/place_admin_panel.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/services/dashboard_snapshot_service.dart';
import 'package:palmnazi/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
// Admin Dashboard
//
// Navigation:
//   0 — Dashboard overview
//   1 — Resort Cities CRUD
//   2 — Categories CRUD
//   3 — Places CRUD
//   4 — Blog
//   5 — Role Requests (Admin & MainAdmin — live badge dot on pending count)
//   6 — Payment Methods CRUD (Firestore-backed configuration catalogue)
//   7 — Bookings (Firestore-backed; tourist-submitted booking requests)
//   8 — Reports
//   9 — Messages
//  10 — Settings (MainAdmin only)
//  11 — Static Pages (MainAdmin only)
//  12 — Audit Log (MainAdmin only)
// ─────────────────────────────────────────────────────────────────────────────

// MainAdmin-only tabs: Role Requests (5), Settings (10), Static Pages (11),
// Audit Log (12) — same permission gate as _canManageRoleRequests.
const _mainAdminOnlyIndices = {5, 10, 11, 12};

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _sidebarAnim;

  // Filter context for Places tab
  CityModel? _filterCity;
  CategoryModel? _filterCategory;

  final _apiService = AdminApiService();
  Map<String, dynamic> _stats = {};
  bool _statsLoading = true;

  // ── RBAC — live role + pending requests counter ───────────────────────────
  int _pendingRequestsCount = 0;
  StreamSubscription<int>? _pendingCountSub;
  StreamSubscription<String>? _roleSub;
  String? _adminRole; // 'CityManager', 'ContentAdmin' or 'MainAdmin'

  // ── Place-scoped Admin — the place they're limited to (null = unassigned,
  // shown as an empty state rather than crashing) ───────────────────────────
  String? _managedPlaceId;
  String _managedPlaceName = '';
  String _managedCityName = '';
  bool _managedPlaceLoading = false;

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.location_city_rounded, 'Resort Cities'),
    _NavItem(Icons.category_rounded, 'Categories'),
    _NavItem(Icons.place_rounded, 'Places'),
    _NavItem(Icons.article_rounded, 'Blog'),
    _NavItem(Icons.manage_accounts_rounded, 'Role Requests'),
    _NavItem(Icons.payments_rounded, 'Payment Methods'),
    _NavItem(Icons.calendar_month_rounded, 'Bookings'),
    _NavItem(Icons.bar_chart_rounded, 'Reports'),
    _NavItem(Icons.mail_outline_rounded, 'Messages'),
    _NavItem(Icons.settings_rounded, 'Settings'),
    _NavItem(Icons.description_outlined, 'Static Pages'),
    _NavItem(Icons.history_rounded, 'Audit Log'),
  ];

  @override
  void initState() {
    super.initState();
    _log.i(
        '🏁 [AdminDashboard] initState — uid=${FirebaseAuth.instance.currentUser?.uid ?? "null"}');
    _sidebarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    _loadStats();
    _initRbac();
  }

  // ── Load admin identity & start RBAC listeners ──────────────────
  Future<void> _initRbac() async {
    await _waitForFirebaseAuth();

    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (!mounted) return;

    if (firebaseUid == null) {
      _log.e(
          '❌ [AdminDashboard._initRbac] Firebase uid still null after wait — RBAC listeners not started');
      return;
    }

    _log.i(
        '🔐 [AdminDashboard._initRbac] Starting Firestore role stream for uid=$firebaseUid');
    _roleSub?.cancel();

    // Role is read directly from the Firestore Users/{firebaseUid} document —
    // the 'role' field is the single source of truth and never proxied via the API.
    _roleSub = FirebaseFirestore.instance
        .collection('Users')
        .doc(firebaseUid)
        .snapshots()
        .map((snap) => RbacService.normalizeRole(
            (snap.data()?['role'] as String? ?? '').trim()))
        .listen(
      (role) {
        if (!mounted) return;

        // The Firestore snapshot is already mapped, trimmed and normalized
        // above, but we trim again here as a permanent safety net.
        final cleanRole = role.trim();

        // Only MainAdmin approves/denies other admins — a place-scoped
        // City Manager / Content Admin has no reason to see or be notified
        // about role requests.
        final wasMainAdmin = _adminRole == RbacService.roleMainAdmin;
        final isMainAdmin = cleanRole == RbacService.roleMainAdmin;

        setState(() => _adminRole = cleanRole);

        if (isMainAdmin && !wasMainAdmin) {
          _log.i(
              '🔐 [AdminDashboard._initRbac] Role confirmed as MainAdmin — starting Role Requests listeners');
          _pendingCountSub?.cancel();
          _pendingCountSub = RbacService.pendingRequestsCountStream().listen(
            (pendingCount) {
              if (mounted) setState(() => _pendingRequestsCount = pendingCount);
            },
            onError: (e) =>
                _log.w('⚠️ [AdminDashboard] pendingCountStream error: $e'),
          );
          NotificationService.startAdminRequestsListener();
        } else if (isMainAdmin && wasMainAdmin) {
          // Role re-confirmed, no action needed
        } else if (!isMainAdmin && wasMainAdmin) {
          _log.w(
              '⚠️ [AdminDashboard._initRbac] Role downgraded from MainAdmin — cancelling Role Requests listeners');
          _pendingCountSub?.cancel();
          _pendingCountSub = null;
          setState(() => _pendingRequestsCount = 0);
        }

        if (RbacService.isPlaceScopedRole(cleanRole)) {
          _loadManagedPlace(firebaseUid);
        } else {
          setState(() {
            _managedPlaceId = null;
            _managedPlaceName = '';
            _managedCityName = '';
          });
        }
      },
      onError: (e) {
        _log.e('❌ [AdminDashboard._initRbac] Firestore role stream error: $e',
            error: e);
      },
      onDone: () {
        _log.w(
            '⚠️ [AdminDashboard._initRbac] Firestore role stream closed unexpectedly');
      },
    );
  }

  // ── Fetch the place a City Manager / Content Admin is scoped to ──────────
  Future<void> _loadManagedPlace(String firebaseUid) async {
    setState(() => _managedPlaceLoading = true);
    final place = await RbacService.getManagedPlace(firebaseUid);
    if (!mounted) return;
    setState(() {
      _managedPlaceId = place?.placeId;
      _managedPlaceName = place?.placeName ?? '';
      _managedCityName = place?.cityName ?? '';
      _managedPlaceLoading = false;
    });
  }

  // ── MainAdmin: open the Place Admin Panel for any place they choose ──────
  Future<void> _openPlaceAdminPicker() async {
    final picked = await showPlaceSearchPicker(context);
    if (picked == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaceAdminPanel(
        placeId: picked.id,
        placeName: picked.name,
        cityName: picked.cityName,
        isMainAdminView: true,
      ),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Wait until Firebase Auth has a signed-in user (max 3 s).
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _waitForFirebaseAuth({int maxWaitMs = 3000}) async {
    const tickMs = 200;
    int waited = 0;
    if (FirebaseAuth.instance.currentUser != null) return;
    _log.w(
        '⚠️ [AdminDashboard._waitForFirebaseAuth] Firebase user null — polling…');
    while (FirebaseAuth.instance.currentUser == null && waited < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
      waited += tickMs;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      _log.e(
        '❌ [AdminDashboard._waitForFirebaseAuth] Firebase user still null after ${maxWaitMs}ms — '
        'Role Requests UI will not appear.',
      );
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await _apiService.getDashboardStats();
      DashboardSnapshotService.recordToday(s);
      if (mounted) {
        setState(() {
          _stats = s;
          _statsLoading = false;
        });
      }
    } catch (e, st) {
      _log.e('❌ [AdminDashboard._loadStats] getDashboardStats failed',
          error: e, stackTrace: st);
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  void dispose() {
    _log.i('🗑️ [AdminDashboard] dispose');
    _sidebarAnim.dispose();
    _roleSub?.cancel();
    _pendingCountSub?.cancel();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 3) {
        _filterCategory = null;
        _filterCity = null;
      }
    });
  }

  // Only MainAdmin approves/denies other admins — MainAdmin is the sole
  // role that can assign or revoke any role in the system.
  bool get _canManageRoleRequests => _adminRole == RbacService.roleMainAdmin;

  // ── Whole-screen body for a place-scoped City Manager / Content Admin —
  // no sidebar/nav at all ────────────────────────────────────────────────
  Widget _buildPlaceScopedBody() {
    if (_managedPlaceLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF14FFEC))),
      );
    }
    if (_managedPlaceId == null || _managedPlaceId!.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business_outlined,
                    color: Colors.white24, size: 56),
                const SizedBox(height: 16),
                const Text('No place assigned yet',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'A MainAdmin needs to link your account to a place before you can manage anything here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white54, size: 16),
                  label: const Text('Back to App',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PlaceAdminPanel(
      placeId: _managedPlaceId!,
      placeName: _managedPlaceName,
      cityName: _managedCityName,
    );
  }

  @override
  Widget build(BuildContext context) {
    // City Manager and Content Admin have no system-wide console — the
    // Place Admin Panel for their one assigned place IS the whole app for
    // them. They differ only in delete rights within that place
    // (RbacService.canDeleteCoreData), not in which screens they can reach.
    if (_adminRole != null && RbacService.isPlaceScopedRole(_adminRole!)) {
      return _buildPlaceScopedBody();
    }

    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final isDesktop = w >= 1100;
    // A phone in landscape has w ≥ 700 but h < 500 — treat as mobile so the
    // bottom nav stays visible and the sidebar doesn't overflow.
    final isTablet = w >= 700 && h >= 500;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Row(
        children: [
          if (isTablet)
            _AdminSidebar(
              items: _navItems,
              selectedIndex: _selectedIndex,
              isExpanded: isDesktop,
              onTap: _onNavTap,
              filterCity: _filterCity,
              filterCategory: _filterCategory,
              pendingRequestsCount:
                  _canManageRoleRequests ? _pendingRequestsCount : 0,
              canManageRoleRequests: _canManageRoleRequests,
              onOpenPlaceAdmin: _adminRole == RbacService.roleMainAdmin
                  ? _openPlaceAdminPicker
                  : null,
            ),
          Expanded(
            child: Column(
              children: [
                _AdminTopBar(
                  title: _pageTitle,
                  subtitle: _pageSubtitle,
                  onMenuTap: isTablet ? null : () => _showMobileDrawer(context),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isTablet ? null : _buildMobileNavBar(),
    );
  }

  // ── Mobile bottom nav with badge ──────────────────────────────────────────
  Widget _buildMobileNavBar() {
    final destinations = <NavigationDestination>[];
    for (int i = 0; i < _navItems.length; i++) {
      final item = _navItems[i];
      if (_mainAdminOnlyIndices.contains(i) && !_canManageRoleRequests) {
        continue;
      }

      final isRoleRequests = i == 5;
      final hasBadge = isRoleRequests && _pendingRequestsCount > 0;

      destinations.add(NavigationDestination(
        icon: hasBadge
            ? _BadgedIcon(
                icon: item.icon,
                count: _pendingRequestsCount,
                color: Colors.white54)
            : Icon(item.icon, color: Colors.white54),
        selectedIcon: hasBadge
            ? _BadgedIcon(
                icon: item.icon,
                count: _pendingRequestsCount,
                color: const Color(0xFF14FFEC))
            : Icon(item.icon, color: const Color(0xFF14FFEC)),
        label: item.label,
      ));
    }

    final logicalIndices = [
      0,
      1,
      2,
      3,
      4,
      if (_canManageRoleRequests) 5,
      6,
      7,
      8,
      9,
      if (_canManageRoleRequests) ...[10, 11, 12],
    ];
    final visualIndex = logicalIndices.contains(_selectedIndex)
        ? logicalIndices.indexOf(_selectedIndex)
        : 0;

    return NavigationBar(
      backgroundColor: const Color(0xFF111827),
      indicatorColor: const Color(0xFF14FFEC).withValues(alpha: 0.15),
      selectedIndex: visualIndex,
      onDestinationSelected: (vi) => _onNavTap(logicalIndices[vi]),
      destinations: destinations,
    );
  }

  // ── Page title / subtitle ─────────────────────────────────────────────────
  String get _pageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Admin Console';
      case 1:
        return 'Resort Cities';
      case 2:
        return 'Categories';
      case 3:
        if (_filterCategory != null && _filterCity != null) {
          return '${_filterCategory!.name} — ${_filterCity!.name}';
        }
        if (_filterCity != null) return 'Places — ${_filterCity!.name}';
        if (_filterCategory != null) return 'Places — ${_filterCategory!.name}';
        return 'Places';
      case 4:
        return 'Blog';
      case 5:
        return 'Role Requests';
      case 6:
        return 'Payment Methods';
      case 7:
        return 'Bookings';
      case 8:
        return 'Reports';
      case 9:
        return 'Messages';
      case 10:
        return 'Settings';
      case 11:
        return 'Static Pages';
      case 12:
        return 'Audit Log';
      default:
        return 'Admin';
    }
  }

  String get _pageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'System overview & quick actions';
      case 1:
        return 'Add, edit and remove resort destinations';
      case 2:
        return 'Manage global categories and subcategories';
      case 3:
        if (_filterCity != null && _filterCategory == null) {
          return 'Showing places in ${_filterCity!.name}';
        }
        return 'Manage listings and places';
      case 4:
        return 'Create, edit and publish blog articles';
      case 5:
        final c = _pendingRequestsCount;
        return c > 0
            ? '$c pending request${c == 1 ? '' : 's'} awaiting review'
            : 'Review and manage admin role requests';
      case 6:
        return 'Configure the payment options places can accept';
      case 7:
        return 'Review and manage tourist booking requests';
      case 8:
        return 'System-wide bookings analytics';
      case 9:
        return 'Messages submitted through the landing page contact form';
      case 10:
        return 'Contact info, footer links, maintenance mode and data export';
      case 11:
        return 'Edit About Us, Privacy Policy, Terms of Service, Cookie Policy';
      case 12:
        return 'Every admin action, in order — who did what, and when';
      default:
        return '';
    }
  }

  // ── Body router ───────────────────────────────────────────────────────────
  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _DashboardOverview(
          stats: _stats,
          isLoading: _statsLoading,
          onGoTo: _onNavTap,
          pendingRequestsCount:
              _canManageRoleRequests ? _pendingRequestsCount : 0,
          canManageRoleRequests: _canManageRoleRequests,
        );
      case 1:
        return AdminResortCitiesScreen(
          apiService: _apiService,
          onCitySelected: (city) => setState(() {
            _filterCity = city;
            _filterCategory = null;
            _selectedIndex = 3;
          }),
          onCityForCategoriesSelected: (city) => setState(() {
            _filterCity = city;
            _filterCategory = null;
            _selectedIndex = 3;
          }),
        );
      case 2:
        return AdminCategoriesScreen(apiService: _apiService);
      case 3:
        return AdminPlacesScreen(
          apiService: _apiService,
          filterCity: _filterCity,
          filterCategory: _filterCategory,
          onCityFilterChanged: (city) => setState(() => _filterCity = city),
          onCategoryFilterChanged: (cat) =>
              setState(() => _filterCategory = cat),
        );
      case 4:
        return AdminBlogListScreen(apiService: _apiService);
      case 5:
        return const AdminRoleRequestsScreen();
      case 6:
        return const AdminPaymentMethodsScreen();
      case 7:
        return const AdminBookingsScreen();
      case 8:
        return AdminReportsScreen(apiService: _apiService);
      case 9:
        return const AdminContactMessagesScreen();
      case 10:
        return const AdminSettingsScreen();
      case 11:
        return const AdminStaticPagesScreen();
      case 12:
        return const AdminAuditLogScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Mobile drawer ─────────────────────────────────────────────────────────
  void _showMobileDrawer(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.80),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ..._navItems
                  .asMap()
                  .entries
                  .where((e) =>
                      !_mainAdminOnlyIndices.contains(e.key) ||
                      _canManageRoleRequests)
                  .map((e) {
                final isRoleReq = e.key == 5;
                return ListTile(
                  leading: isRoleReq && _pendingRequestsCount > 0
                      ? _BadgedIcon(
                          icon: e.value.icon,
                          count: _pendingRequestsCount,
                          color: _selectedIndex == e.key
                              ? const Color(0xFF14FFEC)
                              : Colors.white54,
                        )
                      : Icon(e.value.icon,
                          color: _selectedIndex == e.key
                              ? const Color(0xFF14FFEC)
                              : Colors.white54),
                  title: Text(e.value.label,
                      style: TextStyle(
                        color: _selectedIndex == e.key
                            ? const Color(0xFF14FFEC)
                            : Colors.white70,
                        fontWeight: _selectedIndex == e.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      )),
                  onTap: () {
                    Navigator.pop(context);
                    _onNavTap(e.key);
                  },
                );
              }),
              if (_adminRole == RbacService.roleMainAdmin) ...[
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: const Icon(Icons.storefront_rounded,
                      color: Color(0xFF14FFEC)),
                  title: const Text('Place Admin',
                      style: TextStyle(
                          color: Color(0xFF14FFEC),
                          fontWeight: FontWeight.w600)),
                  subtitle: const Text('Manage a specific place',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    _openPlaceAdminPicker();
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────
class _AdminSidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final bool isExpanded;
  final ValueChanged<int> onTap;
  final CityModel? filterCity;
  final CategoryModel? filterCategory;
  final int pendingRequestsCount;
  final bool canManageRoleRequests;
  final VoidCallback? onOpenPlaceAdmin;

  const _AdminSidebar({
    required this.items,
    required this.selectedIndex,
    required this.isExpanded,
    required this.onTap,
    this.filterCity,
    this.filterCategory,
    this.pendingRequestsCount = 0,
    this.canManageRoleRequests = false,
    this.onOpenPlaceAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isShortScreen = screenHeight < 500;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: isExpanded ? 220 : 72,
      color: const Color(0xFF111827),
      child: Column(
        children: [
          SizedBox(height: isShortScreen ? 16 : 48),

          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded,
                    color: Color(0xFF14FFEC), size: 20),
              ),
              if (isExpanded) ...[
                const SizedBox(width: 12),
                const Text('Admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ]),
          ),
          SizedBox(height: isShortScreen ? 8 : 24),

          // Nav items — scrollable so they never overflow in landscape
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...items.asMap().entries.map((e) {
                    if (_mainAdminOnlyIndices.contains(e.key) &&
                        !canManageRoleRequests) {
                      return const SizedBox.shrink();
                    }

                    final isSelected = selectedIndex == e.key;
                    final isRoleReq = e.key == 5;
                    final hasBadge = isRoleReq && pendingRequestsCount > 0;

                    return _SidebarItem(
                      icon: e.value.icon,
                      label: e.value.label,
                      isSelected: isSelected,
                      isExpanded: isExpanded,
                      badgeCount: hasBadge ? pendingRequestsCount : 0,
                      onTap: () => onTap(e.key),
                    );
                  }),
                ],
              ),
            ),
          ),

          // Active filter chips
          if (isExpanded && (filterCity != null || filterCategory != null)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active filters',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 6),
                  if (filterCity != null)
                    _ContextChip(
                        icon: Icons.location_city_rounded,
                        label: filterCity!.name,
                        color: const Color(0xFF0D7377)),
                  if (filterCategory != null) ...[
                    const SizedBox(height: 4),
                    _ContextChip(
                        icon: Icons.category_rounded,
                        label: filterCategory!.name,
                        color: const Color(0xFF2196F3)),
                  ],
                ],
              ),
            ),
          ],

          // Place Admin — MainAdmin-only entry point to inspect any place's
          // scoped panel without leaving their own account.
          if (onOpenPlaceAdmin != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: onOpenPlaceAdmin,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                      horizontal: isExpanded ? 12 : 0, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.storefront_rounded,
                          size: 20, color: Color(0xFF14FFEC)),
                      if (isExpanded) ...[
                        const SizedBox(width: 12),
                        const Text('Place Admin',
                            style: TextStyle(
                                color: Color(0xFF14FFEC), fontSize: 14)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: isShortScreen ? 8 : 12),
          ],

          SizedBox(height: isShortScreen ? 8 : 24),

          // Back to App
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(
                    horizontal: isExpanded ? 12 : 0, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded,
                        size: 20, color: Colors.white38),
                    if (isExpanded) ...[
                      const SizedBox(width: 12),
                      const Text('Back to App',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: isShortScreen ? 8 : 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar item — with optional live badge count
// ─────────────────────────────────────────────────────────────────────────────
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding:
            EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 0, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF14FFEC).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          mainAxisAlignment:
              isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            badgeCount > 0
                ? _BadgedIcon(
                    icon: icon,
                    count: badgeCount,
                    color:
                        isSelected ? const Color(0xFF14FFEC) : Colors.white38,
                  )
                : Icon(icon,
                    size: 20,
                    color:
                        isSelected ? const Color(0xFF14FFEC) : Colors.white38),
            if (isExpanded) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF14FFEC)
                            : Colors.white54,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal)),
              ),
              if (badgeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$badgeCount',
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Badged Icon — floating dot top-right of the icon
// ─────────────────────────────────────────────────────────────────────────────
class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _BadgedIcon({
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 20, color: color),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Color(0xFFFF9800),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Context chip
// ─────────────────────────────────────────────────────────────────────────────
class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ContextChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _AdminTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onMenuTap;
  const _AdminTopBar(
      {required this.title, required this.subtitle, this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onMenuTap != null) ...[
            IconButton(
              onPressed: onMenuTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.menu_rounded,
                  color: Colors.white54, size: 22),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isNarrow ? 15 : 18,
                      fontWeight: FontWeight.bold),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white38, fontSize: isNarrow ? 10 : 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isNarrow)
            IconButton(
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: Color(0xFF14FFEC)),
            )
          else
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: Color(0xFF14FFEC)),
              label: const Text('Back to App',
                  style: TextStyle(
                      color: Color(0xFF14FFEC),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                backgroundColor:
                    const Color(0xFF14FFEC).withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Overview
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardOverview extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isLoading;
  final ValueChanged<int> onGoTo;
  final int pendingRequestsCount;
  final bool canManageRoleRequests;

  const _DashboardOverview({
    required this.stats,
    required this.isLoading,
    required this.onGoTo,
    this.pendingRequestsCount = 0,
    this.canManageRoleRequests = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final int statColumns = availableWidth < 480
            ? 2
            : availableWidth < 900
                ? 3
                : 4;
        final double statCardW =
            ((availableWidth - 48) - (statColumns - 1) * 16) / statColumns;

        final int actionColumns = availableWidth < 480
            ? 1
            : availableWidth < 900
                ? 2
                : 3;
        final double actionCardW =
            ((availableWidth - 48) - (actionColumns - 1) * 16) / actionColumns;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stats cards ──────────────────────────────────────────────
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    icon: Icons.location_city_rounded,
                    label: 'Resort Cities',
                    value: isLoading ? '…' : '${stats['cities_total'] ?? 0}',
                    color: const Color(0xFF0D7377),
                    cardWidth: statCardW,
                    onTap: () => onGoTo(1),
                  ),
                  _StatCard(
                    icon: Icons.people_rounded,
                    label: 'Registered Users',
                    value: isLoading ? '…' : '${stats['users_total'] ?? 0}',
                    color: const Color(0xFF2196F3),
                    cardWidth: statCardW,
                    onTap: () => onGoTo(0),
                  ),
                  _StatCard(
                    icon: Icons.place_rounded,
                    label: 'Active Places',
                    value: isLoading ? '…' : '${stats['places_active'] ?? 0}',
                    color: const Color(0xFF9C27B0),
                    cardWidth: statCardW,
                    onTap: () => onGoTo(3),
                  ),
                  _StatCard(
                    icon: Icons.pending_actions_rounded,
                    label: 'Pending Drafts',
                    value: isLoading ? '…' : '${stats['places_pending'] ?? 0}',
                    color: const Color(0xFFFF9800),
                    cardWidth: statCardW,
                    onTap: () => onGoTo(3),
                  ),
                  if (canManageRoleRequests)
                    _StatCard(
                      icon: Icons.manage_accounts_rounded,
                      label: 'Role Requests',
                      value: '$pendingRequestsCount',
                      color: const Color(0xFFFF9800),
                      cardWidth: statCardW,
                      onTap: () => onGoTo(5),
                      badge: pendingRequestsCount > 0
                          ? pendingRequestsCount
                          : null,
                    ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Growth chart ─────────────────────────────────────────────
              const _GrowthChartCard(),

              const SizedBox(height: 32),

              // ── Quick Actions ──────────────────────────────────────────
              const Text('Quick Actions',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _QuickAction(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Add Resort City',
                    description: 'Create a new resort destination',
                    color: const Color(0xFF0D7377),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(1),
                  ),
                  _QuickAction(
                    icon: Icons.add_box_rounded,
                    label: 'Add Category',
                    description: 'Create a global service category',
                    color: const Color(0xFF2196F3),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(2),
                  ),
                  _QuickAction(
                    icon: Icons.add_business_rounded,
                    label: 'Add Place',
                    description: 'List a new place or business',
                    color: const Color(0xFF9C27B0),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(3),
                  ),
                  _QuickAction(
                    icon: Icons.edit_note_rounded,
                    label: 'Write Blog Post',
                    description: 'Publish a new article or guide',
                    color: const Color(0xFFE91E8C),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(4),
                  ),
                  if (canManageRoleRequests)
                    _QuickAction(
                      icon: Icons.manage_accounts_rounded,
                      label: 'Role Requests',
                      description: pendingRequestsCount > 0
                          ? '$pendingRequestsCount pending • tap to review'
                          : 'Review admin role applications',
                      color: const Color(0xFFFF9800),
                      cardWidth: actionCardW,
                      onTap: () => onGoTo(5),
                      badge: pendingRequestsCount > 0
                          ? pendingRequestsCount
                          : null,
                    ),
                  _QuickAction(
                    icon: Icons.payments_rounded,
                    label: 'Payment Methods',
                    description: 'Configure accepted payment options',
                    color: const Color(0xFF0D7377),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(6),
                  ),
                  _QuickAction(
                    icon: Icons.calendar_month_rounded,
                    label: 'Bookings',
                    description: 'Review tourist booking requests',
                    color: const Color(0xFF2196F3),
                    cardWidth: actionCardW,
                    onTap: () => onGoTo(7),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              _WorkflowGuide(),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Growth Chart — line chart over DashboardSnapshots (see
// dashboard_snapshot_service.dart). Starts sparse on a fresh install and
// fills in day by day — no fabricated history.
// ─────────────────────────────────────────────────────────────────────────────
class _GrowthChartCard extends StatelessWidget {
  const _GrowthChartCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Growth — Last 30 Days',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Active places, resort cities and registered users, sampled '
              'once per day.',
              style: TextStyle(color: Colors.white38, fontSize: 11.5)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: StreamBuilder<List<DashboardSnapshot>>(
              stream: DashboardSnapshotService.streamRecent(),
              builder: (context, snap) {
                final points = snap.data ?? const <DashboardSnapshot>[];
                if (points.length < 2) {
                  return const Center(
                    child: Text(
                      'Not enough history yet — check back after a few '
                      'days of activity to see a trend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  );
                }
                return _GrowthLineChart(points: points);
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 6, children: const [
            _LegendDot(color: Color(0xFF9C27B0), label: 'Active places'),
            _LegendDot(color: Color(0xFF0D7377), label: 'Resort cities'),
            _LegendDot(color: Color(0xFF2196F3), label: 'Users'),
          ]),
        ],
      ),
    );
  }
}

class _GrowthLineChart extends StatelessWidget {
  final List<DashboardSnapshot> points;
  const _GrowthLineChart({required this.points});

  List<FlSpot> _spots(int Function(DashboardSnapshot) value) => List.generate(
      points.length, (i) => FlSpot(i.toDouble(), value(points[i]).toDouble()));

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<int>(
        1,
        (m, p) => [m, p.placesActive, p.citiesTotal, p.usersTotal]
            .reduce((a, b) => a > b ? a : b));

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY * 1.2).ceilToDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) => Text('${v.toInt()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (points.length / 4).clamp(1, points.length).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final d = points[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.day}/${d.month}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1F2937),
          ),
        ),
        lineBarsData: [
          _line(_spots((p) => p.placesActive), const Color(0xFF9C27B0)),
          _line(_spots((p) => p.citiesTotal), const Color(0xFF0D7377)),
          _line(_spots((p) => p.usersTotal), const Color(0xFF2196F3)),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData:
            BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Card — with optional badge
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final int? badge;
  final double? cardWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.badge,
    this.cardWidth,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF9800), shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        badge! > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(
                              color: color,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                    ),
                    Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ]),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action card — with optional live badge
// ─────────────────────────────────────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
  final double? cardWidth;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
    this.badge,
    this.cardWidth,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  Icon(icon, color: color, size: 28),
                  if (badge != null && badge! > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF9800), shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            badge! > 9 ? '9+' : '$badge',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]),
              const SizedBox(height: 12),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Workflow guide
// ─────────────────────────────────────────────────────────────────────────────
class _WorkflowGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.map_rounded, color: Color(0xFF14FFEC), size: 18),
              SizedBox(width: 10),
              Text('Setup Workflow',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ]),
            const SizedBox(height: 20),
            _step(
                '1',
                'Resort Cities',
                'Create each destination city (e.g. Mombasa, Nairobi).',
                const Color(0xFF0D7377)),
            _step(
                '2',
                'Categories',
                'Create global categories (Accommodation, Dining, Wellness…).',
                const Color(0xFF2196F3)),
            _step('3', 'Places', 'Add each place via the 11-step wizard.',
                const Color(0xFF9C27B0)),
            _step('4', 'Blog', 'Publish articles, guides, and city highlights.',
                const Color(0xFFE91E8C)),
            _step(
                '5',
                'Role Requests',
                'Review and approve admin role applications from users.',
                const Color(0xFFFF9800)),
            _step(
                '6',
                'Payment Methods',
                'Define which payment options places can accept (M-Pesa, Card, Cash…).',
                const Color(0xFF0D7377)),
            _step(
                '7',
                'Bookings',
                'Review and confirm booking requests submitted by tourists.',
                const Color(0xFF2196F3)),
          ],
        ),
      );

  Widget _step(String num, String title, String body, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Center(
                  child: Text(num,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
