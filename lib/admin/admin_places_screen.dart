import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/models.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Admin Places Screen
/// Lists all places for a given (city + channel) pair.
/// Both city and channel must be selected before managing places.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminPlacesScreen extends StatefulWidget {
  final AdminApiService apiService;
  final CityModel? selectedCity;
  final ChannelItem? selectedChannel;
  final VoidCallback onCityPickRequested;
  final VoidCallback onChannelPickRequested;

  const AdminPlacesScreen({
    super.key,
    required this.apiService,
    required this.selectedCity,
    required this.selectedChannel,
    required this.onCityPickRequested,
    required this.onChannelPickRequested,
  });

  @override
  State<AdminPlacesScreen> createState() => _AdminPlacesScreenState();
}

class _AdminPlacesScreenState extends State<AdminPlacesScreen> {
  List<PlaceItem> _places = [];
  bool _loading = false;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (widget.selectedCity != null && widget.selectedChannel != null) _fetch();
  }

  @override
  void didUpdateWidget(AdminPlacesScreen old) {
    super.didUpdateWidget(old);
    final cityChanged = widget.selectedCity?.id != old.selectedCity?.id;
    final channelChanged = widget.selectedChannel?.id != old.selectedChannel?.id;
    if (cityChanged || channelChanged) {
      _places = [];
      if (widget.selectedCity != null && widget.selectedChannel != null) {
        _fetch();
      }
    }
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pl = await widget.apiService.getPlaces(
          widget.selectedCity!.id, widget.selectedChannel!.id);
      if (mounted) setState(() { _places = pl; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(PlaceItem place) async {
    final confirmed =
        await adminConfirm(context, 'Delete "${place.name}"?',
            'This action cannot be undone.');
    if (!confirmed) return;
    try {
      await widget.apiService.deletePlace(
          widget.selectedCity!.id, widget.selectedChannel!.id, place.id);
      _fetch();
      _snack('Deleted ${place.name}', isError: false);
    } catch (e) {
      _snack('Delete failed: $e', isError: true);
    }
  }

  void _openForm({PlaceItem? place}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlaceFormDialog(
        existing: place,
        channelTitle: widget.selectedChannel?.title ?? '',
        onSave: (payload) async {
          try {
            if (place == null) {
              await widget.apiService.createPlace(
                  widget.selectedCity!.id,
                  widget.selectedChannel!.id,
                  payload);
              _snack('Place created!', isError: false);
            } else {
              await widget.apiService.updatePlace(
                  widget.selectedCity!.id,
                  widget.selectedChannel!.id,
                  place.id,
                  payload);
              _snack('Place updated!', isError: false);
            }
            _fetch();
          } catch (e) {
            _snack('Error: $e', isError: true);
            rethrow;
          }
        },
      ),
    );
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

  List<PlaceItem> get _filtered {
    if (_search.trim().isEmpty) return _places;
    final q = _search.toLowerCase();
    return _places
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q) ||
            p.address.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        widget.selectedCity != null && widget.selectedChannel != null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ready) ...[
                    // Breadcrumb
                    Wrap(spacing: 6, children: [
                      _Crumb(
                          icon: Icons.location_city_rounded,
                          label: widget.selectedCity!.name,
                          color: const Color(0xFF0D7377)),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white24, size: 16),
                      _Crumb(
                          icon: widget.selectedChannel!.icon,
                          label: widget.selectedChannel!.title,
                          color: widget.selectedChannel!.color),
                    ]),
                    const SizedBox(height: 6),
                  ],
                  const Text('Places',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text(
                    ready
                        ? 'Listings in ${widget.selectedChannel!.title}'
                        : 'Select a city and channel first',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (ready)
              AdminAddButton(
                label: 'Add Place',
                onTap: () => _openForm(),
              ),
          ]),
          const SizedBox(height: 20),

          // Search bar (only when data exists)
          if (ready && _places.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search places…',
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
                    borderSide:
                        const BorderSide(color: Color(0xFF9C27B0)),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

          Expanded(child: _buildContent(ready)),
        ],
      ),
    );
  }

  Widget _buildContent(bool ready) {
    if (!ready) {
      return _NeedSelectionView(
        hasCity: widget.selectedCity != null,
        onSelectCity: widget.onCityPickRequested,
        onSelectChannel: widget.onChannelPickRequested,
      );
    }
    if (_loading) return const AdminLoader();
    if (_error != null) return AdminErrorView(error: _error!, onRetry: _fetch);
    final filtered = _filtered;
    if (filtered.isEmpty && _places.isEmpty) {
      return AdminEmptyState(
        icon: Icons.place_rounded,
        title: 'No Places Yet',
        body: 'Add the first listing to '
            '${widget.selectedChannel!.title}.',
        actionLabel: 'Add Place',
        onAction: () => _openForm(),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text('No results for "$_search"',
            style: const TextStyle(color: Colors.white38)),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      color: const Color(0xFF9C27B0),
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _PlaceRow(
          place: filtered[i],
          channelColor: widget.selectedChannel?.color ?? Colors.grey,
          onEdit: () => _openForm(place: filtered[i]),
          onDelete: () => _delete(filtered[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────── PLACE ROW ───────────────────────────────────────

class _PlaceRow extends StatefulWidget {
  final PlaceItem place;
  final Color channelColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlaceRow({
    required this.place,
    required this.channelColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PlaceRow> createState() => _PlaceRowState();
}

class _PlaceRowState extends State<_PlaceRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final c = widget.channelColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering
                ? c.withValues(alpha: 0.5)
                : Colors.white12,
          ),
          boxShadow: _hovering
              ? [BoxShadow(
                  color: c.withValues(alpha: 0.15), blurRadius: 14)]
              : [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category icon bubble
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.place_rounded, color: c, size: 22),
            ),
            const SizedBox(width: 16),

            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                    _StatusBadge(isOpen: p.isOpen),
                  ]),
                  const SizedBox(height: 4),
                  Text(p.category,
                      style: TextStyle(
                          color: c, fontSize: 11,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    _InfoChip(
                        icon: Icons.star_rounded,
                        label: p.rating.toStringAsFixed(1),
                        color: Colors.amber),
                    const SizedBox(width: 8),
                    _InfoChip(
                        icon: Icons.rate_review_rounded,
                        label: '${p.reviewCount} reviews',
                        color: Colors.white38),
                    const SizedBox(width: 8),
                    _InfoChip(
                        icon: Icons.attach_money_rounded,
                        label: p.priceRange,
                        color: Colors.greenAccent.shade400),
                  ]),
                ],
              ),
            ),

            const SizedBox(width: 12),
            // Action buttons
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: Colors.white38, size: 18),
                  tooltip: 'Edit',
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_rounded,
                      color: Colors.redAccent, size: 18),
                  tooltip: 'Delete',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── PLACE FORM ──────────────────────────────────────

class _PlaceFormDialog extends StatefulWidget {
  final PlaceItem? existing;
  final String channelTitle;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _PlaceFormDialog({
    this.existing,
    required this.channelTitle,
    required this.onSave,
  });

  @override
  State<_PlaceFormDialog> createState() => _PlaceFormDialogState();
}

class _PlaceFormDialogState extends State<_PlaceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late TextEditingController _name;
  late TextEditingController _category;
  late TextEditingController _description;
  late TextEditingController _imagePath;
  late TextEditingController _address;
  late TextEditingController _phone;
  late TextEditingController _website;
  late TextEditingController _features;
  late TextEditingController _priceRange;
  late TextEditingController _rating;
  late TextEditingController _reviewCount;
  bool _isOpen = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _category = TextEditingController(text: e?.category ?? widget.channelTitle);
    _description = TextEditingController(text: e?.description ?? '');
    _imagePath = TextEditingController(text: e?.imagePath ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _website = TextEditingController(text: e?.website ?? '');
    _features = TextEditingController(
        text: e?.features.join(', ') ?? '');
    _priceRange = TextEditingController(text: e?.priceRange ?? '\$\$');
    _rating = TextEditingController(
        text: e != null ? e.rating.toString() : '4.0');
    _reviewCount = TextEditingController(
        text: e != null ? e.reviewCount.toString() : '0');
    _isOpen = e?.isOpen ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _category.dispose(); _description.dispose();
    _imagePath.dispose(); _address.dispose(); _phone.dispose();
    _website.dispose(); _features.dispose(); _priceRange.dispose();
    _rating.dispose(); _reviewCount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final features = _features.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final payload = {
      'name': _name.text.trim(),
      'category': _category.text.trim(),
      'description': _description.text.trim(),
      'imagePath': _imagePath.text.trim(),
      'address': _address.text.trim(),
      'phone': _phone.text.trim(),
      'website': _website.text.trim(),
      'features': features,
      'priceRange': _priceRange.text.trim(),
      'rating': double.tryParse(_rating.text) ?? 0.0,
      'reviewCount': int.tryParse(_reviewCount.text) ?? 0,
      'isOpen': _isOpen,
    };
    try {
      await widget.onSave(payload);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AdminDialog(
      title: isEdit ? 'Edit Place' : 'Add Place',
      icon: Icons.place_rounded,
      color: const Color(0xFF9C27B0),
      saving: _saving,
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Basic Info ──────────────────────────────────────────
            _SectionHeader('Basic Information'),
            AdminField(ctrl: _name, label: 'Place Name',
                hint: 'e.g. Sarova Whitesands', required: true),
            AdminField(ctrl: _category, label: 'Category',
                hint: 'e.g. Luxury Hotels', required: true),
            AdminField(ctrl: _description, label: 'Description',
                hint: 'A detailed description of this place',
                maxLines: 3, required: true),
            AdminField(ctrl: _imagePath, label: 'Image Path',
                hint: 'e.g. places/sarova_whitesands.jpg',
                helperText: 'Relative path inside assets/images/'),

            // ── Contact ─────────────────────────────────────────────
            _SectionHeader('Contact Details'),
            AdminField(ctrl: _address, label: 'Address',
                hint: 'Full address of the place'),
            AdminField(ctrl: _phone, label: 'Phone',
                hint: '+254 712 345 678',
                keyboardType: TextInputType.phone),
            AdminField(ctrl: _website, label: 'Website',
                hint: 'https://example.com',
                keyboardType: TextInputType.url),

            // ── Meta ────────────────────────────────────────────────
            _SectionHeader('Ratings & Info'),
            Row(children: [
              Expanded(
                child: AdminField(ctrl: _rating, label: 'Rating',
                    hint: '4.5',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminField(ctrl: _reviewCount, label: 'Review Count',
                    hint: '120',
                    keyboardType: TextInputType.number),
              ),
            ]),
            Row(children: [
              Expanded(
                child: AdminField(ctrl: _priceRange, label: 'Price Range',
                    hint: '\$, \$\$, \$\$\$ or \$\$\$\$'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isOpen = !_isOpen),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: _isOpen
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isOpen
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.red.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(children: [
                            Icon(
                              _isOpen
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: _isOpen
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                color: _isOpen
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),

            AdminField(ctrl: _features, label: 'Features',
                hint: 'Pool, Free WiFi, Parking, Pet Friendly',
                helperText: 'Comma-separated list of amenities/features'),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── SUPPORT WIDGETS ────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Row(children: [
          Expanded(
              child: Divider(
                  color: Colors.white12,
                  thickness: 1,
                  endIndent: 10)),
          Text(title,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w500)),
          Expanded(
              child: Divider(
                  color: Colors.white12,
                  thickness: 1,
                  indent: 10)),
        ]),
      );
}

class _StatusBadge extends StatelessWidget {
  final bool isOpen;
  const _StatusBadge({required this.isOpen});
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isOpen
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOpen
                ? Colors.greenAccent.withValues(alpha: 0.4)
                : Colors.redAccent.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          isOpen ? 'Open' : 'Closed',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isOpen ? Colors.greenAccent : Colors.redAccent,
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      );
}

class _Crumb extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Crumb(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _NeedSelectionView extends StatelessWidget {
  final bool hasCity;
  final VoidCallback onSelectCity;
  final VoidCallback onSelectChannel;
  const _NeedSelectionView({
    required this.hasCity,
    required this.onSelectCity,
    required this.onSelectChannel,
  });
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.place_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          Text(
            hasCity ? 'Select a Channel' : 'Select a City First',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            hasCity
                ? 'Pick a channel to manage its places.'
                : 'You need to select a city, then a channel before managing places.',
            style:
                const TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!hasCity)
            ElevatedButton.icon(
              onPressed: onSelectCity,
              icon: const Icon(Icons.location_city_rounded, size: 16),
              label: const Text('Select Resort City'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D7377),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: onSelectChannel,
              icon: const Icon(Icons.layers_rounded, size: 16),
              label: const Text('Select Channel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ]),
      );
}