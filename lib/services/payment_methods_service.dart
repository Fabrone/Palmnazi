import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/payment_method_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentMethodsService
//
// CRUD over the global, admin-managed PaymentMethods catalogue (Firestore).
// Places reference these by id in Place_details.paymentMethods — see
// PlaceDetailsService.savePaymentMethods.
// ─────────────────────────────────────────────────────────────────────────────

class PaymentMethodsService {
  PaymentMethodsService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('PaymentMethods');

  static Stream<List<PaymentMethodModel>> streamAll() {
    return _collection.orderBy('sortOrder').snapshots().map((snap) =>
        snap.docs.map((d) => PaymentMethodModel.fromFirestore(d)).toList());
  }

  /// One-shot fetch of active payment methods, used by the place wizard's
  /// per-place selection list.
  static Future<List<PaymentMethodModel>> getActive() async {
    final snap = await _collection
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .get();
    return snap.docs.map((d) => PaymentMethodModel.fromFirestore(d)).toList();
  }

  static Future<void> create(PaymentMethodModel method) async {
    await _collection.add({
      ...method.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> update(String id, PaymentMethodModel method) async {
    await _collection.doc(id).update(method.toMap());
  }

  static Future<void> setActive(String id, bool isActive) async {
    await _collection.doc(id).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }
}
