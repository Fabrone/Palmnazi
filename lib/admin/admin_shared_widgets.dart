import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// admin_shared_widgets.dart
// Public micro-widgets shared across all admin screens.
// Import with: import 'admin_shared_widgets.dart';
// ─────────────────────────────────────────────────────────────────────────────

// ── Confirm dialog ────────────────────────────────────────────────────────────

Future<bool> adminConfirm(
  BuildContext context,
  String title,
  String body,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: Text(body,
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ── Loading spinner ───────────────────────────────────────────────────────────

class AdminLoader extends StatelessWidget {
  const AdminLoader({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF14FFEC),
          strokeWidth: 2,
        ),
      );
}

// ── Error view ────────────────────────────────────────────────────────────────

class AdminErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const AdminErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded,
                size: 16, color: Color(0xFF14FFEC)),
            label: const Text('Retry',
                style: TextStyle(color: Color(0xFF14FFEC))),
          ),
        ]),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white12, size: 64),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D7377),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ]),
      );
}

// ── Add button ────────────────────────────────────────────────────────────────

class AdminAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const AdminAddButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D7377),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

// ── Popup menu row item ───────────────────────────────────────────────────────

class AdminPopItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const AdminPopItem(this.icon, this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: color ?? Colors.white54),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: color ?? Colors.white70, fontSize: 13)),
      ]);
}

// ── Dialog shell ──────────────────────────────────────────────────────────────

class AdminDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool saving;
  final VoidCallback onSave;
  final Widget child;

  const AdminDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.saving,
    required this.onSave,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border:
                    Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white38, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),

            // ── Scrollable body ──────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: child,
              ),
            ),

            // ── Actions ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white38)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    onPressed: saving ? null : onSave,
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Outline button ────────────────────────────────────────────────────────────

class AdminOutlineBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const AdminOutlineBtn({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
}

// ── Filled button ─────────────────────────────────────────────────────────────

class AdminFilledBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const AdminFilledBtn({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
}

// ── Color picker ──────────────────────────────────────────────────────────────

class AdminColorPicker extends StatelessWidget {
  final String label;
  final Color selected;
  final List<Color> presets;
  final ValueChanged<Color> onChanged;
  const AdminColorPicker({
    super.key,
    required this.label,
    required this.selected,
    required this.presets,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: presets.map((c) {
              final isSelected = c.toARGB32() == selected.toARGB32();
              return GestureDetector(
                onTap: () => onChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: isSelected ? 2.5 : 0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Preview swatch
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: selected,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${selected.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected.computeLuminance() > 0.4
                    ? Colors.black87
                    : Colors.white,
              ),
            ),
          ),
        ],
      );
}

// ── Form field ────────────────────────────────────────────────────────────────

class AdminField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helperText;
  final TextEditingController ctrl;
  final bool required;
  final String? apiError;
  final int maxLines;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const AdminField({
    super.key,
    required this.label,
    required this.ctrl,
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
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 13),
              helperText: apiError != null ? null : helperText,
              helperStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              errorText: apiError,
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
                borderSide:
                    const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.redAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}