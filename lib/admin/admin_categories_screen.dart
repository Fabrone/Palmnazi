import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/audit_log_service.dart';
import 'package:palmnazi/services/category_details_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminCategoriesScreen
//
// Manages the global category tree:
//   Root category (e.g. "Accommodation") → Child categories ("Hotels", "Resorts")
//
// RESPONSIVE STRATEGY
// ───────────────────
// • The toolbar uses a Column + Wrap so the search field is always full-width
//   and the filter chips reflow to a second line on narrow screens instead of
//   overflowing.
// • _RootCategoryCard header row wraps stats/actions via Wrap so nothing clips
//   on small screen widths.
// • _ChildCategoryRow uses Flexible on the name column and wraps its action
//   buttons so they never overflow rightward.
// • All screen-width comparisons use MediaQuery.of(context).size.width so
//   the UI responds to rotations and window resizes dynamically.
// ─────────────────────────────────────────────────────────────────────────────

const double _kNarrow = 480;

class AdminCategoriesScreen extends StatefulWidget {
  final AdminApiService apiService;

  const AdminCategoriesScreen({super.key, required this.apiService});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  // Root categories with their children pre-loaded
  List<CategoryModel> _rootCategories = [];
  List<CityModel> _cities = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  bool? _filterActive;

  // Tracks which roots are expanded in the tree
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchCities();
  }

  Future<void> _fetchCities() async {
    try {
      final cities = await widget.apiService.getCities();
      if (mounted) setState(() => _cities = cities);
    } catch (_) {
      // Non-critical — city-scoping picker just shows no options if this fails.
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roots = await widget.apiService.getCategoryTree();
      if (mounted) {
        setState(() {
          _rootCategories = roots;
          _loading = false;
          // Auto-expand all roots on first load if there are only a few
          if (roots.length <= 5) {
            _expanded.addAll(roots.map((r) => r.id));
          }
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

  List<CategoryModel> get _filteredRoots {
    var list = _rootCategories;
    if (_filterActive != null) {
      list = list.where((c) => c.isActive == _filterActive).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        if (c.name.toLowerCase().contains(q)) return true;
        return c.children.any((child) => child.name.toLowerCase().contains(q));
      }).toList();
    }
    return list;
  }

  void _openRootForm({CategoryModel? existing}) {
    final createdMsg = context.tr('admin_categories_snack_created');
    final updatedMsg = context.tr('admin_categories_snack_updated');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        existing: existing,
        parentCategory: null,
        allRootCategories: _rootCategories,
        allCities: _cities,
        onSave: (payload) async {
          final CategoryModel result;
          if (existing == null) {
            result = await widget.apiService.createCategory(payload);
            AuditLogService.log(
                action: 'create',
                module: 'Category',
                targetId: result.id,
                targetLabel: result.name);
            _snack(createdMsg, isError: false);
          } else {
            result =
                await widget.apiService.updateCategory(existing.id, payload);
            AuditLogService.log(
                action: 'update',
                module: 'Category',
                targetId: existing.id,
                targetLabel: existing.name);
            _snack(updatedMsg, isError: false);
          }
          _fetch();
          return result;
        },
      ),
    );
  }

  void _openSubcategoryForm(CategoryModel parent, {CategoryModel? existing}) {
    final addedPrefix =
        context.tr('admin_categories_snack_subcategory_added_prefix');
    final updatedMsg = context.tr('admin_categories_snack_subcategory_updated');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        existing: existing,
        parentCategory: parent,
        allRootCategories: _rootCategories,
        allCities: _cities,
        onSave: (payload) async {
          final CategoryModel result;
          if (existing == null) {
            result =
                await widget.apiService.createSubcategory(parent.id, payload);
            AuditLogService.log(
                action: 'create',
                module: 'Category',
                targetId: result.id,
                targetLabel: result.name,
                details: 'Subcategory of ${parent.name}');
            _snack('$addedPrefix ${parent.name}', isError: false);
          } else {
            result =
                await widget.apiService.updateCategory(existing.id, payload);
            AuditLogService.log(
                action: 'update',
                module: 'Category',
                targetId: existing.id,
                targetLabel: existing.name);
            _snack(updatedMsg, isError: false);
          }
          _fetch();
          return result;
        },
      ),
    );
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
    final hasChildren = cat.childrenCount > 0 || cat.children.isNotEmpty;
    final hasLinks = cat.placeLinksCount > 0;

    String body = context.tr('admin_categories_delete_confirm_body_default');
    if (hasChildren) {
      body = context.tr('admin_categories_delete_confirm_body_has_children');
    }
    if (hasLinks) {
      body =
          '${context.tr('admin_categories_delete_confirm_body_has_links_prefix')} '
          '${cat.placeLinksCount} '
          '${context.tr('admin_categories_delete_confirm_body_has_links_suffix')}';
    }
    final titlePrefix =
        context.tr('admin_categories_delete_confirm_title_prefix');
    final deleteLabel = context.tr('common_delete');
    final deletedPrefix = context.tr('admin_categories_snack_deleted_prefix');
    final deleteFailedPrefix =
        context.tr('admin_categories_snack_delete_failed_prefix');

    final confirmed = await adminConfirm(
      context,
      '$titlePrefix "${cat.name}"?',
      body,
      confirmLabel: deleteLabel,
    );
    if (!confirmed) return;

    try {
      await widget.apiService.deleteCategory(cat.id, cascade: hasChildren);
      AuditLogService.log(
          action: 'delete',
          module: 'Category',
          targetId: cat.id,
          targetLabel: cat.name);
      _snack('$deletedPrefix ${cat.name}', isError: false);
      _fetch();
    } on AdminApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('$deleteFailedPrefix $e', isError: true);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : AdC.blue,
      behavior: SnackBarBehavior.floating,
    ));
  }

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
                    _buildTitleBlock(context),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AdminAddButton(
                          label: context.tr('admin_categories_add_button'),
                          onTap: () => _openRootForm()),
                    ),
                  ],
                )
              : Row(children: [
                  Expanded(child: _buildTitleBlock(context)),
                  AdminAddButton(
                      label: context.tr('admin_categories_add_button'),
                      onTap: () => _openRootForm()),
                ]),

          const SizedBox(height: 20),

          // ── Toolbar: search always full-width, chips wrap below ──────
          _buildToolbar(context),

          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildTitleBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('admin_categories_page_title'),
          style: TextStyle(
              color: AdC.textPri, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          context.tr('admin_categories_page_subtitle'),
          style: TextStyle(color: AdC.textMute, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search — always full width
        TextField(
          onChanged: (v) => setState(() => _search = v),
          style: TextStyle(color: AdC.textPri, fontSize: 14),
          decoration: InputDecoration(
            hintText: context.tr('admin_categories_search_hint'),
            hintStyle: TextStyle(color: AdC.textMute, fontSize: 13),
            prefixIcon:
                Icon(Icons.search_rounded, color: AdC.textMute, size: 18),
            filled: true,
            fillColor: AdC.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AdC.overlay(0.12))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AdC.overlay(0.12))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AdC.blue)),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 10),
        // Filter chips — Wrap so they never overflow on any screen size
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _FilterChip(
                label: context.tr('category_subcat_all'),
                selected: _filterActive == null,
                onTap: () => setState(() => _filterActive = null)),
            _FilterChip(
                label: context.tr('admin_categories_filter_active'),
                selected: _filterActive == true,
                color: Colors.greenAccent,
                onTap: () => setState(() => _filterActive = true)),
            _FilterChip(
                label: context.tr('admin_categories_filter_inactive'),
                selected: _filterActive == false,
                color: Colors.redAccent,
                onTap: () => setState(() => _filterActive = false)),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AdC.blue));
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 48),
        const SizedBox(height: 12),
        Text(_error!,
            style: TextStyle(color: AdC.textMute), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _fetch,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(context.tr('common_retry')),
          style: ElevatedButton.styleFrom(
              backgroundColor: AdC.blue, foregroundColor: Colors.white),
        ),
      ]));
    }

    final roots = _filteredRoots;
    if (roots.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.category_rounded, color: AdC.textMute, size: 56),
        const SizedBox(height: 16),
        Text(context.tr('admin_categories_empty_title'),
            style: TextStyle(
                color: AdC.textSec, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          context.tr('admin_categories_empty_body'),
          style: TextStyle(color: AdC.textMute, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _openRootForm(),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(context.tr('admin_categories_add_first_button')),
          style: ElevatedButton.styleFrom(
              backgroundColor: AdC.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }

    // Drag-and-drop reordering only makes sense against the unfiltered list —
    // reordering a filtered subset would produce confusing sortOrder writes.
    final canReorder = _search.isEmpty && _filterActive == null;

    Widget buildCard(int i) => _RootCategoryCard(
          key: ValueKey(roots[i].id),
          category: roots[i],
          isExpanded: _expanded.contains(roots[i].id),
          onToggleExpand: () => setState(() {
            if (_expanded.contains(roots[i].id)) {
              _expanded.remove(roots[i].id);
            } else {
              _expanded.add(roots[i].id);
            }
          }),
          onEdit: () => _openRootForm(existing: roots[i]),
          onDelete: () => _deleteCategory(roots[i]),
          onToggleActive: () => widget.apiService.updateCategory(roots[i].id,
              {'isActive': !roots[i].isActive}).then((_) => _fetch()),
          onAddSubcategory: () => _openSubcategoryForm(roots[i]),
          onEditSubcategory: (child) =>
              _openSubcategoryForm(roots[i], existing: child),
          onDeleteSubcategory: (child) => _deleteCategory(child),
          dragHandle: canReorder
              ? Icon(Icons.drag_indicator_rounded,
                  color: AdC.textMute, size: 20)
              : null,
        );

    if (!canReorder) {
      return ListView.separated(
        itemCount: roots.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => buildCard(i),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: roots.length,
      itemBuilder: (ctx, i) => Padding(
        key: ValueKey('${roots[i].id}-pad'),
        padding: const EdgeInsets.only(bottom: 12),
        child: ReorderableDragStartListener(
          index: i,
          child: buildCard(i),
        ),
      ),
      onReorderItem: _reorderRoots,
    );
  }

  // ── Drag-and-drop reorder: PATCH sortOrder for every root whose position
  // changed, matching manual sortOrder edits already supported by the form. ──
  Future<void> _reorderRoots(int oldIndex, int newIndex) async {
    final roots = List<CategoryModel>.from(_filteredRoots);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = roots.removeAt(oldIndex);
    roots.insert(newIndex, moved);

    setState(() {
      _rootCategories = roots;
    });

    for (var i = 0; i < roots.length; i++) {
      if (roots[i].sortOrder == i) continue;
      try {
        await widget.apiService.updateCategory(roots[i].id, {'sortOrder': i});
      } catch (_) {
        // Best-effort — a single failed PATCH shouldn't block the rest;
        // _fetch() below reconciles the UI with whatever the backend has.
      }
    }
    AuditLogService.log(
        action: 'update',
        module: 'Category',
        details: 'Reordered root categories');
    _fetch();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root Category Card — collapsible, shows children
//
// RESPONSIVE NOTES
// ────────────────
// • The header row uses LayoutBuilder to detect narrow card widths and collapses
//   the stats pills so they don't overflow to the right.
// • On narrow cards the stats row is hidden or moved below the name.
// ─────────────────────────────────────────────────────────────────────────────

class _RootCategoryCard extends StatelessWidget {
  final CategoryModel category;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback onAddSubcategory;
  final ValueChanged<CategoryModel> onEditSubcategory;
  final ValueChanged<CategoryModel> onDeleteSubcategory;
  final Widget? dragHandle;

  const _RootCategoryCard({
    super.key,
    required this.category,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    required this.onAddSubcategory,
    required this.onEditSubcategory,
    required this.onDeleteSubcategory,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdC.overlay(0.12)),
      ),
      child: Column(
        children: [
          // ── Parent row ────────────────────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            final cardW = constraints.maxWidth;
            final isNarrowCard = cardW < 380;

            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (dragHandle != null) ...[
                        dragHandle!,
                        const SizedBox(width: 6),
                      ],
                      // Expand toggle
                      GestureDetector(
                        onTap: onToggleExpand,
                        child: AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.chevron_right_rounded,
                              color: AdC.textMute, size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Icon box
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AdC.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AdC.blue.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: category.icon != null
                              ? Text(category.icon!,
                                  style: const TextStyle(fontSize: 17))
                              : const Icon(Icons.category_rounded,
                                  color: AdC.blue, size: 18),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Name + slug — Expanded so it never clips
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AdC.textPri,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _ActiveBadge(isActive: category.isActive),
                            ]),
                            Text(
                              '/${category.slug}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: AdC.textMute, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // On wide cards show stats inline; on narrow cards
                      // they will be rendered below in the second row.
                      if (!isNarrowCard) ...[
                        const SizedBox(width: 8),
                        _CountPill(
                          icon: Icons.subdirectory_arrow_right_rounded,
                          value:
                              '${category.children.isNotEmpty ? category.children.length : category.childrenCount}',
                          label: context.tr('admin_categories_count_subcats'),
                        ),
                        const SizedBox(width: 6),
                        _CountPill(
                          icon: Icons.place_rounded,
                          value: '${category.placeLinksCount}',
                          label: context.tr('admin_categories_count_places'),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Context menu
                      PopupMenuButton<String>(
                        color: AdC.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        icon: Icon(Icons.more_vert_rounded,
                            color: AdC.textMute, size: 18),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        onSelected: (val) {
                          if (val == 'edit') onEdit();
                          if (val == 'toggle') onToggleActive();
                          if (val == 'delete') onDelete();
                        },
                        itemBuilder: (menuCtx) => [
                          PopupMenuItem(
                              value: 'edit',
                              child: _PopItem(Icons.edit_rounded,
                                  menuCtx.tr('admin_categories_menu_edit'))),
                          PopupMenuItem(
                              value: 'toggle',
                              child: _PopItem(
                                  category.isActive
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  category.isActive
                                      ? menuCtx.tr(
                                          'admin_categories_menu_deactivate')
                                      : menuCtx.tr(
                                          'admin_categories_menu_activate'))),
                          PopupMenuItem(
                              value: 'delete',
                              child: _PopItem(Icons.delete_rounded,
                                  menuCtx.tr('common_delete'),
                                  color: Colors.redAccent)),
                        ],
                      ),
                    ],
                  ),

                  // On narrow cards show stats in a Wrap below the header row
                  if (isNarrowCard) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _CountPill(
                            icon: Icons.subdirectory_arrow_right_rounded,
                            value:
                                '${category.children.isNotEmpty ? category.children.length : category.childrenCount}',
                            label: context.tr('admin_categories_count_subcats'),
                          ),
                          _CountPill(
                            icon: Icons.place_rounded,
                            value: '${category.placeLinksCount}',
                            label: context.tr('admin_categories_count_places'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          // ── Children ──────────────────────────────────────────────────
          if (isExpanded) ...[
            Divider(
                color: AdC.overlay(0.06), height: 1, indent: 16, endIndent: 16),
            ...category.children.map((child) => _ChildCategoryRow(
                  child: child,
                  onEdit: () => onEditSubcategory(child),
                  onDelete: () => onDeleteSubcategory(child),
                )),

            // Add subcategory button
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 4, 16, 12),
              child: GestureDetector(
                onTap: onAddSubcategory,
                child: Row(children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: AdC.blue.withValues(alpha: 0.7),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${context.tr('admin_categories_add_subcategory_prefix')} ${category.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AdC.blue.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Child Category Row
//
// RESPONSIVE NOTES
// ────────────────
// • The name column is Flexible so it shrinks before anything overflows.
// • The actions section uses a Wrap so on very narrow rows the edit/delete
//   buttons drop to a second line instead of overflowing right.
// • The badge and count pill are kept compact (no padding inflation).
// ─────────────────────────────────────────────────────────────────────────────

class _ChildCategoryRow extends StatelessWidget {
  final CategoryModel child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ChildCategoryRow(
      {required this.child, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: LayoutBuilder(builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Indent matching parent icon start (~56 dp)
            const SizedBox(width: 42),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AdC.overlay(0.24),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),

            // Name + slug — Flexible so long names truncate
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdC.textSec, fontSize: 13),
                  ),
                  Text(
                    '/${child.slug}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdC.textMute, fontSize: 10),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Right-side actions — never shrink below their intrinsic width;
            // use IntrinsicWidth wrapper so they don't overflow.
            _ActiveBadge(isActive: child.isActive),
            const SizedBox(width: 6),
            _CountPill(
              icon: Icons.place_rounded,
              value: '${child.placeLinksCount}',
              label: context.tr('admin_categories_count_places'),
            ),
            // Edit button
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                icon: Icon(Icons.edit_rounded, color: AdC.textMute, size: 14),
                onPressed: onEdit,
                tooltip: context.tr('admin_categories_menu_edit'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            // Delete button
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                icon: const Icon(Icons.delete_rounded,
                    color: Colors.redAccent, size: 14),
                onPressed: onDelete,
                tooltip: context.tr('common_delete'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Form Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryFormDialog extends StatefulWidget {
  final CategoryModel? existing;
  final CategoryModel? parentCategory;
  final List<CategoryModel> allRootCategories;
  final List<CityModel> allCities;
  final Future<CategoryModel> Function(Map<String, dynamic>) onSave;

  const _CategoryFormDialog({
    this.existing,
    this.parentCategory,
    required this.allRootCategories,
    required this.allCities,
    required this.onSave,
  });

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  // Normalized flat map of field → first error message string.
  // Populated from both POST (Zod _errors) and PUT (fieldErrors) shapes.
  Map<String, String>? _apiErrors;

  late TextEditingController _name;
  late TextEditingController _slug;
  late TextEditingController _icon;
  late TextEditingController _description;
  late TextEditingController _sortOrder;
  late TextEditingController _tags;
  bool _isActive = true;
  String? _selectedParentId;
  bool _slugManuallyEdited = false;

  // ── City-scoping (Firestore CategoryDetails side-table) ──────────────────
  // Empty = visible in every resort city (today's behaviour, unchanged).
  final Set<String> _selectedCityIds = {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _icon = TextEditingController(text: e?.icon ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _sortOrder = TextEditingController(text: '${e?.sortOrder ?? 0}');
    _tags = TextEditingController();
    _isActive = e?.isActive ?? true;
    _selectedParentId = e?.parentId ?? widget.parentCategory?.id;

    if (e != null) {
      CategoryDetailsService.stream(e.id).first.then((details) {
        if (mounted) {
          setState(() {
            _selectedCityIds
              ..clear()
              ..addAll(details.cityIds);
            _tags.text = details.tags.join(', ');
          });
        }
      });
    }

    _name.addListener(() {
      if (!_slugManuallyEdited && widget.existing == null) {
        _slug.text = _name.text
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _icon.dispose();
    _description.dispose();
    _sortOrder.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _apiErrors = null;
    });

    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'slug': _slug.text.trim(),
      if (_icon.text.trim().isNotEmpty) 'icon': _icon.text.trim(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      'sortOrder': int.tryParse(_sortOrder.text) ?? 0,
      'isActive': _isActive,
      if (_selectedParentId != null) 'parentId': _selectedParentId,
    };

    try {
      final saved = await widget.onSave(payload);
      final tags = _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      // Best-effort — the category itself is already saved at this point,
      // so a scoping-write failure shouldn't block closing the dialog.
      unawaited(CategoryDetailsService.setScoping(
        categoryId: saved.id,
        cityIds: _selectedCityIds.toList(),
        tags: tags,
      ));
      if (mounted) Navigator.pop(context);
    } on AdminApiException catch (e) {
      if (mounted) {
        setState(() {
          // Normalize the two different 400 error shapes the backend returns:
          //   POST shape: { "_errors":[], "name":{ "_errors":["Required"] } }
          //   PUT shape:  { "fieldErrors":{ "slug":["msg"] }, "formErrors":[] }
          // Storing e.errors raw and calling .toString() on values produces
          // "{_errors: [Required]}" — the Dart map repr, not the actual message.
          _apiErrors = e.errors != null ? _normalizeApiErrors(e.errors!) : null;
          _saving = false;
        });
        if (e.message.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// POST 400 (Zod): { "_errors": [], "name": { "_errors": ["Required"] } }
  /// PUT  400 (flat): { "fieldErrors": { "slug": ["…"] }, "formErrors": [] }
  Map<String, String> _normalizeApiErrors(Map<String, dynamic> raw) {
    final result = <String, String>{};

    raw.forEach((key, value) {
      // Skip Zod root _errors and PUT formErrors — these are non-field entries.
      if (key == '_errors' || key == 'formErrors') return;

      if (key == 'fieldErrors' && value is Map) {
        // PUT 400: unpack the nested fieldErrors map.
        value.forEach((field, msgs) {
          if (msgs is List && msgs.isNotEmpty) {
            result[field.toString()] = msgs.first.toString();
          } else if (msgs is String && msgs.isNotEmpty) {
            result[field.toString()] = msgs;
          }
        });
        return;
      }

      // POST 400 Zod: value is { "_errors": ["msg"] }
      if (value is Map) {
        final errs = value['_errors'];
        if (errs is List && errs.isNotEmpty) {
          result[key] = errs.first.toString();
        }
        return;
      }

      // Flat string or list at root level (defensive catch-all).
      if (value is List && value.isNotEmpty) {
        result[key] = value.first.toString();
      } else if (value is String && value.isNotEmpty) {
        result[key] = value;
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final isSubcategory = _selectedParentId != null;

    return AdminDialog(
      title: isEditing
          ? (isSubcategory
              ? context.tr('admin_categories_dialog_edit_subcategory')
              : context.tr('admin_categories_dialog_edit_category'))
          : (isSubcategory
              ? context.tr('admin_categories_dialog_add_subcategory')
              : context.tr('admin_categories_dialog_add_category')),
      icon: Icons.category_rounded,
      color: AdC.blue,
      saving: _saving,
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSubcategory || isEditing) ...[
              Text(context.tr('admin_categories_field_category_type'),
                  style: TextStyle(
                      color: AdC.textSec,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AdC.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdC.overlay(0.12)),
                ),
                child: DropdownButton<String?>(
                  value: _selectedParentId,
                  isExpanded: true,
                  dropdownColor: AdC.surface,
                  style: TextStyle(color: AdC.textSec, fontSize: 14),
                  underline: const SizedBox.shrink(),
                  hint: Text(context.tr('admin_categories_root_category_label'),
                      style: TextStyle(color: AdC.textMute, fontSize: 13)),
                  onChanged: (v) => setState(() => _selectedParentId = v),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                          context.tr('admin_categories_root_category_label'),
                          style: TextStyle(color: AdC.textSec)),
                    ),
                    ...widget.allRootCategories
                        .where((r) => r.id != widget.existing?.id)
                        .map((r) => DropdownMenuItem<String?>(
                              value: r.id,
                              child: Text(
                                  '${context.tr('admin_categories_subcategory_of_prefix')} ${r.name}',
                                  style: TextStyle(color: AdC.textSec)),
                            )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            AdminField(
              ctrl: _name,
              label: context.tr('admin_categories_field_name'),
              hint: context.tr('admin_categories_hint_name'),
              required: true,
              apiError: _apiErrors?['name'],
            ),
            AdminField(
              ctrl: _slug,
              label: context.tr('admin_categories_field_slug'),
              hint: context.tr('admin_categories_hint_slug'),
              required: true,
              helperText: context.tr('admin_categories_helper_slug'),
              apiError: _apiErrors?['slug'],
              onChanged: (_) => _slugManuallyEdited = true,
            ),
            AdminField(
              ctrl: _icon,
              label: context.tr('admin_payment_methods_field_icon'),
              hint: context.tr('admin_categories_hint_icon'),
              helperText: context.tr('admin_categories_helper_icon'),
            ),
            AdminField(
              ctrl: _description,
              label: context.tr('admin_categories_field_description'),
              hint: context.tr('admin_categories_hint_description'),
              maxLines: 2,
            ),
            AdminField(
              ctrl: _sortOrder,
              label: context.tr('admin_categories_field_sort_order'),
              hint: '1',
              keyboardType: TextInputType.number,
              helperText: context.tr('admin_categories_helper_sort_order'),
            ),
            AdminField(
              ctrl: _tags,
              label: context.tr('admin_categories_field_tags'),
              hint: context.tr('admin_categories_hint_tags'),
              helperText: context.tr('admin_categories_helper_tags'),
            ),
            const SizedBox(height: 4),
            Text(context.tr('admin_categories_field_visible_in'),
                style: TextStyle(
                    color: AdC.textSec,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              _selectedCityIds.isEmpty
                  ? context.tr('admin_categories_visible_all_cities')
                  : '${_selectedCityIds.length} ${context.tr('admin_categories_visible_selected_suffix')}',
              style: TextStyle(color: AdC.textMute, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.allCities.map((city) {
                final selected = _selectedCityIds.contains(city.id);
                return FilterChip(
                  label: Text(city.name),
                  labelStyle: TextStyle(
                      color: selected ? Colors.black : AdC.textSec,
                      fontSize: 12),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedCityIds.add(city.id);
                    } else {
                      _selectedCityIds.remove(city.id);
                    }
                  }),
                  backgroundColor: AdC.overlay(0.06),
                  selectedColor: AdC.teal,
                  checkmarkColor: Colors.black,
                  side: BorderSide(color: AdC.overlay(0.15)),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(context.tr('admin_payment_methods_field_active'),
                    style: TextStyle(
                        color: AdC.textSec,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              Switch(
                value: _isActive,
                activeThumbColor: Colors.greenAccent,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Support widgets local to this screen
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.green.withValues(alpha: 0.12)
              : Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive
                  ? Colors.greenAccent.withValues(alpha: 0.35)
                  : Colors.redAccent.withValues(alpha: 0.35)),
        ),
        child: Text(
          isActive
              ? context.tr('admin_categories_status_active')
              : context.tr('admin_categories_status_inactive'),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.greenAccent : Colors.redAccent),
        ),
      );
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _CountPill(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AdC.overlay(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdC.overlay(0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: AdC.textMute),
          const SizedBox(width: 4),
          Text('$value $label',
              style: TextStyle(color: AdC.textMute, fontSize: 10)),
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
              color: selected ? c.withValues(alpha: 0.5) : AdC.overlay(0.12)),
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
