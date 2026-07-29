import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/admin/booking_stats.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/services/booking_service.dart';
import 'package:palmnazi/services/page_view_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminReportsScreen
//
// System-wide analytics for MainAdmin:
//   • Bookings — BookingStats aggregator (unchanged from the original build)
//   • Visitor traffic — PageViewService's self-owned daily counter (GA4 data
//     itself isn't readable back from a Flutter client; see AnalyticsService)
//   • Businesses per city / per channel — CityModel.totalPlaces and
//     CategoryModel.placeLinksCount, both already returned by the existing
//     /api/cities and /api/categories endpoints, no new backend calls needed
//   • CSV export of everything on this screen
// Read-only; nothing here writes anything except the export file.
// ─────────────────────────────────────────────────────────────────────────────

const _kSurface = Color(0xFF111827);
const _kTeal = Color(0xFF14FFEC);

class AdminReportsScreen extends StatefulWidget {
  final AdminApiService apiService;
  const AdminReportsScreen({super.key, required this.apiService});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<CityModel> _cities = [];
  List<CategoryModel> _rootCategories = [];
  bool _loadingCatalogue = true;

  @override
  void initState() {
    super.initState();
    _loadCatalogue();
  }

  Future<void> _loadCatalogue() async {
    try {
      final results = await Future.wait([
        widget.apiService.getCities(),
        widget.apiService.getCategoryTree(),
      ]);
      if (mounted) {
        setState(() {
          _cities = results[0] as List<CityModel>;
          _rootCategories = results[1] as List<CategoryModel>;
          _loadingCatalogue = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCatalogue = false);
    }
  }

  // Flattens root + child categories into one list with their own
  // placeLinksCount, so a channel's subcategories aren't hidden from the
  // "businesses per channel" report.
  List<CategoryModel> get _allCategories => [
        for (final root in _rootCategories) ...[root, ...root.children],
      ];

  Future<void> _exportCsv(
      BookingStats stats, List<DailyPageViews> views) async {
    final rows = <List<String>>[
      ['Section', 'Label', 'Value'],
      ['Bookings', 'Total', '${stats.total}'],
      ['Bookings', 'Pending', '${stats.pending}'],
      ['Bookings', 'Confirmed', '${stats.confirmed}'],
      ['Bookings', 'Completed', '${stats.completed}'],
      ['Bookings', 'Cancelled', '${stats.cancelled}'],
      ['Bookings', 'Estimated Revenue', stats.revenue.toStringAsFixed(2)],
      [
        'Visitor Traffic',
        'Total Page Views (30d)',
        '${views.fold<int>(0, (a, b) => a + b.count)}'
      ],
      for (final c in _cities)
        ['Businesses per City', c.name, '${c.totalPlaces}'],
      for (final c in _allCategories)
        ['Businesses per Channel', c.name, '${c.placeLinksCount}'],
    ];
    final csv = rows
        .map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(','))
        .join('\n');
    final fileName =
        'palmnazi-reports-${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
    await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(csv));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingModel>>(
      stream: BookingService.streamAll(),
      builder: (context, bookingSnap) {
        if (bookingSnap.connectionState == ConnectionState.waiting) {
          return const AdminLoader();
        }
        if (bookingSnap.hasError) {
          return AdminErrorView(
              error: bookingSnap.error.toString(), onRetry: () {});
        }
        final bookings = bookingSnap.data ?? const [];
        final stats = BookingStats.from(bookings, withTopPlaces: true);

        return StreamBuilder<List<DailyPageViews>>(
          stream: PageViewService.streamRecent(),
          builder: (context, viewSnap) {
            final views = viewSnap.data ?? const <DailyPageViews>[];

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Reports',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportCsv(stats, views),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: BorderSide(color: _kTeal.withValues(alpha: 0.4)),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Bookings ──────────────────────────────────────────────
                const Text('Bookings — System Wide',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
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
                      color: _kTeal),
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
                        child: _RankRow(
                            label: e.key,
                            value:
                                '${e.value} booking${e.value == 1 ? '' : 's'}'),
                      )),

                const SizedBox(height: 32),

                // ── Visitor traffic ──────────────────────────────────────
                const Text('Visitor Traffic — Last 30 Days',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                    'Landing page loads, tracked by this app (a separate '
                    'copy is also sent to Google Analytics — GA4 data '
                    'itself isn\'t readable back from the app).',
                    style: TextStyle(color: Colors.white38, fontSize: 11.5)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: views.length < 2
                      ? const Center(
                          child: Text(
                              'Not enough traffic history yet — check back '
                              'after a few days.',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        )
                      : _ViewsBarChart(views: views),
                ),

                const SizedBox(height: 32),

                // ── Businesses per city / channel ────────────────────────
                const Text('Businesses per City',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_loadingCatalogue)
                  const AdminLoader()
                else if (_cities.isEmpty)
                  const Text('No resort cities yet.',
                      style: TextStyle(color: Colors.white38, fontSize: 12))
                else
                  ...(_cities.toList()
                        ..sort(
                            (a, b) => b.totalPlaces.compareTo(a.totalPlaces)))
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RankRow(
                                label: c.name,
                                value:
                                    '${c.totalPlaces} place${c.totalPlaces == 1 ? '' : 's'}'),
                          )),

                const SizedBox(height: 28),
                const Text('Businesses per Channel',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_loadingCatalogue)
                  const AdminLoader()
                else if (_allCategories.isEmpty)
                  const Text('No categories yet.',
                      style: TextStyle(color: Colors.white38, fontSize: 12))
                else
                  ...(_allCategories.toList()
                        ..sort((a, b) =>
                            b.placeLinksCount.compareTo(a.placeLinksCount)))
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RankRow(
                                label: c.name,
                                value:
                                    '${c.placeLinksCount} place${c.placeLinksCount == 1 ? '' : 's'}'),
                          )),
              ],
            );
          },
        );
      },
    );
  }
}

class _ViewsBarChart extends StatelessWidget {
  final List<DailyPageViews> views;
  const _ViewsBarChart({required this.views});

  @override
  Widget build(BuildContext context) {
    final maxY = views.fold<int>(1, (m, v) => v.count > m ? v.count : m);
    return BarChart(
      BarChartData(
        maxY: (maxY * 1.2).ceilToDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, meta) => Text('${v.toInt()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (views.length / 4).clamp(1, views.length).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= views.length) return const SizedBox.shrink();
                final d = views[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.day}/${d.month}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(
          views.length,
          (i) => BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: views[i].count.toDouble(),
              color: _kTeal,
              width: (600 / views.length).clamp(3, 14).toDouble(),
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final String label;
  final String value;
  const _RankRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(
                  color: _kTeal, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
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
          color: _kSurface,
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
