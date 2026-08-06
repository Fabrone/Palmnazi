import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyBookingsScreen
//
// Lists the signed-in tourist's own bookings (Firestore Bookings collection,
// filtered by firebaseUid via Firestore security rules). Reachable from
// AccountScreen. Lets the tourist cancel a still-pending booking.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  static const Color aquaBright = Color(0xFF00E5FF);
  static Color get deepNavy =>
      _isDark ? const Color(0xFF01263F) : const Color(0xFFF5F7FA);
  static Color get deepBlue =>
      _isDark ? const Color(0xFF071829) : const Color(0xFFE8EDF2);

  static Color get textPri => _isDark ? Colors.white : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? Colors.white70 : const Color(0xFF3D4F60);
  static Color get textMute =>
      _isDark ? Colors.white38 : const Color(0xFF7C93A8);

  /// Subtle fill for input/button backgrounds that used to be a flat
  /// `Colors.white.withValues(alpha: x)` — invisible once the surface
  /// behind it turns light.
  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
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
        title: Text(context.tr('account_my_bookings'),
            style: TextStyle(color: _P.textPri)),
        iconTheme: IconThemeData(color: _P.textPri),
      ),
      body: uid == null
          ? Center(
              child: Text(context.tr('my_bookings_signin_required'),
                  style: TextStyle(color: _P.textMute)))
          : StreamBuilder<List<BookingModel>>(
              stream: BookingService.streamForUser(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _P.aquaBright));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                        '${context.tr('my_bookings_error_load_prefix')} ${snap.error}',
                        style: TextStyle(color: _P.textMute)),
                  );
                }
                final bookings = snap.data ?? const <BookingModel>[];
                if (bookings.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.tr('my_bookings_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _P.textMute),
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
        return _P.textMute;
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final eligibility = booking.checkCancellationEligibility();
    if (!eligibility.allowed) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _P.deepNavy,
          title: Text(context.tr('my_bookings_dialog_cancel_unavailable_title'),
              style: TextStyle(color: _P.textPri)),
          content:
              Text(eligibility.reason, style: TextStyle(color: _P.textSec)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('common_ok'),
                  style: TextStyle(color: _P.textMute)),
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
        title: Text(context.tr('my_bookings_dialog_cancel_title'),
            style: TextStyle(color: _P.textPri)),
        content: Text(context.tr('my_bookings_dialog_cancel_body'),
            style: TextStyle(color: _P.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('my_bookings_button_keep'),
                style: TextStyle(color: _P.textMute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('my_bookings_button_cancel_booking'),
                style: const TextStyle(color: Colors.redAccent)),
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
        color: _P.overlay(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(booking.placeName,
                  style: TextStyle(
                      color: _P.textPri,
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
              style: TextStyle(color: _P.textMute, fontSize: 12)),
          const SizedBox(height: 6),
          _infoRow(
            Icons.confirmation_number_outlined,
            '${context.tr('my_bookings_reference_prefix')} '
            '${(booking.id.length > 8 ? booking.id.substring(booking.id.length - 8) : booking.id).toUpperCase()}',
          ),
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
                '${booking.currency ?? ''} ${booking.totalAmount!.toStringAsFixed(0)} ${context.tr('my_bookings_estimate_suffix')}'),
          ],
          if (booking.mpesaReceiptNumber != null) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.check_circle_outline_rounded,
                '${context.tr('my_bookings_mpesa_receipt_prefix')} ${booking.mpesaReceiptNumber}'),
          ],
          if (booking.status == BookingStatus.pending) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancel(context),
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: Colors.redAccent),
                label: Text(context.tr('common_cancel'),
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
          child: Text(text, style: TextStyle(color: _P.textSec, fontSize: 12)),
        ),
      ]);
}
