import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/audit_log_entry.dart';
import 'package:palmnazi/services/audit_log_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminAuditLogScreen
//
// Read-only stream of the most recent 200 admin actions (AuditLog collection
// — see AuditLogService.log, called from every admin screen that mutates
// data). MainAdmin-only, same convention as AdminRoleRequestsScreen.
// ─────────────────────────────────────────────────────────────────────────────

const _kSurface = Color(0xFF111827);
const _kTeal = Color(0xFF14FFEC);

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  String? _moduleFilter;
  List<AuditLogEntry> _latest = [];

  Future<void> _export() async {
    final rows = [
      ['Timestamp', 'Admin', 'Action', 'Module', 'Target', 'Details'],
      ..._latest.map((e) => [
            e.timestamp?.toIso8601String() ?? '',
            e.adminEmail,
            e.action,
            e.module,
            e.targetLabel,
            e.details,
          ]),
    ];
    final csv = rows
        .map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(','))
        .join('\n');
    final fileName =
        'palmnazi-audit-log-${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
    await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exported ${_latest.length} row(s).'),
        backgroundColor: const Color(0xFF0D7377),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AuditLogEntry>>(
      stream: AuditLogService.streamRecent(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AdminLoader();
        }
        if (snap.hasError) {
          return AdminErrorView(
              error: 'Could not load audit log: ${snap.error}', onRetry: () {});
        }
        final all = snap.data ?? const <AuditLogEntry>[];
        _latest = all;
        final modules = all.map((e) => e.module).toSet().toList()..sort();
        final visible = _moduleFilter == null
            ? all
            : all.where((e) => e.module == _moduleFilter).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _FilterChip(
                        label: 'All (${all.length})',
                        selected: _moduleFilter == null,
                        onTap: () => setState(() => _moduleFilter = null),
                      ),
                      ...modules.map((m) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _FilterChip(
                              label: m,
                              selected: _moduleFilter == m,
                              onTap: () => setState(() => _moduleFilter = m),
                            ),
                          )),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: all.isEmpty ? null : _export,
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Export CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTeal,
                    side: BorderSide(color: _kTeal.withValues(alpha: 0.4)),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const AdminEmptyState(
                      icon: Icons.history_rounded,
                      title: 'No activity yet',
                      body: 'Admin actions (creating/editing/deleting places, '
                          'cities, categories, roles, blog posts) will show '
                          'up here as they happen.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _EntryTile(entry: visible[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _kTeal.withValues(alpha: 0.15) : _kSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    selected ? _kTeal.withValues(alpha: 0.5) : Colors.white12),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? _kTeal : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

class _EntryTile extends StatelessWidget {
  final AuditLogEntry entry;
  const _EntryTile({required this.entry});

  IconData get _icon {
    switch (entry.action) {
      case 'create':
        return Icons.add_circle_outline_rounded;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline_rounded;
      case 'role_grant':
        return Icons.verified_user_outlined;
      case 'role_revoke':
        return Icons.remove_moderator_outlined;
      default:
        return Icons.bolt_rounded;
    }
  }

  Color get _color {
    switch (entry.action) {
      case 'create':
        return const Color(0xFF00C853);
      case 'delete':
        return const Color(0xFFCF6679);
      case 'role_grant':
      case 'role_revoke':
        return const Color(0xFFFF9800);
      default:
        return _kTeal;
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          Icon(_icon, color: _color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${entry.action.replaceAll('_', ' ')} · ${entry.module}'
                    '${entry.targetLabel.isNotEmpty ? ' — ${entry.targetLabel}' : ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                if (entry.details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(entry.details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
                const SizedBox(height: 2),
                Text('${entry.adminEmail} · ${_fmt(entry.timestamp)}',
                    style:
                        const TextStyle(color: Colors.white24, fontSize: 10.5)),
              ],
            ),
          ),
        ]),
      );
}
