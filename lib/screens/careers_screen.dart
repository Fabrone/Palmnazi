import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:palmnazi/screens/landing_page.dart' show RC;
import 'package:palmnazi/services/app_strings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CareersScreen — reached from the landing page footer's "Careers" link.
//
// Honest, no fabricated job listings — we're not actively hiring, but we
// still want a real, working way for interested people to reach out.
// ─────────────────────────────────────────────────────────────────────────────

class CareersScreen extends StatelessWidget {
  const CareersScreen({super.key});

  static const _email = 'careers@palmnazi.com';

  Future<void> _emailUs(BuildContext context) async {
    final uri = Uri(
        scheme: 'mailto',
        path: _email,
        query: 'subject=Interested in joining Palmnazi');
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('contact_error_email_app'))),
        );
      }
    } catch (e, st) {
      developer.log('Failed to launch careers mailto',
          name: 'CareersScreen', error: e, stackTrace: st);
      if (context.mounted) {
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
        title: Text(context.tr('careers_page_title'),
            style: TextStyle(color: RC.textPri)),
        iconTheme: IconThemeData(color: RC.textPri),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.work_outline_rounded,
                    color: RC.gold, size: 48),
                const SizedBox(height: 20),
                Text(context.tr('careers_not_hiring_heading'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: RC.textPri,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  context.tr('careers_not_hiring_body'),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: RC.textSec, fontSize: 15, height: 1.7),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () => _emailUs(context),
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: const Text(_email),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RC.gold,
                    foregroundColor: RC.navy,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
