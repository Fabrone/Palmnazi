import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/backend_booking_sync.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingService
//
// CRUD over the Bookings collection (Firestore). Created by tourists via
// booking_screen.dart, read back on my_bookings_screen.dart (tourist) and
// admin_bookings_screen.dart (admin).
// ─────────────────────────────────────────────────────────────────────────────

class BookingService {
  BookingService._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('Bookings');

  static Future<String> create(BookingModel booking) async {
    final ref = await _collection.add(booking.toCreateMap());
    // Fire-and-forget — Firestore above is already authoritative; this can
    // never block, delay, or fail the booking. See BackendBookingSync.
    unawaited(BackendBookingSync.pushSilently(booking));
    return ref.id;
  }

  /// Creates one Bookings doc per entry in [bookings], all tagged with a
  /// freshly-generated shared `bookingGroupId` — used when a tourist checks
  /// out with more than one service from the same place in one go (e.g. a
  /// room + a dining item). Each doc keeps working with every existing
  /// per-service mechanism (conflict-checking, cancellation-per-item, admin
  /// per-item confirm/cancel) unchanged; the group id is purely a display/
  /// grouping hint for my_bookings_screen.dart / admin_bookings_screen.dart.
  /// Returns the new doc ids in the same order as [bookings].
  static Future<List<String>> createGroup(List<BookingModel> bookings) async {
    assert(bookings.isNotEmpty);
    final groupId = _collection.doc().id;
    final batch = FirebaseFirestore.instance.batch();
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (final booking in bookings) {
      final ref = _collection.doc();
      refs.add(ref);
      batch.set(ref, {
        ...booking.toCreateMap(),
        'bookingGroupId': groupId,
      });
    }
    await batch.commit();
    for (var i = 0; i < bookings.length; i++) {
      unawaited(BackendBookingSync.pushSilently(bookings[i]));
    }
    return refs.map((r) => r.id).toList();
  }

  /// Tourist submits a payment reference/proof against the place's own
  /// PlacePaymentInstructions — moves the booking to `paymentSubmitted` for
  /// the place admin to review (see PlacePaymentService).
  static Future<void> submitPaymentProof(
    String bookingId, {
    String? text,
    String? imageUrl,
  }) {
    return _collection.doc(bookingId).update({
      'status': BookingStatus.paymentSubmitted.name,
      if (text != null) 'paymentProofText': text,
      if (imageUrl != null) 'paymentProofImageUrl': imageUrl,
      'paymentRejectionReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Place admin approves a submitted payment proof — booking becomes real.
  static Future<void> approvePayment(String bookingId) {
    return _collection.doc(bookingId).update({
      'status': BookingStatus.confirmed.name,
      'paymentRejectionReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Place admin rejects a submitted payment proof — back to awaiting
  /// payment so the tourist can submit a corrected reference.
  static Future<void> rejectPayment(String bookingId, String reason) {
    return _collection.doc(bookingId).update({
      'status': BookingStatus.awaitingPayment.name,
      'paymentRejectionReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Live stream of the signed-in user's own bookings, most recent first.
  static Stream<List<BookingModel>> streamForUser(String firebaseUid) {
    return _collection
        .where('firebaseUid', isEqualTo: firebaseUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => BookingModel.fromFirestore(d)).toList());
  }

  /// Live stream of all bookings, most recent first — MainAdmin only
  /// (enforced by Firestore rules, not by this client-side call).
  static Stream<List<BookingModel>> streamAll() {
    return _collection.orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => BookingModel.fromFirestore(d)).toList());
  }

  /// Live stream of bookings for a single place, most recent first — used by
  /// the Place Admin Panel. A place-scoped Admin's Firestore rules only allow
  /// reads that filter by their own placeId (see isPlaceAdminFor in
  /// firestore.rules), so this — not streamAll() — is what makes their query
  /// actually satisfy those rules rather than being rejected outright.
  static Stream<List<BookingModel>> streamForPlace(String placeId) {
    return _collection
        .where('placeId', isEqualTo: placeId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => BookingModel.fromFirestore(d)).toList());
  }

  static Future<void> updateStatus(String bookingId, BookingStatus status) {
    return _collection.doc(bookingId).update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Tourist-initiated cancellation of their own still-pending booking.
  static Future<void> cancel(String bookingId) =>
      updateStatus(bookingId, BookingStatus.cancelled);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// True when an existing pending/confirmed booking for the same
  /// [placeId] + [serviceName] overlaps [requestedDate]..[checkOutDate].
  ///
  /// This is a same-resource double-booking guard (e.g. two tourists can't
  /// both reserve "Deluxe Ocean View Room" for overlapping nights) — it does
  /// not model capacity/inventory (e.g. a restaurant's table count), since
  /// nested items don't carry a quantity field. Only meaningful when a
  /// specific service is selected; general/no-service bookings are never
  /// flagged as conflicting since there's nothing to distinguish them by.
  static Future<bool> hasConflict({
    required String placeId,
    required String serviceName,
    required DateTime requestedDate,
    DateTime? checkOutDate,
  }) async {
    final snap = await _collection
        .where('placeId', isEqualTo: placeId)
        .where('serviceName', isEqualTo: serviceName)
        .where('status', whereIn: [
      'pending',
      'awaitingPayment',
      'paymentSubmitted',
      'confirmed',
    ]).get();

    final newStart = _dateOnly(requestedDate);
    final newEnd = _dateOnly(checkOutDate ?? requestedDate);

    for (final doc in snap.docs) {
      final booking = BookingModel.fromFirestore(doc);
      final existingStart = _dateOnly(booking.requestedDate);
      final existingEnd =
          _dateOnly(booking.checkOutDate ?? booking.requestedDate);
      final overlaps =
          !newStart.isAfter(existingEnd) && !existingStart.isAfter(newEnd);
      if (overlaps) return true;
    }
    return false;
  }
}
