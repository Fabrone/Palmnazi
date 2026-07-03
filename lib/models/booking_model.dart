import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingModel
//
// Firestore collection : Bookings
// Document ID          : auto-generated
//
// Created by a signed-in tourist from the "Book Now" flow on
// PlaceDetailsScreen (lib/screens/booking_screen.dart) and managed by
// Admin/MainAdmin from the admin dashboard (admin_bookings_screen.dart).
// Not part of the /api/places backend contract — the place/city/service
// fields below are snapshots taken at booking time so the record still
// reads sensibly even if the underlying place is later edited or removed.
// ─────────────────────────────────────────────────────────────────────────────

enum BookingStatus { pending, confirmed, cancelled, completed }

/// Result of checking whether a booking may still be cancelled under its
/// snapshotted cancellation policy. See BookingModel.checkCancellationEligibility.
class CancellationEligibility {
  final bool allowed;
  final String reason;
  const CancellationEligibility(this.allowed, this.reason);
}

class BookingModel {
  final String id;
  final String placeId;
  final String placeName;
  final String cityId;
  final String cityName;
  final String firebaseUid;
  final String userEmail;
  final String? serviceType; // 'rooms' | 'menuItems' | 'shows' | null (general)
  final String? serviceName;
  final DateTime requestedDate;
  final DateTime? checkOutDate;
  final int numberOfGuests;
  final String? notes;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final bool paymentSimulated;
  // Set only when payment actually went through Safaricom's Daraja sandbox
  // (see MpesaService / functions/index.js) — a real gateway round-trip,
  // not a simulation. Null for every other payment method.
  final String? mpesaReceiptNumber;
  final String? mpesaTransactionRef;
  final double? totalAmount;
  final String? currency;
  // Snapshot of the place's bookingSettings.cancellationPolicy at the time
  // this booking was made — 'flexible' | 'moderate' | 'strict'. Snapshotted
  // (rather than re-read from the place at cancel time) so a later change to
  // the place's policy can't retroactively affect an existing booking.
  final String? cancellationPolicy;
  final BookingStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BookingModel({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.cityId,
    required this.cityName,
    required this.firebaseUid,
    required this.userEmail,
    this.serviceType,
    this.serviceName,
    required this.requestedDate,
    this.checkOutDate,
    this.numberOfGuests = 1,
    this.notes,
    this.paymentMethodId,
    this.paymentMethodName,
    this.paymentSimulated = false,
    this.mpesaReceiptNumber,
    this.mpesaTransactionRef,
    this.totalAmount,
    this.currency,
    this.cancellationPolicy,
    this.status = BookingStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  factory BookingModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BookingModel(
      id: doc.id,
      placeId: d['placeId'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '',
      cityId: d['cityId'] as String? ?? '',
      cityName: d['cityName'] as String? ?? '',
      firebaseUid: d['firebaseUid'] as String? ?? '',
      userEmail: d['userEmail'] as String? ?? '',
      serviceType: d['serviceType'] as String?,
      serviceName: d['serviceName'] as String?,
      requestedDate:
          (d['requestedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      checkOutDate: (d['checkOutDate'] as Timestamp?)?.toDate(),
      numberOfGuests: (d['numberOfGuests'] as num?)?.toInt() ?? 1,
      notes: d['notes'] as String?,
      paymentMethodId: d['paymentMethodId'] as String?,
      paymentMethodName: d['paymentMethodName'] as String?,
      paymentSimulated: d['paymentSimulated'] as bool? ?? false,
      mpesaReceiptNumber: d['mpesaReceiptNumber'] as String?,
      mpesaTransactionRef: d['mpesaTransactionRef'] as String?,
      totalAmount: (d['totalAmount'] as num?)?.toDouble(),
      currency: d['currency'] as String?,
      cancellationPolicy: d['cancellationPolicy'] as String?,
      status: _statusFromString(d['status'] as String? ?? 'pending'),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'placeId': placeId,
        'placeName': placeName,
        'cityId': cityId,
        'cityName': cityName,
        'firebaseUid': firebaseUid,
        'userEmail': userEmail,
        if (serviceType != null) 'serviceType': serviceType,
        if (serviceName != null) 'serviceName': serviceName,
        'requestedDate': Timestamp.fromDate(requestedDate),
        if (checkOutDate != null)
          'checkOutDate': Timestamp.fromDate(checkOutDate!),
        'numberOfGuests': numberOfGuests,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
        if (paymentMethodName != null) 'paymentMethodName': paymentMethodName,
        'paymentSimulated': paymentSimulated,
        if (mpesaReceiptNumber != null)
          'mpesaReceiptNumber': mpesaReceiptNumber,
        if (mpesaTransactionRef != null)
          'mpesaTransactionRef': mpesaTransactionRef,
        if (totalAmount != null) 'totalAmount': totalAmount,
        if (currency != null) 'currency': currency,
        if (cancellationPolicy != null) 'cancellationPolicy': cancellationPolicy,
        'status': status.name,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Whether this booking may still be cancelled right now, under its
  /// snapshotted cancellation policy:
  ///   flexible — up until the requested date/time.
  ///   moderate — up to 48 hours before the requested date.
  ///   strict   — up to 7 days before the requested date.
  ///   (missing/unrecognised policy defaults to flexible.)
  CancellationEligibility checkCancellationEligibility({DateTime? now}) {
    if (status != BookingStatus.pending) {
      return CancellationEligibility(
          false, 'Only pending bookings can be cancelled here.');
    }
    final n = now ?? DateTime.now();
    final Duration cutoff;
    switch (cancellationPolicy) {
      case 'strict':
        cutoff = const Duration(days: 7);
        break;
      case 'moderate':
        cutoff = const Duration(hours: 48);
        break;
      default: // 'flexible' or unset
        cutoff = Duration.zero;
    }
    final deadline = requestedDate.subtract(cutoff);
    if (n.isBefore(deadline)) {
      return const CancellationEligibility(true, '');
    }
    final policyLabel = cancellationPolicy ?? 'flexible';
    if (cutoff == Duration.zero) {
      return const CancellationEligibility(
          false, 'The requested date has already passed.');
    }
    return CancellationEligibility(
      false,
      'This place has a $policyLabel cancellation policy — cancellations must be made at least '
      '${cutoff.inDays > 0 ? '${cutoff.inDays} day${cutoff.inDays == 1 ? '' : 's'}' : '${cutoff.inHours} hours'} '
      'before the requested date.',
    );
  }

  static BookingStatus _statusFromString(String s) {
    return BookingStatus.values.firstWhere(
      (t) => t.name == s,
      orElse: () => BookingStatus.pending,
    );
  }

  static String statusLabel(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
    }
  }

  @override
  String toString() =>
      'BookingModel(id: $id, place: $placeName, status: ${status.name})';
}

/// A computed booking estimate — see [estimateBookingTotal].
class EstimatedPrice {
  final double amount;
  final String currency;
  const EstimatedPrice(this.amount, this.currency);
}

/// Estimates a booking's total cost from whatever pricing data is available.
/// This is a rough, transparent estimate shown to the tourist before they
/// submit — not an authoritative quote (the backend doesn't have a pricing
/// engine yet).
///
/// Priority: the selected nested service's own price (room basePrice / menu
/// item price / show ticket price) wins; falls back to the place's own
/// [placeMinPrice] when no service is selected or it has no price field.
/// Returns null when no pricing signal exists at all.
EstimatedPrice? estimateBookingTotal({
  double? placeMinPrice,
  String? placeCurrency,
  Map<String, dynamic>? service,
  required String serviceType,
  required int guests,
  DateTime? checkIn,
  DateTime? checkOut,
}) {
  double? unitPrice;
  String currency = placeCurrency ?? 'KES';

  if (service != null) {
    switch (serviceType) {
      case 'rooms':
        final p = service['basePrice'];
        if (p is num) unitPrice = p.toDouble();
        final c = service['currency'] as String?;
        if (c != null && c.isNotEmpty) currency = c;
        break;
      case 'menuItems':
        final p = service['price'];
        if (p is num) unitPrice = p.toDouble();
        final c = service['currency'] as String?;
        if (c != null && c.isNotEmpty) currency = c;
        break;
      case 'shows':
        final ticketPricing = service['ticketPricing'];
        if (ticketPricing is Map && ticketPricing['standard'] is num) {
          unitPrice = (ticketPricing['standard'] as num).toDouble();
        }
        break;
    }
  }

  unitPrice ??= placeMinPrice;
  if (unitPrice == null) return null;

  int multiplier = 1;
  if (serviceType == 'rooms' && checkIn != null && checkOut != null) {
    final nights = checkOut.difference(checkIn).inDays;
    multiplier = nights > 0 ? nights : 1;
  } else if (serviceType == 'menuItems' || serviceType == 'shows') {
    multiplier = guests > 0 ? guests : 1;
  }

  return EstimatedPrice(unitPrice * multiplier, currency);
}
