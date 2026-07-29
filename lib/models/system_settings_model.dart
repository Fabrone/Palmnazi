import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SystemSettingsModel
//
// Firestore collection : SystemSettings
// Document ID          : 'main' (single global settings doc)
//
// General platform preferences that aren't part of the /api contract:
// public contact info, footer links, and a maintenance-mode switch the
// landing page checks on load. Lives in Firestore for the same reason
// CityDetailsModel does — the backend REST contract is frozen.
// ─────────────────────────────────────────────────────────────────────────────

class FooterLink {
  final String label;
  final String url;

  const FooterLink({required this.label, required this.url});

  factory FooterLink.fromMap(Map<String, dynamic> m) => FooterLink(
        label: m['label'] as String? ?? '',
        url: m['url'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {'label': label, 'url': url};
}

class SystemSettingsModel {
  final String contactEmail;
  final String contactPhone;
  final List<FooterLink> footerLinks;
  final bool maintenanceMode;
  final String maintenanceMessage;
  final DateTime? updatedAt;
  final String? updatedByEmail;

  const SystemSettingsModel({
    this.contactEmail = '',
    this.contactPhone = '',
    this.footerLinks = const [],
    this.maintenanceMode = false,
    this.maintenanceMessage = '',
    this.updatedAt,
    this.updatedByEmail,
  });

  static const empty = SystemSettingsModel();

  factory SystemSettingsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SystemSettingsModel(
      contactEmail: d['contactEmail'] as String? ?? '',
      contactPhone: d['contactPhone'] as String? ?? '',
      footerLinks: (d['footerLinks'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(FooterLink.fromMap)
              .toList() ??
          const [],
      maintenanceMode: d['maintenanceMode'] as bool? ?? false,
      maintenanceMessage: d['maintenanceMessage'] as String? ?? '',
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      updatedByEmail: d['updatedByEmail'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'contactEmail': contactEmail,
        'contactPhone': contactPhone,
        'footerLinks': footerLinks.map((f) => f.toMap()).toList(),
        'maintenanceMode': maintenanceMode,
        'maintenanceMessage': maintenanceMessage,
      };
}
