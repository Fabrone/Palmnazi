import 'package:flutter/material.dart';
import 'package:palmnazi/models/static_page_model.dart';
import 'package:palmnazi/services/static_page_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaticInfoScreen
//
// Reusable title + heading/body sections screen — backs the footer's Legal
// column (Privacy Policy, Terms of Service, Cookie Policy) on
// landing_page.dart. Visual language mirrors the landing page's refreshed
// gold-forward navy palette without importing landing_page.dart directly
// (each screen keeps its own small palette, matching the convention already
// used across resort_city_screen.dart / category_screen.dart / etc).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color navy = Color(0xFF121F2E);
  static const Color deepBlue = Color(0xFF1C2E42);
  static const Color gold = Color(0xFFD4AF37);
  static const Color textSec = Color(0xFFC7D6E3);
  static const Color textMute = Color(0xFF7C93A8);
}

class StaticInfoSection {
  final String heading;
  final String body;
  const StaticInfoSection({required this.heading, required this.body});
}

class StaticInfoScreen extends StatelessWidget {
  final String title;
  final String? lastUpdated;
  final List<StaticInfoSection> sections;

  const StaticInfoScreen({
    super.key,
    required this.title,
    required this.sections,
    this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.navy,
      appBar: AppBar(
        backgroundColor: _P.deepBlue,
        title: Text(title, style: const TextStyle(color: Colors.white)),
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                if (lastUpdated != null) ...[
                  const SizedBox(height: 8),
                  Text('Last updated: $lastUpdated',
                      style: const TextStyle(color: _P.textMute, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                ...sections.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s.heading.isNotEmpty) ...[
                            Text(s.heading,
                                style: const TextStyle(
                                    color: _P.gold,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                          ],
                          Text(s.body,
                              style: const TextStyle(
                                  color: _P.textSec,
                                  fontSize: 14,
                                  height: 1.7)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StaticPageScreen
//
// Live wrapper around [StaticInfoScreen] — streams admin-edited content from
// StaticPageService/StaticPageModel (see admin_static_pages_screen.dart) and
// falls back to the given hardcoded copy until an admin has edited the page,
// so nothing goes blank pre-migration.
// ─────────────────────────────────────────────────────────────────────────────
class StaticPageScreen extends StatelessWidget {
  final String slug;
  final String fallbackTitle;
  final String? fallbackLastUpdated;
  final List<StaticInfoSection> fallbackSections;

  const StaticPageScreen({
    super.key,
    required this.slug,
    required this.fallbackTitle,
    required this.fallbackSections,
    this.fallbackLastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StaticPageModel?>(
      stream: StaticPageService.stream(slug),
      builder: (context, snap) {
        final page = snap.data;
        if (page == null || page.sections.isEmpty) {
          return StaticInfoScreen(
            title: fallbackTitle,
            lastUpdated: fallbackLastUpdated,
            sections: fallbackSections,
          );
        }
        return StaticInfoScreen(
          title: page.title.isNotEmpty ? page.title : fallbackTitle,
          lastUpdated: page.lastUpdatedLabel.isNotEmpty
              ? page.lastUpdatedLabel
              : fallbackLastUpdated,
          sections: page.sections
              .map((s) => StaticInfoSection(heading: s.heading, body: s.body))
              .toList(),
        );
      },
    );
  }
}
