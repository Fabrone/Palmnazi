import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';
import 'package:palmnazi/widgets/booking_message_thread.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminBookingsScreen
//
// Read/manage view over the Bookings collection (Firestore) created by
// tourists from PlaceDetailsScreen's "Book Now" flow (see booking_screen.dart
// and BookingService). Admin/MainAdmin can confirm, cancel, or complete a
// booking, review submitted payment proof, and message the tourist; tourists
// manage their own bookings from lib/screens/my_bookings_screen.dart.
//
// Bookings created together from one multi-service checkout share a
// `bookingGroupId` (see BookingService.createGroup) — those render as one
// grouped section with a shared reference header; every other booking
// renders exactly as a standalone row, unchanged from before.
// ─────────────────────────────────────────────────────────────────────────────

class AdminBookingsScreen extends StatefulWidget {
  /// When set, shows only this place's bookings (Place Admin Panel usage) via
  /// BookingService.streamForPlace — required for a place-scoped Admin's
  /// query to satisfy firestore.rules. Null shows every booking (MainAdmin).
  final String? placeId;

  const AdminBookingsScreen({super.key, this.placeId});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  BookingStatus? _filter;

  static const _tabs = <BookingStatus?>[
    null,
    BookingStatus.pending,
    BookingStatus.awaitingPayment,
    BookingStatus.paymentSubmitted,
    BookingStatus.confirmed,
    BookingStatus.completed,
    BookingStatus.cancelled,
  ];

  String _tabLabel(BuildContext context, BookingStatus? s) => s == null
      ? context.tr('category_subcat_all')
      : BookingModel.statusLabel(s);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isNarrow = mq.size.width < 480;
    final hPad = isNarrow ? 12.0 : 24.0;
    final vPad = isNarrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('admin_bookings_page_title'),
              style: TextStyle(
                  color: AdC.textPri,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(context.tr('admin_bookings_page_subtitle'),
              style: TextStyle(color: AdC.textMute, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final tab = _tabs[i];
                final selected = _filter == tab;
                return ChoiceChip(
                  label: Text(_tabLabel(context, tab)),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = tab),
                  selectedColor: AdC.tealDark.withValues(alpha: 0.4),
                  backgroundColor: AdC.surface,
                  labelStyle: TextStyle(
                      color: selected ? AdC.textPri : AdC.textMute,
                      fontSize: 12),
                  side: BorderSide(
                      color: selected ? AdC.tealDark : AdC.overlay(0.12)),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<BookingModel>>(
              stream: widget.placeId != null
                  ? BookingService.streamForPlace(widget.placeId!)
                  : BookingService.streamAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const AdminLoader();
                }
                if (snap.hasError) {
                  return AdminErrorView(
                      error: snap.error.toString(), onRetry: () {});
                }
                final all = snap.data ?? const <BookingModel>[];
                final bookings = _filter == null
                    ? all
                    : all.where((b) => b.status == _filter).toList();
                if (bookings.isEmpty) {
                  return AdminEmptyState(
                    icon: Icons.calendar_month_rounded,
                    title: context.tr('admin_bookings_empty_title'),
                    body: _filter == null
                        ? context.tr('admin_bookings_empty_body_all')
                        : '${context.tr('admin_bookings_empty_filtered_prefix')} '
                            '${_tabLabel(context, _filter).toLowerCase()} '
                            '${context.tr('admin_bookings_empty_filtered_suffix')}',
                  );
                }
                final groups = _groupBookings(bookings);
                return ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _BookingGroupSection(group: groups[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Short, uppercased tail of a Firestore doc id — same truncation pattern
/// used throughout (see booking_screen.dart's post-booking success dialog).
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

class _BookingGroupSection extends StatelessWidget {
  final List<BookingModel> group;
  const _BookingGroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    if (group.length <= 1) {
      return _BookingRow(booking: group.first);
    }
    final groupId = group.first.bookingGroupId ?? group.first.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(children: [
            Icon(Icons.layers_rounded, size: 15, color: AdC.teal),
            const SizedBox(width: 6),
            Text(
              'Booking #${_shortRef(groupId)} — ${group.length} services',
              style: TextStyle(
                  color: AdC.textPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        for (var i = 0; i < group.length; i++) ...[
          _BookingRow(booking: group[i]),
          if (i != group.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BookingRow extends StatefulWidget {
  final BookingModel booking;
  const _BookingRow({required this.booking});

  @override
  State<_BookingRow> createState() => _BookingRowState();
}

class _BookingRowState extends State<_BookingRow> {
  bool _showMessages = false;

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
        return AdC.textMute;
    }
  }

  Future<void> _approve() async {
    try {
      await BookingService.approvePayment(booking.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not approve: $e')));
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdC.surface,
        title:
            Text('Reject payment proof', style: TextStyle(color: AdC.textPri)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: TextStyle(color: AdC.textPri),
          decoration: InputDecoration(
            hintText: 'Reason (shown to the tourist)',
            hintStyle: TextStyle(color: AdC.textMute),
            filled: true,
            fillColor: AdC.overlay(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('common_cancel'),
                style: TextStyle(color: AdC.textMute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child:
                const Text('Reject', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) {
      try {
        await BookingService.rejectPayment(booking.id, reason);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Could not reject: $e')));
        }
      }
    }
  }

  void _viewProofImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AdC.surface,
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(booking.placeName,
                  style: TextStyle(
                      color: AdC.textPri,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(BookingModel.statusLabel(booking.status),
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${booking.cityName} · ${booking.userEmail}',
            style: TextStyle(color: AdC.textMute, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _infoChip(
              Icons.confirmation_number_outlined,
              '${context.tr('admin_bookings_reference_prefix')} '
              '${_shortRef(booking.id)}',
            ),
            if (booking.serviceName != null)
              _infoChip(Icons.room_service_outlined, booking.serviceName!),
            _infoChip(
                Icons.calendar_today_rounded,
                '${booking.requestedDate.day}/${booking.requestedDate.month}/${booking.requestedDate.year}'
                '${booking.checkOutDate != null ? ' – ${booking.checkOutDate!.day}/${booking.checkOutDate!.month}/${booking.checkOutDate!.year}' : ''}'),
            _infoChip(Icons.people_outline_rounded,
                '${booking.numberOfGuests} ${booking.numberOfGuests == 1 ? context.tr('admin_bookings_guest_singular') : context.tr('admin_bookings_guest_plural')}'),
            if (booking.paymentMethodName != null)
              _infoChip(Icons.payments_outlined, booking.paymentMethodName!),
            if (booking.totalAmount != null)
              _infoChip(Icons.receipt_long_rounded,
                  '${booking.currency ?? ''} ${booking.totalAmount!.toStringAsFixed(0)}'),
            if (booking.mpesaReceiptNumber != null)
              _infoChip(Icons.check_circle_outline_rounded,
                  'M-Pesa: ${booking.mpesaReceiptNumber}'),
            if (booking.cancellationPolicy != null)
              _infoChip(Icons.policy_outlined,
                  '${booking.cancellationPolicy} ${context.tr('admin_bookings_cancellation_suffix')}'),
          ]),
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${booking.notes}"',
                style: TextStyle(
                    color: AdC.textMute,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
          if (booking.status == BookingStatus.awaitingPayment) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    'Waiting for tourist to submit payment proof.',
                    style: TextStyle(color: AdC.textSec, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ],
          if (booking.status == BookingStatus.paymentSubmitted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdC.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdC.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Submitted payment proof',
                      style: TextStyle(
                          color: AdC.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  if (booking.paymentProofText != null &&
                      booking.paymentProofText!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(booking.paymentProofText!,
                        style: TextStyle(color: AdC.textSec, fontSize: 12)),
                  ],
                  if (booking.paymentProofImageUrl != null) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _viewProofImage(
                          context, booking.paymentProofImageUrl!),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.image_outlined, size: 14, color: AdC.blue),
                        const SizedBox(width: 4),
                        Text('View attached image',
                            style: TextStyle(
                                color: AdC.blue,
                                fontSize: 11,
                                decoration: TextDecoration.underline)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    AdminOutlineBtn(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      color: Colors.greenAccent,
                      onTap: _approve,
                    ),
                    const SizedBox(width: 8),
                    AdminOutlineBtn(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      color: Colors.redAccent,
                      onTap: () => _reject(context),
                    ),
                  ]),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _messagesToggle(context),
          if (booking.status == BookingStatus.pending ||
              booking.status == BookingStatus.confirmed) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (booking.status == BookingStatus.pending) ...[
                AdminOutlineBtn(
                  label: context.tr('admin_bookings_btn_confirm'),
                  icon: Icons.check_rounded,
                  color: Colors.greenAccent,
                  onTap: () => BookingService.updateStatus(
                      booking.id, BookingStatus.confirmed),
                ),
                const SizedBox(width: 8),
              ],
              if (booking.status == BookingStatus.confirmed) ...[
                AdminOutlineBtn(
                  label: context.tr('admin_bookings_btn_mark_completed'),
                  icon: Icons.done_all_rounded,
                  color: AdC.textMute,
                  onTap: () => BookingService.updateStatus(
                      booking.id, BookingStatus.completed),
                ),
                const SizedBox(width: 8),
              ],
              AdminOutlineBtn(
                label: context.tr('common_cancel'),
                icon: Icons.close_rounded,
                color: Colors.redAccent,
                onTap: () => BookingService.updateStatus(
                    booking.id, BookingStatus.cancelled),
              ),
            ]),
          ],
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _showMessages
                    ? Icons.expand_less_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 15,
                color: AdC.teal),
            const SizedBox(width: 6),
            Text('Messages',
                style: TextStyle(
                    color: AdC.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        if (_showMessages) ...[
          const SizedBox(height: 8),
          BookingMessageThread(bookingId: booking.id, isAdmin: true),
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AdC.teal),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: AdC.textMute, fontSize: 11)),
        ],
      );
}
