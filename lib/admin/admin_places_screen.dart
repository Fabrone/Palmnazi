import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_place_wizard_screen.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminPlacesScreen
//
// List view for all places. Supports:
//   • Optional city and category filter (passed down from dashboard context)
//   • Status tab filter: All / Active / Pending / Suspended / Archived
//   • Search by name or location
//   • Launch the AdminPlaceWizardScreen to create or edit a place
//   • Delete a place (with confirmation)
//
// RESPONSIVE STRATEGY
// ───────────────────
// • Header row stacks vertically on narrow screens (< 480 dp).
// • _FilterRow stacks dropdowns vertically on narrow screens.
// • Status tabs are in a horizontally-scrollable ListView — never overflow.
// • _PlaceCard uses LayoutBuilder for its own width + NO Spacer() inside
//   GridView cells (Spacer in a Column inside a fixed-aspect grid cell is the
//   root cause of the bottom-overflow errors). Content fills naturally; the
//   grid aspect ratio is generous enough that nothing clips.
// • Single-column layout on narrow screens uses ListView (height = content).
// ─────────────────────────────────────────────────────────────────────────────

const double _kNarrow = 480;
const double _kMedium = 900;

class AdminPlacesScreen extends StatefulWidget {
  final AdminApiService apiService;
  final CityModel? filterCity;
  final CategoryModel? filterCategory;
  final ValueChanged<CityModel?> onCityFilterChanged;
  final ValueChanged<CategoryModel?> onCategoryFilterChanged;

  const AdminPlacesScreen({
    super.key,
    required this.apiService,
    required this.onCityFilterChanged,
    required this.onCategoryFilterChanged,
    this.filterCity,
    this.filterCategory,
  });

  @override
  State<AdminPlacesScreen> createState() => _AdminPlacesScreenState();
}

class _AdminPlacesScreenState extends State<AdminPlacesScreen> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<PlaceModel> _places = [];
  List<CityModel> _cities = [];
  List<CategoryModel> _categories = [];

  bool _loading = false;
  String? _error;
  String _search = '';
  String? _statusFilter; // null = all

  // Local filter copies (user can change inside this screen)
  CityModel? _cityFilter;
  CategoryModel? _categoryFilter;

  static const _statusTabs = [
    null,
    'ACTIVE',
    'PENDING',
    'SUSPENDED',
    'ARCHIVED'
  ];
  static const _statusLabels = [
    'All',
    'Active',
    'Pending',
    'Suspended',
    'Archived'
  ];

  @override
  void initState() {
    super.initState();
    _cityFilter = widget.filterCity;
    _categoryFilter = widget.filterCategory;
    _loadAll();
  }

  @override
  void didUpdateWidget(AdminPlacesScreen old) {
    super.didUpdateWidget(old);
    final cityChanged = widget.filterCity?.id != old.filterCity?.id;
    final catChanged = widget.filterCategory?.id != old.filterCategory?.id;
    if (cityChanged || catChanged) {
      final incomingCityId = widget.filterCity?.id;
      final incomingCatId = widget.filterCategory?.id;
      setState(() {
        _cityFilter = incomingCityId == null
            ? null
            : _cities.where((c) => c.id == incomingCityId).firstOrNull ??
                widget.filterCity;
        _categoryFilter = incomingCatId == null
            ? null
            : _categories.where((c) => c.id == incomingCatId).firstOrNull ??
                widget.filterCategory;
      });
      if (_cities.isEmpty) {
        _loadAll();
      } else {
        _fetchPlaces();
      }
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiService.getCities(),
        widget.apiService.getCategoryTree(),
        widget.apiService.getPlaces(
          cityId: _cityFilter?.id,
          categoryId: _categoryFilter?.id,
          status: _statusFilter,
          search: _search.trim().isNotEmpty ? _search.trim() : null,
          limit: 50,
        ),
      ]);
      if (mounted) {
        final freshCities = results[0] as List<CityModel>;
        final freshCategories = results[1] as List<CategoryModel>;
        setState(() {
          _cities = freshCities;
          _categories = freshCategories;
          _places = results[2] as List<PlaceModel>;
          // Reconcile filter objects by id so DropdownButton doesn't throw
          if (_cityFilter != null) {
            _cityFilter = freshCities
                .where((c) => c.id == _cityFilter!.id)
                .firstOrNull;
          }
          if (_categoryFilter != null) {
            _categoryFilter = freshCategories
                .where((c) => c.id == _categoryFilter!.id)
                .firstOrNull;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchPlaces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.apiService.getPlaces(
        cityId: _cityFilter?.id,
        categoryId: _categoryFilter?.id,
        status: _statusFilter,
        search: _search.trim().isNotEmpty ? _search.trim() : null,
        limit: 50,
      );
      if (mounted) setState(() { _places = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(PlaceModel place) async {
    final confirmed = await adminConfirm(
      context,
      'Delete "${place.name}"?',
      place.isActive
          ? 'This place is currently ACTIVE. Deleting it will remove it from the app. This cannot be undone.'
          : 'This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await widget.apiService.deletePlaceById(place.id);
      _snack('Deleted ${place.name}', isError: false);
      _fetchPlaces();
    } on AdminApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Delete failed: $e', isError: true);
    }
  }

  void _openWizard({PlaceModel? existing}) async {
    if (_cities.isEmpty || _categories.isEmpty) {
      _snack('Loading data…', isError: false);
      await _loadAll();
    }
    if (!mounted) return;
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdminPlaceWizardScreen(
          apiService: widget.apiService,
          cities: _cities,
          categories: _categories,
          existingPlace: existing,
        ),
      ),
    );
    if (refreshed != null) _fetchPlaces();
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? Colors.red.shade700 : const Color(0xFF9C27B0),
      behavior: SnackBarBehavior.floating,
    ));
  }

  List<PlaceModel> get _filtered {
    var list = _places;
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              (p.address?.toLowerCase().contains(q) ?? false) ||
              p.cityName.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final isNarrow = screenW < _kNarrow;
    final hPad = isNarrow ? 12.0 : 24.0;
    final vPad = isNarrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleBlock(),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: AdminAddButton(
                          label: 'Add Place', onTap: () => _openWizard()),
                    ),
                  ],
                )
              : Row(children: [
                  Expanded(child: _buildTitleBlock()),
                  AdminAddButton(
                      label: 'Add Place', onTap: () => _openWizard()),
                ]),
          const SizedBox(height: 14),

          // ── Active filter chips ───────────────────────────────────────
          if (_cityFilter != null || _categoryFilter != null)
            _ActiveFilterBar(
              cityFilter: _cityFilter,
              categoryFilter: _categoryFilter,
              onClearCity: () {
                setState(() => _cityFilter = null);
                widget.onCityFilterChanged(null);
                _fetchPlaces();
              },
              onClearCategory: () {
                setState(() => _categoryFilter = null);
                widget.onCategoryFilterChanged(null);
                _fetchPlaces();
              },
            ),

          // ── Filter dropdowns — responsive ─────────────────────────────
          _FilterRow(
            cities: _cities,
            categories: _categories,
            selectedCity: _cityFilter,
            selectedCategory: _categoryFilter,
            isNarrow: isNarrow,
            onCityChanged: (city) {
              setState(() => _cityFilter = city);
              widget.onCityFilterChanged(city);
              _fetchPlaces();
            },
            onCategoryChanged: (cat) {
              setState(() => _categoryFilter = cat);
              widget.onCategoryFilterChanged(cat);
              _fetchPlaces();
            },
          ),
          const SizedBox(height: 10),

          // ── Search ───────────────────────────────────────────────────
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: isNarrow
                  ? 'Search places…'
                  : 'Search by name, city, or address…',
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Colors.white38, size: 18),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: Colors.white38, size: 16),
                      onPressed: () => setState(() => _search = ''),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF9C27B0))),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 10),

          // ── Status tabs — horizontally scrollable, never overflows ────
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _statusTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => _StatusTab(
                label: _statusLabels[i],
                selected: _statusFilter == _statusTabs[i],
                onTap: () {
                  setState(() => _statusFilter = _statusTabs[i]);
                  _fetchPlaces();
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTitleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Places',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        Text(
          _buildSubtitle(),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (_cityFilter != null) parts.add(_cityFilter!.name);
    if (_categoryFilter != null) parts.add(_categoryFilter!.name);
    if (parts.isEmpty) return 'All places across all cities';
    return 'Filtered by: ${parts.join(' · ')}';
  }

  Widget _buildBody() {
    if (_loading) return const AdminLoader();
    if (_error != null) {
      return AdminErrorView(error: _error!, onRetry: _loadAll);
    }

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return AdminEmptyState(
        icon: Icons.place_rounded,
        title: _places.isEmpty ? 'No places yet' : 'No matches',
        body: _places.isEmpty
            ? 'Create your first place using the wizard.\nFill in basic info, location, media, and link it to categories.'
            : 'Try a different search or filter.',
        actionLabel: _places.isEmpty ? 'Add First Place' : null,
        onAction: _places.isEmpty ? () => _openWizard() : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPlaces,
      color: const Color(0xFF9C27B0),
      child: LayoutBuilder(builder: (_, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= _kMedium ? 3 : (w >= _kNarrow ? 2 : 1);

        // Single-column: use ListView so card height follows content —
        // avoids every aspect-ratio-related overflow in one step.
        if (cols == 1) {
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _PlaceCard(
              place: filtered[i],
              onEdit: () => _openWizard(existing: filtered[i]),
              onDelete: () => _delete(filtered[i]),
            ),
          );
        }

        // Multi-column grid — aspect ratio tuned to fit card content.
        // A generous ratio avoids the bottom-overflow caused by Spacer
        // competing with a too-short cell height.
        final aspectRatio = cols == 3 ? 1.05 : 1.25;

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: filtered.length,
          itemBuilder: (_, i) => _PlaceCard(
            place: filtered[i],
            onEdit: () => _openWizard(existing: filtered[i]),
            onDelete: () => _delete(filtered[i]),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActiveFilterBar — removable chips for current city/category filters
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveFilterBar extends StatelessWidget {
  final CityModel? cityFilter;
  final CategoryModel? categoryFilter;
  final VoidCallback onClearCity;
  final VoidCallback onClearCategory;

  const _ActiveFilterBar({
    required this.cityFilter,
    required this.categoryFilter,
    required this.onClearCity,
    required this.onClearCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (cityFilter != null)
            _RemovableChip(
              icon: Icons.location_city_rounded,
              label: cityFilter!.name,
              color: const Color(0xFF0D7377),
              onRemove: onClearCity,
            ),
          if (categoryFilter != null)
            _RemovableChip(
              icon: Icons.category_rounded,
              label: categoryFilter!.name,
              color: const Color(0xFF2196F3),
              onRemove: onClearCategory,
            ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _RemovableChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 14, color: color.withValues(alpha: 0.7)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _FilterRow — city and category dropdowns
//
// RESPONSIVE: on narrow screens the two dropdowns stack vertically.
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final List<CityModel> cities;
  final List<CategoryModel> categories;
  final CityModel? selectedCity;
  final CategoryModel? selectedCategory;
  final bool isNarrow;
  final ValueChanged<CityModel?> onCityChanged;
  final ValueChanged<CategoryModel?> onCategoryChanged;

  const _FilterRow({
    required this.cities,
    required this.categories,
    required this.selectedCity,
    required this.selectedCategory,
    required this.isNarrow,
    required this.onCityChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cityDropdown = _FilterDropdown<CityModel>(
      hint: 'All cities',
      icon: Icons.location_city_rounded,
      value: selectedCity,
      items: cities
          .map((c) => DropdownMenuItem<CityModel>(
                value: c,
                child: Text(c.name),
              ))
          .toList(),
      onChanged: onCityChanged,
    );

    final categoryDropdown = _FilterDropdown<CategoryModel>(
      hint: 'All categories',
      icon: Icons.category_rounded,
      value: selectedCategory,
      items: categories
          .where((c) => c.isRoot)
          .map((c) => DropdownMenuItem<CategoryModel>(
                value: c,
                child: Row(children: [
                  if (c.icon != null) ...[
                    Text(c.icon!, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                      child: Text(c.name,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ))
          .toList(),
      onChanged: onCategoryChanged,
    );

    if (isNarrow) {
      // Stack vertically on small screens — no side-by-side overflow
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cityDropdown,
          const SizedBox(height: 8),
          categoryDropdown,
        ],
      );
    }

    return Row(children: [
      Expanded(child: cityDropdown),
      const SizedBox(width: 10),
      Expanded(child: categoryDropdown),
    ]);
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String hint;
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.hint,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Guard: if value isn't in the items list (brief window during navigation),
    // treat it as null so DropdownButton doesn't throw.
    final allValues = items.map((i) => i.value).toSet();
    final safeValue =
        (value != null && allValues.contains(value)) ? value : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: safeValue != null
                ? const Color(0xFF9C27B0).withValues(alpha: 0.4)
                : Colors.white12),
      ),
      child: DropdownButton<T>(
        value: safeValue,
        isExpanded: true,
        dropdownColor: const Color(0xFF1F2937),
        style:
            const TextStyle(color: Colors.white70, fontSize: 13),
        underline: const SizedBox.shrink(),
        hint: Row(children: [
          Icon(icon, size: 13, color: Colors.white38),
          const SizedBox(width: 6),
          Text(hint,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 13)),
        ]),
        onChanged: onChanged,
        items: [
          DropdownMenuItem<T>(
            value: null,
            child: Text(hint,
                style: const TextStyle(color: Colors.white54)),
          ),
          ...items,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatusTab
// ─────────────────────────────────────────────────────────────────────────────

class _StatusTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusTab(
      {required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF9C27B0);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.5)
                  : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? accent : Colors.white38,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlaceCard
//
// RESPONSIVE NOTES
// ────────────────
// • Uses LayoutBuilder to know its rendered width and scale content.
// • NO Spacer() — Spacer in a Column inside a fixed-aspect GridView cell
//   fights the cell height and causes the bottom-overflow errors.
//   Content is tightly packed with SizedBox gaps instead.
// • Description is capped at 2 lines with ellipsis.
// • Category pills are in a Wrap — they reflow instead of overflowing.
// • The bottom row (progress bar + edit button) uses Expanded + fixed
//   widths so it never overflows horizontally.
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceCard extends StatefulWidget {
  final PlaceModel place;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlaceCard({
    required this.place,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    const accent = Color(0xFF9C27B0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering
                ? accent.withValues(alpha: 0.5)
                : Colors.white12,
            width: _hovering ? 1.5 : 1,
          ),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 16)
                ]
              : [],
        ),
        // LayoutBuilder so we scale relative to actual rendered width
        child: LayoutBuilder(builder: (context, cardConstraints) {
          final cardW = cardConstraints.maxWidth;
          final scale = (cardW / 280.0).clamp(0.80, 1.2);

          return SingleChildScrollView(
            // NeverScrollable: prevents scroll inside grid cell while
            // still allowing content to lay out at its natural height,
            // which prevents overflow when aspect ratio is generous enough.
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all((14 * scale).clamp(10, 16).toDouble()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top row: thumbnail + name + status + menu ────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      Container(
                        width: (42 * scale).clamp(32, 48).toDouble(),
                        height: (42 * scale).clamp(32, 48).toDouble(),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                          image: p.coverImage != null
                              ? DecorationImage(
                                  image: NetworkImage(p.coverImage!),
                                  fit: BoxFit.cover,
                                  onError: (_, __) {},
                                )
                              : null,
                        ),
                        child: p.coverImage == null
                            ? Icon(Icons.image_rounded,
                                color: Colors.white24,
                                size: (20 * scale)
                                    .clamp(16, 22)
                                    .toDouble())
                            : null,
                      ),
                      SizedBox(width: (8 * scale).clamp(6, 10).toDouble()),

                      // Name + city — Expanded prevents overflow
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: (13 * scale)
                                      .clamp(11, 15)
                                      .toDouble()),
                            ),
                            if (p.cityName.isNotEmpty)
                              Text(
                                p.cityName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: (10 * scale)
                                        .clamp(9, 12)
                                        .toDouble()),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 4),
                      // Status badge — compact
                      AdminStatusBadge(status: p.status),
                      // Menu
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded,
                              color: Colors.white38, size: 15),
                          iconSize: 15,
                          padding: EdgeInsets.zero,
                          color: const Color(0xFF1F2937),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          onSelected: (v) {
                            if (v == 'edit') widget.onEdit();
                            if (v == 'delete') widget.onDelete();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'edit',
                                child: AdminPopItem(
                                    Icons.edit_rounded,
                                    'Edit / Continue')),
                            const PopupMenuItem(
                                value: 'delete',
                                child: AdminPopItem(
                                    Icons.delete_rounded, 'Delete',
                                    color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: (8 * scale).clamp(6, 10).toDouble()),

                  // ── Description snippet ──────────────────────────────
                  if (p.shortDescription != null &&
                      p.shortDescription!.isNotEmpty)
                    Text(
                      p.shortDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: (10 * scale)
                              .clamp(9, 12)
                              .toDouble(),
                          height: 1.4),
                    ),

                  SizedBox(height: (6 * scale).clamp(4, 8).toDouble()),

                  // ── Category pills — Wrap, no overflow ───────────────
                  if (p.categoryLinks.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: p.categoryLinks
                          .take(3)
                          .map((link) => Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      accent.withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(4),
                                  border: Border.all(
                                      color: accent
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  link.parentName != null
                                      ? '${link.parentName} › ${link.categoryName}'
                                      : link.categoryName,
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: (9 * scale)
                                          .clamp(8, 10)
                                          .toDouble()),
                                ),
                              ))
                          .toList(),
                    ),

                  SizedBox(height: (8 * scale).clamp(6, 10).toDouble()),

                  // ── Bottom: completion bar + edit button ─────────────
                  // NO Spacer() here — use fixed spacing above instead.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Progress bar + % label
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                '${p.completionPercent}% complete',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: (9 * scale)
                                        .clamp(8, 11)
                                        .toDouble()),
                              ),
                              if (p.isDraft) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent
                                        .withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                  child: const Text('DRAFT',
                                      style: TextStyle(
                                          color: Colors.blueAccent,
                                          fontSize: 9,
                                          fontWeight:
                                              FontWeight.bold)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: p.completionPercent / 100,
                                backgroundColor: Colors.white12,
                                color: p.isActive
                                    ? Colors.greenAccent
                                    : p.isDraft
                                        ? Colors.blueAccent
                                        : accent,
                                minHeight: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                          width:
                              (8 * scale).clamp(6, 10).toDouble()),

                      // Edit/Continue button — intrinsic width, never pushed
                      GestureDetector(
                        onTap: widget.onEdit,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal:
                                  (10 * scale).clamp(7, 12).toDouble(),
                              vertical:
                                  (5 * scale).clamp(4, 7).toDouble()),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  p.isDraft
                                      ? Icons.arrow_forward_rounded
                                      : Icons.edit_rounded,
                                  size:
                                      (11 * scale).clamp(10, 13).toDouble(),
                                  color: accent,
                                ),
                                SizedBox(
                                    width: (3 * scale)
                                        .clamp(2, 5)
                                        .toDouble()),
                                Text(
                                  p.isDraft ? 'Continue' : 'Edit',
                                  style: TextStyle(
                                      color: accent,
                                      fontSize: (10 * scale)
                                          .clamp(9, 12)
                                          .toDouble(),
                                      fontWeight: FontWeight.w600),
                                ),
                              ]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}