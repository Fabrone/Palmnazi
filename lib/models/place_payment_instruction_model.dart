import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlacePaymentInstructionModel
//
// Firestore collection : PlacePaymentInstructions
// Document ID          : auto-generated
//
// A place's OWN instructions for a payment method it accepts — the global
// PaymentMethods catalogue (see payment_method_model.dart) still defines
// *what kinds* of payment exist app-wide (M-Pesa/Card/Bank/Cash, icon,
// label); this collection is each place's own account/till/paybill details
// for the kinds it accepts, since payment details are place-specific, not
// system-wide (a tourist paying Villa Rosa Kempinski by bank transfer needs
// THAT hotel's account number, not a shared global one).
// ─────────────────────────────────────────────────────────────────────────────

class PlacePaymentInstructionModel {
  final String id;
  final String placeId;
  final String paymentMethodId; // references PaymentMethods/{id}
  final String instructions; // free text: till/paybill/account details, etc.
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PlacePaymentInstructionModel({
    required this.id,
    required this.placeId,
    required this.paymentMethodId,
    required this.instructions,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PlacePaymentInstructionModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PlacePaymentInstructionModel(
      id: doc.id,
      placeId: d['placeId'] as String? ?? '',
      paymentMethodId: d['paymentMethodId'] as String? ?? '',
      instructions: d['instructions'] as String? ?? '',
      isActive: d['isActive'] as bool? ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap({required String placeId}) => {
        'placeId': placeId,
        'paymentMethodId': paymentMethodId,
        'instructions': instructions,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
