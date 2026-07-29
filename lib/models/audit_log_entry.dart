import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuditLogEntry
//
// Firestore collection : AuditLog
// Document ID          : auto-generated
//
// Append-only record of admin actions — who did what, to what, and when.
// Written by AuditLogService.log(...) from the admin screens that mutate
// data (places, cities, categories, roles, blog, static pages, settings).
// ─────────────────────────────────────────────────────────────────────────────

class AuditLogEntry {
  final String id;
  final DateTime? timestamp;
  final String adminUid;
  final String adminEmail;
  final String action; // e.g. 'create' | 'update' | 'delete' | 'role_grant'
  final String module; // e.g. 'Place' | 'City' | 'Category' | 'Role' | 'Blog'
  final String targetId;
  final String targetLabel; // human-readable name for display
  final String details;

  const AuditLogEntry({
    required this.id,
    this.timestamp,
    required this.adminUid,
    required this.adminEmail,
    required this.action,
    required this.module,
    this.targetId = '',
    this.targetLabel = '',
    this.details = '',
  });

  factory AuditLogEntry.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AuditLogEntry(
      id: doc.id,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      adminUid: d['adminUid'] as String? ?? '',
      adminEmail: d['adminEmail'] as String? ?? '',
      action: d['action'] as String? ?? '',
      module: d['module'] as String? ?? '',
      targetId: d['targetId'] as String? ?? '',
      targetLabel: d['targetLabel'] as String? ?? '',
      details: d['details'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'adminUid': adminUid,
        'adminEmail': adminEmail,
        'action': action,
        'module': module,
        'targetId': targetId,
        'targetLabel': targetLabel,
        'details': details,
      };
}
