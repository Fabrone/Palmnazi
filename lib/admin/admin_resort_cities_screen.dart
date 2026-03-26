import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/models/city_model.dart';

// File-scoped logger — same PrettyPrinter config as api_client.dart
final Logger _screenLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// AdminResortCitiesScreen
//
// Full CRUD management for resort cities using the live API.
// Data model: CityModel (matches backend JSON exactly).
// All field names in the form match the POST /api/cities request body.
// ─────────────────────────────────────────────────────────────────────────────

class AdminResortCitiesScreen extends StatefulWidget {
  final AdminApiService apiService;
  final ValueChanged<CityModel> onCitySelected;

  const AdminResortCitiesScreen({
    super.key,
    required this.apiService,
    required this.onCitySelected,
  });

  @override
  State<AdminResortCitiesScreen> createState() =>
      _AdminResortCitiesScreenState();
}

class _AdminResortCitiesScreenState extends State<AdminResortCitiesScreen>
    with SingleTickerProviderStateMixin {

  List<CityModel> _cities = [];
  List<CityModel> _filtered = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  // Filter state
  bool? _filterActive; // null = all, true = active, false = inactive

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _screenLog.i("NAV 'AdminDashboard', 'AdminResortCitiesScreen'");
    _fetch();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    _screenLog.i('Loading resort cities…');
    setState(() { _loading = true; _error = null; });

    try {
      final filters = <String, String>{};
      if (_filterActive != null) {
        filters['isActive'] = _filterActive.toString();
      }

      final cities = await widget.apiService.getCities(filters: filters);
      _screenLog.i('Loaded ${cities.length} cities successfully');

      if (mounted) {
        setState(() {
          _cities = cities;
          _loading = false;
        });
        _applySearch(_search);
        _fadeCtrl.forward(from: 0);
      }
    } on AdminApiException catch (e, st) {
      _screenLog.e('getCities failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e, st) {
      _screenLog.e('Unexpected error loading cities', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = 'Unexpected error: $e';
          _loading = false;
        });
      }
    }
  }

  void _applySearch(String query) {
    _search = query;
    if (query.trim().isEmpty) {
      _filtered = List.from(_cities);
    } else {
      final q = query.toLowerCase();
      _filtered = _cities
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.country.toLowerCase().contains(q) ||
              c.region.toLowerCase().contains(q) ||
              c.slug.toLowerCase().contains(q))
          .toList();
    }
    _screenLog.d('Search "$query" → ${_filtered.length}/${_cities.length} cities');
    if (mounted) setState(() {});
  }

  void _applyFilter(bool? isActive) {
    _screenLog.d('Filter isActive=$isActive');
    _filterActive = isActive;
    _fetch();
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> _delete(CityModel city) async {
    _screenLog.i('Delete requested for city "${city.name}"');

    final confirmed = await _showConfirmDialog(
      title: 'Delete "${city.name}"?',
      body: 'This will permanently remove the city and all its places. This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (!confirmed) {
      _screenLog.d('Delete cancelled for city ${city.id}');
      return;
    }

    try {
      await widget.apiService.deleteCity(city.id);
      _snack('Deleted "${city.name}"', isError: false);
      _fetch();
    } on AdminApiException catch (e) {
      _screenLog.e('deleteCity failed', error: e);
      _snack(e.message, isError: true);
    } catch (e) {
      _screenLog.e('Unexpected delete error', error: e);
      _snack('Failed to delete city', isError: true);
    }
  }

  Future<void> _toggleActive(CityModel city) async {
    _screenLog.i('Toggling isActive for "${city.name}" → ${!city.isActive}');
    try {
      final updated = await widget.apiService
          .updateCity(city.id, {'isActive': !city.isActive});
      _snack(
        '"${updated.name}" is now ${updated.isActive ? "active" : "inactive"}',
        isError: false,
      );
      _fetch();
    } on AdminApiException catch (e) {
      _screenLog.e('toggleActive failed', error: e);
      _snack(e.message, isError: true);
    }
  }

  void _openForm({CityModel? city}) {
    _screenLog.i(city == null ? 'Opening ADD city form' : 'Opening EDIT form for ${city.name}');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CityFormDialog(
        existing: city,
        onSave: (payload) async {
          try {
            if (city == null) {
              final created =
                  await widget.apiService.createCity(payload);
              _snack('Created "${created.name}"!', isError: false);
            } else {
              final updated =
                  await widget.apiService.updateCity(city.id, payload);
              _snack('Updated "${updated.name}"!', isError: false);
            }
            _fetch();
          } on AdminApiException {
            rethrow; // Let the form dialog handle field errors
          } catch (e) {
            _screenLog.e('Form save error', error: e);
            rethrow;
          }
        },
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildToolbar(),
          const SizedBox(height: 20),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resort Cities',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _loading
                    ? 'Loading…'
                    : '${_cities.length} ${_cities.length == 1 ? "city" : "cities"} total'
                        '${_filterActive != null ? " · filtered" : ""}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Resort City'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF14FFEC),
            foregroundColor: Colors.black87,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 3,
          child: TextField(
            onChanged: _applySearch,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by name, country, region or slug…',
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Colors.white38, size: 18),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF14FFEC)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Active filter
        _FilterChip(
          label: 'All',
          selected: _filterActive == null,
          onTap: () => _applyFilter(null),
        ),
        const SizedBox(width: 6),
        _FilterChip(
          label: 'Active',
          selected: _filterActive == true,
          color: Colors.greenAccent,
          onTap: () => _applyFilter(true),
        ),
        const SizedBox(width: 6),
        _FilterChip(
          label: 'Inactive',
          selected: _filterActive == false,
          color: Colors.redAccent,
          onTap: () => _applyFilter(false),
        ),
        const SizedBox(width: 12),
        // Refresh
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: Colors.white38),
          onPressed: _loading ? null : _fetch,
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF14FFEC)));
    }

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded,
              color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          Text('Failed to load cities',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14FFEC),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      );
    }

    if (_cities.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_city_rounded,
              color: Colors.white24, size: 64),
          const SizedBox(height: 20),
          const Text('No Resort Cities Yet',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Add your first resort city to make it available in the app.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('Add First City'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14FFEC),
              foregroundColor: Colors.black87,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      );
    }

    if (_filtered.isEmpty && _search.isNotEmpty) {
      return Center(
        child: Text(
          'No cities match "$_search"',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: const Color(0xFF14FFEC),
        child: LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth > 1000 ? 3 : (c.maxWidth > 600 ? 2 : 1);
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: cols == 1 ? 2.4 : 1.4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _filtered.length,
            itemBuilder: (_, i) => _CityCard(
              city: _filtered[i],
              onEdit: () => _openForm(city: _filtered[i]),
              onDelete: () => _delete(_filtered[i]),
              onToggleActive: () => _toggleActive(_filtered[i]),
              onViewPlaces: () =>
                  widget.onCitySelected(_filtered[i]),
            ),
          );
        }),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    _screenLog.i('Snackbar: $msg (error=$isError)');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor:
          isError ? Colors.red.shade700 : const Color(0xFF0D7377),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111827),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(
                isDestructive
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded,
                color: isDestructive ? Colors.redAccent : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16)),
              ),
            ]),
            content: Text(body,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDestructive
                      ? Colors.red.shade700
                      : const Color(0xFF14FFEC),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CityCard  — displays a single CityModel with all backend fields
// ─────────────────────────────────────────────────────────────────────────────

class _CityCard extends StatefulWidget {
  final CityModel city;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback onViewPlaces;

  const _CityCard({
    required this.city,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    required this.onViewPlaces,
  });

  @override
  State<_CityCard> createState() => _CityCardState();
}

class _CityCardState extends State<_CityCard> {
  bool _hovering = false;

  static const _accentColor = Color(0xFF0D7377);

  @override
  Widget build(BuildContext context) {
    final c = widget.city;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovering
                ? _accentColor.withValues(alpha: 0.6)
                : (c.isActive
                    ? _accentColor.withValues(alpha: 0.25)
                    : Colors.white12),
            width: _hovering ? 1.5 : 1,
          ),
          boxShadow: _hovering
              ? [BoxShadow(
                  color: _accentColor.withValues(alpha: 0.2),
                  blurRadius: 20)]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: icon + name + menu ─────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Cover image thumbnail
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _accentColor.withValues(alpha: 0.3)),
                  ),
                  child: c.coverImage.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.network(
                            c.coverImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.location_city_rounded,
                              color: _accentColor,
                              size: 24,
                            ),
                          ),
                        )
                      : Icon(Icons.location_city_rounded,
                          color: _accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.public_rounded,
                            size: 11, color: Colors.white38),
                        const SizedBox(width: 4),
                        Text(
                          '${c.country}${c.region.isNotEmpty ? " · ${c.region}" : ""}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ]),
                    ],
                  ),
                ),
                // Active badge
                _ActiveBadge(isActive: c.isActive),
                const SizedBox(width: 4),
                // Context menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white38, size: 18),
                  color: const Color(0xFF1F2937),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (v) {
                    if (v == 'channels') widget.onViewPlaces();
                    if (v == 'edit') widget.onEdit();
                    if (v == 'toggle') widget.onToggleActive();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'channels',
                        child: _PopItem(
                            Icons.place_rounded, 'View Places')),
                    const PopupMenuItem(
                        value: 'edit',
                        child: _PopItem(Icons.edit_rounded, 'Edit City')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: _PopItem(
                          c.isActive
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          c.isActive ? 'Set Inactive' : 'Set Active',
                        )),
                    const PopupMenuItem(
                        value: 'delete',
                        child: _PopItem(Icons.delete_rounded, 'Delete',
                            color: Colors.red)),
                  ],
                ),
              ]),

              const SizedBox(height: 14),

              // ── Description ──────────────────────────────────────────────
              Text(
                c.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.5),
              ),

              const SizedBox(height: 12),

              // ── Slug + coordinates ───────────────────────────────────────
              Wrap(spacing: 8, runSpacing: 6, children: [
                _MetaChip(
                  icon: Icons.tag_rounded,
                  label: c.slug.isNotEmpty ? c.slug : '—',
                ),
                _MetaChip(
                  icon: Icons.explore_rounded,
                  label:
                      '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                ),
              ]),

              const SizedBox(height: 12),

              // ── Stats row ────────────────────────────────────────────────
              Row(children: [
                _StatPill(
                    icon: Icons.place_rounded,
                    value: '${c.totalPlaces}',
                    label: 'Places'),
                const SizedBox(width: 10),
                _StatPill(
                    icon: Icons.event_rounded,
                    value: '${c.totalEvents}',
                    label: 'Events'),
                if (c.categoryCounts != null &&
                    c.categoryCounts!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _StatPill(
                      icon: Icons.layers_rounded,
                      value: '${c.categoryCounts!.length}',
                      label: 'Categories'),
                ],
              ]),

              const SizedBox(height: 10),

              // ── Action buttons ────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 13),
                    label: const Text('Edit',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onViewPlaces,
                    icon: const Icon(Icons.place_rounded, size: 13),
                    label: const Text('Places',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _CityFormDialog
//
// Handles both CREATE and EDIT.
// Field names match POST /api/cities body exactly.
// Surfaces per-field validation errors returned in 400 responses.
// ─────────────────────────────────────────────────────────────────────────────

class _CityFormDialog extends StatefulWidget {
  final CityModel? existing;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _CityFormDialog({this.existing, required this.onSave});

  @override
  State<_CityFormDialog> createState() => _CityFormDialogState();
}

class _CityFormDialogState extends State<_CityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // ── Backend field controllers ──────────────────────────────────────────
  late TextEditingController _name;
  late TextEditingController _country;
  late TextEditingController _region;
  late TextEditingController _slug;
  late TextEditingController _latitude;
  late TextEditingController _longitude;
  late TextEditingController _coverImage;
  late TextEditingController _description;
  late bool _isActive;

  // API-returned field errors { field: message }
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name        = TextEditingController(text: e?.name ?? '');
    _country     = TextEditingController(text: e?.country ?? 'Kenya');
    _region      = TextEditingController(text: e?.region ?? '');
    _slug        = TextEditingController(text: e?.slug ?? '');
    _latitude    = TextEditingController(
        text: e != null ? e.latitude.toString() : '');
    _longitude   = TextEditingController(
        text: e != null ? e.longitude.toString() : '');
    _coverImage  = TextEditingController(text: e?.coverImage ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _isActive    = e?.isActive ?? true;

    // Auto-generate slug from name while name is being typed (create only)
    if (e == null) {
      _name.addListener(_autoSlug);
    }

    _screenLog.d('CityFormDialog opened — mode=${e == null ? "CREATE" : "EDIT(${e.id})"}');
  }

  void _autoSlug() {
    final raw = _name.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (_slug.text != raw) {
      _slug.text = raw;
      _screenLog.d('Auto-slug: $raw');
    }
  }

  @override
  void dispose() {
    _name.removeListener(_autoSlug);
    for (final c in [
      _name, _country, _region, _slug, _latitude, _longitude,
      _coverImage, _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Clear previous API errors, then re-validate local rules
    setState(() => _fieldErrors = {});
    if (!_formKey.currentState!.validate()) {
      _screenLog.d('Form validation failed (local rules)');
      return;
    }

    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null || lng == null) {
      setState(() {
        if (lat == null) _fieldErrors['latitude']  = 'Must be a valid number';
        if (lng == null) _fieldErrors['longitude'] = 'Must be a valid number';
      });
      return;
    }

    setState(() => _saving = true);

    final payload = <String, dynamic>{
      'name':        _name.text.trim(),
      'country':     _country.text.trim(),
      'region':      _region.text.trim(),
      'slug':        _slug.text.trim(),
      'latitude':    lat,
      'longitude':   lng,
      if (_coverImage.text.trim().isNotEmpty) 'coverImage': _coverImage.text.trim(),
      'description': _description.text.trim(),
      'isActive':    _isActive,
    };

    _screenLog.d('Submitting city payload: $payload');

    try {
      await widget.onSave(payload);
      if (mounted) Navigator.pop(context);
    } on AdminApiException catch (e) {
      _screenLog.w('API returned validation errors: ${e.errors}', error: e);
      if (mounted) {
        setState(() {
          _saving = false;
          // Map backend field errors for inline display
          if (e.errors != null) {
            _fieldErrors = {};
            e.errors!.forEach((k, v) {
              // Skip the top-level _errors key the backend always includes
              if (k == '_errors') return;
              List<dynamic> msgs;
              if (v is List) {
                msgs = v;
              } else if (v is Map && v['_errors'] is List) {
                msgs = v['_errors'] as List;
              } else {
                msgs = [v.toString()];
              }
              if (msgs.isNotEmpty) _fieldErrors[k] = msgs.first.toString();
            });
          }
          if (_fieldErrors.isEmpty) {
            // Show in snackbar if no field-level detail
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ));
          }
        });
      }
    } catch (e, st) {
      _screenLog.e('Unexpected form save error', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('An unexpected error occurred.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: const Color(0xFF111827),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Dialog header ──────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D7377).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEdit
                        ? Icons.edit_location_alt_rounded
                        : Icons.add_location_alt_rounded,
                    color: const Color(0xFF0D7377),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit ? 'Edit Resort City' : 'Add Resort City',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      if (isEdit)
                        Text(
                          'ID: ${widget.existing!.id}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),

              // ── Form body (scrollable) ──────────────────────────────────
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height * 0.60,
                  ),
                  child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Basic info ────────────────────────────────────
                        _sectionHeader('Basic Information'),

                        _FormField(
                          label: 'City Name',
                          hint: 'e.g. Nairobi',
                          controller: _name,
                          required: true,
                          apiError: _fieldErrors['name'],
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'City name is required'
                              : null,
                        ),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _FormField(
                                label: 'Country',
                                hint: 'e.g. Kenya',
                                controller: _country,
                                required: true,
                                apiError: _fieldErrors['country'],
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _FormField(
                                label: 'Region / County',
                                hint: 'e.g. Coast',
                                controller: _region,
                                required: true,
                                apiError: _fieldErrors['region'],
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                          ],
                        ),

                        _FormField(
                          label: 'Slug',
                          hint: 'e.g. nairobi  (auto-generated from name)',
                          helperText:
                              'URL-safe identifier used in deep links — lowercase, hyphens only.',
                          controller: _slug,
                          required: true,
                          apiError: _fieldErrors['slug'],
                          prefixIcon: Icons.tag_rounded,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Slug is required';
                            if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v.trim())) {
                              return 'Only lowercase letters, digits and hyphens allowed';
                            }
                            return null;
                          },
                        ),

                        // ── Description ───────────────────────────────────
                        _sectionHeader('Description'),

                        _FormField(
                          label: 'Description',
                          hint: 'A short description of the city shown to users',
                          controller: _description,
                          maxLines: 3,
                          required: true,
                          apiError: _fieldErrors['description'],
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Description is required'
                              : null,
                        ),

                        // ── Media ─────────────────────────────────────────
                        _sectionHeader('Media'),

                        _FormField(
                          label: 'Cover Image URL',
                          hint: 'https://example.com/mombasa.jpg',
                          helperText:
                              'Full URL to the cover image for this city.',
                          controller: _coverImage,
                          apiError: _fieldErrors['coverImage'],
                          prefixIcon: Icons.image_rounded,
                          keyboardType: TextInputType.url,
                          validator: (v) {
                            if (v != null && v.trim().isNotEmpty) {
                              if (!v.trim().startsWith('http')) {
                                return 'Must be a full URL starting with http';
                              }
                            }
                            return null;
                          },
                        ),

                        // ── Location ──────────────────────────────────────
                        _sectionHeader('Location Coordinates'),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _FormField(
                                label: 'Latitude',
                                hint: 'e.g. -1.2921',
                                controller: _latitude,
                                required: true,
                                apiError: _fieldErrors['latitude'],
                                prefixIcon: Icons.location_on_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^-?\d*\.?\d*')),
                                ],
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final d = double.tryParse(v.trim());
                                  if (d == null) return 'Must be a number';
                                  if (d < -90 || d > 90) {
                                    return 'Must be between -90 and 90';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _FormField(
                                label: 'Longitude',
                                hint: 'e.g. 36.8219',
                                controller: _longitude,
                                required: true,
                                apiError: _fieldErrors['longitude'],
                                prefixIcon: Icons.location_on_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^-?\d*\.?\d*')),
                                ],
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final d = double.tryParse(v.trim());
                                  if (d == null) return 'Must be a number';
                                  if (d < -180 || d > 180) {
                                    return 'Must be between -180 and 180';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),

                        // ── Visibility ────────────────────────────────────
                        _sectionHeader('Visibility'),

                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(children: [
                            Icon(
                              _isActive
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: _isActive
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Active / Visible',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                    _isActive
                                        ? 'City is published and visible to browsing users.'
                                        : 'City is hidden from browsing users.',
                                    style: TextStyle(
                                        color: _isActive
                                            ? Colors.greenAccent
                                                .withValues(alpha: 0.8)
                                            : Colors.white38,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isActive,
                              activeThumbColor: Colors.greenAccent,
                              onChanged: (v) {
                                _screenLog.d('isActive toggled → $v');
                                setState(() => _isActive = v);
                              },
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),   // closes ConstrainedBox
              ),   // closes Flexible

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 14),

              // ── Dialog actions ─────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7377),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isEdit
                                    ? Icons.save_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isEdit ? 'Save Changes' : 'Create City',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                            ],
                          ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Row(children: [
          Expanded(
            child: Divider(
                color: Colors.white12, endIndent: 10, thickness: 1)),
          Text(title,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Divider(
                color: Colors.white12, indent: 10, thickness: 1)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helperText;
  final TextEditingController controller;
  final bool required;
  final String? apiError;   // ← from backend 400 response
  final int maxLines;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _FormField({
    required this.label,
    required this.controller,
    this.hint,
    this.helperText,
    this.required = false,
    this.apiError,
    this.maxLines = 1,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      color: Color(0xFF14FFEC), fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 13),
              helperText:
                  apiError != null ? null : helperText, // show one at a time
              helperStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              errorText: apiError, // API error shown as field error
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 16, color: Colors.white38)
                  : null,
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: apiError != null
                        ? Colors.redAccent.withValues(alpha: 0.5)
                        : Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: apiError != null
                        ? Colors.redAccent
                        : const Color(0xFF14FFEC)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Colors.greenAccent.withValues(alpha: 0.4)
                : Colors.redAccent.withValues(alpha: 0.4),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ]),
      );
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.white38),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11)),
        ]),
      );
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatPill(
      {required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0D7377).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF0D7377).withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF14FFEC)),
          const SizedBox(width: 5),
          Text(
            '$value $label',
            style: const TextStyle(
                color: Colors.white60, fontSize: 11),
          ),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF14FFEC);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? c : Colors.white38,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _PopItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _PopItem(this.icon, this.label, {this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: color ?? Colors.white54),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: color ?? Colors.white70, fontSize: 13)),
      ]);
}