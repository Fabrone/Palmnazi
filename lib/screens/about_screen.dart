import 'package:flutter/material.dart';
import 'package:palmnazi/models/static_page_model.dart';
import 'package:palmnazi/services/static_page_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AboutScreen — reached from the landing page footer's "About Us" link.
//
// Streams admin-edited copy from StaticPageService (slug: 'about') and falls
// back to the hardcoded defaults below until an admin has edited the page —
// see admin_static_pages_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color navy = Color(0xFF121F2E);
  static const Color deepBlue = Color(0xFF1C2E42);
  static const Color gold = Color(0xFFD4AF37);
  static const Color textSec = Color(0xFFC7D6E3);
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _fallbackTagline = 'For Every Trip, Every Traveller';
  static const _fallbackParagraphs = [
    "Palmnazi Resort Cities brings every part of planning a trip across Africa's "
        "finest destinations into one place — whether you're booking a leisure "
        "escape, organizing a team retreat, or arranging a business meeting venue.",
    "We work directly with resort cities and the hotels, dining spots, "
        "experiences, and event venues within them, so every listing you see is "
        "verified and bookable through the same platform — no juggling separate "
        "sites for accommodation, meetings, and activities.",
    "Our goal is simple: make it effortless to find the right place for any "
        "trip, for any kind of traveller.",
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StaticPageModel?>(
      stream: StaticPageService.stream('about'),
      builder: (context, snap) {
        final page = snap.data;
        final tagline = (page != null && page.subtitle.isNotEmpty)
            ? page.subtitle
            : _fallbackTagline;
        final paragraphs = (page != null && page.sections.isNotEmpty)
            ? page.sections.map((s) => s.body).toList()
            : _fallbackParagraphs;
        return _buildScaffold(context, tagline, paragraphs);
      },
    );
  }

  Widget _buildScaffold(
      BuildContext context, String tagline, List<String> paragraphs) {
    return Scaffold(
      backgroundColor: _P.navy,
      appBar: AppBar(
        backgroundColor: _P.deepBlue,
        title: const Text('About Us', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient:
                          LinearGradient(colors: [_P.gold, Color(0xFFC49A2C)]),
                    ),
                    child: const Icon(Icons.travel_explore_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('PALMNAZI RC',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5)),
                ]),
                const SizedBox(height: 28),
                Text(tagline,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ...paragraphs.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(p,
                          style: const TextStyle(
                              color: _P.textSec, fontSize: 15, height: 1.7)),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
