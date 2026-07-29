import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardSnapshotService
//
// Firestore collection : DashboardSnapshots
// Document ID          : 'yyyy-MM-dd' (one doc per calendar day)
//
// The /api dashboard-stats endpoint only ever returns *current* totals —
// there's no historical series to chart "growth over time" against. Rather
// than fabricate one, this records a real daily snapshot of those totals
// (idempotent per day — safe to call on every dashboard load) so a genuine
// trend builds up the longer the platform runs. Charts read this collection;
// they start sparse and fill in day by day rather than showing invented
// history.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardSnapshot {
  final DateTime day;
  final int citiesTotal;
  final int usersTotal;
  final int placesActive;
  final int placesPending;

  const DashboardSnapshot({
    required this.day,
    this.citiesTotal = 0,
    this.usersTotal = 0,
    this.placesActive = 0,
    this.placesPending = 0,
  });

  factory DashboardSnapshot.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DashboardSnapshot(
      day: DateTime.tryParse(doc.id) ?? DateTime.now(),
      citiesTotal: (d['citiesTotal'] as num?)?.toInt() ?? 0,
      usersTotal: (d['usersTotal'] as num?)?.toInt() ?? 0,
      placesActive: (d['placesActive'] as num?)?.toInt() ?? 0,
      placesPending: (d['placesPending'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardSnapshotService {
  DashboardSnapshotService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('DashboardSnapshots');

  static String _docIdFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fire-and-forget: merges today's totals into today's doc. Safe to call
  /// on every dashboard load — later calls the same day just overwrite the
  /// same numbers.
  static void recordToday(Map<String, dynamic> stats) {
    final id = _docIdFor(DateTime.now());
    _collection.doc(id).set({
      'citiesTotal': stats['cities_total'] ?? 0,
      'usersTotal': stats['users_total'] ?? 0,
      'placesActive': stats['places_active'] ?? 0,
      'placesPending': stats['places_pending'] ?? 0,
      'recordedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((_) {
      // Non-critical — a missed snapshot just leaves a gap in the chart.
    });
  }

  static Stream<List<DashboardSnapshot>> streamRecent({int days = 30}) {
    final sinceId = _docIdFor(DateTime.now().subtract(Duration(days: days)));
    return _collection
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: sinceId)
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DashboardSnapshot.fromFirestore(d)).toList());
  }
}
