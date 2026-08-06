import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:palmnazi/models/contact_message_model.dart';
import 'package:palmnazi/models/system_settings_model.dart';
import 'package:palmnazi/screens/landing_page.dart' show RC;
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/contact_message_service.dart';
import 'package:palmnazi/services/system_settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactScreen — reached from the landing page footer's "Contact Us" link.
//
// A real working form: submits to Firestore's ContactMessages collection
// (public create, mirrors the PlaceQueries create pattern) — no sign-in
// required, since a footer contact link has to work for a visitor who isn't
// logged in. Also offers a direct mailto: quick-action as a fallback.
// ─────────────────────────────────────────────────────────────────────────────

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  static const _fallbackSupportEmail = 'support@palmnazi.com';

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  // ── Admin-configurable contact info (Settings screen) — falls back to the
  // hardcoded defaults until an admin sets it. ────────────────────────────
  String _supportEmail = _fallbackSupportEmail;
  String _supportPhone = '';
  StreamSubscription<SystemSettingsModel>? _settingsSub;

  @override
  void initState() {
    super.initState();
    _settingsSub = SystemSettingsService.stream().listen((s) {
      if (!mounted) return;
      setState(() {
        _supportEmail =
            s.contactEmail.isNotEmpty ? s.contactEmail : _fallbackSupportEmail;
        _supportPhone = s.contactPhone;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await ContactMessageService.submit(ContactMessageModel(
        id: '',
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
      ));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e, st) {
      developer.log('Failed to submit contact message',
          name: 'ContactScreen', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('contact_error_send_failed'))),
      );
    }
  }

  Future<void> _emailDirectly() async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('contact_error_email_app'))),
        );
      }
    } catch (e, st) {
      developer.log('Failed to launch contact mailto',
          name: 'ContactScreen', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('contact_error_email_app'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RC.navy,
      appBar: AppBar(
        backgroundColor: RC.deepBlue,
        title: Text(context.tr('contact_page_title'),
            style: TextStyle(color: RC.textPri)),
        iconTheme: IconThemeData(color: RC.textPri),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _submitted ? _buildSuccess(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: RC.gold, size: 56),
        const SizedBox(height: 20),
        Text(context.tr('contact_success_title'),
            style: TextStyle(
                color: RC.textPri, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          context.tr('contact_success_body'),
          textAlign: TextAlign.center,
          style: TextStyle(color: RC.textSec, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: RC.gold,
            side: const BorderSide(color: RC.gold),
          ),
          child: Text(context.tr('contact_back_button')),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('contact_hero_heading'),
              style: TextStyle(
                  color: RC.textPri,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            context.tr('contact_hero_body'),
            style: TextStyle(color: RC.textSec, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 24),
          _field(
              _nameCtrl, context.tr('contact_field_name'), TextInputType.name,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('contact_error_name_required')
                  : null),
          const SizedBox(height: 14),
          _field(_emailCtrl, context.tr('contact_field_email'),
              TextInputType.emailAddress, validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) {
              return context.tr('contact_error_email_required');
            }
            if (!value.contains('@') || !value.contains('.')) {
              return context.tr('contact_error_email_invalid');
            }
            return null;
          }),
          const SizedBox(height: 14),
          _field(_messageCtrl, context.tr('contact_field_message'),
              TextInputType.multiline,
              maxLines: 5,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('contact_error_message_required')
                  : null),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: RC.gold,
                foregroundColor: RC.navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: RC.navy, strokeWidth: 2),
                    )
                  : Text(context.tr('contact_send_button'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _emailDirectly,
              icon: Icon(Icons.email_outlined, color: RC.textMute, size: 16),
              label: Text(
                  '${context.tr('contact_email_directly_prefix')} $_supportEmail',
                  style: TextStyle(color: RC.textMute, fontSize: 13)),
            ),
          ),
          if (_supportPhone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_outlined, color: RC.textMute, size: 14),
                  const SizedBox(width: 6),
                  Text(_supportPhone,
                      style: TextStyle(color: RC.textMute, fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    TextInputType type, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: RC.textPri),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: RC.textMute),
        filled: true,
        fillColor: RC.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}
