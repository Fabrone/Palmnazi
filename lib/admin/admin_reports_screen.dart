import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/admin/booking_stats.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/services/booking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminReportsScreen
//
// System-wide analytics for MainAdmin — the "Reports" section asked for
// alongside the place-scoping work. Built on BookingService.streamAll() via
// the shared BookingStats aggregator (see booking_stats.dart), the same one
// that powers each Place Admin Panel's per-place Overview tab. Read-only;
// nothing here writes anything.
// ─────────────────────────────────────────────────────────────────────────────

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingModel>>(
      stream: BookingService.streamAll(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AdminLoader();
        }
        if (snap.hasError) {
          return AdminErrorView(error: snap.error.toString(), onRetry: () {});
        }
        final bookings = snap.data ?? const [];
        final stats = BookingStats.from(bookings, withTopPlaces: true);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Bookings — System Wide',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Live totals across every place on the platform.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _StatCard(
                  label: 'Total Bookings',
                  value: '${stats.total}',
                  color: Colors.white70),
              _StatCard(
                  label: 'Pending',
                  value: '${stats.pending}',
                  color: const Color(0xFFFF9800)),
              _StatCard(
                  label: 'Confirmed',
                  value: '${stats.confirmed}',
                  color: const Color(0xFF14FFEC)),
              _StatCard(
                  label: 'Completed',
                  value: '${stats.completed}',
                  color: const Color(0xFF00C853)),
              _StatCard(
                  label: 'Cancelled',
                  value: '${stats.cancelled}',
                  color: const Color(0xFFCF6679)),
              _StatCard(
                  label: 'Paid via M-Pesa',
                  value: '${stats.paidViaMpesa}',
                  color: const Color(0xFF00C853)),
              _StatCard(
                  label: 'Simulated Payments',
                  value: '${stats.simulatedPayments}',
                  color: Colors.white54),
              _StatCard(
                  label: 'Estimated Revenue',
                  value: stats.revenue.toStringAsFixed(0),
                  color: const Color(0xFFFFD600)),
            ]),
            const SizedBox(height: 28),
            const Text('Top Places by Bookings',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (stats.topPlaces.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No bookings yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              )
            else
              ...stats.topPlaces.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ),
                        Text('${e.value} booking${e.value == 1 ? '' : 's'}',
                            style: const TextStyle(
                                color: Color(0xFF14FFEC),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
}
