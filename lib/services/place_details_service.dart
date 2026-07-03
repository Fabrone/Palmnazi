import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceDetailsService
//
// Stores supplementary place data that is not yet part of the backend API
// contract — currently: images attached to nested items (rooms, menu items,
// shows) created in the AdminPlaceWizardScreen.
//
// Collection: Place_details
// Document id: the place's API id (one doc per place).
// Shape:
// {
//   placeId:        "p123",
//   rooms:           [ { name, images: [url, ...] }, ... ],
//   menuItems:       [ { name, images: [url, ...] }, ... ],
//   shows:           [ { name, images: [url, ...] }, ... ],
//   exhibitions:     [ { name, images: [url, ...] }, ... ],
//   artifacts:       [ { name, images: [url, ...] }, ... ],
//   paymentMethods:  [ "methodId", ... ]  (doc ids into PaymentMethods),
//   updatedAt: <server timestamp>
// }
//
// This is intentionally separate from the /api/places REST contract: the
// backend redesign that will absorb this data has not happened yet, so these
// extra fields live in Firestore only.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceDetailsService {
  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('Place_details');

  /// Merges nested-item image data for [placeId]. Only the passed-in sections
  /// (rooms / menuItems / shows) are overwritten — omitted sections are left
  /// untouched in the existing document.
  static Future<void> saveNestedItemImages(
    String placeId, {
    List<Map<String, dynamic>>? rooms,
    List<Map<String, dynamic>>? menuItems,
    List<Map<String, dynamic>>? shows,
    List<Map<String, dynamic>>? exhibitions,
    List<Map<String, dynamic>>? artifacts,
  }) async {
    final data = <String, dynamic>{
      'placeId': placeId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (rooms != null) data['rooms'] = rooms;
    if (menuItems != null) data['menuItems'] = menuItems;
    if (shows != null) data['shows'] = shows;
    if (exhibitions != null) data['exhibitions'] = exhibitions;
    if (artifacts != null) data['artifacts'] = artifacts;

    await _collection.doc(placeId).set(data, SetOptions(merge: true));
  }

  /// Returns the raw Place_details document for [placeId], or null if none
  /// has been saved yet.
  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final snap = await _collection.doc(placeId).get();
    return snap.data();
  }

  /// Saves the set of PaymentMethods doc ids this place accepts.
  static Future<void> savePaymentMethods(
      String placeId, List<String> methodIds) async {
    await _collection.doc(placeId).set({
      'placeId': placeId,
      'paymentMethods': methodIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
