import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/place_query_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceQueryService
//
// CRUD over the PlaceQueries collection (Firestore). Created by tourists from
// place_details_screen.dart's "Ask a Question", read/replied to by that
// place's Admin (or MainAdmin) from the Place Admin Panel's Queries tab, and
// streamed back to the tourist on my_bookings_screen.dart-style "My
// Questions" views.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceQueryService {
  PlaceQueryService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('PlaceQueries');

  static Future<void> submit(PlaceQueryModel query) =>
      _collection.add(query.toCreateMap());

  /// Live stream of every query for one place, newest first — Place Admin
  /// Panel's Queries tab.
  static Stream<List<PlaceQueryModel>> streamForPlace(String placeId) {
    return _collection
        .where('placeId', isEqualTo: placeId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PlaceQueryModel.fromFirestore(d)).toList());
  }

  /// Live stream of the signed-in tourist's own queries, newest first.
  static Stream<List<PlaceQueryModel>> streamForUser(String firebaseUid) {
    return _collection
        .where('firebaseUid', isEqualTo: firebaseUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PlaceQueryModel.fromFirestore(d)).toList());
  }

  static Future<void> reply({
    required String queryId,
    required String reply,
    required String repliedBy,
  }) {
    return _collection.doc(queryId).update({
      'status': 'answered',
      'adminReply': reply,
      'repliedBy': repliedBy,
      'repliedAt': FieldValue.serverTimestamp(),
    });
  }
}
