import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminBookingsScreen
//
// Read/manage view over the Bookings collection (Firestore) created by
// tourists from PlaceDetailsScreen's "Book Now" flow (see booking_screen.dart
// and BookingService). Admin/MainAdmin can confirm, cancel, or complete a
// booking; tourists manage their own pending bookings from
// lib/screens/my_bookings_screen.dart.
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
                return ListView.separated(
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _BookingRow(booking: bookings[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final BookingModel booking;
  const _BookingRow({required this.booking});

  Color get _statusColor {
    switch (booking.status) {
      case BookingStatus.pending:
        return Colors.orangeAccent;
      case BookingStatus.confirmed:
        return Colors.greenAccent;
      case BookingStatus.cancelled:
        return Colors.redAccent;
      case BookingStatus.completed:
        return AdC.textMute;
    }
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
              '${(booking.id.length > 8 ? booking.id.substring(booking.id.length - 8) : booking.id).toUpperCase()}',
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

  Widget _infoChip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AdC.teal),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: AdC.textMute, fontSize: 11)),
        ],
      );
}
