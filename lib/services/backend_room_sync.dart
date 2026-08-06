import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/models/room_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackendRoomSync
//
// As of Phase 3, Firestore (Rooms collection, via RoomService) is the sole
// authoritative store for room data — the backend REST API
// (admin_api_service.dart) has proven unreliable (its unfiltered rooms GET
// 500s server-side) and is now only a best-effort mirror. Every method here
// is fire-and-forget and error-swallowing by design, mirroring
// BackendBookingSync: a sync failure must never surface to the admin or
// affect the Firestore-confirmed save that already succeeded — only a
// developer.log trail should show it happened.
//
// The backend assigns its own id on create, distinct from the Firestore doc
// id. That id is persisted back onto the Firestore doc as `restId` (itself
// best-effort) so a later edit/delete can still target the right backend
// resource — if it's missing (backend was down on create, or this room
// predates Phase 3), update/delete sync is skipped with a log line rather
// than guessed at.
// ─────────────────────────────────────────────────────────────────────────────

class BackendRoomSync {
  BackendRoomSync._();

  /// Call unawaited, right after RoomService.create succeeds.
  static Future<void> pushCreateSilently(
    AdminApiService api,
    String firestoreRoomId,
    String placeId,
    RoomModel room,
  ) async {
    try {
      final created = await api.createRooms(placeId, [room.toCreateMap()]);
      final restId = created.isNotEmpty ? created.first['id'] as String? : null;
      developer.log(
        'Room "${room.name}" synced to backend (restId=${restId ?? "unknown"})',
        name: 'BackendRoomSync',
      );
      if (restId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('Rooms')
              .doc(firestoreRoomId)
              .update({'restId': restId});
        } catch (e, st) {
          developer.log(
            'Failed to persist restId back onto Rooms/$firestoreRoomId (non-blocking)',
            name: 'BackendRoomSync',
            error: e,
            stackTrace: st,
          );
        }
      }
    } catch (e, st) {
      developer.log(
        'Create sync failed for room "${room.name}" (non-blocking, already saved to Firestore)',
        name: 'BackendRoomSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Call unawaited, right after RoomService.update succeeds. [restId] is the
  /// backend id previously persisted by pushCreateSilently — null when the
  /// backend never confirmed a create (or this room predates Phase 3).
  static Future<void> pushUpdateSilently(
    AdminApiService api,
    String? restId,
    RoomModel room,
  ) async {
    if (restId == null) {
      developer.log(
        'Skipping update sync for room "${room.name}" — no backend id known yet',
        name: 'BackendRoomSync',
      );
      return;
    }
    try {
      await api.updateRoom(restId, room.toCreateMap());
      developer.log(
          'Room "${room.name}" update synced to backend (restId=$restId)',
          name: 'BackendRoomSync');
    } catch (e, st) {
      developer.log(
        'Update sync failed for room "${room.name}" (non-blocking, already updated in Firestore)',
        name: 'BackendRoomSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Call unawaited, right after RoomService.delete succeeds.
  static Future<void> pushDeleteSilently(
      AdminApiService api, String? restId) async {
    if (restId == null) {
      developer.log('Skipping delete sync — no backend id known for this room',
          name: 'BackendRoomSync');
      return;
    }
    try {
      await api.deleteRoom(restId);
      developer.log('Room delete synced to backend (restId=$restId)',
          name: 'BackendRoomSync');
    } catch (e, st) {
      developer.log(
        'Delete sync failed (non-blocking, already deleted from Firestore)',
        name: 'BackendRoomSync',
        error: e,
        stackTrace: st,
      );
    }
  }
}
