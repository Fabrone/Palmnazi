import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:palmnazi/models/system_settings_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SystemSettingsService
//
// Reads/writes the single SystemSettings/main doc, plus a best-effort export
// of every Firestore collection this app owns (see [exportFirestoreData]).
//
// NOTE on "backup and restore": this export covers only the Firestore side
// of the platform's data. Places/Cities/Categories/Bookings-config live in
// the backend's own Postgres database (the frozen /api contract) — a real
// backup of that data requires DB-level tooling (pg_dump / hosting-provider
// snapshots) or a backend export endpoint, neither of which a Flutter admin
// client can perform. Restore is intentionally not offered here — writing an
// arbitrary JSON blob back into Firestore without server-side validation is
// a real way to corrupt live data, and doing it safely needs a reviewed
// Cloud Function, not a client-side button.
// ─────────────────────────────────────────────────────────────────────────────

class SystemSettingsService {
  SystemSettingsService._();

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('SystemSettings').doc('main');

  static Stream<SystemSettingsModel> stream() =>
      _doc.snapshots().map((snap) => snap.exists
          ? SystemSettingsModel.fromFirestore(snap)
          : SystemSettingsModel.empty);

  static Future<SystemSettingsModel> get() async {
    final snap = await _doc.get();
    return snap.exists
        ? SystemSettingsModel.fromFirestore(snap)
        : SystemSettingsModel.empty;
  }

  static Future<void> save(SystemSettingsModel settings) {
    final me = FirebaseAuth.instance.currentUser;
    return _doc.set({
      ...settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': me?.email ?? '',
    }, SetOptions(merge: true));
  }

  static Future<void> setMaintenanceMode(bool enabled, {String? message}) {
    final me = FirebaseAuth.instance.currentUser;
    return _doc.set({
      'maintenanceMode': enabled,
      if (message != null) 'maintenanceMessage': message,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': me?.email ?? '',
    }, SetOptions(merge: true));
  }

  // ── Firestore-only data export ──────────────────────────────────────────
  static const List<String> _exportableCollections = [
    'Users',
    'Favorites',
    'ContactMessages',
    'Bookings',
    'AdminRequests',
    'PaymentMethods',
    'Place_details',
    'PlaceQueries',
    'City_details',
    'CategoryDetails',
    'SystemSettings',
    'StaticPages',
    'AuditLog',
  ];

  /// Pulls every document from every collection this app writes to and
  /// prompts a save/download of the result as one timestamped JSON file.
  /// Returns the number of documents exported, or throws on failure.
  static Future<int> exportFirestoreData() async {
    final out = <String, List<Map<String, dynamic>>>{};
    int total = 0;

    for (final name in _exportableCollections) {
      final snap = await FirebaseFirestore.instance.collection(name).get();
      out[name] =
          snap.docs.map((d) => {'id': d.id, ..._jsonSafe(d.data())}).toList();
      total += snap.docs.length;
    }

    final payload = jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'collections': out,
    });

    final fileName =
        'palmnazi-firestore-export-${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
    await FilePicker.saveFile(
      fileName: fileName,
      bytes: utf8.encode(payload),
    );

    return total;
  }

  /// Firestore Timestamp/DocumentReference/GeoPoint aren't directly
  /// JSON-encodable — convert them to plain strings so jsonEncode doesn't
  /// throw partway through a large export.
  static Map<String, dynamic> _jsonSafe(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, _jsonSafeValue(v)));
  }

  static dynamic _jsonSafeValue(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DocumentReference) return v.path;
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is Map) {
      return v.map((k, vv) => MapEntry(k.toString(), _jsonSafeValue(vv)));
    }
    if (v is List) return v.map(_jsonSafeValue).toList();
    return v;
  }
}
