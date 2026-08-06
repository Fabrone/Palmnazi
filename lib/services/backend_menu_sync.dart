import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/models/menu_item_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackendMenuSync
//
// As of Phase 3, Firestore (MenuSections/MenuItems, via MenuService) is the
// sole authoritative store for Dining data — the backend REST API's global
// menu-items list has proven unreliable (500s on a missing DB column) and is
// now only a best-effort mirror. Same fire-and-forget, error-swallowing
// design as BackendRoomSync/BackendBookingSync — a sync failure must never
// surface to the admin or affect the Firestore-confirmed save.
//
// Menu items are section-scoped on the backend, so an item's create/update/
// delete sync needs its parent section's *backend* id (not the Firestore
// one) — passed in by the caller, which reads it off the section's own
// `restId` (persisted by pushCreateSectionSilently, same restId round-trip
// as BackendRoomSync). If the parent section was never synced, item sync is
// skipped with a log line rather than guessed at.
// ─────────────────────────────────────────────────────────────────────────────

class BackendMenuSync {
  BackendMenuSync._();

  // ── Sections ─────────────────────────────────────────────────────────────

  static Future<void> pushCreateSectionSilently(
    AdminApiService api,
    String firestoreSectionId,
    String placeId,
    MenuSectionModel section,
  ) async {
    try {
      final created =
          await api.createMenuSections(placeId, [section.toCreateMap()]);
      final restId = created.isNotEmpty ? created.first['id'] as String? : null;
      developer.log(
        'Section "${section.name}" synced to backend (restId=${restId ?? "unknown"})',
        name: 'BackendMenuSync',
      );
      if (restId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('MenuSections')
              .doc(firestoreSectionId)
              .update({'restId': restId});
        } catch (e, st) {
          developer.log(
            'Failed to persist restId onto MenuSections/$firestoreSectionId (non-blocking)',
            name: 'BackendMenuSync',
            error: e,
            stackTrace: st,
          );
        }
      }
    } catch (e, st) {
      developer.log(
        'Create sync failed for section "${section.name}" (non-blocking, already saved to Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> pushUpdateSectionSilently(
    AdminApiService api,
    String placeId,
    String? restId,
    MenuSectionModel section,
  ) async {
    if (restId == null) {
      developer.log(
        'Skipping update sync for section "${section.name}" — no backend id known yet',
        name: 'BackendMenuSync',
      );
      return;
    }
    try {
      await api.updateMenuSection(placeId, restId, section.toCreateMap());
      developer.log('Section "${section.name}" update synced (restId=$restId)',
          name: 'BackendMenuSync');
    } catch (e, st) {
      developer.log(
        'Update sync failed for section "${section.name}" (non-blocking, already updated in Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> pushDeleteSectionSilently(
      AdminApiService api, String placeId, String? restId) async {
    if (restId == null) {
      developer.log(
          'Skipping delete sync — no backend id known for this section',
          name: 'BackendMenuSync');
      return;
    }
    try {
      await api.deleteMenuSection(placeId, restId);
      developer.log('Section delete synced (restId=$restId)',
          name: 'BackendMenuSync');
    } catch (e, st) {
      developer.log(
        'Delete sync failed for section (non-blocking, already deleted from Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Items ────────────────────────────────────────────────────────────────

  /// [restSectionId] is the parent section's *backend* id — null means the
  /// section itself was never confirmed on the backend, so there is nowhere
  /// to file this item under; sync is skipped rather than guessed at.
  static Future<void> pushCreateItemSilently(
    AdminApiService api,
    String firestoreItemId,
    String placeId,
    String? restSectionId,
    MenuItemModel item,
  ) async {
    if (restSectionId == null) {
      developer.log(
        'Skipping create sync for item "${item.name}" — parent section has no backend id yet',
        name: 'BackendMenuSync',
      );
      return;
    }
    try {
      final created = await api
          .createMenuSectionItems(placeId, restSectionId, [item.toCreateMap()]);
      final restId = created.isNotEmpty ? created.first['id'] as String? : null;
      developer.log(
        'Item "${item.name}" synced to backend (restId=${restId ?? "unknown"})',
        name: 'BackendMenuSync',
      );
      if (restId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('MenuItems')
              .doc(firestoreItemId)
              .update({'restId': restId});
        } catch (e, st) {
          developer.log(
            'Failed to persist restId onto MenuItems/$firestoreItemId (non-blocking)',
            name: 'BackendMenuSync',
            error: e,
            stackTrace: st,
          );
        }
      }
    } catch (e, st) {
      developer.log(
        'Create sync failed for item "${item.name}" (non-blocking, already saved to Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> pushUpdateItemSilently(
    AdminApiService api,
    String placeId,
    String? restSectionId,
    String? restId,
    MenuItemModel item,
  ) async {
    if (restSectionId == null || restId == null) {
      developer.log(
        'Skipping update sync for item "${item.name}" — missing backend section/item id',
        name: 'BackendMenuSync',
      );
      return;
    }
    try {
      await api.updateMenuSectionItem(
          placeId, restSectionId, restId, item.toCreateMap());
      developer.log('Item "${item.name}" update synced (restId=$restId)',
          name: 'BackendMenuSync');
    } catch (e, st) {
      developer.log(
        'Update sync failed for item "${item.name}" (non-blocking, already updated in Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> pushDeleteItemSilently(
    AdminApiService api,
    String placeId,
    String? restSectionId,
    String? restId,
  ) async {
    if (restSectionId == null || restId == null) {
      developer.log(
        'Skipping delete sync — missing backend section/item id',
        name: 'BackendMenuSync',
      );
      return;
    }
    try {
      await api.deleteMenuSectionItem(placeId, restSectionId, restId);
      developer.log('Item delete synced (restId=$restId)',
          name: 'BackendMenuSync');
    } catch (e, st) {
      developer.log(
        'Delete sync failed for item (non-blocking, already deleted from Firestore)',
        name: 'BackendMenuSync',
        error: e,
        stackTrace: st,
      );
    }
  }
}
