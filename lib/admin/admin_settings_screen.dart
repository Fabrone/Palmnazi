import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/system_settings_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
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
    final systemSettingsTargetLabel =
        context.tr('admin_settings_audit_target_system_settings');
    final savedSuccessMsg = context.tr('admin_settings_saved_success');
    final saveFailedPrefix =
        context.tr('admin_settings_error_save_failed_prefix');
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
          action: 'update',
          module: 'Settings',
          targetLabel: systemSettingsTargetLabel);
      _log.i('✅ [AdminSettingsScreen] Settings saved');
      if (mounted) _snack(savedSuccessMsg, ok: true);
    } catch (e) {
      _log.e('❌ [AdminSettingsScreen] Save failed', error: e);
      if (mounted) _snack('$saveFailedPrefix $e', ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleMaintenance(bool next) async {
    final enabledLabel = context.tr('admin_settings_audit_enabled');
    final disabledLabel = context.tr('admin_settings_audit_disabled');
    final maintenanceEnabledMsg =
        context.tr('admin_settings_maintenance_enabled');
    final maintenanceDisabledMsg =
        context.tr('admin_settings_maintenance_disabled');
    final maintenanceUpdateFailedPrefix =
        context.tr('admin_settings_error_maintenance_update_failed_prefix');
    final maintenanceModeTargetLabel =
        context.tr('admin_settings_audit_target_maintenance_mode');
    if (next) {
      final confirm = await adminConfirm(
        context,
        context.tr('admin_settings_maintenance_confirm_title'),
        context.tr('admin_settings_maintenance_confirm_body'),
        confirmLabel: context.tr('admin_settings_btn_enable'),
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
          targetLabel: maintenanceModeTargetLabel,
          details: next ? enabledLabel : disabledLabel);
      if (mounted) {
        _snack(next ? maintenanceEnabledMsg : maintenanceDisabledMsg,
            ok: !next);
      }
    } catch (e) {
      setState(() => _maintenanceMode = !next); // revert on failure
      if (mounted) _snack('$maintenanceUpdateFailedPrefix $e', ok: false);
    }
  }

  Future<void> _exportData() async {
    final exportSuccessPrefix =
        context.tr('admin_settings_export_success_prefix');
    final exportSuccessSuffix =
        context.tr('admin_settings_export_success_suffix');
    final exportFailedPrefix =
        context.tr('admin_settings_error_export_failed_prefix');
    setState(() => _exporting = true);
    try {
      final count = await SystemSettingsService.exportFirestoreData();
      if (mounted) {
        _snack('$exportSuccessPrefix $count $exportSuccessSuffix', ok: true);
      }
    } catch (e) {
      _log.e('❌ [AdminSettingsScreen] Export failed', error: e);
      if (mounted) _snack('$exportFailedPrefix $e', ok: false);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? AdC.tealDark : AdC.red,
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
                  title: context.tr('admin_settings_section_contact_title'),
                  subtitle:
                      context.tr('admin_settings_section_contact_subtitle'),
                  child: Column(children: [
                    AdminField(
                        ctrl: _emailCtrl,
                        label: context.tr('admin_settings_field_contact_email'),
                        hint: 'info@palmnaziresortcities.com',
                        keyboardType: TextInputType.emailAddress),
                    AdminField(
                        ctrl: _phoneCtrl,
                        label: context.tr('admin_settings_field_contact_phone'),
                        hint: '+254722123456',
                        keyboardType: TextInputType.phone),
                  ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title:
                      context.tr('admin_settings_section_footer_links_title'),
                  subtitle: context
                      .tr('admin_settings_section_footer_links_subtitle'),
                  child: Column(children: [
                    ..._footerLinks.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Expanded(
                              child: AdminField(
                                  ctrl: e.value.labelCtrl,
                                  label: context
                                      .tr('admin_settings_field_link_label'),
                                  hint: context
                                      .tr('admin_settings_hint_link_label')),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdminField(
                                  ctrl: e.value.urlCtrl,
                                  label: context
                                      .tr('admin_settings_field_link_url'),
                                  hint: 'https://…'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AdC.red, size: 20),
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
                            color: AdC.teal, size: 18),
                        label: Text(context.tr('admin_settings_add_link'),
                            style: const TextStyle(color: AdC.teal)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: context.tr('admin_settings_section_maintenance_title'),
                  subtitle:
                      context.tr('admin_settings_section_maintenance_subtitle'),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _maintenanceMode,
                          onChanged: _toggleMaintenance,
                          activeThumbColor: AdC.orange,
                          title: Text(
                              _maintenanceMode
                                  ? context.tr('admin_settings_maintenance_on')
                                  : context
                                      .tr('admin_settings_maintenance_off'),
                              style: TextStyle(
                                  color: _maintenanceMode
                                      ? AdC.orange
                                      : AdC.textPri,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        const SizedBox(height: 6),
                        AdminField(
                            ctrl: _maintenanceMsgCtrl,
                            label: context
                                .tr('admin_settings_field_maintenance_message'),
                            hint: context
                                .tr('admin_settings_hint_maintenance_message'),
                            maxLines: 2),
                      ]),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: context.tr('admin_settings_section_export_title'),
                  subtitle:
                      context.tr('admin_settings_section_export_subtitle'),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : _exportData,
                      icon: _exporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AdC.teal))
                          : const Icon(Icons.download_rounded, size: 16),
                      label: Text(_exporting
                          ? context.tr('admin_settings_exporting')
                          : context.tr('admin_settings_export_button')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdC.teal,
                        side:
                            BorderSide(color: AdC.teal.withValues(alpha: 0.5)),
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
                    label: Text(_saving
                        ? context.tr('admin_settings_saving')
                        : context.tr('admin_settings_save_button')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdC.teal,
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
          color: AdC.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AdC.overlay(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: AdC.textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style:
                    TextStyle(color: AdC.textMute, fontSize: 12, height: 1.4)),
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
