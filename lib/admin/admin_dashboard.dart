import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_resort_cities_screen.dart';
import 'package:palmnazi/admin/admin_channels_screen.dart';
import 'package:palmnazi/admin/admin_places_screen.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/models.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Admin Dashboard
/// Shell that hosts the sidebar/rail navigation and renders the active section.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _sidebarAnim;

  // Drill-down context
  CityModel? _selectedCity;
  ChannelItem? _selectedChannel;

  final _apiService = AdminApiService();
  Map<String, dynamic> _stats = {};
  bool _statsLoading = true;

  // Sidebar item definition
  static const _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.location_city_rounded, 'Resort Cities'),
    _NavItem(Icons.layers_rounded, 'Channels'),
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
    try {
      final s = await _apiService.getDashboardStats();
      if (mounted) setState(() { _stats = s; _statsLoading = false; });
    } catch (_) {
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
      // Reset drill-down when switching top-level tabs
      if (index != 2) _selectedChannel = null;
      if (index != 2 && index != 3) _selectedCity = null;
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
          // ── Sidebar (desktop/tablet) ────────────────────────────────────
          if (isTablet)
            _AdminSidebar(
              items: _navItems,
              selectedIndex: _selectedIndex,
              isExpanded: isDesktop,
              onTap: _onNavTap,
              selectedCity: _selectedCity,
              selectedChannel: _selectedChannel,
            ),

          // ── Main content ────────────────────────────────────────────────
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

      // ── Bottom nav (mobile) ─────────────────────────────────────────────
      bottomNavigationBar: isTablet
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xFF111827),
              indicatorColor: const Color(0xFF14FFEC).withValues(alpha: 0.15),
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onNavTap,
              destinations: _navItems
                  .map((e) => NavigationDestination(
                        icon: Icon(e.icon,
                            color: Colors.white54),
                        selectedIcon: Icon(e.icon,
                            color: const Color(0xFF14FFEC)),
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
      case 2:
        if (_selectedCity != null) return 'Channels — ${_selectedCity!.name}';
        return 'Channels';
      case 3:
        if (_selectedChannel != null) {
          return 'Places — ${_selectedChannel!.title}';
        }
        if (_selectedCity != null) return 'Places — ${_selectedCity!.name}';
        return 'Places';
      default: return 'Admin';
    }
  }

  String get _pageSubtitle {
    switch (_selectedIndex) {
      case 0: return 'System overview & quick actions';
      case 1: return 'Add, edit and remove resort destinations';
      case 2: return 'Manage categories within a city';
      case 3: return 'Manage specific listings & places';
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
          onCitySelected: (city) {
            setState(() {
              _selectedCity = city;
              _selectedIndex = 2;
            });
          },
        );
      case 2:
        return AdminChannelsScreen(
          apiService: _apiService,
          selectedCity: _selectedCity,
          onCityPickRequested: () => setState(() => _selectedIndex = 1),
          onChannelSelected: (channel) {
            setState(() {
              _selectedChannel = channel;
              _selectedIndex = 3;
            });
          },
        );
      case 3:
        return AdminPlacesScreen(
          apiService: _apiService,
          selectedCity: _selectedCity,
          selectedChannel: _selectedChannel,
          onCityPickRequested: () => setState(() => _selectedIndex = 1),
          onChannelPickRequested: () => setState(() => _selectedIndex = 2),
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

// ─────────────────────────────── SIDEBAR ─────────────────────────────────────

class _AdminSidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final bool isExpanded;
  final ValueChanged<int> onTap;
  final CityModel? selectedCity;
  final ChannelItem? selectedChannel;

  const _AdminSidebar({
    required this.items,
    required this.selectedIndex,
    required this.isExpanded,
    required this.onTap,
    this.selectedCity,
    this.selectedChannel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: isExpanded ? 230 : 72,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(right: BorderSide(color: Color(0xFF1F2937), width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                    ),
                  ),
                  child: const Icon(Icons.landscape, color: Colors.white, size: 22),
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'PALMNAZI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_rounded, size: 12, color: Color(0xFF14FFEC)),
                    SizedBox(width: 4),
                    Text('Admin Console',
                        style: TextStyle(fontSize: 10, color: Color(0xFF14FFEC))),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) {
                final selected = selectedIndex == i;
                return Tooltip(
                  message: isExpanded ? '' : items[i].label,
                  child: InkWell(
                    onTap: () => onTap(i),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        horizontal: isExpanded ? 14 : 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF14FFEC).withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(
                                color:
                                    const Color(0xFF14FFEC).withValues(alpha: 0.3),
                                width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            items[i].icon,
                            size: 20,
                            color: selected
                                ? const Color(0xFF14FFEC)
                                : Colors.white38,
                          ),
                          if (isExpanded) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                items[i].label,
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF14FFEC)
                                      : Colors.white54,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Breadcrumb trail
          if (isExpanded && (selectedCity != null || selectedChannel != null))
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2233),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Context',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                            letterSpacing: 1)),
                    const SizedBox(height: 6),
                    if (selectedCity != null)
                      _crumb(Icons.location_city_rounded, selectedCity!.name),
                    if (selectedChannel != null) ...[
                      const SizedBox(height: 4),
                      _crumb(Icons.layers_rounded, selectedChannel!.title),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _crumb(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 12, color: const Color(0xFF14FFEC)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ],
    );
  }
}

// ─────────────────────────────── TOP BAR ─────────────────────────────────────

class _AdminTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onMenuTap;

  const _AdminTopBar({
    required this.title,
    required this.subtitle,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937), width: 1)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white54),
              onPressed: onMenuTap,
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded,
                    size: 14, color: Color(0xFF14FFEC)),
                SizedBox(width: 8),
                Text('Admin',
                    style: TextStyle(
                        color: Color(0xFF14FFEC),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── OVERVIEW SCREEN ────────────────────────────────

class _DashboardOverview extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isLoading;
  final ValueChanged<int> onGoTo;

  const _DashboardOverview({
    required this.stats,
    required this.isLoading,
    required this.onGoTo,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overview',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Manage all resort city data from this console.',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 28),

          // Stats row
          LayoutBuilder(builder: (_, c) {
            final cols = c.maxWidth > 800 ? 4 : (c.maxWidth > 500 ? 2 : 1);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
              children: [
                _StatCard(
                  icon: Icons.location_city_rounded,
                  label: 'Resort Cities',
                  value: isLoading
                      ? '—'
                      : '${stats['resortCities'] ?? 0}',
                  color: const Color(0xFF0D7377),
                  onTap: () => onGoTo(1),
                ),
                _StatCard(
                  icon: Icons.layers_rounded,
                  label: 'Channels',
                  value: isLoading ? '—' : '${stats['channels'] ?? 0}',
                  color: const Color(0xFF2196F3),
                  onTap: () => onGoTo(2),
                ),
                _StatCard(
                  icon: Icons.place_rounded,
                  label: 'Places',
                  value: isLoading ? '—' : '${stats['places'] ?? 0}',
                  color: const Color(0xFF9C27B0),
                  onTap: () => onGoTo(3),
                ),
                _StatCard(
                  icon: Icons.visibility_rounded,
                  label: 'Published',
                  value: isLoading
                      ? '—'
                      : '${stats['published'] ?? 0}',
                  color: const Color(0xFF14FFEC),
                  onTap: null,
                ),
              ],
            );
          }),

          const SizedBox(height: 32),

          // Quick-action cards
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
                label: 'Add Channel',
                description: 'Add a category to an existing city',
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

          // How-to guide
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
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
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
}

class _WorkflowGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.map_rounded, color: Color(0xFF14FFEC), size: 18),
              SizedBox(width: 10),
              Text('Setup Workflow',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 20),
          _step('1', 'Resort Cities', 'Create each destination city (e.g. Mombasa, Diani Beach).',
              const Color(0xFF0D7377)),
          _step('2', 'Channels', 'Add categories to each city (e.g. Accommodation, Dining, Events).',
              const Color(0xFF2196F3)),
          _step('3', 'Places', 'List specific businesses and locations inside each channel.',
              const Color(0xFF9C27B0)),
        ],
      ),
    );
  }

  Widget _step(String num, String title, String body, Color color) {
    return Padding(
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
                      fontSize: 13)),
            ),
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
}

// ───────────────────────────── DATA CLASSES ──────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}