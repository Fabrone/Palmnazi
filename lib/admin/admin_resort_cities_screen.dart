import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_place_map_picker.dart';
import 'package:palmnazi/models/city_details_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/audit_log_service.dart';
import 'package:palmnazi/services/city_details_service.dart';

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
//
// RESPONSIVE STRATEGY
// ───────────────────
// • All sizing decisions derive from MediaQuery.of(context).size so the layout
//   responds to rotations and window resizes without hard-coded pixel breakpoints.
// • Three layout tiers driven by available width (not hardcoded px comparisons):
//     narrow  < 480 dp  → 1 column, card aspect ratio auto (shrinkWrap-like)
//     medium  < 900 dp  → 2 columns
//     wide   >= 900 dp  → 3 columns
// • The toolbar wraps via Wrap so filter chips never overflow on narrow screens.
// • _CityCard uses LayoutBuilder to scale its own internal content.
// ─────────────────────────────────────────────────────────────────────────────

// Breakpoints — expressed as named constants so they are easy to tweak.
const double _kNarrow = 480;
const double _kMedium = 900;

class AdminResortCitiesScreen extends StatefulWidget {
  final AdminApiService apiService;

  /// Called when the user taps "Places" on a city card → navigates to
  /// the Places tab pre-filtered by this city.
  final ValueChanged<CityModel> onCitySelected;

  /// Called when the user taps "View by Category" in the ⋮ menu → navigates
  /// to the Places tab pre-filtered by this city so the user can then pick
  /// a category from the filter row.
  final ValueChanged<CityModel> onCityForCategoriesSelected;

  const AdminResortCitiesScreen({
    super.key,
    required this.apiService,
    required this.onCitySelected,
    required this.onCityForCategoriesSelected,
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

  // Presentation config (featured / manual sort order) — Firestore, keyed by
  // cityId. Drives both this admin list's ordering and the tourist landing
  // page's city grid ordering (see CityDetailsService.sortByDetails).
  Map<String, CityDetailsModel> _cityDetails = {};

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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final filters = <String, String>{};
      if (_filterActive != null) {
        filters['isActive'] = _filterActive.toString();
      }

      final results = await Future.wait([
        widget.apiService.getCities(filters: filters),
        CityDetailsService.getAll(),
      ]);
      final cities = results[0] as List<CityModel>;
      final details = results[1] as Map<String, CityDetailsModel>;
      _screenLog.i('Loaded ${cities.length} cities successfully');

      if (mounted) {
        setState(() {
          _cities = cities;
          _cityDetails = details;
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
    List<CityModel> base;
    if (query.trim().isEmpty) {
      base = List.from(_cities);
    } else {
      final q = query.toLowerCase();
      base = _cities
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.country.toLowerCase().contains(q) ||
              c.region.toLowerCase().contains(q) ||
              c.slug.toLowerCase().contains(q))
          .toList();
    }
    _filtered = CityDetailsService.sortByDetails(
        base, _cityDetails, (c) => c.id, (c) => c.name);
    _screenLog
        .d('Search "$query" → ${_filtered.length}/${_cities.length} cities');
    if (mounted) setState(() {});
  }

  Future<void> _toggleFeatured(CityModel city) async {
    final current = _cityDetails[city.id] ?? CityDetailsModel.empty;
    await CityDetailsService.setFeatured(city.id, !current.featured);
    final updated = await CityDetailsService.getAll();
    if (mounted) {
      setState(() => _cityDetails = updated);
      _applySearch(_search);
    }
  }

  Future<void> _editSortOrder(CityModel city) async {
    final current = _cityDetails[city.id] ?? CityDetailsModel.empty;
    final ctrl = TextEditingController(text: '${current.sortOrder}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdC.surface,
        title: Text(context.tr('admin_resort_set_sort_order_title'),
            style: TextStyle(color: AdC.textPri)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: AdC.textPri),
          decoration: InputDecoration(
            hintText: context.tr('admin_resort_set_sort_order_hint'),
            hintStyle: TextStyle(color: AdC.textMute),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel'),
                style: TextStyle(color: AdC.textMute)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(context.tr('common_save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    await CityDetailsService.setSortOrder(city.id, result);
    final updated = await CityDetailsService.getAll();
    if (mounted) {
      setState(() => _cityDetails = updated);
      _applySearch(_search);
    }
  }

  void _applyFilter(bool? isActive) {
    _screenLog.d('Filter isActive=$isActive');
    _filterActive = isActive;
    _fetch();
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> _delete(CityModel city) async {
    _screenLog.i('Delete requested for city "${city.name}"');

    final deletedPrefix = context.tr('admin_resort_snack_deleted_prefix');
    final deleteFailedMsg = context.tr('admin_resort_snack_delete_failed');

    final confirmed = await _showConfirmDialog(
      title:
          '${context.tr('admin_resort_delete_title_prefix')} "${city.name}"?',
      body: context.tr('admin_resort_delete_body'),
      confirmLabel: context.tr('common_delete'),
      isDestructive: true,
    );

    if (!confirmed) {
      _screenLog.d('Delete cancelled for city ${city.id}');
      return;
    }

    try {
      await widget.apiService.deleteCity(city.id);
      AuditLogService.log(
          action: 'delete',
          module: 'City',
          targetId: city.id,
          targetLabel: city.name);
      _snack('$deletedPrefix "${city.name}"', isError: false);
      _fetch();
    } on AdminApiException catch (e) {
      _screenLog.e('deleteCity failed', error: e);
      _snack(e.message, isError: true);
    } catch (e) {
      _screenLog.e('Unexpected delete error', error: e);
      _snack(deleteFailedMsg, isError: true);
    }
  }

  Future<void> _toggleActive(CityModel city) async {
    _screenLog.i('Toggling isActive for "${city.name}" → ${!city.isActive}');
    final nowPrefix = context.tr('admin_resort_snack_now_prefix');
    final activeWord = context.tr('admin_resort_filter_active').toLowerCase();
    final inactiveWord =
        context.tr('admin_resort_filter_inactive').toLowerCase();
    try {
      final updated = await widget.apiService
          .updateCity(city.id, {'isActive': !city.isActive});
      AuditLogService.log(
          action: 'update',
          module: 'City',
          targetId: updated.id,
          targetLabel: updated.name,
          details: updated.isActive ? 'Set active' : 'Set inactive');
      _snack(
        '"${updated.name}" $nowPrefix ${updated.isActive ? activeWord : inactiveWord}',
        isError: false,
      );
      _fetch();
    } on AdminApiException catch (e) {
      _screenLog.e('toggleActive failed', error: e);
      _snack(e.message, isError: true);
    }
  }

  void _openForm({CityModel? city}) {
    _screenLog.i(city == null
        ? 'Opening ADD city form'
        : 'Opening EDIT form for ${city.name}');
    final createdSuffix = context.tr('admin_resort_snack_created_suffix');
    final updatedSuffix = context.tr('admin_resort_snack_updated_suffix');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CityFormDialog(
        existing: city,
        onSave: (payload) async {
          try {
            if (city == null) {
              final created = await widget.apiService.createCity(payload);
              AuditLogService.log(
                  action: 'create',
                  module: 'City',
                  targetId: created.id,
                  targetLabel: created.name);
              _snack('$createdSuffix "${created.name}"!', isError: false);
            } else {
              final updated =
                  await widget.apiService.updateCity(city.id, payload);
              AuditLogService.log(
                  action: 'update',
                  module: 'City',
                  targetId: updated.id,
                  targetLabel: updated.name);
              _snack('$updatedSuffix "${updated.name}"!', isError: false);
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
    // Use MediaQuery for responsive padding — tighter on narrow screens.
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final hPad = screenW < _kNarrow ? 12.0 : 24.0;
    final vPad = screenW < _kNarrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(screenW),
          const SizedBox(height: 16),
          _buildToolbar(screenW),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(double screenW) {
    final isNarrow = screenW < _kNarrow;
    return isNarrow
        // On narrow screens stack title and button vertically
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleBlock(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildAddButton(),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTitleBlock()),
              const SizedBox(width: 16),
              _buildAddButton(),
            ],
          );
  }

  Widget _buildTitleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('admin_resort_title'),
          style: TextStyle(
              color: AdC.textPri, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _loading
              ? context.tr('admin_resort_loading')
              : '${_cities.length} ${_cities.length == 1 ? context.tr('admin_resort_city_singular') : context.tr('admin_resort_city_plural')} ${context.tr('admin_resort_total_suffix')}'
                  '${_filterActive != null ? ' · ${context.tr('admin_resort_filtered_suffix')}' : ''}',
          style: TextStyle(color: AdC.textMute, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: () => _openForm(),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(context.tr('admin_resort_add_city')),
      style: ElevatedButton.styleFrom(
        backgroundColor: AdC.teal,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildToolbar(double screenW) {
    final isNarrow = screenW < _kNarrow;

    // On narrow screens the search field sits above the filter chips (Wrap
    // handles wrapping naturally for the chips).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field — always full width
        TextField(
          onChanged: _applySearch,
          style: TextStyle(color: AdC.textPri, fontSize: 14),
          decoration: InputDecoration(
            hintText: isNarrow
                ? context.tr('admin_resort_search_hint_narrow')
                : context.tr('admin_resort_search_hint_wide'),
            hintStyle: TextStyle(color: AdC.textMute, fontSize: 13),
            prefixIcon:
                Icon(Icons.search_rounded, color: AdC.textMute, size: 18),
            filled: true,
            fillColor: AdC.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdC.overlay(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdC.overlay(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AdC.teal),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        // Filter chips + refresh in a Wrap — never overflows
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterChip(
              label: context.tr('admin_resort_filter_all'),
              selected: _filterActive == null,
              onTap: () => _applyFilter(null),
            ),
            _FilterChip(
              label: context.tr('admin_resort_filter_active'),
              selected: _filterActive == true,
              color: Colors.greenAccent,
              onTap: () => _applyFilter(true),
            ),
            _FilterChip(
              label: context.tr('admin_resort_filter_inactive'),
              selected: _filterActive == false,
              color: Colors.redAccent,
              onTap: () => _applyFilter(false),
            ),
            IconButton(
              tooltip: context.tr('admin_resort_refresh_tooltip'),
              icon: Icon(Icons.refresh_rounded, color: AdC.textMute),
              onPressed: _loading ? null : _fetch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AdC.teal));
    }

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded,
              color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          Text(
            context.tr('admin_resort_failed_load'),
            style: TextStyle(
                color: AdC.textSec, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdC.textMute, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('common_retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdC.teal,
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
          Icon(Icons.location_city_rounded, color: AdC.textMute, size: 64),
          const SizedBox(height: 20),
          Text(context.tr('admin_resort_empty_title'),
              style: TextStyle(
                  color: AdC.textSec,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            context.tr('admin_resort_empty_body'),
            style: TextStyle(color: AdC.textMute, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: Text(context.tr('admin_resort_add_first_city')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdC.teal,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
          '${context.tr('admin_resort_no_match_prefix')} "$_search"',
          style: TextStyle(color: AdC.textMute, fontSize: 14),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: AdC.teal,
        child: LayoutBuilder(builder: (_, constraints) {
          final w = constraints.maxWidth;
          // Responsive column count driven by actual available width
          final cols = w >= _kMedium ? 3 : (w >= _kNarrow ? 2 : 1);

          // For single-column layout on very narrow screens use a ListView
          // so the card height is determined by its own content (no fixed
          // aspect ratio that would clip content).
          if (cols == 1) {
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _CityCard(
                city: _filtered[i],
                featured:
                    (_cityDetails[_filtered[i].id] ?? CityDetailsModel.empty)
                        .featured,
                sortOrder:
                    (_cityDetails[_filtered[i].id] ?? CityDetailsModel.empty)
                        .sortOrder,
                onEdit: () => _openForm(city: _filtered[i]),
                onDelete: () => _delete(_filtered[i]),
                onToggleActive: () => _toggleActive(_filtered[i]),
                onToggleFeatured: () => _toggleFeatured(_filtered[i]),
                onEditSortOrder: () => _editSortOrder(_filtered[i]),
                onViewPlaces: () => widget.onCitySelected(_filtered[i]),
                onViewCategories: () =>
                    widget.onCityForCategoriesSelected(_filtered[i]),
              ),
            );
          }

          // Multi-column: use GridView with a comfortable aspect ratio.
          // childAspectRatio is tuned per column count so content is never
          // clipped — use a generous ratio; cards will clip only if content
          // somehow exceeds it which is prevented by the card's own layout.
          final aspectRatio = cols == 3 ? 1.15 : 1.35;

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: _filtered.length,
            itemBuilder: (_, i) => _CityCard(
              city: _filtered[i],
              featured:
                  (_cityDetails[_filtered[i].id] ?? CityDetailsModel.empty)
                      .featured,
              sortOrder:
                  (_cityDetails[_filtered[i].id] ?? CityDetailsModel.empty)
                      .sortOrder,
              onEdit: () => _openForm(city: _filtered[i]),
              onDelete: () => _delete(_filtered[i]),
              onToggleActive: () => _toggleActive(_filtered[i]),
              onToggleFeatured: () => _toggleFeatured(_filtered[i]),
              onEditSortOrder: () => _editSortOrder(_filtered[i]),
              onViewPlaces: () => widget.onCitySelected(_filtered[i]),
              onViewCategories: () =>
                  widget.onCityForCategoriesSelected(_filtered[i]),
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
      backgroundColor: isError ? Colors.red.shade700 : AdC.tealDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AdC.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(
                isDestructive
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded,
                color: isDestructive ? Colors.redAccent : AdC.textMute,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(color: AdC.textPri, fontSize: 16)),
              ),
            ]),
            content: Text(body,
                style:
                    TextStyle(color: AdC.textMute, fontSize: 13, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('common_cancel'),
                    style: TextStyle(color: AdC.textMute)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isDestructive ? Colors.red.shade700 : AdC.teal,
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
// _CityCard
//
// Displays a single CityModel.
//
// RESPONSIVE NOTES
// ────────────────
// • Uses LayoutBuilder internally so it knows its own rendered width.
// • All text sizes, spacing, icon sizes, and padding scale with the card
//   width using a simple _scale() helper — no hardcoded pixel values for
//   anything that could cause overflow.
// • The "Categories" action button has been REMOVED per spec.
//   It remains accessible via the ⋮ popup menu ("View by Category").
// • Stats use Wrap instead of a fixed Row so they reflow on narrow cards.
// • The action row at the bottom only contains the "Places" button now
//   (full width), preventing the two-button row that overflowed.
// ─────────────────────────────────────────────────────────────────────────────

class _CityCard extends StatefulWidget {
  final CityModel city;
  final bool featured;
  final int sortOrder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback onToggleFeatured;
  final VoidCallback onEditSortOrder;
  final VoidCallback onViewPlaces;
  final VoidCallback onViewCategories; // kept for ⋮ menu

  const _CityCard({
    required this.city,
    this.featured = false,
    this.sortOrder = 0,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onEditSortOrder,
    required this.onViewPlaces,
    required this.onViewCategories,
  });

  @override
  State<_CityCard> createState() => _CityCardState();
}

class _CityCardState extends State<_CityCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.city;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AdC.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovering
                ? AdC.tealDark.withValues(alpha: 0.6)
                : (c.isActive
                    ? AdC.tealDark.withValues(alpha: 0.25)
                    : AdC.overlay(0.12)),
            width: _hovering ? 1.5 : 1,
          ),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                      color: AdC.tealDark.withValues(alpha: 0.2),
                      blurRadius: 20)
                ]
              : [],
        ),
        // LayoutBuilder lets the card size itself based on available width.
        child: LayoutBuilder(
          builder: (context, cardConstraints) {
            final cardW = cardConstraints.maxWidth;
            // Scale factor: 1.0 at 300 dp, scales linearly down to 0.78 at 140 dp.
            final scale = (cardW / 300.0).clamp(0.78, 1.2);

            return SingleChildScrollView(
              // SingleChildScrollView prevents overflow inside GridView cells
              // when content is taller than the cell on edge cases.
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(16 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top row: thumbnail + name + status badge + menu ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover image thumbnail
                        Container(
                          width: 44 * scale,
                          height: 44 * scale,
                          decoration: BoxDecoration(
                            color: AdC.tealDark.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10 * scale),
                            border: Border.all(
                                color: AdC.tealDark.withValues(alpha: 0.3)),
                          ),
                          child: c.coverImage.isNotEmpty
                              ? ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(9 * scale),
                                  child: Image.network(
                                    c.coverImage,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.location_city_rounded,
                                      color: AdC.tealDark,
                                      size: 22 * scale,
                                    ),
                                  ),
                                )
                              : Icon(Icons.location_city_rounded,
                                  color: AdC.tealDark, size: 22 * scale),
                        ),
                        SizedBox(width: 10 * scale),
                        // Name + country/region — Expanded prevents overflow
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AdC.textPri,
                                    fontWeight: FontWeight.bold,
                                    fontSize:
                                        (15 * scale).clamp(11, 17).toDouble()),
                              ),
                              const SizedBox(height: 2),
                              Row(children: [
                                Icon(Icons.public_rounded,
                                    size: 10 * scale, color: AdC.textMute),
                                SizedBox(width: 3 * scale),
                                Flexible(
                                  child: Text(
                                    '${c.country}${c.region.isNotEmpty ? " · ${c.region}" : ""}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AdC.textMute,
                                        fontSize: (10 * scale)
                                            .clamp(9, 12)
                                            .toDouble()),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Featured badge
                        if (widget.featured) ...[
                          Icon(Icons.star_rounded,
                              color: Colors.amber, size: 16 * scale),
                          const SizedBox(width: 2),
                        ],
                        // Active badge
                        _ActiveBadge(isActive: c.isActive, scale: scale),
                        const SizedBox(width: 2),
                        // Context menu — kept compact
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert,
                                color: AdC.textMute, size: 16),
                            iconSize: 16,
                            padding: EdgeInsets.zero,
                            color: AdC.surface,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onSelected: (v) {
                              if (v == 'places') widget.onViewPlaces();
                              if (v == 'categories') {
                                widget.onViewCategories();
                              }
                              if (v == 'edit') widget.onEdit();
                              if (v == 'toggle') widget.onToggleActive();
                              if (v == 'feature') widget.onToggleFeatured();
                              if (v == 'sortOrder') widget.onEditSortOrder();
                              if (v == 'delete') widget.onDelete();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'places',
                                  child: _PopItem(
                                      Icons.place_rounded,
                                      context
                                          .tr('admin_resort_pop_view_places'))),
                              PopupMenuItem(
                                  value: 'categories',
                                  child: _PopItem(
                                      Icons.category_rounded,
                                      context.tr(
                                          'admin_resort_pop_view_by_category'))),
                              PopupMenuItem(
                                  value: 'edit',
                                  child: _PopItem(
                                      Icons.edit_rounded,
                                      context
                                          .tr('admin_resort_pop_edit_city'))),
                              PopupMenuItem(
                                  value: 'toggle',
                                  child: _PopItem(
                                    c.isActive
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    c.isActive
                                        ? context
                                            .tr('admin_resort_pop_set_inactive')
                                        : context
                                            .tr('admin_resort_pop_set_active'),
                                  )),
                              PopupMenuItem(
                                  value: 'feature',
                                  child: _PopItem(
                                    widget.featured
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    widget.featured
                                        ? context.tr(
                                            'admin_resort_pop_unfeature_city')
                                        : context.tr(
                                            'admin_resort_pop_feature_city'),
                                  )),
                              PopupMenuItem(
                                  value: 'sortOrder',
                                  child: _PopItem(
                                      Icons.swap_vert_rounded,
                                      context.tr(
                                          'admin_resort_pop_set_sort_order'))),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: _PopItem(Icons.delete_rounded,
                                      context.tr('common_delete'),
                                      color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 10 * scale),

                    // ── Description ──────────────────────────────────────
                    Text(
                      c.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AdC.textMute,
                          fontSize: (11 * scale).clamp(10, 13).toDouble(),
                          height: 1.4),
                    ),

                    SizedBox(height: 8 * scale),

                    // ── Slug + coordinates — Wrap prevents overflow ───────
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MetaChip(
                          icon: Icons.tag_rounded,
                          label: c.slug.isNotEmpty ? c.slug : '—',
                          scale: scale,
                        ),
                        _MetaChip(
                          icon: Icons.explore_rounded,
                          label:
                              '${c.latitude.toStringAsFixed(3)}, ${c.longitude.toStringAsFixed(3)}',
                          scale: scale,
                        ),
                      ],
                    ),

                    SizedBox(height: 8 * scale),

                    // ── Stats — Wrap so pills reflow on narrow cards ──────
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _StatPill(
                          icon: Icons.place_rounded,
                          value: '${c.totalPlaces}',
                          label: context.tr('admin_resort_stat_places'),
                          scale: scale,
                        ),
                        _StatPill(
                          icon: Icons.event_rounded,
                          value: '${c.totalEvents}',
                          label: context.tr('admin_resort_stat_events'),
                          scale: scale,
                        ),
                        if (c.categoryCounts != null &&
                            c.categoryCounts!.isNotEmpty)
                          _StatPill(
                            icon: Icons.layers_rounded,
                            value: '${c.categoryCounts!.length}',
                            label: context.tr('admin_resort_stat_cats'),
                            scale: scale,
                          ),
                      ],
                    ),

                    SizedBox(height: 10 * scale),

                    // ── Single action button: Places ──────────────────────
                    // The "Categories" button has been removed from the card.
                    // It remains accessible via the ⋮ popup menu above.
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onViewPlaces,
                        icon: Icon(Icons.place_rounded,
                            size: (13 * scale).clamp(11, 15).toDouble()),
                        label: Text(
                          context.tr('admin_resort_pop_view_places'),
                          style: TextStyle(
                              fontSize: (12 * scale).clamp(10, 13).toDouble()),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdC.tealDark.withValues(alpha: 0.85),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              vertical: (8 * scale).clamp(6, 10).toDouble()),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

  // ── Image upload state ─────────────────────────────────────────────────
  Uint8List? _pickedImageBytes; // bytes for local preview before/after upload
  bool _uploadingImage = false;
  double _uploadProgress = 0.0;

  // Pre-captured FirebaseStorage instance.
  //
  // WHY: On Flutter Web, DDC (Dart Dev Compiler) compiles every `async`
  // function body — including the synchronous lines before the first `await`
  // — into an `_asyncStartSync` JS trampoline. That means ANY access to
  // `FirebaseStorage.instance` inside an `async` function runs inside the JS
  // async machinery, where firebase_core_web's `app()` method cannot resolve
  // the Dart-side Firebase registry. The result is:
  //   "type 'FirebaseException' is not a subtype of type 'JavaScriptObject'"
  //
  // `initState()` is a plain synchronous Dart lifecycle call — it is never
  // wrapped in any JS async trampoline — so capturing the instance here is the
  // only location that is guaranteed to work on Flutter Web.
  FirebaseStorage? _storage;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _country = TextEditingController(text: e?.country ?? 'Kenya');
    _region = TextEditingController(text: e?.region ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _latitude =
        TextEditingController(text: e != null ? e.latitude.toString() : '');
    _longitude =
        TextEditingController(text: e != null ? e.longitude.toString() : '');
    _coverImage = TextEditingController(text: e?.coverImage ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _isActive = e?.isActive ?? true;

    // Auto-generate slug from name while name is being typed (create only)
    if (e == null) {
      _name.addListener(_autoSlug);
    }

    // Capture FirebaseStorage.instance synchronously here — NOT inside any
    // async function — so it resolves within the plain Dart execution context.
    // See the _storage field declaration above for the full explanation.
    try {
      _storage = FirebaseStorage.instance;
      _screenLog.d('FirebaseStorage instance pre-cached successfully');
    } catch (storageErr, storageSt) {
      _screenLog.e(
          'Failed to pre-cache FirebaseStorage instance — image upload will be unavailable',
          error: storageErr,
          stackTrace: storageSt);
    }

    _screenLog.d(
        'CityFormDialog opened — mode=${e == null ? "CREATE" : "EDIT(${e.id})"}');
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

  // ── Image pick + Firebase Storage upload ──────────────────────────────

  Future<void> _pickAndUploadImage() async {
    // Use the pre-cached FirebaseStorage instance captured in initState().
    //
    // CRITICAL — do NOT call FirebaseStorage.instance here or anywhere inside
    // an async function on Flutter Web. DDC (Dart Dev Compiler) compiles the
    // entire async function body — including lines before the first `await` —
    // into an `_asyncStartSync` JS trampoline. Inside that trampoline,
    // firebase_core_web cannot resolve the Dart-side Firebase app registry and
    // throws:
    //   "type 'FirebaseException' is not a subtype of type 'JavaScriptObject'"
    //
    // The instance must be captured in initState() (a plain synchronous Dart
    // lifecycle call, never wrapped in JS async machinery). See _storage field.
    final storage = _storage;
    if (storage == null) {
      _screenLog.e('FirebaseStorage was not initialised — cannot upload image. '
          'Ensure Firebase.initializeApp() completes before opening this dialog.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('admin_resort_error_storage_unavailable')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    // Use file_picker so this works on mobile, web AND desktop.
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData:
          true, // ensures bytes are available on all platforms (incl. web)
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      // Should not happen with withData: true, but guard anyway.
      _screenLog.w('FilePicker returned null bytes — skipping upload');
      return;
    }

    // Determine extension and content type.
    final ext = (file.extension ?? 'jpg').toLowerCase();
    final contentType = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : ext == 'gif'
                ? 'image/gif'
                : 'image/jpeg';

    // Build a collision-safe storage path:
    // city-covers/{slug or "city"}-{timestamp}.{ext}
    final slug = _slug.text.trim().isNotEmpty ? _slug.text.trim() : 'city';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'city-covers/$slug-$ts.$ext';

    _screenLog.i('Starting image upload → $storagePath');

    setState(() {
      _pickedImageBytes = bytes;
      _uploadingImage = true;
      _uploadProgress = 0.0;
    });

    try {
      final ref = storage.ref(storagePath);
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );

      // Stream upload progress to the UI.
      uploadTask.snapshotEvents.listen((snapshot) {
        if (mounted && snapshot.totalBytes > 0) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _coverImage.text = downloadUrl;
          _uploadingImage = false;
          _uploadProgress = 1.0;
        });
        _screenLog.i('City cover uploaded OK → $downloadUrl');
      }
    } catch (e, st) {
      _screenLog.e('City cover upload failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _uploadingImage = false;
          _pickedImageBytes = null;
          _uploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${context.tr('admin_resort_error_image_upload_prefix')} $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  void dispose() {
    _name.removeListener(_autoSlug);
    for (final c in [
      _name,
      _country,
      _region,
      _slug,
      _latitude,
      _longitude,
      _coverImage,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _fieldErrors = {});
    if (!_formKey.currentState!.validate()) {
      _screenLog.d('Form validation failed (local rules)');
      return;
    }

    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null || lng == null) {
      final validNumberMsg = context.tr('admin_resort_error_valid_number');
      setState(() {
        if (lat == null) _fieldErrors['latitude'] = validNumberMsg;
        if (lng == null) _fieldErrors['longitude'] = validNumberMsg;
      });
      return;
    }

    setState(() => _saving = true);

    // On CREATE omit coverImage when empty so the backend does not receive
    // an empty-string URL it may reject with a validation error.
    // On EDIT always include it (even when empty) so the admin can
    // intentionally clear an existing image — the backend's partial-update
    // PUT only touches fields that are sent, meaning omitting the key on
    // EDIT would leave an old image permanently stuck with no way to remove it.
    final isEdit = widget.existing != null;

    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'country': _country.text.trim(),
      'region': _region.text.trim(),
      'slug': _slug.text.trim(),
      'latitude': lat,
      'longitude': lng,
      if (isEdit || _coverImage.text.trim().isNotEmpty)
        'coverImage': _coverImage.text.trim(),
      'description': _description.text.trim(),
      'isActive': _isActive,
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
          if (e.errors != null) {
            _fieldErrors = {};
            e.errors!.forEach((k, v) {
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
          content: Text(context.tr('admin_resort_error_unexpected')),
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
    final mq = MediaQuery.of(context);
    // Dialog width is capped and adapts to narrow screens
    final dialogMaxW = (mq.size.width * 0.92).clamp(280.0, 620.0);

    return Dialog(
      backgroundColor: AdC.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxW,
          maxHeight: mq.size.height * 0.90,
        ),
        child: Padding(
          padding: EdgeInsets.all(mq.size.width < _kNarrow ? 18 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Dialog header ──────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdC.tealDark.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEdit
                        ? Icons.edit_location_alt_rounded
                        : Icons.add_location_alt_rounded,
                    color: AdC.tealDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit
                            ? context.tr('admin_resort_edit_city_title')
                            : context.tr('admin_resort_add_city_title'),
                        style: TextStyle(
                            color: AdC.textPri,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      if (isEdit)
                        Text(
                          '${context.tr('admin_resort_id_prefix')} ${widget.existing!.id}',
                          style: TextStyle(color: AdC.textMute, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AdC.textMute),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 16),
              Divider(color: AdC.overlay(0.12)),
              const SizedBox(height: 12),

              // ── Form body (scrollable) ─────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                            context.tr('admin_resort_section_basic_info')),

                        _FormField(
                          label: context.tr('admin_resort_field_city_name'),
                          hint: context.tr('admin_resort_field_city_name_hint'),
                          controller: _name,
                          required: true,
                          apiError: _fieldErrors['name'],
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? context
                                  .tr('admin_resort_error_city_name_required')
                              : null,
                        ),

                        // Country + Region — stack on narrow screens
                        LayoutBuilder(builder: (_, c) {
                          if (c.maxWidth < 340) {
                            return Column(children: [
                              _FormField(
                                label: context.tr('admin_resort_field_country'),
                                hint: context
                                    .tr('admin_resort_field_country_hint'),
                                controller: _country,
                                required: true,
                                apiError: _fieldErrors['country'],
                                validator: (v) => (v == null ||
                                        v.trim().isEmpty)
                                    ? context.tr('admin_resort_error_required')
                                    : null,
                              ),
                              _FormField(
                                label: context.tr('admin_resort_field_region'),
                                hint: context
                                    .tr('admin_resort_field_region_hint'),
                                controller: _region,
                                required: true,
                                apiError: _fieldErrors['region'],
                                validator: (v) => (v == null ||
                                        v.trim().isEmpty)
                                    ? context.tr('admin_resort_error_required')
                                    : null,
                              ),
                            ]);
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _FormField(
                                  label:
                                      context.tr('admin_resort_field_country'),
                                  hint: context
                                      .tr('admin_resort_field_country_hint'),
                                  controller: _country,
                                  required: true,
                                  apiError: _fieldErrors['country'],
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? context
                                              .tr('admin_resort_error_required')
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _FormField(
                                  label:
                                      context.tr('admin_resort_field_region'),
                                  hint: context
                                      .tr('admin_resort_field_region_hint'),
                                  controller: _region,
                                  required: true,
                                  apiError: _fieldErrors['region'],
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? context
                                              .tr('admin_resort_error_required')
                                          : null,
                                ),
                              ),
                            ],
                          );
                        }),

                        _FormField(
                          label: context.tr('admin_resort_field_slug'),
                          hint: context.tr('admin_resort_field_slug_hint'),
                          helperText:
                              context.tr('admin_resort_field_slug_helper'),
                          controller: _slug,
                          required: true,
                          apiError: _fieldErrors['slug'],
                          prefixIcon: Icons.tag_rounded,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return context
                                  .tr('admin_resort_error_slug_required');
                            }
                            if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v.trim())) {
                              return context
                                  .tr('admin_resort_error_slug_format');
                            }
                            return null;
                          },
                        ),

                        _sectionHeader(
                            context.tr('admin_resort_section_description')),

                        _FormField(
                          label: context.tr('admin_resort_field_description'),
                          hint:
                              context.tr('admin_resort_field_description_hint'),
                          controller: _description,
                          maxLines: 3,
                          required: true,
                          apiError: _fieldErrors['description'],
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? context
                                  .tr('admin_resort_error_description_required')
                              : null,
                        ),

                        _sectionHeader(
                            context.tr('admin_resort_section_media')),

                        // ── Cover Image upload section ─────────────────────
                        _CoverImageUploadSection(
                          imageBytes: _pickedImageBytes,
                          existingUrl: _coverImage.text,
                          uploading: _uploadingImage,
                          uploadProgress: _uploadProgress,
                          onPickTap: _saving || _uploadingImage
                              ? null
                              : _pickAndUploadImage,
                          urlController: _coverImage,
                          urlApiError: _fieldErrors['coverImage'],
                        ),

                        _sectionHeader(
                            context.tr('admin_resort_section_location')),

                        // ── Map picker launch button ───────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openMapPicker,
                            icon: const Icon(Icons.map_rounded, size: 16),
                            label: Text(context.tr('admin_resort_pick_on_map'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdC.teal,
                              side: BorderSide(
                                  color: AdC.teal.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.lightbulb_outline_rounded,
                              color: AdC.textMute, size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              context.tr('admin_resort_map_hint'),
                              style: TextStyle(
                                  color: AdC.textMute,
                                  fontSize: 11,
                                  height: 1.4),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),

                        // Lat + Lng — stack on narrow screens
                        LayoutBuilder(builder: (_, c) {
                          if (c.maxWidth < 340) {
                            return Column(children: [
                              _FormField(
                                label:
                                    context.tr('admin_resort_field_latitude'),
                                hint: context
                                    .tr('admin_resort_field_latitude_hint'),
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
                                validator: _latValidator,
                              ),
                              _FormField(
                                label:
                                    context.tr('admin_resort_field_longitude'),
                                hint: context
                                    .tr('admin_resort_field_longitude_hint'),
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
                                validator: _lngValidator,
                              ),
                            ]);
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _FormField(
                                  label:
                                      context.tr('admin_resort_field_latitude'),
                                  hint: context
                                      .tr('admin_resort_field_latitude_hint'),
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
                                  validator: _latValidator,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _FormField(
                                  label: context
                                      .tr('admin_resort_field_longitude'),
                                  hint: context
                                      .tr('admin_resort_field_longitude_hint'),
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
                                  validator: _lngValidator,
                                ),
                              ),
                            ],
                          );
                        }),

                        _sectionHeader(
                            context.tr('admin_resort_section_visibility')),

                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AdC.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AdC.overlay(0.12)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: Row(children: [
                              Icon(
                                _isActive
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                color: _isActive
                                    ? Colors.greenAccent
                                    : AdC.textMute,
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        context
                                            .tr('admin_resort_active_visible'),
                                        style: TextStyle(
                                            color: AdC.textSec,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    Text(
                                      _isActive
                                          ? context
                                              .tr('admin_resort_visible_desc')
                                          : context
                                              .tr('admin_resort_hidden_desc'),
                                      style: TextStyle(
                                          color: _isActive
                                              ? Colors.greenAccent
                                                  .withValues(alpha: 0.8)
                                              : AdC.textMute,
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
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: AdC.overlay(0.12)),
              const SizedBox(height: 14),

              // ── Dialog actions ─────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdC.textMute,
                      side: BorderSide(color: AdC.overlay(0.24)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(context.tr('common_cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdC.tealDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isEdit ? Icons.save_rounded : Icons.add_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isEdit
                                    ? context.tr('admin_resort_save_changes')
                                    : context.tr('admin_resort_create_city'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
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

  String? _latValidator(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr('admin_resort_error_required');
    }
    final d = double.tryParse(v.trim());
    if (d == null) return context.tr('admin_resort_error_must_be_number');
    if (d < -90 || d > 90) return context.tr('admin_resort_error_lat_range');
    return null;
  }

  String? _lngValidator(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr('admin_resort_error_required');
    }
    final d = double.tryParse(v.trim());
    if (d == null) return context.tr('admin_resort_error_must_be_number');
    if (d < -180 || d > 180) return context.tr('admin_resort_error_lng_range');
    return null;
  }

  Future<void> _openMapPicker() async {
    final existingLat = double.tryParse(_latitude.text.trim());
    final existingLng = double.tryParse(_longitude.text.trim());

    final result = await Navigator.of(context).push<PlaceLocationResult>(
      MaterialPageRoute(
        builder: (_) => AdminPlaceMapPicker(
          initialSelectedLocation: existingLat != null && existingLng != null
              ? LatLng(existingLat, existingLng)
              : null,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _latitude.text = result.latitude.toStringAsFixed(7);
      _longitude.text = result.longitude.toStringAsFixed(7);
    });
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Row(children: [
          Expanded(
              child: Divider(
                  color: AdC.overlay(0.12), endIndent: 10, thickness: 1)),
          Text(title,
              style: TextStyle(
                  color: AdC.textMute,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w500)),
          Expanded(
              child:
                  Divider(color: AdC.overlay(0.12), indent: 10, thickness: 1)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _CoverImageUploadSection
//
// Handles the full cover-image flow for the city form:
//   1. Admin taps "Select & Upload Image" → file_picker opens
//   2. Bytes upload to Firebase Storage with live progress bar
//   3. Download URL auto-fills the editable URL field below
//   4. Image preview renders from bytes (while uploading) or URL (when editing)
//
// The URL text field remains editable so admins can paste a URL directly
// if they prefer, or correct an auto-filled one.
// ─────────────────────────────────────────────────────────────────────────────

class _CoverImageUploadSection extends StatelessWidget {
  final Uint8List? imageBytes;
  final String existingUrl;
  final bool uploading;
  final double uploadProgress;
  final VoidCallback? onPickTap;
  final TextEditingController urlController;
  final String? urlApiError;

  const _CoverImageUploadSection({
    required this.imageBytes,
    required this.existingUrl,
    required this.uploading,
    required this.uploadProgress,
    required this.onPickTap,
    required this.urlController,
    this.urlApiError,
  });

  bool get _hasPreview => imageBytes != null || existingUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section label ──────────────────────────────────────────────
          Text(
            context.tr('admin_resort_cover_image_label'),
            style: TextStyle(
                color: AdC.textSec, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),

          // ── Preview + upload area ──────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AdC.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: uploading
                    ? AdC.teal.withValues(alpha: 0.4)
                    : AdC.overlay(0.12),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image preview (16 : 9) ─────────────────────────────
                if (_hasPreview)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildPreview(),
                  ),

                // ── Upload progress bar ────────────────────────────────
                if (uploading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            minHeight: 5,
                            backgroundColor: AdC.overlay(0.12),
                            valueColor: const AlwaysStoppedAnimation(AdC.teal),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${context.tr('admin_resort_uploading_prefix')} ${(uploadProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: AdC.textMute, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                // ── Pick / change button ───────────────────────────────
                if (!uploading)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: OutlinedButton.icon(
                      onPressed: onPickTap,
                      icon: Icon(
                        _hasPreview
                            ? Icons.change_circle_rounded
                            : Icons.upload_file_rounded,
                        size: 16,
                        color: onPickTap != null ? AdC.teal : AdC.textMute,
                      ),
                      label: Text(
                        _hasPreview
                            ? context.tr('admin_resort_change_image')
                            : context.tr('admin_resort_select_upload_image'),
                        style: TextStyle(
                          fontSize: 13,
                          color: onPickTap != null ? AdC.teal : AdC.textMute,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(
                          color: onPickTap != null
                              ? AdC.teal.withValues(alpha: 0.6)
                              : AdC.overlay(0.12),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),

                // Tiny spacer while uploading (button hidden)
                if (uploading) const SizedBox(height: 10),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── URL field (autofilled; still editable as fallback) ─────────
          _FormField(
            label: context.tr('admin_resort_field_cover_image_url'),
            hint: context.tr('admin_resort_field_cover_image_url_hint'),
            helperText: uploading
                ? context.tr('admin_resort_cover_image_uploading_helper')
                : context.tr('admin_resort_cover_image_helper'),
            controller: urlController,
            apiError: urlApiError,
            prefixIcon: Icons.link_rounded,
            keyboardType: TextInputType.url,
            validator: (v) {
              if (v != null && v.trim().isNotEmpty) {
                if (!v.trim().startsWith('http')) {
                  return context.tr('admin_resort_error_url_format');
                }
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    // If we have fresh bytes from a just-picked file, show those directly
    // (avoids a round-trip and works even mid-upload).
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _brokenPlaceholder(),
      );
    }

    // Otherwise render from the URL already stored (edit mode).
    if (existingUrl.trim().isNotEmpty) {
      return Image.network(
        existingUrl.trim(),
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                color: AdC.overlay(0.04),
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    color: AdC.teal,
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => _brokenPlaceholder(),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _brokenPlaceholder() => Container(
        color: AdC.overlay(0.04),
        child: Center(
          child:
              Icon(Icons.broken_image_rounded, color: AdC.textMute, size: 40),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _FormField  (unchanged — kept here for local use in this file)
// ─────────────────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helperText;
  final TextEditingController controller;
  final bool required;
  final String? apiError;
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
                style: TextStyle(
                    color: AdC.textSec,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (required)
              const Text(' *', style: TextStyle(color: AdC.teal, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(color: AdC.textPri, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AdC.textMute, fontSize: 13),
              helperText: apiError != null ? null : helperText,
              helperStyle: TextStyle(color: AdC.textMute, fontSize: 11),
              errorText: apiError,
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 16, color: AdC.textMute)
                  : null,
              filled: true,
              fillColor: AdC.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AdC.overlay(0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: apiError != null
                        ? Colors.redAccent.withValues(alpha: 0.5)
                        : AdC.overlay(0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: apiError != null ? Colors.redAccent : AdC.teal),
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

/// Scale-aware active/inactive badge.
class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  final double scale;
  const _ActiveBadge({required this.isActive, this.scale = 1.0});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: (7 * scale).clamp(5, 9).toDouble(),
            vertical: (2 * scale).clamp(2, 4).toDouble()),
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
            width: (6 * scale).clamp(4, 7).toDouble(),
            height: (6 * scale).clamp(4, 7).toDouble(),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          SizedBox(width: (4 * scale).clamp(3, 6).toDouble()),
          Text(
            isActive
                ? context.tr('admin_resort_active_badge')
                : context.tr('admin_resort_inactive_badge'),
            style: TextStyle(
              fontSize: (9 * scale).clamp(8, 11).toDouble(),
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ]),
      );
}

/// Scale-aware meta chip (slug / coordinates).
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double scale;
  const _MetaChip({required this.icon, required this.label, this.scale = 1.0});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: (7 * scale).clamp(5, 9).toDouble(),
            vertical: (3 * scale).clamp(2, 5).toDouble()),
        decoration: BoxDecoration(
          color: AdC.overlay(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdC.overlay(0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: (10 * scale).clamp(9, 12).toDouble(), color: AdC.textMute),
          SizedBox(width: (4 * scale).clamp(3, 6).toDouble()),
          Text(label,
              style: TextStyle(
                  color: AdC.textMute,
                  fontSize: (10 * scale).clamp(9, 12).toDouble())),
        ]),
      );
}

/// Scale-aware stat pill.
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final double scale;
  const _StatPill(
      {required this.icon,
      required this.value,
      required this.label,
      this.scale = 1.0});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: (8 * scale).clamp(6, 10).toDouble(),
            vertical: (4 * scale).clamp(3, 6).toDouble()),
        decoration: BoxDecoration(
          color: AdC.tealDark.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdC.tealDark.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: (11 * scale).clamp(9, 13).toDouble(), color: AdC.teal),
          SizedBox(width: (4 * scale).clamp(3, 6).toDouble()),
          Text(
            '$value $label',
            style: TextStyle(
                color: AdC.textMute,
                fontSize: (10 * scale).clamp(9, 12).toDouble()),
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
    final c = color ?? AdC.teal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.5) : AdC.overlay(0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? c : AdC.textMute,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
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
        Icon(icon, size: 15, color: color ?? AdC.textMute),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(color: color ?? AdC.textSec, fontSize: 13)),
      ]);
}
