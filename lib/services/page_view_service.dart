import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PageViewService
//
// Firestore collection : PageViews
// Document ID          : 'yyyy-MM-dd' (one doc per calendar day)
//
// A lightweight, self-owned visitor counter — increments a daily doc on
// every landing page load. Exists because GA4 data (see AnalyticsService)
// isn't readable back from a Flutter client, so this is what actually
// powers the "visitor statistics" numbers shown on AdminReportsScreen.
// ─────────────────────────────────────────────────────────────────────────────

class DailyPageViews {
  final DateTime day;
  final int count;
  const DailyPageViews({required this.day, required this.count});
}

class PageViewService {
  PageViewService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('PageViews');

  static String _docIdFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fire-and-forget: increments today's visit counter by one.
  static void recordVisit() {
    final id = _docIdFor(DateTime.now());
    _collection.doc(id).set({
      'count': FieldValue.increment(1),
    }, SetOptions(merge: true)).catchError((_) {});
  }

  static Stream<List<DailyPageViews>> streamRecent({int days = 30}) {
    final sinceId = _docIdFor(DateTime.now().subtract(Duration(days: days)));
    return _collection
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: sinceId)
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DailyPageViews(
                  day: DateTime.tryParse(d.id) ?? DateTime.now(),
                  count: (d.data()['count'] as num?)?.toInt() ?? 0,
                ))
            .toList());
  }
}
