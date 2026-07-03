import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/booking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyBookingsScreen
//
// Lists the signed-in tourist's own bookings (Firestore Bookings collection,
// filtered by firebaseUid via Firestore security rules). Reachable from
// AccountScreen. Lets the tourist cancel a still-pending booking.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
}

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: AppBar(
        backgroundColor: _P.deepNavy,
        title: const Text('My Bookings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: uid == null
          ? const Center(
              child: Text('Sign in to view your bookings.',
                  style: TextStyle(color: Colors.white54)))
          : StreamBuilder<List<BookingModel>>(
              stream: BookingService.streamForUser(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _P.aquaBright));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load bookings: ${snap.error}',
                        style: const TextStyle(color: Colors.white54)),
                  );
                }
                final bookings = snap.data ?? const <BookingModel>[];
                if (bookings.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No bookings yet. Find a place you love and tap "Book Now".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _BookingCard(booking: bookings[i]),
                );
              },
            ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingModel booking;
  const _BookingCard({required this.booking});

  Color get _statusColor {
    switch (booking.status) {
      case BookingStatus.pending:
        return Colors.orangeAccent;
      case BookingStatus.confirmed:
        return Colors.greenAccent;
      case BookingStatus.cancelled:
        return Colors.redAccent;
      case BookingStatus.completed:
        return Colors.white54;
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final eligibility = booking.checkCancellationEligibility();
    if (!eligibility.allowed) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _P.deepNavy,
          title: const Text('Cancellation not available',
              style: TextStyle(color: Colors.white)),
          content: Text(eligibility.reason,
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _P.deepNavy,
        title: const Text('Cancel booking?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Keep it', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BookingService.cancel(booking.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(booking.placeName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                BookingModel.statusLabel(booking.status),
                style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(booking.cityName,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 10),
          if (booking.serviceName != null) ...[
            _infoRow(Icons.room_service_outlined, booking.serviceName!),
            const SizedBox(height: 6),
          ],
          _infoRow(
              Icons.calendar_today_rounded,
              '${booking.requestedDate.day}/${booking.requestedDate.month}/${booking.requestedDate.year}'
              '${booking.checkOutDate != null ? ' — ${booking.checkOutDate!.day}/${booking.checkOutDate!.month}/${booking.checkOutDate!.year}' : ''}'),
          const SizedBox(height: 6),
          _infoRow(Icons.people_outline_rounded,
              '${booking.numberOfGuests} guest${booking.numberOfGuests == 1 ? '' : 's'}'),
          if (booking.paymentMethodName != null) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.payments_outlined, booking.paymentMethodName!),
          ],
          if (booking.totalAmount != null) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.receipt_long_rounded,
                '${booking.currency ?? ''} ${booking.totalAmount!.toStringAsFixed(0)} (estimate)'),
          ],
          if (booking.mpesaReceiptNumber != null) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.check_circle_outline_rounded,
                'Paid via M-Pesa — receipt ${booking.mpesaReceiptNumber}'),
          ],
          if (booking.status == BookingStatus.pending) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancel(context),
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: Colors.redAccent),
                label: const Text('Cancel',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 14, color: _P.aquaBright),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ]);
}
