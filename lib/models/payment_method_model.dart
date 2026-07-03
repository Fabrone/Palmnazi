import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentMethodModel
//
// Firestore collection : PaymentMethods
// Document ID          : auto-generated
//
// Admin-managed catalogue of payment options that places can be configured to
// accept (M-Pesa, Card, PayPal, Bank Transfer, Cash on Arrival, …). This is
// purely descriptive/configuration data — no real payment processing or
// gateway integration happens here (see PaymentSimulationScreen). It lives in
// Firestore rather than the /api/places backend since that contract hasn't
// been extended for booking/payment yet.
//
// [config] holds provider-specific placeholder settings an admin would need
// to fill in before a real gateway integration could go live — e.g. an
// M-Pesa paybill number, or a card gateway's publishable key. See
// [configFieldsFor] for which keys apply to which [PaymentMethodType].
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentMethodType { mpesa, card, paypal, bankTransfer, cash, other }

class PaymentConfigField {
  final String key;
  final String label;
  final String hint;
  const PaymentConfigField(this.key, this.label, this.hint);
}

class PaymentMethodModel {
  final String id;
  final String name;
  final PaymentMethodType type;
  final String? description;
  final String? icon;
  final bool isActive;
  final int sortOrder;
  final Map<String, String> config;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PaymentMethodModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.icon,
    this.isActive = true,
    this.sortOrder = 0,
    this.config = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory PaymentMethodModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PaymentMethodModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      type: _typeFromString(d['type'] as String? ?? 'other'),
      description: d['description'] as String?,
      icon: d['icon'] as String?,
      isActive: d['isActive'] as bool? ?? true,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
      config: Map<String, String>.from(
          (d['config'] as Map<dynamic, dynamic>?) ?? const {}),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.name,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        'isActive': isActive,
        'sortOrder': sortOrder,
        'config': config,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static PaymentMethodType _typeFromString(String s) {
    return PaymentMethodType.values.firstWhere(
      (t) => t.name == s,
      orElse: () => PaymentMethodType.other,
    );
  }

  static String typeLabel(PaymentMethodType type) {
    switch (type) {
      case PaymentMethodType.mpesa:
        return 'M-Pesa';
      case PaymentMethodType.card:
        return 'Card';
      case PaymentMethodType.paypal:
        return 'PayPal';
      case PaymentMethodType.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethodType.cash:
        return 'Cash';
      case PaymentMethodType.other:
        return 'Other';
    }
  }

  /// The placeholder configuration fields an admin would fill in per type —
  /// these are what a real gateway integration would eventually need, but
  /// today they're stored and displayed only; nothing reads them to move
  /// money. See PaymentSimulationScreen for how they surface to a tourist.
  static List<PaymentConfigField> configFieldsFor(PaymentMethodType type) {
    switch (type) {
      case PaymentMethodType.mpesa:
        return const [
          PaymentConfigField('paybillNumber', 'Paybill / Till Number', 'e.g. 400200'),
          PaymentConfigField('accountReference', 'Account Reference (optional)', 'e.g. PALMNAZI'),
        ];
      case PaymentMethodType.card:
        return const [
          PaymentConfigField('publishableKey', 'Gateway Publishable Key', 'pk_live_… / pk_test_…'),
          PaymentConfigField('merchantId', 'Merchant ID (optional)', 'e.g. MERCH-00123'),
        ];
      case PaymentMethodType.paypal:
        return const [
          PaymentConfigField('clientId', 'PayPal Client ID', 'e.g. AZ8x…'),
          PaymentConfigField('merchantEmail', 'Merchant Email', 'business@example.com'),
        ];
      case PaymentMethodType.bankTransfer:
        return const [
          PaymentConfigField('bankName', 'Bank Name', 'e.g. Equity Bank'),
          PaymentConfigField('accountNumber', 'Account Number', 'e.g. 0123456789'),
          PaymentConfigField('accountName', 'Account Name', 'e.g. Palmnazi Resorts Ltd'),
        ];
      case PaymentMethodType.cash:
      case PaymentMethodType.other:
        return const [];
    }
  }

  @override
  String toString() =>
      'PaymentMethodModel(id: $id, name: $name, type: ${type.name}, isActive: $isActive)';
}
