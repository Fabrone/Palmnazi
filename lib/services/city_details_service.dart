import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/city_details_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CityDetailsService
//
// Reads/writes the City_details collection — see CityDetailsModel for the
// shape and why this lives outside the /api/cities contract.
// ─────────────────────────────────────────────────────────────────────────────

class CityDetailsService {
  CityDetailsService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('City_details');

  /// One-shot fetch of all City_details docs, keyed by cityId. Cities with no
  /// doc yet simply aren't present in the map (callers should treat a
  /// missing entry as CityDetailsModel.empty).
  static Future<Map<String, CityDetailsModel>> getAll() async {
    final snap = await _collection.get();
    return {
      for (final doc in snap.docs) doc.id: CityDetailsModel.fromFirestore(doc),
    };
  }

  static Future<void> setFeatured(String cityId, bool featured) {
    return _collection.doc(cityId).set(
      {'featured': featured, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  static Future<void> setSortOrder(String cityId, int sortOrder) {
    return _collection.doc(cityId).set(
      {'sortOrder': sortOrder, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Sorts [cities] by featured (first), then sortOrder (ascending), then
  /// name — the convention used by both the admin Resort Cities list and the
  /// tourist-facing landing page.
  static List<T> sortByDetails<T>(
    List<T> cities,
    Map<String, CityDetailsModel> details,
    String Function(T) idOf,
    String Function(T) nameOf,
  ) {
    final sorted = List<T>.from(cities);
    sorted.sort((a, b) {
      final da = details[idOf(a)] ?? CityDetailsModel.empty;
      final db = details[idOf(b)] ?? CityDetailsModel.empty;
      if (da.featured != db.featured) return da.featured ? -1 : 1;
      if (da.sortOrder != db.sortOrder) {
        return da.sortOrder.compareTo(db.sortOrder);
      }
      return nameOf(a).compareTo(nameOf(b));
    });
    return sorted;
  }
}
