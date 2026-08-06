import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/menu_item_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MenuService
//
// Firestore collections: MenuSections, MenuItems
// Document id: auto-generated — canonical id for both from Phase 3 onward
// (previously the backend REST API's id). Firestore is authoritative; the
// backend REST API is written to as a best-effort mirror only — see
// BackendMenuSync. Mirrors BookingService/RoomService's shape/conventions.
// ─────────────────────────────────────────────────────────────────────────────

class MenuService {
  MenuService._();

  static CollectionReference<Map<String, dynamic>> get _sections =>
      FirebaseFirestore.instance.collection('MenuSections');

  static CollectionReference<Map<String, dynamic>> get _items =>
      FirebaseFirestore.instance.collection('MenuItems');

  // ── Sections ─────────────────────────────────────────────────────────────

  static Future<String> createSection(MenuSectionModel section,
      {required String placeId}) async {
    final ref = await _sections.add(section.toFirestoreMap(placeId: placeId));
    return ref.id;
  }

  static Future<void> updateSection(String sectionId, MenuSectionModel section,
      {required String placeId}) {
    return _sections
        .doc(sectionId)
        .update(section.toFirestoreMap(placeId: placeId));
  }

  static Future<void> deleteSection(String sectionId) =>
      _sections.doc(sectionId).delete();

  static Future<List<MenuSectionModel>> getSectionsForPlace(
      String placeId) async {
    final snap = await _sections.where('placeId', isEqualTo: placeId).get();
    return snap.docs.map((d) => MenuSectionModel.fromFirestore(d)).toList();
  }

  // ── Items ────────────────────────────────────────────────────────────────

  static Future<String> createItem(MenuItemModel item,
      {required String placeId, required String sectionId}) async {
    final ref = await _items
        .add(item.toFirestoreMap(placeId: placeId, sectionId: sectionId));
    return ref.id;
  }

  static Future<void> updateItem(String itemId, MenuItemModel item,
      {required String placeId, required String sectionId}) {
    return _items
        .doc(itemId)
        .update(item.toFirestoreMap(placeId: placeId, sectionId: sectionId));
  }

  static Future<void> deleteItem(String itemId) => _items.doc(itemId).delete();

  /// One-shot read of every menu item belonging to [placeId] — no stream
  /// variant needed, matching RoomService.getForPlace.
  static Future<List<MenuItemModel>> getItemsForPlace(String placeId) async {
    final snap = await _items.where('placeId', isEqualTo: placeId).get();
    return snap.docs.map((d) => MenuItemModel.fromFirestore(d)).toList();
  }

  // ── Live variants — see RoomService.streamForPlace/streamOne for why ─────

  static Stream<List<MenuSectionModel>> streamSectionsForPlace(
          String placeId) =>
      _sections.where('placeId', isEqualTo: placeId).snapshots().map(
          (snap) => snap.docs.map(MenuSectionModel.fromFirestore).toList());

  static Stream<List<MenuItemModel>> streamItemsForPlace(String placeId) =>
      _items
          .where('placeId', isEqualTo: placeId)
          .snapshots()
          .map((snap) => snap.docs.map(MenuItemModel.fromFirestore).toList());

  static Stream<MenuItemModel?> streamItem(String itemId) => _items
      .doc(itemId)
      .snapshots()
      .map((doc) => doc.exists ? MenuItemModel.fromFirestore(doc) : null);
}
