import 'package:palmnazi/models/booking_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingStats
//
// Shared bookings aggregation used by both the MainAdmin's system-wide
// Reports screen (admin_reports_screen.dart) and the Place Admin Panel's
// per-place Overview tab (place_admin/place_admin_panel.dart) — same
// computation, just fed a different (system-wide vs. place-filtered) list.
// ─────────────────────────────────────────────────────────────────────────────

class BookingStats {
  final int total;
  final int pending;
  final int confirmed;
  final int completed;
  final int cancelled;
  final int paidViaMpesa;
  final int simulatedPayments;
  final double revenue;

  /// Place name → booking count, sorted descending. Only meaningful for a
  /// system-wide (unfiltered) list — a place-scoped list is all one place.
  final List<MapEntry<String, int>> topPlaces;

  const BookingStats({
    required this.total,
    required this.pending,
    required this.confirmed,
    required this.completed,
    required this.cancelled,
    required this.paidViaMpesa,
    required this.simulatedPayments,
    required this.revenue,
    this.topPlaces = const [],
  });

  static BookingStats from(List<BookingModel> bookings,
      {bool withTopPlaces = false}) {
    final byPlace = <String, int>{};
    double revenue = 0;
    int paid = 0;
    int simulated = 0;

    for (final b in bookings) {
      if (withTopPlaces) {
        byPlace.update(b.placeName, (n) => n + 1, ifAbsent: () => 1);
      }
      if (b.mpesaReceiptNumber != null) paid++;
      if (b.paymentSimulated) simulated++;
      if (b.status != BookingStatus.cancelled && b.totalAmount != null) {
        revenue += b.totalAmount!;
      }
    }

    final topPlaces = byPlace.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return BookingStats(
      total: bookings.length,
      pending: bookings.where((b) => b.status == BookingStatus.pending).length,
      confirmed:
          bookings.where((b) => b.status == BookingStatus.confirmed).length,
      completed:
          bookings.where((b) => b.status == BookingStatus.completed).length,
      cancelled:
          bookings.where((b) => b.status == BookingStatus.cancelled).length,
      paidViaMpesa: paid,
      simulatedPayments: simulated,
      revenue: revenue,
      topPlaces: withTopPlaces ? topPlaces.take(5).toList() : const [],
    );
  }
}
