// ─────────────────────────────────────────────────────────────────────────────
// TourismLabels
//
// Tourist-facing vocabulary for the "Category" and "Place" concepts. The
// underlying Dart classes (CategoryModel, PlaceModel), file names, Firestore
// fields, and REST API params are unchanged — this only governs what a
// tourist reads on screen, so it's the single place to adjust if the wording
// changes again later.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class TourismLabels {
  static const String categorySingular = 'Service';
  static const String categoryPlural = 'Services';

  static const String placeSingular = 'Listing';
  static const String placePlural = 'Listings';
}
