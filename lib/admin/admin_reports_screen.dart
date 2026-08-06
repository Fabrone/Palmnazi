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
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
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
    final section = context.tr('admin_reports_csv_section_bookings');
    final trafficSection =
        context.tr('admin_reports_csv_section_visitor_traffic');
    final citySection =
        context.tr('admin_reports_csv_section_businesses_per_city');
    final channelSection =
        context.tr('admin_reports_csv_section_businesses_per_channel');
    final rows = <List<String>>[
      [
        context.tr('admin_reports_csv_header_section'),
        context.tr('admin_reports_csv_header_label'),
        context.tr('admin_reports_csv_header_value'),
      ],
      [section, context.tr('admin_reports_csv_label_total'), '${stats.total}'],
      [
        section,
        context.tr('admin_reports_csv_label_pending'),
        '${stats.pending}'
      ],
      [
        section,
        context.tr('admin_reports_csv_label_confirmed'),
        '${stats.confirmed}'
      ],
      [
        section,
        context.tr('admin_reports_csv_label_completed'),
        '${stats.completed}'
      ],
      [
        section,
        context.tr('admin_reports_csv_label_cancelled'),
        '${stats.cancelled}'
      ],
      [
        section,
        context.tr('admin_reports_csv_label_estimated_revenue'),
        stats.revenue.toStringAsFixed(2)
      ],
      [
        trafficSection,
        context.tr('admin_reports_csv_label_total_page_views'),
        '${views.fold<int>(0, (a, b) => a + b.count)}'
      ],
      for (final c in _cities) [citySection, c.name, '${c.totalPlaces}'],
      for (final c in _allCategories)
        [channelSection, c.name, '${c.placeLinksCount}'],
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
                    child: Text(context.tr('admin_reports_page_title'),
                        style: TextStyle(
                            color: AdC.textPri,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportCsv(stats, views),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: Text(context.tr('admin_reports_export_button')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdC.teal,
                      side: BorderSide(color: AdC.teal.withValues(alpha: 0.4)),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Bookings ──────────────────────────────────────────────
                Text(context.tr('admin_reports_bookings_heading'),
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(context.tr('admin_reports_bookings_subtitle'),
                    style: TextStyle(color: AdC.textMute, fontSize: 12)),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _StatCard(
                      label: context.tr('admin_reports_stat_total_bookings'),
                      value: '${stats.total}',
                      color: AdC.textSec),
                  _StatCard(
                      label: context.tr('admin_reports_csv_label_pending'),
                      value: '${stats.pending}',
                      color: AdC.orange),
                  _StatCard(
                      label: context.tr('admin_reports_csv_label_confirmed'),
                      value: '${stats.confirmed}',
                      color: AdC.teal),
                  _StatCard(
                      label: context.tr('admin_reports_csv_label_completed'),
                      value: '${stats.completed}',
                      color: AdC.green),
                  _StatCard(
                      label: context.tr('admin_reports_csv_label_cancelled'),
                      value: '${stats.cancelled}',
                      color: AdC.red),
                  _StatCard(
                      label: context.tr('admin_reports_stat_paid_via_mpesa'),
                      value: '${stats.paidViaMpesa}',
                      color: AdC.green),
                  _StatCard(
                      label:
                          context.tr('admin_reports_stat_simulated_payments'),
                      value: '${stats.simulatedPayments}',
                      color: AdC.textMute),
                  _StatCard(
                      label: context
                          .tr('admin_reports_csv_label_estimated_revenue'),
                      value: stats.revenue.toStringAsFixed(0),
                      color: const Color(0xFFFFD600)),
                ]),
                const SizedBox(height: 28),

                Text(context.tr('admin_reports_top_places_heading'),
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (stats.topPlaces.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(context.tr('admin_reports_no_bookings_yet'),
                        style: TextStyle(color: AdC.textMute, fontSize: 12)),
                  )
                else
                  ...stats.topPlaces.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RankRow(
                            label: e.key,
                            value:
                                '${e.value} ${e.value == 1 ? context.tr('admin_reports_booking_singular') : context.tr('admin_reports_booking_plural')}'),
                      )),

                const SizedBox(height: 32),

                // ── Visitor traffic ──────────────────────────────────────
                Text(context.tr('admin_reports_visitor_traffic_heading'),
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(context.tr('admin_reports_visitor_traffic_subtitle'),
                    style: TextStyle(color: AdC.textMute, fontSize: 11.5)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: views.length < 2
                      ? Center(
                          child: Text(
                              context.tr('admin_reports_traffic_not_enough'),
                              style:
                                  TextStyle(color: AdC.textMute, fontSize: 12)),
                        )
                      : _ViewsBarChart(views: views),
                ),

                const SizedBox(height: 32),

                // ── Businesses per city / channel ────────────────────────
                Text(
                    context.tr('admin_reports_csv_section_businesses_per_city'),
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_loadingCatalogue)
                  const AdminLoader()
                else if (_cities.isEmpty)
                  Text(context.tr('admin_reports_no_cities_yet'),
                      style: TextStyle(color: AdC.textMute, fontSize: 12))
                else
                  ...(_cities.toList()
                        ..sort(
                            (a, b) => b.totalPlaces.compareTo(a.totalPlaces)))
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RankRow(
                                label: c.name,
                                value:
                                    '${c.totalPlaces} ${c.totalPlaces == 1 ? context.tr('admin_reports_place_singular') : context.tr('admin_reports_place_plural')}'),
                          )),

                const SizedBox(height: 28),
                Text(
                    context
                        .tr('admin_reports_csv_section_businesses_per_channel'),
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_loadingCatalogue)
                  const AdminLoader()
                else if (_allCategories.isEmpty)
                  Text(context.tr('admin_reports_no_categories_yet'),
                      style: TextStyle(color: AdC.textMute, fontSize: 12))
                else
                  ...(_allCategories.toList()
                        ..sort((a, b) =>
                            b.placeLinksCount.compareTo(a.placeLinksCount)))
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RankRow(
                                label: c.name,
                                value:
                                    '${c.placeLinksCount} ${c.placeLinksCount == 1 ? context.tr('admin_reports_place_singular') : context.tr('admin_reports_place_plural')}'),
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
              FlLine(color: AdC.overlay(0.1), strokeWidth: 1),
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
                  style: TextStyle(color: AdC.textMute, fontSize: 10)),
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
                      style: TextStyle(color: AdC.textMute, fontSize: 10)),
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
              color: AdC.teal,
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
          color: AdC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdC.overlay(0.08)),
        ),
        child: Row(children: [
          Expanded(
            child:
                Text(label, style: TextStyle(color: AdC.textPri, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(
                  color: AdC.teal, fontSize: 12, fontWeight: FontWeight.w600)),
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
          color: AdC.surface,
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
            Text(label, style: TextStyle(color: AdC.textMute, fontSize: 12)),
          ],
        ),
      );
}
