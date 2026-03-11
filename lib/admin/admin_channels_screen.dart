import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/models.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Admin Channels Screen
/// Lists all channels for a given resort city.
/// Requires a city to be selected from the Resort Cities screen first.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminChannelsScreen extends StatefulWidget {
  final AdminApiService apiService;
  final CityModel? selectedCity;
  final VoidCallback onCityPickRequested;
  final ValueChanged<ChannelItem> onChannelSelected;

  const AdminChannelsScreen({
    super.key,
    required this.apiService,
    required this.selectedCity,
    required this.onCityPickRequested,
    required this.onChannelSelected,
  });

  @override
  State<AdminChannelsScreen> createState() => _AdminChannelsScreenState();
}

class _AdminChannelsScreenState extends State<AdminChannelsScreen> {
  List<ChannelItem> _channels = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.selectedCity != null) _fetch();
  }

  @override
  void didUpdateWidget(AdminChannelsScreen old) {
    super.didUpdateWidget(old);
    if (widget.selectedCity?.id != old.selectedCity?.id) {
      _channels = [];
      if (widget.selectedCity != null) _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final ch = await widget.apiService.getChannels(widget.selectedCity!.id);
      if (mounted) setState(() { _channels = ch; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(ChannelItem channel) async {
    final confirmed = await adminConfirm(
        context, 'Delete "${channel.title}"?',
        'All places within this channel will also be removed.');
    if (!confirmed) return;
    try {
      await widget.apiService.deleteChannel(
          widget.selectedCity!.id, channel.id);
      _fetch();
      _snack('Deleted ${channel.title}', isError: false);
    } catch (e) {
      _snack('Delete failed: $e', isError: true);
    }
  }

  void _openForm({ChannelItem? channel}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChannelFormDialog(
        existing: channel,
        onSave: (payload) async {
          try {
            if (channel == null) {
              await widget.apiService.createChannel(
                  widget.selectedCity!.id, payload);
              _snack('Channel created!', isError: false);
            } else {
              await widget.apiService.updateChannel(
                  widget.selectedCity!.id, channel.id, payload);
              _snack('Channel updated!', isError: false);
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
          isError ? Colors.red.shade700 : const Color(0xFF2196F3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Expanded(
              child: widget.selectedCity == null
                  ? const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Channels',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        Text('Select a resort city first',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D7377)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFF0D7377)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              Icon(Icons.location_city_rounded,
                                  size: 12,
                                  color: const Color(0xFF0D7377)),
                              const SizedBox(width: 6),
                              Text(widget.selectedCity!.name,
                                  style: TextStyle(
                                      color: const Color(0xFF0D7377),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        const Text('Channels',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const Text('Manage categories within this city',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ),
            ),
            if (widget.selectedCity != null)
              AdminAddButton(
                label: 'Add Channel',
                onTap: () => _openForm(),
              ),
          ]),
          const SizedBox(height: 24),

          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (widget.selectedCity == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.layers_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          const Text('No City Selected',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Please select a resort city first to manage its channels.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: widget.onCityPickRequested,
            icon: const Icon(Icons.location_city_rounded, size: 16),
            label: const Text('Select Resort City'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      );
    }
    if (_loading) return const AdminLoader();
    if (_error != null) return AdminErrorView(error: _error!, onRetry: _fetch);
    if (_channels.isEmpty) {
      return AdminEmptyState(
        icon: Icons.layers_rounded,
        title: 'No Channels Yet',
        body: 'Add your first channel to ${widget.selectedCity!.name}.',
        actionLabel: 'Add Channel',
        onAction: () => _openForm(),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      color: const Color(0xFF2196F3),
      child: LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1.2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _channels.length,
          itemBuilder: (_, i) => _ChannelCard(
            channel: _channels[i],
            onEdit: () => _openForm(channel: _channels[i]),
            onDelete: () => _delete(_channels[i]),
            onManagePlaces: () => widget.onChannelSelected(_channels[i]),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────── CHANNEL CARD ────────────────────────────────────

class _ChannelCard extends StatefulWidget {
  final ChannelItem channel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManagePlaces;

  const _ChannelCard({
    required this.channel,
    required this.onEdit,
    required this.onDelete,
    required this.onManagePlaces,
  });

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
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
                ? ch.color.withValues(alpha: 0.6)
                : ch.color.withValues(alpha: 0.2),
            width: _hovering ? 1.5 : 1,
          ),
          boxShadow: _hovering
              ? [BoxShadow(
                  color: ch.color.withValues(alpha: 0.2), blurRadius: 20)]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ch.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(ch.icon, color: ch.color, size: 24),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white38, size: 18),
                  color: const Color(0xFF1F2937),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit();
                    if (v == 'delete') widget.onDelete();
                    if (v == 'places') widget.onManagePlaces();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'places',
                        child: AdminPopItem(
                            Icons.place_rounded, 'Manage Places')),
                    const PopupMenuItem(
                        value: 'edit',
                        child: AdminPopItem(Icons.edit_rounded, 'Edit')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: AdminPopItem(Icons.delete_rounded, 'Delete',
                            color: Colors.red)),
                  ],
                ),
              ]),
              const SizedBox(height: 14),
              Text(ch.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              const SizedBox(height: 6),
              Text(ch.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.5)),
              const SizedBox(height: 10),
              // Subcategory chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ch.subcategories.take(3).map((s) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ch.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: ch.color.withValues(alpha: 0.25)),
                  ),
                  child: Text(s,
                      style: TextStyle(fontSize: 10, color: ch.color)),
                )).toList(),
              ),
              const Spacer(),
              Row(children: [
                Expanded(
                  child: AdminOutlineBtn(
                    label: 'Edit',
                    icon: Icons.edit_rounded,
                    color: Colors.white38,
                    onTap: widget.onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdminFilledBtn(
                    label: 'Places',
                    icon: Icons.place_rounded,
                    color: ch.color,
                    onTap: widget.onManagePlaces,
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

// ──────────────────────── CHANNEL FORM DIALOG ────────────────────────────────

class _ChannelFormDialog extends StatefulWidget {
  final ChannelItem? existing;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _ChannelFormDialog({this.existing, required this.onSave});

  @override
  State<_ChannelFormDialog> createState() => _ChannelFormDialogState();
}

class _ChannelFormDialogState extends State<_ChannelFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late TextEditingController _title;
  late TextEditingController _description;
  late TextEditingController _imagePath;
  late TextEditingController _subcategories;
  Color _selectedColor = const Color(0xFF2196F3);
  String _selectedIconName = 'king_bed_outlined';

  static const _presetColors = [
    Color(0xFF0D7377), Color(0xFF2196F3), Color(0xFF00897B),
    Color(0xFFE91E63), Color(0xFFFF9800), Color(0xFF9C27B0),
    Color(0xFF1A237E), Color(0xFF4CAF50), Color(0xFFFF5722),
  ];

  static const _iconOptions = [
    _IconOption('king_bed_outlined', Icons.king_bed_outlined, 'Accommodation'),
    _IconOption('restaurant_menu', Icons.restaurant_menu, 'Dining'),
    _IconOption('celebration', Icons.celebration, 'Events'),
    _IconOption('shopping_bag_outlined', Icons.shopping_bag_outlined, 'Shopping'),
    _IconOption('terrain', Icons.terrain, 'Adventure'),
    _IconOption('spa_outlined', Icons.spa_outlined, 'Wellness'),
    _IconOption('beach_access', Icons.beach_access, 'Beach'),
    _IconOption('nightlife', Icons.nightlife, 'Nightlife'),
    _IconOption('directions_car', Icons.directions_car, 'Transport'),
    _IconOption('museum', Icons.museum, 'Culture'),
    _IconOption('fitness_center', Icons.fitness_center, 'Fitness'),
    _IconOption('local_hospital', Icons.local_hospital, 'Health'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _imagePath = TextEditingController(text: e?.imagePath ?? '');
    _subcategories = TextEditingController(
        text: e?.subcategories.join(', ') ?? '');
    if (e != null) {
      _selectedColor = e.color;
      _selectedIconName = _ChannelIconHelper.getIconName(e.icon);
    }
  }

  @override
  void dispose() {
    _title.dispose(); _description.dispose();
    _imagePath.dispose(); _subcategories.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final subs = _subcategories.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final payload = {
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'imagePath': _imagePath.text.trim(),
      'iconName': _selectedIconName,
      'colorHex':
          '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      'subcategories': subs,
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
    return AdminDialog(
      title: widget.existing != null ? 'Edit Channel' : 'Add Channel',
      icon: Icons.layers_rounded,
      color: const Color(0xFF2196F3),
      saving: _saving,
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminField(ctrl: _title, label: 'Channel Title',
                hint: 'e.g. Dining', required: true),
            AdminField(ctrl: _description, label: 'Description',
                hint: 'Short description of this channel',
                maxLines: 2, required: true),
            AdminField(ctrl: _imagePath, label: 'Image Path',
                hint: 'e.g. channels/dining.jpg',
                helperText: 'Relative path inside assets/images/'),
            AdminField(ctrl: _subcategories, label: 'Subcategories',
                hint: 'Fine Dining, Seafood, Street Food',
                helperText: 'Comma-separated subcategory names'),
            const SizedBox(height: 16),

            // Icon picker
            const Text('Channel Icon',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _iconOptions.map((opt) {
                final isSelected = _selectedIconName == opt.name;
                return Tooltip(
                  message: opt.label,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedIconName = opt.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _selectedColor.withValues(alpha: 0.25)
                            : const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? _selectedColor
                              : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Icon(opt.icon,
                          size: 22,
                          color: isSelected
                              ? _selectedColor
                              : Colors.white38),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            AdminColorPicker(
              label: 'Channel Color',
              selected: _selectedColor,
              presets: _presetColors,
              onChanged: (c) => setState(() => _selectedColor = c),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconOption {
  final String name;
  final IconData icon;
  final String label;
  const _IconOption(this.name, this.icon, this.label);
}

// Expose helper for icon name lookup used in form
extension _ChannelIconHelper on ChannelItem {
  static String getIconName(IconData icon) {
    if (icon == Icons.king_bed_outlined) return 'king_bed_outlined';
    if (icon == Icons.restaurant_menu) return 'restaurant_menu';
    if (icon == Icons.celebration) return 'celebration';
    if (icon == Icons.shopping_bag_outlined) return 'shopping_bag_outlined';
    if (icon == Icons.terrain) return 'terrain';
    if (icon == Icons.spa_outlined) return 'spa_outlined';
    if (icon == Icons.beach_access) return 'beach_access';
    if (icon == Icons.nightlife) return 'nightlife';
    if (icon == Icons.directions_car) return 'directions_car';
    if (icon == Icons.museum) return 'museum';
    if (icon == Icons.fitness_center) return 'fitness_center';
    if (icon == Icons.local_hospital) return 'local_hospital';
    return 'king_bed_outlined';
  }
}