// ─────────────────────────────────────────────────────────────────────────────
// lib/config/maps_config.dart
//
// Google Maps / Places API key configuration.
//
// The key is stored here as a plain static constant so that all team members
// and testers can build and run the app without any extra --dart-define flags
// or launch-configuration changes.
//
// ── UPDATING THE KEY ─────────────────────────────────────────────────────────
// Replace the value of [placesApiKey] below with the real key from Google
// Cloud Console.  Commit the change once and every developer/tester picks it
// up automatically on the next `flutter pub get` / hot-restart.
//
// ── GOOGLE CLOUD CONSOLE SETUP (required) ────────────────────────────────────
// 1. Visit https://console.cloud.google.com/
// 2. Enable BOTH "Places API" and "Geocoding API" under
//    APIs & Services › Library — the wizard's Step 3 map picker calls both
//    (Places Text Search for the name search box, Geocoding for converting a
//    dropped/dragged pin back into a readable address). A key missing either
//    one will fail silently on just that feature.
// 3. Create or select an API key under APIs & Services › Credentials.
//    NOTE: this is a *separate* key from the one in index.html /
//    AndroidManifest.xml (com.google.android.geo.API_KEY). That key only
//    renders the visual map tiles via the Maps JavaScript / Android SDK —
//    it is unrelated to the REST calls this file's key authenticates.
// 4. Restrict the key:
//      • Android apps → add your package name + SHA-1 fingerprint
//      • iOS apps     → add your bundle ID
//      • HTTP referrers (Web) → add your domain
//    These REST calls are made client-side from both web and mobile, so a
//    single "Application restrictions: None" with "API restrictions"
//    locked to just Places API + Geocoding API is usually the simplest
//    setup that still works across platforms.
// 5. Quota: set a daily cap on Places Text Search + Geocoding calls
//    under APIs & Services › Quotas to prevent runaway billing.
//
// ── SECURITY NOTE ────────────────────────────────────────────────────────────
// Embedding the key in source is acceptable for admin/internal tools where the
// build artefact is not distributed publicly.  If this app is ever published
// to a public store, restrict the key tightly in Cloud Console (package name +
// SHA-1 for Android, bundle ID for iOS) so it cannot be misused even if
// extracted from the binary.
//
// ── KENYA DATA COVERAGE NOTE ─────────────────────────────────────────────────
// The Places API covers Kenyan cities, towns, hotels, restaurants, parks,
// beaches, and businesses well.  For very remote rural areas the coverage may
// be limited — the manual lat/lng fallback fields in Step 3 handle this case.
// ─────────────────────────────────────────────────────────────────────────────

class MapsConfig {
  MapsConfig._(); // non-instantiable

  /// Google Places / Geocoding REST API key.
  ///
  /// REPLACE THE PLACEHOLDER BELOW with your full, un-truncated
  /// "Geocoding API Key" from Google Cloud Console. This used to share the
  /// same key as the Maps JavaScript/Android SDK widget (the one in
  /// index.html / AndroidManifest.xml) — they're now split so the REST
  /// search/geocode features and the visual map can be configured (and
  /// fail) independently of each other.
  ///
  /// All other files in this project reference this constant via
  /// [MapsConfig.placesApiKey] — no other file needs to change.
  ///
  /// When this string is empty the wizard silently hides the "Find Place on
  /// Google Maps" search section and falls back to manual coordinate entry.
  static const String placesApiKey = 'AIzaSyB804z77EETT5nMaEIJpJZeNedH9q8CqPc';

  /// True when a real API key is present and Places search is enabled.
  /// Guards against the placeholder above being left unswapped, so a
  /// forgotten key fails safely into the manual-entry fallback instead of
  /// firing requests Google will reject anyway.
  static bool get hasPlacesKey =>
      placesApiKey.isNotEmpty && !placesApiKey.startsWith('PALMNAZI_');
}