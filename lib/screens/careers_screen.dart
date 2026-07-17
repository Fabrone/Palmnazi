import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CareersScreen — reached from the landing page footer's "Careers" link.
//
// Honest, no fabricated job listings — we're not actively hiring, but we
// still want a real, working way for interested people to reach out.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color navy = Color(0xFF121F2E);
  static const Color deepBlue = Color(0xFF1C2E42);
  static const Color gold = Color(0xFFD4AF37);
  static const Color textSec = Color(0xFFC7D6E3);
}

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
          const SnackBar(content: Text('Could not open your email app.')),
        );
      }
    } catch (e, st) {
      developer.log('Failed to launch careers mailto',
          name: 'CareersScreen', error: e, stackTrace: st);
      if (context.mounted) {
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
        title: const Text('Careers', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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
                    color: _P.gold, size: 48),
                const SizedBox(height: 20),
                const Text("We're not actively hiring right now",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                  "But we're always excited to hear from people who care about "
                  'building a great travel platform. Drop us a note and tell us '
                  "what you'd love to work on — we keep every message on file "
                  'for when a role opens up.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: _P.textSec, fontSize: 15, height: 1.7),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () => _emailUs(context),
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: const Text(_email),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _P.gold,
                    foregroundColor: _P.navy,
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
