import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/system_settings_model.dart';
import 'package:palmnazi/services/audit_log_service.dart';
import 'package:palmnazi/services/system_settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminSettingsScreen
//
// System-wide preferences (contact info, footer links, maintenance mode) and
// a Firestore data export. MainAdmin-only — routing guard lives in
// AdminDashboard, same convention as AdminRoleRequestsScreen.
// ─────────────────────────────────────────────────────────────────────────────

final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

const _kSurface = Color(0xFF111827);
const _kTeal = Color(0xFF14FFEC);
const _kOrange = Color(0xFFFF9800);
const _kRed = Color(0xFFCF6679);

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _maintenanceMsgCtrl = TextEditingController();
  final List<_FooterLinkEditRow> _footerLinks = [];

  bool _maintenanceMode = false;
  bool _loaded = false;
  bool _saving = false;
  bool _exporting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _maintenanceMsgCtrl.dispose();
    for (final row in _footerLinks) {
      row.dispose();
    }
    super.dispose();
  }

  void _hydrate(SystemSettingsModel s) {
    if (_loaded) return; // only pre-fill once; don't clobber in-progress edits
    _emailCtrl.text = s.contactEmail;
    _phoneCtrl.text = s.contactPhone;
    _maintenanceMsgCtrl.text = s.maintenanceMessage;
    _maintenanceMode = s.maintenanceMode;
    _footerLinks
      ..clear()
      ..addAll(s.footerLinks.map((f) => _FooterLinkEditRow.from(f)));
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = SystemSettingsModel(
        contactEmail: _emailCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        footerLinks: _footerLinks
            .where((r) => r.labelCtrl.text.trim().isNotEmpty)
            .map((r) => FooterLink(
                label: r.labelCtrl.text.trim(), url: r.urlCtrl.text.trim()))
            .toList(),
        maintenanceMode: _maintenanceMode,
        maintenanceMessage: _maintenanceMsgCtrl.text.trim(),
      );
      await SystemSettingsService.save(settings);
      AuditLogService.log(
          action: 'update', module: 'Settings', targetLabel: 'System Settings');
      _log.i('✅ [AdminSettingsScreen] Settings saved');
      if (mounted) _snack('Settings saved.', ok: true);
    } catch (e) {
      _log.e('❌ [AdminSettingsScreen] Save failed', error: e);
      if (mounted) _snack('Could not save settings: $e', ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleMaintenance(bool next) async {
    if (next) {
      final confirm = await adminConfirm(
        context,
        'Enable Maintenance Mode?',
        'Tourists will see a maintenance notice instead of the landing page '
            'until this is turned off again. Admins are unaffected.',
        confirmLabel: 'Enable',
      );
      if (!confirm) return;
    }
    setState(() => _maintenanceMode = next);
    try {
      await SystemSettingsService.setMaintenanceMode(next,
          message: _maintenanceMsgCtrl.text.trim());
      AuditLogService.log(
          action: 'update',
          module: 'Settings',
          targetLabel: 'Maintenance Mode',
          details: next ? 'Enabled' : 'Disabled');
      if (mounted) {
        _snack(
            next ? 'Maintenance mode enabled.' : 'Maintenance mode disabled.',
            ok: !next);
      }
    } catch (e) {
      setState(() => _maintenanceMode = !next); // revert on failure
      if (mounted) _snack('Could not update maintenance mode: $e', ok: false);
    }
  }

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final count = await SystemSettingsService.exportFirestoreData();
      if (mounted) {
        _snack(
            'Exported $count document(s) across every Firestore '
            'collection. Places/Cities/Categories/Bookings-config live in '
            'the backend database and are not covered by this export.',
            ok: true);
      }
    } catch (e) {
      _log.e('❌ [AdminSettingsScreen] Export failed', error: e);
      if (mounted) _snack('Export failed: $e', ok: false);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? const Color(0xFF0D7377) : _kRed,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: ok ? 3 : 6),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SystemSettingsModel>(
      stream: SystemSettingsService.stream(),
      builder: (context, snap) {
        if (!snap.hasData && !_loaded) return const AdminLoader();
        if (snap.hasData) _hydrate(snap.data!);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  title: 'Public Contact Info',
                  subtitle:
                      'Shown in the landing page footer and contact screens.',
                  child: Column(children: [
                    AdminField(
                        ctrl: _emailCtrl,
                        label: 'Contact Email',
                        hint: 'info@palmnaziresortcities.com',
                        keyboardType: TextInputType.emailAddress),
                    AdminField(
                        ctrl: _phoneCtrl,
                        label: 'Contact Phone',
                        hint: '+254722123456',
                        keyboardType: TextInputType.phone),
                  ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Footer Links',
                  subtitle: 'Extra links shown in the landing page footer.',
                  child: Column(children: [
                    ..._footerLinks.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Expanded(
                              child: AdminField(
                                  ctrl: e.value.labelCtrl,
                                  label: 'Label',
                                  hint: 'e.g. Terms of Service'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdminField(
                                  ctrl: e.value.urlCtrl,
                                  label: 'URL',
                                  hint: 'https://…'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: _kRed, size: 20),
                              onPressed: () => setState(() {
                                _footerLinks.removeAt(e.key).dispose();
                              }),
                            ),
                          ]),
                        )),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                            () => _footerLinks.add(_FooterLinkEditRow())),
                        icon: const Icon(Icons.add_rounded,
                            color: _kTeal, size: 18),
                        label: const Text('Add link',
                            style: TextStyle(color: _kTeal)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Maintenance Mode',
                  subtitle:
                      'When on, tourists see a maintenance notice instead of '
                      'the landing page. Admins can still sign in and manage '
                      'the platform as normal.',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _maintenanceMode,
                          onChanged: _toggleMaintenance,
                          activeThumbColor: _kOrange,
                          title: Text(
                              _maintenanceMode
                                  ? 'Maintenance mode is ON'
                                  : 'Maintenance mode is OFF',
                              style: TextStyle(
                                  color: _maintenanceMode
                                      ? _kOrange
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        const SizedBox(height: 6),
                        AdminField(
                            ctrl: _maintenanceMsgCtrl,
                            label: 'Maintenance Message',
                            hint:
                                "We'll be back shortly — thanks for your patience.",
                            maxLines: 2),
                      ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Data Export',
                  subtitle:
                      'Downloads every Firestore-backed collection (Users, '
                      'Favorites, Bookings, Admin Requests, Payment Methods, '
                      'Place details, Place Queries, City details, Category '
                      'details, Settings, Static Pages, Audit Log) as one '
                      'JSON file. Places, Cities, Categories and Bookings '
                      'configuration live in the backend database — a real '
                      'backup of that data needs DB-level tooling on the '
                      'hosting side, not this button.',
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : _exportData,
                      icon: _exporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _kTeal))
                          : const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                          _exporting ? 'Exporting…' : 'Export Firestore Data'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: BorderSide(color: _kTeal.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black38))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kTeal,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionCard(
          {required String title,
          required String subtitle,
          required Widget child}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12, height: 1.4)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

class _FooterLinkEditRow {
  final TextEditingController labelCtrl;
  final TextEditingController urlCtrl;

  _FooterLinkEditRow()
      : labelCtrl = TextEditingController(),
        urlCtrl = TextEditingController();

  _FooterLinkEditRow.from(FooterLink link)
      : labelCtrl = TextEditingController(text: link.label),
        urlCtrl = TextEditingController(text: link.url);

  void dispose() {
    labelCtrl.dispose();
    urlCtrl.dispose();
  }
}
