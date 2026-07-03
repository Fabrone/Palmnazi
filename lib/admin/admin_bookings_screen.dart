import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/booking_model.dart';
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

  String _tabLabel(BookingStatus? s) =>
      s == null ? 'All' : BookingModel.statusLabel(s);

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
          const Text('Bookings',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Requests submitted by tourists from the place pages',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                  label: Text(_tabLabel(tab)),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = tab),
                  selectedColor: const Color(0xFF0D7377).withValues(alpha: 0.4),
                  backgroundColor: const Color(0xFF111827),
                  labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white54,
                      fontSize: 12),
                  side: BorderSide(
                      color:
                          selected ? const Color(0xFF0D7377) : Colors.white12),
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
                    title: 'No bookings',
                    body: _filter == null
                        ? 'Bookings submitted by tourists will show up here.'
                        : 'No ${_tabLabel(_filter).toLowerCase()} bookings.',
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
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(booking.placeName,
                  style: const TextStyle(
                      color: Colors.white,
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
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            if (booking.serviceName != null)
              _infoChip(Icons.room_service_outlined, booking.serviceName!),
            _infoChip(
                Icons.calendar_today_rounded,
                '${booking.requestedDate.day}/${booking.requestedDate.month}/${booking.requestedDate.year}'
                '${booking.checkOutDate != null ? ' – ${booking.checkOutDate!.day}/${booking.checkOutDate!.month}/${booking.checkOutDate!.year}' : ''}'),
            _infoChip(Icons.people_outline_rounded,
                '${booking.numberOfGuests} guest${booking.numberOfGuests == 1 ? '' : 's'}'),
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
                  '${booking.cancellationPolicy} cancellation'),
          ]),
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${booking.notes}"',
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
          if (booking.status == BookingStatus.pending ||
              booking.status == BookingStatus.confirmed) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (booking.status == BookingStatus.pending) ...[
                AdminOutlineBtn(
                  label: 'Confirm',
                  icon: Icons.check_rounded,
                  color: Colors.greenAccent,
                  onTap: () => BookingService.updateStatus(
                      booking.id, BookingStatus.confirmed),
                ),
                const SizedBox(width: 8),
              ],
              if (booking.status == BookingStatus.confirmed) ...[
                AdminOutlineBtn(
                  label: 'Mark Completed',
                  icon: Icons.done_all_rounded,
                  color: Colors.white54,
                  onTap: () => BookingService.updateStatus(
                      booking.id, BookingStatus.completed),
                ),
                const SizedBox(width: 8),
              ],
              AdminOutlineBtn(
                label: 'Cancel',
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
          Icon(icon, size: 12, color: const Color(0xFF14FFEC)),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      );
}
