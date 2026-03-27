import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/category_model.dart';

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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        existing: existing,
        parentCategory: null,
        allRootCategories: _rootCategories,
        onSave: (payload) async {
          if (existing == null) {
            await widget.apiService.createCategory(payload);
            _snack('Category created', isError: false);
          } else {
            await widget.apiService.updateCategory(existing.id, payload);
            _snack('Category updated', isError: false);
          }
          _fetch();
        },
      ),
    );
  }

  void _openSubcategoryForm(CategoryModel parent, {CategoryModel? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        existing: existing,
        parentCategory: parent,
        allRootCategories: _rootCategories,
        onSave: (payload) async {
          if (existing == null) {
            await widget.apiService.createSubcategory(parent.id, payload);
            _snack('Subcategory added to ${parent.name}', isError: false);
          } else {
            await widget.apiService.updateCategory(existing.id, payload);
            _snack('Subcategory updated', isError: false);
          }
          _fetch();
        },
      ),
    );
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
    final hasChildren = cat.childrenCount > 0 || cat.children.isNotEmpty;
    final hasLinks = cat.placeLinksCount > 0;

    String body = 'This action cannot be undone.';
    if (hasChildren) {
      body = 'This will also delete all subcategories. Use cascade delete.';
    }
    if (hasLinks) {
      body =
          'This category is linked to ${cat.placeLinksCount} place(s). Remove links first.';
    }

    final confirmed = await adminConfirm(
      context,
      'Delete "${cat.name}"?',
      body,
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    try {
      await widget.apiService.deleteCategory(cat.id, cascade: hasChildren);
      _snack('Deleted ${cat.name}', isError: false);
      _fetch();
    } on AdminApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Delete failed: $e', isError: true);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? Colors.red.shade700 : const Color(0xFF2196F3),
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
                    _buildTitleBlock(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AdminAddButton(
                          label: 'Add Category',
                          onTap: () => _openRootForm()),
                    ),
                  ],
                )
              : Row(children: [
                  Expanded(child: _buildTitleBlock()),
                  AdminAddButton(
                      label: 'Add Category',
                      onTap: () => _openRootForm()),
                ]),

          const SizedBox(height: 20),

          // ── Toolbar: search always full-width, chips wrap below ──────
          _buildToolbar(),

          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTitleBlock() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        Text(
          'Global service categories — shared across all cities',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search — always full width
        TextField(
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search categories…',
            hintStyle:
                const TextStyle(color: Colors.white24, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.white38, size: 18),
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
                    const BorderSide(color: Color(0xFF2196F3))),
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
                label: 'All',
                selected: _filterActive == null,
                onTap: () => setState(() => _filterActive = null)),
            _FilterChip(
                label: 'Active',
                selected: _filterActive == true,
                color: Colors.greenAccent,
                onTap: () => setState(() => _filterActive = true)),
            _FilterChip(
                label: 'Inactive',
                selected: _filterActive == false,
                color: Colors.redAccent,
                onTap: () => setState(() => _filterActive = false)),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2196F3)));
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 48),
        const SizedBox(height: 12),
        Text(_error!,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _fetch,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white),
        ),
      ]));
    }

    final roots = _filteredRoots;
    if (roots.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.category_rounded,
            color: Colors.white24, size: 56),
        const SizedBox(height: 16),
        const Text('No categories yet',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Create your first category like Accommodation, Dining, or Wellness.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _openRootForm(),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add First Category'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }

    return ListView.separated(
      itemCount: roots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _RootCategoryCard(
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
        onToggleActive: () => widget.apiService
            .updateCategory(roots[i].id, {'isActive': !roots[i].isActive})
            .then((_) => _fetch()),
        onAddSubcategory: () => _openSubcategoryForm(roots[i]),
        onEditSubcategory: (child) =>
            _openSubcategoryForm(roots[i], existing: child),
        onDeleteSubcategory: (child) => _deleteCategory(child),
      ),
    );
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

  const _RootCategoryCard({
    required this.category,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    required this.onAddSubcategory,
    required this.onEditSubcategory,
    required this.onDeleteSubcategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
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
                      // Expand toggle
                      GestureDetector(
                        onTap: onToggleExpand,
                        child: AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.chevron_right_rounded,
                              color: Colors.white38, size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Icon box
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF2196F3)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: category.icon != null
                              ? Text(category.icon!,
                                  style: const TextStyle(fontSize: 17))
                              : const Icon(Icons.category_rounded,
                                  color: Color(0xFF2196F3), size: 18),
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
                                  style: const TextStyle(
                                      color: Colors.white,
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
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
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
                          label: 'subcats',
                        ),
                        const SizedBox(width: 6),
                        _CountPill(
                          icon: Icons.place_rounded,
                          value: '${category.placeLinksCount}',
                          label: 'places',
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Context menu
                      PopupMenuButton<String>(
                        color: const Color(0xFF1F2937),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.white38, size: 18),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 30, minHeight: 30),
                        onSelected: (val) {
                          if (val == 'edit') onEdit();
                          if (val == 'toggle') onToggleActive();
                          if (val == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit',
                              child: _PopItem(Icons.edit_rounded, 'Edit')),
                          PopupMenuItem(
                              value: 'toggle',
                              child: _PopItem(
                                  category.isActive
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  category.isActive
                                      ? 'Deactivate'
                                      : 'Activate')),
                          const PopupMenuItem(
                              value: 'delete',
                              child: _PopItem(
                                  Icons.delete_rounded, 'Delete',
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
                            label: 'subcats',
                          ),
                          _CountPill(
                            icon: Icons.place_rounded,
                            value: '${category.placeLinksCount}',
                            label: 'places',
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
                color: Colors.white.withValues(alpha: 0.06),
                height: 1,
                indent: 16,
                endIndent: 16),
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
                    color:
                        const Color(0xFF2196F3).withValues(alpha: 0.7),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Add subcategory to ${category.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: const Color(0xFF2196F3)
                              .withValues(alpha: 0.8),
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
                color: Colors.white24,
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
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '/${child.slug}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 10),
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
              label: 'places',
            ),
            // Edit button
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: Colors.white38, size: 14),
                onPressed: onEdit,
                tooltip: 'Edit',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
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
                tooltip: 'Delete',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
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
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _CategoryFormDialog({
    this.existing,
    this.parentCategory,
    required this.allRootCategories,
    required this.onSave,
  });

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  Map<String, dynamic>? _apiErrors;

  late TextEditingController _name;
  late TextEditingController _slug;
  late TextEditingController _icon;
  late TextEditingController _description;
  late TextEditingController _sortOrder;
  bool _isActive = true;
  String? _selectedParentId;
  bool _slugManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _icon = TextEditingController(text: e?.icon ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _sortOrder = TextEditingController(text: '${e?.sortOrder ?? 0}');
    _isActive = e?.isActive ?? true;
    _selectedParentId = e?.parentId ?? widget.parentCategory?.id;

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
      await widget.onSave(payload);
      if (mounted) Navigator.pop(context);
    } on AdminApiException catch (e) {
      if (mounted) {
        setState(() {
          _apiErrors = e.errors;
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final isSubcategory = _selectedParentId != null;

    return AdminDialog(
      title: isEditing
          ? 'Edit ${isSubcategory ? "Subcategory" : "Category"}'
          : 'Add ${isSubcategory ? "Subcategory" : "Category"}',
      icon: Icons.category_rounded,
      color: const Color(0xFF2196F3),
      saving: _saving,
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSubcategory || isEditing) ...[
              const Text('Category Type',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButton<String?>(
                  value: _selectedParentId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1F2937),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                  underline: const SizedBox.shrink(),
                  hint: const Text('Root category (top level)',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  onChanged: (v) => setState(() => _selectedParentId = v),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Root category (top level)',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    ...widget.allRootCategories
                        .where((r) => r.id != widget.existing?.id)
                        .map((r) => DropdownMenuItem<String?>(
                              value: r.id,
                              child: Text('Subcategory of: ${r.name}',
                                  style: const TextStyle(
                                      color: Colors.white70)),
                            )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            AdminField(
              ctrl: _name,
              label: 'Category Name',
              hint: 'e.g. Accommodation',
              required: true,
              apiError: _apiErrors?['name']?.toString(),
            ),

            AdminField(
              ctrl: _slug,
              label: 'Slug',
              hint: 'e.g. accommodation',
              required: true,
              helperText: 'Auto-generated from name. Lowercase, hyphens only.',
              apiError: _apiErrors?['slug']?.toString(),
              onChanged: (_) => _slugManuallyEdited = true,
            ),

            AdminField(
              ctrl: _icon,
              label: 'Icon (emoji)',
              hint: '🏨',
              helperText: 'Paste a single emoji character',
            ),

            AdminField(
              ctrl: _description,
              label: 'Description',
              hint: 'Brief description of this category',
              maxLines: 2,
            ),

            AdminField(
              ctrl: _sortOrder,
              label: 'Sort Order',
              hint: '1',
              keyboardType: TextInputType.number,
              helperText: 'Lower numbers appear first',
            ),

            const SizedBox(height: 8),
            Row(children: [
              const Expanded(
                child: Text('Active',
                    style: TextStyle(
                        color: Colors.white70,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          isActive ? 'Active' : 'Inactive',
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
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: Colors.white38),
          const SizedBox(width: 4),
          Text('$value $label',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 10)),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? c.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? c.withValues(alpha: 0.5)
                  : Colors.white12),
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