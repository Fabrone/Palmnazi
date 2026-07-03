import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:palmnazi/models/booking_model.dart';

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
    return ref.id;
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

  /// Live stream of all bookings, most recent first — admin dashboard only
  /// (enforced by Firestore rules, not by this client-side call).
  static Stream<List<BookingModel>> streamAll() {
    return _collection.orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => BookingModel.fromFirestore(d)).toList());
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
        .where('status', whereIn: ['pending', 'confirmed'])
        .get();

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
