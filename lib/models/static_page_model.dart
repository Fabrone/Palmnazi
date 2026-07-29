import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaticPageModel
//
// Firestore collection : StaticPages
// Document ID          : a fixed slug ('about', 'privacy-policy',
//                         'terms-of-service', 'cookie-policy')
//
// Admin-editable content for the platform's static pages. Each screen that
// renders one of these (about_screen.dart, static_info_screen.dart via
// StaticPageScreen) falls back to hardcoded default copy when no Firestore
// doc exists yet, so the page is never blank pre-migration.
// ─────────────────────────────────────────────────────────────────────────────

class StaticPageSection {
  final String heading;
  final String body;

  const StaticPageSection({this.heading = '', required this.body});

  factory StaticPageSection.fromMap(Map<String, dynamic> m) =>
      StaticPageSection(
        heading: m['heading'] as String? ?? '',
        body: m['body'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {'heading': heading, 'body': body};
}

class StaticPageModel {
  final String slug;
  final String title;
  final String subtitle;
  final String lastUpdatedLabel;
  final List<StaticPageSection> sections;
  final DateTime? updatedAt;
  final String? updatedByEmail;

  const StaticPageModel({
    required this.slug,
    required this.title,
    this.subtitle = '',
    this.lastUpdatedLabel = '',
    this.sections = const [],
    this.updatedAt,
    this.updatedByEmail,
  });

  factory StaticPageModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StaticPageModel(
      slug: doc.id,
      title: d['title'] as String? ?? '',
      subtitle: d['subtitle'] as String? ?? '',
      lastUpdatedLabel: d['lastUpdatedLabel'] as String? ?? '',
      sections: (d['sections'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(StaticPageSection.fromMap)
              .toList() ??
          const [],
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      updatedByEmail: d['updatedByEmail'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'lastUpdatedLabel': lastUpdatedLabel,
        'sections': sections.map((s) => s.toMap()).toList(),
      };
}
