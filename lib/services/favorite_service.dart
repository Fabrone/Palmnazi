import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/favorite_model.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FavoriteService
//
// CRUD over the Favorites collection (Firestore). Toggled from the heart icon
// on place_details_screen.dart, listed on my_favorites_screen.dart. Doc id is
// deterministic ({uid}_{placeId}) so toggling is a plain create/delete.
// ─────────────────────────────────────────────────────────────────────────────

class FavoriteService {
  FavoriteService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('Favorites');

  static String _docId(String uid, String placeId) => '${uid}_$placeId';

  /// Adds the favorite if it doesn't exist yet, removes it if it does.
  static Future<void> toggle({
    required String uid,
    required PlaceModel place,
  }) async {
    final ref = _collection.doc(_docId(uid, place.id));
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set(FavoriteModel(
        id: ref.id,
        firebaseUid: uid,
        placeId: place.id,
        placeName: place.name,
        placeCoverImage: place.coverImage,
        cityId: place.cityId,
        cityName: place.cityName,
      ).toCreateMap());
    }
  }

  /// Removes a favorite directly, without needing the full PlaceModel —
  /// used by my_favorites_screen.dart's remove action, where only the lean
  /// stored snapshot (placeId) is available.
  static Future<void> remove(String uid, String placeId) =>
      _collection.doc(_docId(uid, placeId)).delete();

  /// Live filled/outline state for the heart icon on a single place.
  static Stream<bool> isFavorited(String uid, String placeId) {
    return _collection
        .doc(_docId(uid, placeId))
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Live list of the signed-in tourist's own favorites, newest first.
  static Stream<List<FavoriteModel>> streamForUser(String uid) {
    return _collection
        .where('firebaseUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => FavoriteModel.fromFirestore(d)).toList());
  }
}
