import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/room_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomService
//
// Firestore collection: Rooms
// Document id: auto-generated — this id is a room's canonical id from Phase 3
// onward (previously the backend REST API's id). Firestore is authoritative;
// the backend REST API is written to as a best-effort mirror only — see
// BackendRoomSync. Mirrors BookingService's shape/conventions.
// ─────────────────────────────────────────────────────────────────────────────

class RoomService {
  RoomService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('Rooms');

  /// Creates a room for [placeId] and returns its new Firestore doc id.
  static Future<String> create(RoomModel room,
      {required String placeId}) async {
    final ref = await _collection.add({
      ...room.toFirestoreMap(placeId: placeId),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> update(String roomId, RoomModel room,
      {required String placeId}) {
    return _collection.doc(roomId).update({
      ...room.toFirestoreMap(placeId: placeId),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> delete(String roomId) => _collection.doc(roomId).delete();

  /// One-shot read of every room belonging to [placeId] — used both by the
  /// admin wizard (reopening an existing place) and the tourist-facing place
  /// details screen. No stream variant needed: both call sites already fetch
  /// once on load, matching the previous REST-backed behavior.
  static Future<List<RoomModel>> getForPlace(String placeId) async {
    final snap = await _collection.where('placeId', isEqualTo: placeId).get();
    return snap.docs.map((d) => RoomModel.fromFirestore(d)).toList();
  }
}
