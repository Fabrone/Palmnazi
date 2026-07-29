import 'package:firebase_analytics/firebase_analytics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalyticsService
//
// Thin wrapper over FirebaseAnalytics — sends screen-view / event data to
// Google Analytics (GA4). This is the "integrated with Google Analytics"
// half of the contract's reporting ask.
//
// NOTE: GA4 data is NOT readable back from a Flutter client SDK — it flows
// into the Firebase/GA4 console and (optionally) BigQuery, not into any
// Firestore collection this app can query. For in-app "downloadable
// reports" (numbers an admin can see on the Reports screen), see
// PageViewService instead, which keeps its own lightweight Firestore
// counter this app fully owns and can read back.
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static Future<void> logScreenView(String screenName) =>
      _analytics.logScreenView(screenName: screenName).catchError((_) {});

  static Future<void> logEvent(String name, {Map<String, Object>? params}) =>
      _analytics.logEvent(name: name, parameters: params).catchError((_) {});
}
