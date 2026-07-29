import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:palmnazi/models/contact_message_model.dart';
import 'package:palmnazi/models/system_settings_model.dart';
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

abstract final class _P {
  static const Color navy = Color(0xFF121F2E);
  static const Color deepBlue = Color(0xFF1C2E42);
  static const Color surface = Color(0xFF23374D);
  static const Color gold = Color(0xFFD4AF37);
  static const Color textSec = Color(0xFFC7D6E3);
  static const Color textMute = Color(0xFF7C93A8);
}

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
        const SnackBar(
            content: Text('Could not send your message. Please try again.')),
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
          const SnackBar(content: Text('Could not open your email app.')),
        );
      }
    } catch (e, st) {
      developer.log('Failed to launch contact mailto',
          name: 'ContactScreen', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open your email app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.navy,
      appBar: AppBar(
        backgroundColor: _P.deepBlue,
        title: const Text('Contact Us', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _submitted ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: _P.gold, size: 56),
        const SizedBox(height: 20),
        const Text('Message sent',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          "Thanks for reaching out — we'll get back to you as soon as we can.",
          textAlign: TextAlign.center,
          style: TextStyle(color: _P.textSec, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _P.gold,
            side: const BorderSide(color: _P.gold),
          ),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Get in Touch',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            "Questions about a booking, a place you'd like to see added, or "
            "just feedback — send us a message and we'll reply by email.",
            style: TextStyle(color: _P.textSec, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 24),
          _field(_nameCtrl, 'Your Name', TextInputType.name,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Your Email', TextInputType.emailAddress,
              validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return 'Enter your email';
            if (!value.contains('@') || !value.contains('.')) {
              return 'Enter a valid email';
            }
            return null;
          }),
          const SizedBox(height: 14),
          _field(_messageCtrl, 'Message', TextInputType.multiline,
              maxLines: 5,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a message' : null),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _P.gold,
                foregroundColor: _P.navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: _P.navy, strokeWidth: 2),
                    )
                  : const Text('Send Message',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _emailDirectly,
              icon: const Icon(Icons.email_outlined,
                  color: _P.textMute, size: 16),
              label: Text('Or email us directly at $_supportEmail',
                  style: const TextStyle(color: _P.textMute, fontSize: 13)),
            ),
          ),
          if (_supportPhone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_outlined,
                      color: _P.textMute, size: 14),
                  const SizedBox(width: 6),
                  Text(_supportPhone,
                      style: const TextStyle(color: _P.textMute, fontSize: 13)),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _P.textMute),
        filled: true,
        fillColor: _P.surface,
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
