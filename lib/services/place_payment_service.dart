import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/place_payment_instruction_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlacePaymentService
//
// CRUD over the PlacePaymentInstructions collection — see
// place_payment_instruction_model.dart for why this exists alongside the
// global PaymentMethodsService catalogue.
// ─────────────────────────────────────────────────────────────────────────────

class PlacePaymentService {
  PlacePaymentService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('PlacePaymentInstructions');

  static Future<String> create(
    String placeId,
    PlacePaymentInstructionModel instruction,
  ) async {
    final ref = await _collection.add({
      ...instruction.toMap(placeId: placeId),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> update(
    String id,
    String placeId,
    PlacePaymentInstructionModel instruction,
  ) {
    return _collection.doc(id).update(instruction.toMap(placeId: placeId));
  }

  static Future<void> delete(String id) => _collection.doc(id).delete();

  static Stream<List<PlacePaymentInstructionModel>> streamForPlace(
          String placeId) =>
      _collection.where('placeId', isEqualTo: placeId).snapshots().map((snap) =>
          snap.docs.map(PlacePaymentInstructionModel.fromFirestore).toList());

  static Future<List<PlacePaymentInstructionModel>> getForPlace(
      String placeId) async {
    final snap = await _collection.where('placeId', isEqualTo: placeId).get();
    return snap.docs.map(PlacePaymentInstructionModel.fromFirestore).toList();
  }
}
