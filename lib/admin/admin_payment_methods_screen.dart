import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/services/payment_methods_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminPaymentMethodsScreen
//
// Manages the global PaymentMethods catalogue (Firestore) — the set of
// payment options a place can be configured to accept (e.g. M-Pesa, Card,
// Bank Transfer, Cash on Arrival). Configuration only; no payment processing
// happens here. Places select which of these they accept from Step 8 of the
// place wizard (see admin_place_wizard_screen.dart).
// ─────────────────────────────────────────────────────────────────────────────

class AdminPaymentMethodsScreen extends StatelessWidget {
  const AdminPaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isNarrow = mq.size.width < 480;
    final hPad = isNarrow ? 12.0 : 24.0;
    final vPad = isNarrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleBlock(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AdminAddButton(
                        label: 'Add Payment Method',
                        onTap: () => _openForm(context),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _titleBlock()),
                    const SizedBox(width: 16),
                    AdminAddButton(
                      label: 'Add Payment Method',
                      onTap: () => _openForm(context),
                    ),
                  ],
                ),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<List<PaymentMethodModel>>(
              stream: PaymentMethodsService.streamAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const AdminLoader();
                }
                if (snap.hasError) {
                  return AdminErrorView(
                    error: snap.error.toString(),
                    onRetry: () {},
                  );
                }
                final methods = snap.data ?? const <PaymentMethodModel>[];
                if (methods.isEmpty) {
                  return AdminEmptyState(
                    icon: Icons.payments_rounded,
                    title: 'No payment methods yet',
                    body:
                        'Add the payment options places can accept, e.g. M-Pesa, Card, or Cash on Arrival.',
                    actionLabel: 'Add Payment Method',
                    onAction: () => _openForm(context),
                  );
                }
                return ListView.separated(
                  itemCount: methods.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _PaymentMethodRow(
                    method: methods[i],
                    onEdit: () => _openForm(context, existing: methods[i]),
                    onToggleActive: () => PaymentMethodsService.setActive(
                        methods[i].id, !methods[i].isActive),
                    onDelete: () => _delete(context, methods[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleBlock() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Methods',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(
            'Configure the payment options places can accept',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );

  Future<void> _delete(BuildContext context, PaymentMethodModel method) async {
    final confirmed = await adminConfirm(
      context,
      'Delete "${method.name}"?',
      'Places that accept this payment method will no longer show it as an option. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await PaymentMethodsService.delete(method.id);
  }

  void _openForm(BuildContext context, {PaymentMethodModel? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentMethodFormDialog(existing: existing),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentMethodRow extends StatelessWidget {
  final PaymentMethodModel method;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _PaymentMethodRow({
    required this.method,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  static const _accentColor = Color(0xFF0D7377);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: method.isActive
              ? _accentColor.withValues(alpha: 0.25)
              : Colors.white12,
        ),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: method.icon != null && method.icon!.isNotEmpty
                ? Text(method.icon!, style: const TextStyle(fontSize: 18))
                : const Icon(Icons.payments_rounded,
                    color: _accentColor, size: 18),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(method.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    PaymentMethodModel.typeLabel(method.type),
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
              ]),
              if (method.description != null &&
                  method.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(method.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ],
          ),
        ),
        Switch(
          value: method.isActive,
          activeThumbColor: Colors.greenAccent,
          onChanged: (_) => onToggleActive(),
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 18),
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 18),
          onPressed: onDelete,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentMethodFormDialog extends StatefulWidget {
  final PaymentMethodModel? existing;
  const _PaymentMethodFormDialog({this.existing});

  @override
  State<_PaymentMethodFormDialog> createState() =>
      _PaymentMethodFormDialogState();
}

class _PaymentMethodFormDialogState extends State<_PaymentMethodFormDialog> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _descCtrl =
      TextEditingController(text: widget.existing?.description);
  late final _iconCtrl = TextEditingController(text: widget.existing?.icon);
  late final _sortOrderCtrl =
      TextEditingController(text: '${widget.existing?.sortOrder ?? 0}');
  late PaymentMethodType _type =
      widget.existing?.type ?? PaymentMethodType.mpesa;
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  // Rebuilt whenever _type changes — see _rebuildConfigControllers. Keyed by
  // PaymentConfigField.key so _save() can read them back into a plain map.
  Map<String, TextEditingController> _configCtrls = {};

  @override
  void initState() {
    super.initState();
    _rebuildConfigControllers();
  }

  void _rebuildConfigControllers({bool disposeOld = false}) {
    if (disposeOld) {
      for (final c in _configCtrls.values) {
        c.dispose();
      }
    }
    final existingConfig = widget.existing?.config ?? const {};
    _configCtrls = {
      for (final field in PaymentMethodModel.configFieldsFor(_type))
        field.key: TextEditingController(text: existingConfig[field.key]),
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _iconCtrl.dispose();
    _sortOrderCtrl.dispose();
    for (final c in _configCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = <String, String>{
        for (final entry in _configCtrls.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      };
      final method = PaymentMethodModel(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        type: _type,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        icon: _iconCtrl.text.trim().isEmpty ? null : _iconCtrl.text.trim(),
        isActive: _isActive,
        sortOrder: int.tryParse(_sortOrderCtrl.text.trim()) ?? 0,
        config: config,
      );
      if (widget.existing == null) {
        await PaymentMethodsService.create(method);
      } else {
        await PaymentMethodsService.update(widget.existing!.id, method);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Save failed: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminDialog(
      title: widget.existing == null
          ? 'Add Payment Method'
          : 'Edit Payment Method',
      icon: Icons.payments_rounded,
      color: const Color(0xFF0D7377),
      saving: _saving,
      onSave: _save,
      saveLabel: widget.existing == null ? 'Add' : 'Save',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          ],
          AdminField(
            ctrl: _nameCtrl,
            label: 'Name',
            hint: 'e.g. M-Pesa',
            required: true,
          ),
          const Text('Type',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButton<PaymentMethodType>(
              value: _type,
              isExpanded: true,
              dropdownColor: const Color(0xFF1F2937),
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              items: PaymentMethodType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(PaymentMethodModel.typeLabel(t)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _type = v ?? _type;
                _rebuildConfigControllers(disposeOld: true);
              }),
            ),
          ),
          const SizedBox(height: 16),
          AdminField(
            ctrl: _descCtrl,
            label: 'Description',
            hint: 'Optional note shown to admins, e.g. "Paybill 123456"',
            maxLines: 2,
          ),
          AdminField(
            ctrl: _iconCtrl,
            label: 'Icon (emoji)',
            hint: 'e.g. 📱',
          ),
          AdminField(
            ctrl: _sortOrderCtrl,
            label: 'Sort Order',
            hint: '0',
            keyboardType: TextInputType.number,
          ),
          if (PaymentMethodModel.configFieldsFor(_type).isNotEmpty) ...[
            const Text('Gateway Configuration (placeholder)',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text(
                'These fields are stored for reference only — no real gateway is wired up yet. Fill them in once this method is ready for actual integration.',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 10),
            ...PaymentMethodModel.configFieldsFor(_type).map((field) =>
                AdminField(
                  ctrl: _configCtrls[field.key]!,
                  label: field.label,
                  hint: field.hint,
                )),
          ],
          Row(children: [
            const Expanded(
              child: Text('Active',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            Switch(
              value: _isActive,
              activeThumbColor: Colors.greenAccent,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
