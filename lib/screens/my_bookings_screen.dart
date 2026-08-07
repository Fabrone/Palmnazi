import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';
import 'package:palmnazi/widgets/booking_message_thread.dart';
import 'package:palmnazi/widgets/main_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyBookingsScreen
//
// Lists the signed-in tourist's own bookings (Firestore Bookings collection,
// filtered by firebaseUid via Firestore security rules). Reachable from
// AccountScreen. Lets the tourist cancel a still-pending booking, resubmit
// payment proof after a rejection, and message the place admin per booking.
//
// Bookings created together from one multi-service checkout share a
// `bookingGroupId` (see BookingService.createGroup) — those are rendered as
// one grouped section with a shared reference header; every other booking
// renders exactly as a standalone card, unchanged from before.
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

/// Short, uppercased tail of a Firestore doc id — same truncation pattern
/// used by booking_screen.dart's post-booking success dialog — good enough
/// to read aloud/write down while staying visually short in a header.
String _shortRef(String id) =>
    (id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase();

/// Groups [bookings] by `bookingGroupId`, preserving first-seen order.
/// Bookings with a null groupId are each returned as their own single-item
/// group (rendered with zero extra chrome — the common case).
List<List<BookingModel>> _groupBookings(List<BookingModel> bookings) {
  final grouped = <String, List<BookingModel>>{};
  final result = <List<BookingModel>>[];
  for (final b in bookings) {
    final groupId = b.bookingGroupId;
    if (groupId == null) {
      result.add([b]);
      continue;
    }
    final existing = grouped[groupId];
    if (existing == null) {
      final list = <BookingModel>[b];
      grouped[groupId] = list;
      result.add(list);
    } else {
      existing.add(b);
    }
  }
  return result;
}

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: PalmnaziNavBar(
        compact: true,
        showBack: true,
        title: context.tr('account_my_bookings'),
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
                final groups = _groupBookings(bookings);
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _BookingGroupSection(group: groups[i]),
                );
              },
            ),
    );
  }
}

class _BookingGroupSection extends StatelessWidget {
  final List<BookingModel> group;
  const _BookingGroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    if (group.length <= 1) {
      return _BookingCard(booking: group.first);
    }
    final groupId = group.first.bookingGroupId ?? group.first.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(children: [
            Icon(Icons.layers_rounded, size: 16, color: _P.aquaBright),
            const SizedBox(width: 6),
            Text(
              'Booking #${_shortRef(groupId)} — ${group.length} services',
              style: TextStyle(
                  color: _P.textPri, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        for (var i = 0; i < group.length; i++) ...[
          _BookingCard(booking: group[i]),
          if (i != group.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BookingCard extends StatefulWidget {
  final BookingModel booking;
  const _BookingCard({required this.booking});

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _showMessages = false;
  bool _resubmitting = false;
  final _resubmitCtrl = TextEditingController();

  @override
  void dispose() {
    _resubmitCtrl.dispose();
    super.dispose();
  }

  BookingModel get booking => widget.booking;

  Color get _statusColor {
    switch (booking.status) {
      case BookingStatus.pending:
        return Colors.orangeAccent;
      case BookingStatus.awaitingPayment:
        return Colors.amberAccent;
      case BookingStatus.paymentSubmitted:
        return Colors.lightBlueAccent;
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

  Future<void> _resubmit(BuildContext context) async {
    final text = _resubmitCtrl.text.trim();
    if (text.isEmpty || _resubmitting) return;
    setState(() => _resubmitting = true);
    try {
      await BookingService.submitPaymentProof(booking.id, text: text);
      _resubmitCtrl.clear();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resubmit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resubmitting = false);
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
            '${_shortRef(booking.id)}',
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
          if (booking.status == BookingStatus.awaitingPayment) ...[
            const SizedBox(height: 12),
            if (booking.paymentRejectionReason != null)
              _resubmitForm(context)
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.hourglass_top_rounded,
                      size: 14, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Awaiting payment confirmation — the place admin will '
                      'review your submitted proof shortly.',
                      style: TextStyle(color: _P.textSec, fontSize: 12),
                    ),
                  ),
                ]),
              ),
          ],
          const SizedBox(height: 10),
          _messagesToggle(context),
          if (const {
            BookingStatus.pending,
            BookingStatus.awaitingPayment,
            BookingStatus.paymentSubmitted,
          }.contains(booking.status)) ...[
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

  Widget _resubmitForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded,
                size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Text('Payment rejected',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(booking.paymentRejectionReason!,
              style: TextStyle(color: _P.textSec, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _resubmitCtrl,
            style: TextStyle(color: _P.textPri, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'New payment reference / proof',
              hintStyle: TextStyle(color: _P.textMute),
              isDense: true,
              filled: true,
              fillColor: _P.overlay(0.06),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _resubmitting ? null : () => _resubmit(context),
              icon: _resubmitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 14),
              label: const Text('Resubmit', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: _P.aquaBright),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messagesToggle(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showMessages = !_showMessages),
          child: Row(children: [
            Icon(
                _showMessages
                    ? Icons.expand_less_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 16,
                color: _P.aquaBright),
            const SizedBox(width: 6),
            Text('Messages',
                style: TextStyle(
                    color: _P.aquaBright,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        if (_showMessages) ...[
          const SizedBox(height: 8),
          BookingMessageThread(bookingId: booking.id, isAdmin: false),
        ],
      ],
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
