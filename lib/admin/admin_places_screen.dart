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
//   • Launch the 11-step AdminPlaceWizardScreen to create or edit a place
//   • Delete a place (with confirmation)
//
// This screen owns the city and category lists so the wizard has them when
// launched. Both lists are fetched on init alongside the places list.
// ─────────────────────────────────────────────────────────────────────────────

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

  static const _statusTabs = [null, 'ACTIVE', 'PENDING', 'SUSPENDED', 'ARCHIVED'];
  static const _statusLabels = ['All', 'Active', 'Pending', 'Suspended', 'Archived'];

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
    // Re-sync if parent dashboard changes context
    final cityChanged = widget.filterCity?.id != old.filterCity?.id;
    final catChanged  = widget.filterCategory?.id != old.filterCategory?.id;
    if (cityChanged || catChanged) {
      // Resolve the incoming prop against our already-fetched lists so the
      // DropdownButton always gets an object that exists in its items list.
      // If lists aren't loaded yet, _loadAll() will reconcile on completion.
      final incomingCityId = widget.filterCity?.id;
      final incomingCatId  = widget.filterCategory?.id;
      setState(() {
        _cityFilter = incomingCityId == null
            ? null
            : _cities.where((c) => c.id == incomingCityId).firstOrNull
                ?? widget.filterCity; // fallback: keep prop until list loads
        _categoryFilter = incomingCatId == null
            ? null
            : _categories.where((c) => c.id == incomingCatId).firstOrNull
                ?? widget.filterCategory;
      });
      // If lists are empty the full load will reconcile; otherwise just re-fetch places.
      if (_cities.isEmpty) {
        _loadAll();
      } else {
        _fetchPlaces();
      }
    }
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
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
        final freshCities     = results[0] as List<CityModel>;
        final freshCategories = results[1] as List<CategoryModel>;
        setState(() {
          _cities     = freshCities;
          _categories = freshCategories;
          _places     = results[2] as List<PlaceModel>;
          // ── Reconcile filter objects by id ───────────────────────────────
          // The filter value passed from the dashboard may be a different
          // object instance than what is now in _cities / _categories.
          // DropdownButton asserts exactly one item.value == value (by ==),
          // so we must re-resolve both filters against the freshly fetched
          // lists. CityModel / CategoryModel equality is identity unless ==
          // is overridden, so we match by id string instead.
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
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchPlaces() async {
    setState(() { _loading = true; _error = null; });
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
    // Ensure we have cities and categories loaded before launching
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
    // true = submitted & activated, false = saved & exited draft
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Places',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text(
                    _buildSubtitle(),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            AdminAddButton(
              label: 'Add Place',
              onTap: () => _openWizard(),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Active filter chips ──────────────────────────────────────
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

          // ── Filter dropdowns ─────────────────────────────────────────
          _FilterRow(
            cities: _cities,
            categories: _categories,
            selectedCity: _cityFilter,
            selectedCategory: _categoryFilter,
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
          const SizedBox(height: 12),

          // ── Search ───────────────────────────────────────────────────
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by name, city, or address…',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
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
                  borderSide: const BorderSide(color: Color(0xFF9C27B0))),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),

          // ── Status tabs ──────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _statusTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
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
          const SizedBox(height: 16),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
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
    if (_error != null) return AdminErrorView(error: _error!, onRetry: _loadAll);

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return AdminEmptyState(
        icon: Icons.place_rounded,
        title: _places.isEmpty ? 'No places yet' : 'No matches',
        body: _places.isEmpty
            ? 'Create your first place using the 11-step wizard.\nFill in basic info, location, media, and link it to categories.'
            : 'Try a different search or filter.',
        actionLabel: _places.isEmpty ? 'Add First Place' : null,
        onAction: _places.isEmpty ? () => _openWizard() : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPlaces,
      color: const Color(0xFF9C27B0),
      child: LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth > 1000 ? 3 : (c.maxWidth > 620 ? 2 : 1);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: cols == 1 ? 3.0 : 1.55,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
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
// _ActiveFilterBar — shows removable chips for current city/category filters
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
      padding: const EdgeInsets.only(bottom: 12),
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
      {required this.icon, required this.label, required this.color, required this.onRemove});

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
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: color.withValues(alpha: 0.7)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _FilterRow — city and category dropdowns
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final List<CityModel> cities;
  final List<CategoryModel> categories;
  final CityModel? selectedCity;
  final CategoryModel? selectedCategory;
  final ValueChanged<CityModel?> onCityChanged;
  final ValueChanged<CategoryModel?> onCategoryChanged;

  const _FilterRow({
    required this.cities,
    required this.categories,
    required this.selectedCity,
    required this.selectedCategory,
    required this.onCityChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _FilterDropdown<CityModel>(
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
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _FilterDropdown<CategoryModel>(
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
                      Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    ]),
                  ))
              .toList(),
          onChanged: onCategoryChanged,
        ),
      ),
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
    // DropdownButton asserts: if value != null, exactly one item must match it.
    // Guard: if the value object is not present in the items list (can happen
    // during the brief window between navigation and _loadAll completing), treat
    // it as null so the hint is shown instead of throwing.
    final allValues = items.map((i) => i.value).toSet();
    final safeValue = (value != null && allValues.contains(value)) ? value : null;

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
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          underline: const SizedBox.shrink(),
          hint: Row(children: [
            Icon(icon, size: 13, color: Colors.white38),
            const SizedBox(width: 6),
            Text(hint, style: const TextStyle(color: Colors.white24, fontSize: 13)),
          ]),
          onChanged: onChanged,
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text(hint, style: const TextStyle(color: Colors.white54)),
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
  const _StatusTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF9C27B0);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? accent.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? accent : Colors.white38,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlaceCard
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
              ? [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 16)]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: cover image thumb + status + menu ─────────
              Row(children: [
                // Thumbnail
                Container(
                  width: 44, height: 44,
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
                      ? const Icon(Icons.image_rounded,
                          color: Colors.white24, size: 22)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    if (p.cityName.isNotEmpty)
                      Text(p.cityName,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                  ],
                )),
                const SizedBox(width: 6),
                AdminStatusBadge(status: p.status),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white38, size: 16),
                  color: const Color(0xFF1F2937),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit',
                        child: AdminPopItem(Icons.edit_rounded, 'Edit / Continue')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: AdminPopItem(Icons.delete_rounded, 'Delete',
                            color: Colors.redAccent)),
                  ],
                ),
              ]),

              const SizedBox(height: 10),

              // ── Description snippet ──────────────────────────────────
              if (p.shortDescription != null && p.shortDescription!.isNotEmpty)
                Text(
                  p.shortDescription!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, height: 1.5),
                ),

              const Spacer(),

              // ── Category pills ───────────────────────────────────────
              if (p.categoryLinks.isNotEmpty)
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: p.categoryLinks.take(3).map((link) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: accent.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      link.parentName != null
                          ? '${link.parentName} › ${link.categoryName}'
                          : link.categoryName,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 9),
                    ),
                  )).toList(),
                ),

              const SizedBox(height: 10),

              // ── Bottom row: completion bar + edit button ─────────────
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${p.completionPercent}% complete',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10)),
                        if (p.isDraft) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('DRAFT',
                                style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
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
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: widget.onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        p.isDraft
                            ? Icons.arrow_forward_rounded
                            : Icons.edit_rounded,
                        size: 12,
                        color: accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.isDraft ? 'Continue' : 'Edit',
                        style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}