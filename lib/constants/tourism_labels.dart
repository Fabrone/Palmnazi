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
  static const String categorySingular = 'Experience Type';
  static const String categoryPlural = 'Experience Types';

  static const String placeSingular = 'Attraction';
  static const String placePlural = 'Attractions';
}
