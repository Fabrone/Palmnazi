import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/audit_log_entry.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuditLogService
//
// Append-only writer + reader for the AuditLog collection. [log] is fire-
// and-forget by design: a logging failure must never block the admin action
// it's recording (e.g. a place edit still succeeds even if the audit write
// fails), so callers don't need to await or handle its errors.
// ─────────────────────────────────────────────────────────────────────────────

class AuditLogService {
  AuditLogService._();

  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('AuditLog');

  /// Fire-and-forget: records an admin action. Never throws to the caller.
  static void log({
    required String action,
    required String module,
    String targetId = '',
    String targetLabel = '',
    String details = '',
  }) {
    final me = FirebaseAuth.instance.currentUser;
    _collection.add({
      'adminUid': me?.uid ?? '',
      'adminEmail': me?.email ?? 'unknown',
      'action': action,
      'module': module,
      'targetId': targetId,
      'targetLabel': targetLabel,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    }).catchError((Object e) {
      _log.w('⚠️ AuditLogService.log: write failed (non-blocking): $e');
      return _collection.doc(); // dummy DocumentReference to satisfy the type
    });
  }

  static Stream<List<AuditLogEntry>> streamRecent({int limit = 200}) {
    return _collection
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AuditLogEntry.fromFirestore(d)).toList());
  }
}
