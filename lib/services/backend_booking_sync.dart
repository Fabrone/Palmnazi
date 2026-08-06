import 'dart:developer' as developer;

import 'package:palmnazi/models/booking_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackendBookingSync
//
// The backend Place API (see admin_api_service.dart) is catalog-only today —
// full CRUD for places, rooms, menu items, shows, exhibitions, artifacts —
// but has no reservation/booking endpoint. Firestore (BookingService) is
// therefore the sole, authoritative source of truth for bookings; it is not
// a cache or a staging area for the backend.
//
// This class exists so the call site is already correctly wired for the day
// a real reservation endpoint ships: pushSilently() is fire-and-forget and
// error-swallowing by design — a sync failure (or the endpoint simply not
// existing yet, as today) must never surface to the tourist or affect the
// Firestore-confirmed booking that already succeeded.
// ─────────────────────────────────────────────────────────────────────────────

class BackendBookingSync {
  BackendBookingSync._();

  /// Best-effort mirror of a confirmed booking to the backend. Call this
  /// unawaited, after the Firestore write has already succeeded — never
  /// await it inline with the booking flow, and never let it throw outward.
  static Future<void> pushSilently(BookingModel booking) async {
    try {
      // ToDO: once a real reservation endpoint exists (e.g.
      // POST /api/places/:placeId/rooms/:roomId/reservations or similar),
      // fire a non-blocking HTTP POST here with booking.toCreateMap() plus
      // booking.id. Keep it wrapped in this same try/catch — a failed sync
      // must stay silent and Firestore must remain authoritative regardless
      // of the backend's availability.
      developer.log(
        'No backend reservation endpoint exists yet — booking '
        '${booking.placeName} (serviceId=${booking.serviceId ?? "none"}) '
        'stays Firestore-only.',
        name: 'BackendBookingSync',
      );
    } catch (e, st) {
      developer.log(
        'pushSilently failed (non-blocking, booking already confirmed in Firestore)',
        name: 'BackendBookingSync',
        error: e,
        stackTrace: st,
      );
    }
  }
}
