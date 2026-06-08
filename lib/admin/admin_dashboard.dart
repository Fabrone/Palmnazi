import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_resort_cities_screen.dart';
import 'package:palmnazi/admin/admin_categories_screen.dart';
import 'package:palmnazi/admin/admin_places_screen.dart';
import 'package:palmnazi/admin/admin_blog_list_screen.dart';
import 'package:palmnazi/admin/admin_role_requests_screen.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:palmnazi/services/rbac_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logger
// ─────────────────────────────────────────────────────────────────────────────
final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount:      0,
    errorMethodCount: 8,
    lineLength:       100,
    colors:           true,
    printEmojis:      true,
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
//   5 — Role Requests (MainAdmin only — live badge dot on pending count)
// ─────────────────────────────────────────────────────────────────────────────

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
  CityModel?     _filterCity;
  CategoryModel? _filterCategory;

  final _apiService = AdminApiService();
  Map<String, dynamic> _stats = {};
  bool _statsLoading = true;

  // ── RBAC — live role + pending requests counter ───────────────────────────
  int                         _pendingRequestsCount = 0;
  StreamSubscription<int>?    _pendingCountSub;
  StreamSubscription<String>? _roleSub;
  String?                     _adminRole; // 'Admin' or 'MainAdmin'

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded,       'Dashboard'),
    _NavItem(Icons.location_city_rounded,   'Resort Cities'),
    _NavItem(Icons.category_rounded,        'Categories'),
    _NavItem(Icons.place_rounded,           'Places'),
    _NavItem(Icons.article_rounded,         'Blog'),
    _NavItem(Icons.manage_accounts_rounded, 'Role Requests'),
  ];

  @override
  void initState() {
    super.initState();
    _log.i('🏁 [AdminDashboard] initState — uid=${FirebaseAuth.instance.currentUser?.uid ?? "null"}');
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
      _log.e('❌ [AdminDashboard._initRbac] Firebase uid still null after wait — RBAC listeners not started');
      return;
    }

    _log.i('🔐 [AdminDashboard._initRbac] Starting Firestore role stream for uid=$firebaseUid');
    _roleSub?.cancel();

    // Role is read directly from the Firestore Users/{firebaseUid} document —
    // the 'role' field is the single source of truth and never proxied via the API.
    _roleSub = FirebaseFirestore.instance
        .collection('Users')
        .doc(firebaseUid)
        .snapshots()
        .map((snap) => (snap.data()?['role'] as String? ?? '').trim())
        .listen(
      (role) {
        if (!mounted) return;

        // The Firestore snapshot is already mapped and trimmed above, but we
        // trim again here as a permanent safety net.
        final cleanRole    = role.trim();
        final wasMainAdmin = _adminRole?.trim() == 'MainAdmin';

        setState(() => _adminRole = cleanRole);

        if (cleanRole == 'MainAdmin' && !wasMainAdmin) {
          _log.i('🔐 [AdminDashboard._initRbac] Role confirmed as MainAdmin — starting listeners');
          _pendingCountSub?.cancel();
          _pendingCountSub = RbacService.pendingRequestsCountStream().listen(
            (count) {
              if (mounted) setState(() => _pendingRequestsCount = count);
            },
            onError: (e) => _log.w('⚠️ [AdminDashboard] pendingCountStream error: $e'),
          );
          NotificationService.startAdminRequestsListener();

        } else if (cleanRole == 'MainAdmin' && wasMainAdmin) {
          // Role re-confirmed, no action needed
        } else if (cleanRole != 'MainAdmin' && wasMainAdmin) {
          _log.w('⚠️ [AdminDashboard._initRbac] Role downgraded from MainAdmin → "$cleanRole" — cancelling listeners');
          _pendingCountSub?.cancel();
          _pendingCountSub = null;
          setState(() => _pendingRequestsCount = 0);
        } else {
          _log.w('⚠️ [AdminDashboard._initRbac] Role is "$cleanRole" — Role Requests UI hidden');
        }
      },
      onError: (e) {
        _log.e('❌ [AdminDashboard._initRbac] Firestore role stream error: $e', error: e);
      },
      onDone: () {
        _log.w('⚠️ [AdminDashboard._initRbac] Firestore role stream closed unexpectedly');
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Wait until Firebase Auth has a signed-in user (max 3 s).
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _waitForFirebaseAuth({int maxWaitMs = 3000}) async {
    const tickMs = 200;
    int waited = 0;
    if (FirebaseAuth.instance.currentUser != null) return;
    _log.w('⚠️ [AdminDashboard._waitForFirebaseAuth] Firebase user null — polling…');
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
      if (mounted) setState(() { _stats = s; _statsLoading = false; });
    } catch (e, st) {
      _log.e('❌ [AdminDashboard._loadStats] getDashboardStats failed', error: e, stackTrace: st);
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
        _filterCity     = null;
      }
    });
  }

  bool get _isMainAdmin => _adminRole?.trim() == 'MainAdmin';

  @override
  Widget build(BuildContext context) {
    final w         = MediaQuery.of(context).size.width;
    final h         = MediaQuery.of(context).size.height;
    final isDesktop = w >= 1100;
    // A phone in landscape has w ≥ 700 but h < 500 — treat as mobile so the
    // bottom nav stays visible and the sidebar doesn't overflow.
    final isTablet  = w >= 700 && h >= 500;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Row(
        children: [
          if (isTablet)
            _AdminSidebar(
              items:                _navItems,
              selectedIndex:        _selectedIndex,
              isExpanded:           isDesktop,
              onTap:                _onNavTap,
              filterCity:           _filterCity,
              filterCategory:       _filterCategory,
              pendingRequestsCount: _isMainAdmin ? _pendingRequestsCount : 0,
              isMainAdmin:          _isMainAdmin,
            ),
          Expanded(
            child: Column(
              children: [
                _AdminTopBar(
                  title:     _pageTitle,
                  subtitle:  _pageSubtitle,
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
      if (i == 5 && !_isMainAdmin) continue;

      final isRoleRequests = i == 5;
      final hasBadge = isRoleRequests && _pendingRequestsCount > 0;

      destinations.add(NavigationDestination(
        icon: hasBadge
            ? _BadgedIcon(icon: item.icon, count: _pendingRequestsCount, color: Colors.white54)
            : Icon(item.icon, color: Colors.white54),
        selectedIcon: hasBadge
            ? _BadgedIcon(icon: item.icon, count: _pendingRequestsCount, color: const Color(0xFF14FFEC))
            : Icon(item.icon, color: const Color(0xFF14FFEC)),
        label: item.label,
      ));
    }

    final logicalIndices = [0, 1, 2, 3, 4, if (_isMainAdmin) 5];
    final visualIndex = logicalIndices.contains(_selectedIndex)
        ? logicalIndices.indexOf(_selectedIndex)
        : 0;

    return NavigationBar(
      backgroundColor:      const Color(0xFF111827),
      indicatorColor:       const Color(0xFF14FFEC).withValues(alpha: 0.15),
      selectedIndex:        visualIndex,
      onDestinationSelected: (vi) => _onNavTap(logicalIndices[vi]),
      destinations:         destinations,
    );
  }

  // ── Page title / subtitle ─────────────────────────────────────────────────
  String get _pageTitle {
    switch (_selectedIndex) {
      case 0:  return 'Admin Console';
      case 1:  return 'Resort Cities';
      case 2:  return 'Categories';
      case 3:
        if (_filterCategory != null && _filterCity != null) {
          return '${_filterCategory!.name} — ${_filterCity!.name}';
        }
        if (_filterCity     != null) return 'Places — ${_filterCity!.name}';
        if (_filterCategory != null) return 'Places — ${_filterCategory!.name}';
        return 'Places';
      case 4:  return 'Blog';
      case 5:  return 'Role Requests';
      default: return 'Admin';
    }
  }

  String get _pageSubtitle {
    switch (_selectedIndex) {
      case 0:  return 'System overview & quick actions';
      case 1:  return 'Add, edit and remove resort destinations';
      case 2:  return 'Manage global categories and subcategories';
      case 3:
        if (_filterCity != null && _filterCategory == null) {
          return 'Showing places in ${_filterCity!.name}';
        }
        return 'Manage listings and places';
      case 4:  return 'Create, edit and publish blog articles';
      case 5:
        final c = _pendingRequestsCount;
        return c > 0
            ? '$c pending request${c == 1 ? '' : 's'} awaiting review'
            : 'Review and manage admin role requests';
      default: return '';
    }
  }

  // ── Body router ───────────────────────────────────────────────────────────
  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _DashboardOverview(
          stats:                _stats,
          isLoading:            _statsLoading,
          onGoTo:               _onNavTap,
          pendingRequestsCount: _isMainAdmin ? _pendingRequestsCount : 0,
          isMainAdmin:          _isMainAdmin,
        );
      case 1:
        return AdminResortCitiesScreen(
          apiService:               _apiService,
          onCitySelected:           (city) => setState(() {
            _filterCity     = city;
            _filterCategory = null;
            _selectedIndex  = 3;
          }),
          onCityForCategoriesSelected: (city) => setState(() {
            _filterCity     = city;
            _filterCategory = null;
            _selectedIndex  = 3;
          }),
        );
      case 2:
        return AdminCategoriesScreen(apiService: _apiService);
      case 3:
        return AdminPlacesScreen(
          apiService:              _apiService,
          filterCity:              _filterCity,
          filterCategory:          _filterCategory,
          onCityFilterChanged:     (city) => setState(() => _filterCity     = city),
          onCategoryFilterChanged: (cat)  => setState(() => _filterCategory = cat),
        );
      case 4:
        return AdminBlogListScreen(apiService: _apiService);
      case 5:
        return const AdminRoleRequestsScreen();
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ..._navItems.asMap().entries
                  .where((e) => e.key != 5 || _isMainAdmin)
                  .map((e) {
                final isRoleReq = e.key == 5;
                return ListTile(
                  leading: isRoleReq && _pendingRequestsCount > 0
                      ? _BadgedIcon(
                          icon:  e.value.icon,
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
  final List<_NavItem>    items;
  final int               selectedIndex;
  final bool              isExpanded;
  final ValueChanged<int> onTap;
  final CityModel?        filterCity;
  final CategoryModel?    filterCategory;
  final int               pendingRequestsCount;
  final bool              isMainAdmin;

  const _AdminSidebar({
    required this.items,
    required this.selectedIndex,
    required this.isExpanded,
    required this.onTap,
    this.filterCity,
    this.filterCategory,
    this.pendingRequestsCount = 0,
    this.isMainAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight  = MediaQuery.of(context).size.height;
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
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.3)),
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
                    if (e.key == 5 && !isMainAdmin) return const SizedBox.shrink();

                    final isSelected = selectedIndex == e.key;
                    final isRoleReq  = e.key == 5;
                    final hasBadge   = isRoleReq && pendingRequestsCount > 0;

                    return _SidebarItem(
                      icon:       e.value.icon,
                      label:      e.value.label,
                      isSelected: isSelected,
                      isExpanded: isExpanded,
                      badgeCount: hasBadge ? pendingRequestsCount : 0,
                      onTap:      () => onTap(e.key),
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
                        icon:  Icons.location_city_rounded,
                        label: filterCity!.name,
                        color: const Color(0xFF0D7377)),
                  if (filterCategory != null) ...[
                    const SizedBox(height: 4),
                    _ContextChip(
                        icon:  Icons.category_rounded,
                        label: filterCategory!.name,
                        color: const Color(0xFF2196F3)),
                  ],
                ],
              ),
            ),
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded, size: 20, color: Colors.white38),
                    if (isExpanded) ...[
                      const SizedBox(width: 12),
                      const Text('Back to App',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
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
  final IconData     icon;
  final String       label;
  final bool         isSelected;
  final bool         isExpanded;
  final int          badgeCount;
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
        margin:  const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: EdgeInsets.symmetric(
            horizontal: isExpanded ? 12 : 0, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF14FFEC).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF14FFEC).withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          mainAxisAlignment: isExpanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            badgeCount > 0
                ? _BadgedIcon(
                    icon:  icon,
                    count: badgeCount,
                    color: isSelected ? const Color(0xFF14FFEC) : Colors.white38,
                  )
                : Icon(icon,
                    size:  20,
                    color: isSelected ? const Color(0xFF14FFEC) : Colors.white38),

            if (isExpanded) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: isSelected ? const Color(0xFF14FFEC) : Colors.white54,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
  final int      count;
  final Color    color;

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
            top: -4, right: -4,
            child: Container(
              width: 14, height: 14,
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
  final String   label;
  final Color    color;
  const _ContextChip({required this.icon, required this.label, required this.color});

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
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _AdminTopBar extends StatelessWidget {
  final String        title;
  final String        subtitle;
  final VoidCallback? onMenuTap;
  const _AdminTopBar({required this.title, required this.subtitle, this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow    = screenWidth < 400;

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onMenuTap != null) ...[
            IconButton(
              onPressed: onMenuTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.menu_rounded, color: Colors.white54, size: 22),
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
                        color: Colors.white38,
                        fontSize: isNarrow ? 10 : 11),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                backgroundColor: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
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
  final bool                 isLoading;
  final ValueChanged<int>    onGoTo;
  final int                  pendingRequestsCount;
  final bool                 isMainAdmin;

  const _DashboardOverview({
    required this.stats,
    required this.isLoading,
    required this.onGoTo,
    this.pendingRequestsCount = 0,
    this.isMainAdmin = false,
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
                    icon:     Icons.location_city_rounded,
                    label:    'Resort Cities',
                    value:    isLoading ? '…' : '${stats['cities_total'] ?? 0}',
                    color:    const Color(0xFF0D7377),
                    cardWidth: statCardW,
                    onTap:    () => onGoTo(1),
                  ),
                  _StatCard(
                    icon:     Icons.people_rounded,
                    label:    'Registered Users',
                    value:    isLoading ? '…' : '${stats['users_total'] ?? 0}',
                    color:    const Color(0xFF2196F3),
                    cardWidth: statCardW,
                    onTap:    () => onGoTo(0),
                  ),
                  _StatCard(
                    icon:     Icons.place_rounded,
                    label:    'Active Places',
                    value:    isLoading ? '…' : '${stats['places_active'] ?? 0}',
                    color:    const Color(0xFF9C27B0),
                    cardWidth: statCardW,
                    onTap:    () => onGoTo(3),
                  ),
                  _StatCard(
                    icon:     Icons.pending_actions_rounded,
                    label:    'Pending Drafts',
                    value:    isLoading ? '…' : '${stats['places_pending'] ?? 0}',
                    color:    const Color(0xFFFF9800),
                    cardWidth: statCardW,
                    onTap:    () => onGoTo(3),
                  ),
                  if (isMainAdmin)
                    _StatCard(
                      icon:     Icons.manage_accounts_rounded,
                      label:    'Role Requests',
                      value:    '$pendingRequestsCount',
                      color:    const Color(0xFFFF9800),
                      cardWidth: statCardW,
                      onTap:    () => onGoTo(5),
                      badge:    pendingRequestsCount > 0 ? pendingRequestsCount : null,
                    ),
                ],
              ),

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
                    icon:        Icons.add_location_alt_rounded,
                    label:       'Add Resort City',
                    description: 'Create a new resort destination',
                    color:       const Color(0xFF0D7377),
                    cardWidth:   actionCardW,
                    onTap:       () => onGoTo(1),
                  ),
                  _QuickAction(
                    icon:        Icons.add_box_rounded,
                    label:       'Add Category',
                    description: 'Create a global service category',
                    color:       const Color(0xFF2196F3),
                    cardWidth:   actionCardW,
                    onTap:       () => onGoTo(2),
                  ),
                  _QuickAction(
                    icon:        Icons.add_business_rounded,
                    label:       'Add Place',
                    description: 'List a new place or business',
                    color:       const Color(0xFF9C27B0),
                    cardWidth:   actionCardW,
                    onTap:       () => onGoTo(3),
                  ),
                  _QuickAction(
                    icon:        Icons.edit_note_rounded,
                    label:       'Write Blog Post',
                    description: 'Publish a new article or guide',
                    color:       const Color(0xFFE91E8C),
                    cardWidth:   actionCardW,
                    onTap:       () => onGoTo(4),
                  ),
                  if (isMainAdmin)
                    _QuickAction(
                      icon:        Icons.manage_accounts_rounded,
                      label:       'Role Requests',
                      description: pendingRequestsCount > 0
                          ? '$pendingRequestsCount pending • tap to review'
                          : 'Review admin role applications',
                      color:       const Color(0xFFFF9800),
                      cardWidth:   actionCardW,
                      onTap:       () => onGoTo(5),
                      badge:       pendingRequestsCount > 0 ? pendingRequestsCount : null,
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
// Stat Card — with optional badge
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final String        value;
  final Color         color;
  final VoidCallback? onTap;
  final int?          badge;
  final double?       cardWidth;

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
                  top: -4, right: -4,
                  child: Container(
                    width: 16, height: 16,
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
  final IconData     icon;
  final String       label;
  final String       description;
  final Color        color;
  final VoidCallback onTap;
  final int?         badge;
  final double?      cardWidth;

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
                      top: -6, right: -6,
                      child: Container(
                        width: 16, height: 16,
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
            _step('1', 'Resort Cities',
                'Create each destination city (e.g. Mombasa, Nairobi).',
                const Color(0xFF0D7377)),
            _step('2', 'Categories',
                'Create global categories (Accommodation, Dining, Wellness…).',
                const Color(0xFF2196F3)),
            _step('3', 'Places',
                'Add each place via the 11-step wizard.',
                const Color(0xFF9C27B0)),
            _step('4', 'Blog',
                'Publish articles, guides, and city highlights.',
                const Color(0xFFE91E8C)),
            _step('5', 'Role Requests',
                'Review and approve admin role applications from users.',
                const Color(0xFFFF9800)),
          ],
        ),
      );

  Widget _step(String num, String title, String body, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28, height: 28,
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
  final String   label;
  const _NavItem(this.icon, this.label);
}