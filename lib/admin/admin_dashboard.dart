import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_resort_cities_screen.dart';
import 'package:palmnazi/admin/admin_categories_screen.dart';
import 'package:palmnazi/admin/admin_places_screen.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin Dashboard
//
// Navigation:
//   0 — Dashboard overview
//   1 — Resort Cities CRUD
//   2 — Categories CRUD (global — no city scope)
//   3 — Places CRUD (city + category filter, multi-step wizard)
//
// Key architectural change from previous version:
//   • Channels are now Categories — they are GLOBAL, not scoped to a city.
//   • Selecting a city is not required to manage categories.
//   • The Places tab accepts optional city/category filter context
//     but does not require them — it shows all places by default.
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

  // Optional filter context passed to the Places tab
  CityModel? _filterCity;
  CategoryModel? _filterCategory;

  final _apiService = AdminApiService();
  Map<String, dynamic> _stats = {};
  bool _statsLoading = true;

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.location_city_rounded, 'Resort Cities'),
    _NavItem(Icons.category_rounded, 'Categories'),
    _NavItem(Icons.place_rounded, 'Places'),
  ];

  @override
  void initState() {
    super.initState();
    _sidebarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    _loadStats();
  }

  Future<void> _loadStats() async {
    debugPrint('📊 [Dashboard] Loading stats');
    try {
      final s = await _apiService.getDashboardStats();
      debugPrint('✅ [Dashboard] Stats loaded — keys=${s.keys.toList()}');
      if (mounted) setState(() { _stats = s; _statsLoading = false; });
    } catch (e, st) {
      debugPrint('❌ [Dashboard] getDashboardStats failed: $e\n$st');
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  void dispose() {
    _sidebarAnim.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 3) {
        // Clear both filters when leaving Places via the nav bar/sidebar so
        // returning later starts with the full unfiltered list.
        _filterCategory = null;
        _filterCity = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= 1100;
    final isTablet = w >= 700;

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
      bottomNavigationBar: isTablet
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xFF111827),
              indicatorColor: const Color(0xFF14FFEC).withValues(alpha: 0.15),
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onNavTap,
              destinations: _navItems
                  .map((e) => NavigationDestination(
                        icon: Icon(e.icon, color: Colors.white54),
                        selectedIcon:
                            Icon(e.icon, color: const Color(0xFF14FFEC)),
                        label: e.label,
                      ))
                  .toList(),
            ),
    );
  }

  String get _pageTitle {
    switch (_selectedIndex) {
      case 0: return 'Admin Console';
      case 1: return 'Resort Cities';
      case 2: return 'Categories';
      case 3:
        if (_filterCategory != null && _filterCity != null) {
          return '${_filterCategory!.name} — ${_filterCity!.name}';
        }
        if (_filterCity != null) return 'Places — ${_filterCity!.name}';
        if (_filterCategory != null) return 'Places — ${_filterCategory!.name}';
        return 'Places';
      default: return 'Admin';
    }
  }

  String get _pageSubtitle {
    switch (_selectedIndex) {
      case 0: return 'System overview & quick actions';
      case 1: return 'Add, edit and remove resort destinations';
      case 2: return 'Manage global categories and subcategories';
      case 3:
        if (_filterCity != null && _filterCategory == null) {
          return 'Showing places in ${_filterCity!.name} · use the category filter to narrow down';
        }
        return 'Manage listings and places';
      default: return '';
    }
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _DashboardOverview(
          stats: _stats,
          isLoading: _statsLoading,
          onGoTo: _onNavTap,
        );
      case 1:
        return AdminResortCitiesScreen(
          apiService: _apiService,
          // "Places" button → Places tab pre-filtered by city only
          onCitySelected: (city) => setState(() {
            _filterCity = city;
            _filterCategory = null;
            _selectedIndex = 3;
          }),
          // "Categories" button → Places tab pre-filtered by city;
          // the user picks a category from the filter row to drill down further.
          // We also clear any stale category filter so the dropdown starts fresh.
          onCityForCategoriesSelected: (city) => setState(() {
            _filterCity = city;
            _filterCategory = null;
            _selectedIndex = 3;
          }),
        );
      case 2:
        // Categories are global — no city context required
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
      default:
        return const SizedBox.shrink();
    }
  }

  void _showMobileDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
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
          ..._navItems.asMap().entries.map((e) => ListTile(
                leading: Icon(e.value.icon,
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
              )),
          const SizedBox(height: 16),
        ],
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

  const _AdminSidebar({
    required this.items,
    required this.selectedIndex,
    required this.isExpanded,
    required this.onTap,
    this.filterCity,
    this.filterCategory,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: isExpanded ? 220 : 72,
      color: const Color(0xFF111827),
      child: Column(
        children: [
          const SizedBox(height: 48),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
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
          const SizedBox(height: 24),

          // Nav items
          ...items.asMap().entries.map((e) {
            final isSelected = selectedIndex == e.key;
            return _SidebarItem(
              icon: e.value.icon,
              label: e.value.label,
              isSelected: isSelected,
              isExpanded: isExpanded,
              onTap: () => onTap(e.key),
            );
          }),

          const Spacer(),

          // Active filter context chips
          if (isExpanded && (filterCity != null || filterCategory != null)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active filters',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: EdgeInsets.symmetric(
            horizontal: isExpanded ? 12 : 0, vertical: 12),
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
          mainAxisAlignment: isExpanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 20,
                color: isSelected
                    ? const Color(0xFF14FFEC)
                    : Colors.white38),
            if (isExpanded) ...[
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: isSelected ? const Color(0xFF14FFEC) : Colors.white54,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ],
        ),
      ),
    );
  }
}

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
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(children: [
        if (onMenuTap != null) ...[
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.menu_rounded, color: Colors.white54, size: 22),
          ),
          const SizedBox(width: 8),
        ],
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(subtitle,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard overview
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardOverview extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isLoading;
  final ValueChanged<int> onGoTo;

  const _DashboardOverview(
      {required this.stats, required this.isLoading, required this.onGoTo});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                icon: Icons.location_city_rounded,
                label: 'Resort Cities',
                value: isLoading ? '…' : '${stats['totalCities'] ?? 0}',
                color: const Color(0xFF0D7377),
                onTap: () => onGoTo(1),
              ),
              _StatCard(
                icon: Icons.category_rounded,
                label: 'Categories',
                value: isLoading ? '…' : '${stats['totalCategories'] ?? 0}',
                color: const Color(0xFF2196F3),
                onTap: () => onGoTo(2),
              ),
              _StatCard(
                icon: Icons.place_rounded,
                label: 'Active Places',
                value: isLoading ? '…' : '${stats['totalPlaces'] ?? 0}',
                color: const Color(0xFF9C27B0),
                onTap: () => onGoTo(3),
              ),
              _StatCard(
                icon: Icons.pending_actions_rounded,
                label: 'Pending Drafts',
                value: isLoading ? '…' : '${stats['pendingPlaces'] ?? 0}',
                color: const Color(0xFFFF9800),
                onTap: () => onGoTo(3),
              ),
            ],
          ),
          const SizedBox(height: 32),
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
                onTap: () => onGoTo(1),
              ),
              _QuickAction(
                icon: Icons.add_box_rounded,
                label: 'Add Category',
                description: 'Create a global service category',
                color: const Color(0xFF2196F3),
                onTap: () => onGoTo(2),
              ),
              _QuickAction(
                icon: Icons.add_business_rounded,
                label: 'Add Place',
                description: 'List a new place or business',
                color: const Color(0xFF9C27B0),
                onTap: () => onGoTo(3),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _WorkflowGuide(),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.color, this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 28, fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ]),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon, required this.label,
    required this.description, required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(description,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
      );
}

class _WorkflowGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.map_rounded, color: Color(0xFF14FFEC), size: 18),
            SizedBox(width: 10),
            Text('Setup Workflow',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          ]),
          const SizedBox(height: 20),
          _step('1', 'Resort Cities',
              'Create each destination city (e.g. Mombasa, Nairobi).',
              const Color(0xFF0D7377)),
          _step('2', 'Categories',
              'Create global categories (Accommodation, Dining, Wellness…). These are shared across all cities.',
              const Color(0xFF2196F3)),
          _step('3', 'Places',
              'Add each place via the 11-step wizard. At step 9, link it to all categories it belongs to — this is how one place appears in multiple channels.',
              const Color(0xFF9C27B0)),
        ]),
      );

  Widget _step(String num, String title, String body, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text(body,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12, height: 1.5)),
          ])),
        ]),
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