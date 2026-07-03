import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_bookings_screen.dart';
import 'package:palmnazi/admin/booking_stats.dart';
import 'package:palmnazi/admin/admin_place_wizard_screen.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_query_model.dart';
import 'package:palmnazi/services/booking_service.dart';
import 'package:palmnazi/services/place_details_service.dart';
import 'package:palmnazi/services/payment_methods_service.dart';
import 'package:palmnazi/services/place_query_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceAdminPanel
//
// The place-scoped counterpart to AdminDashboard. A plain 'Admin' is limited
// to exactly one place (Users/{uid}.managedPlaceId — see rbac_service.dart);
// this panel is everything they can see and do:
//   Overview  — booking stats for this place only
//   Bookings  — AdminBookingsScreen(placeId: …), reusing the existing screen
//   Details   — AdminPlaceWizardScreen(existingPlace: …) in edit mode
//   Payments  — pick which of the MainAdmin-configured global payment
//               methods this place accepts (Place_details.paymentMethods)
//   Queries   — tourist questions about this place (see place_queries later)
//
// admin_dashboard.dart embeds this directly (full-bleed, no back button) when
// role == 'Admin', and pushes it as its own route (with a back button) when
// MainAdmin opens "Place Admin" for a place they've chosen to inspect.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceAdminPanel extends StatefulWidget {
  final String placeId;
  final String placeName;
  final String cityName;

  /// True when pushed as its own route by MainAdmin (shows a back button);
  /// false when it IS the whole app for a place-scoped Admin (shows
  /// "Back to App" instead, matching AdminDashboard's sidebar convention).
  final bool isMainAdminView;

  const PlaceAdminPanel({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.cityName,
    this.isMainAdminView = false,
  });

  @override
  State<PlaceAdminPanel> createState() => _PlaceAdminPanelState();
}

class _PlaceAdminPanelState extends State<PlaceAdminPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _apiService = AdminApiService();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        leading: widget.isMainAdminView
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white54, size: 20),
                tooltip: 'Back to App',
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.placeName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(widget.cityName,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: const Color(0xFF14FFEC),
          labelColor: const Color(0xFF14FFEC),
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Bookings'),
            Tab(text: 'Place Details'),
            Tab(text: 'Payment Methods'),
            Tab(text: 'Queries'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(placeId: widget.placeId),
          AdminBookingsScreen(placeId: widget.placeId),
          _PlaceDetailsTab(
            placeId: widget.placeId,
            placeName: widget.placeName,
            apiService: _apiService,
          ),
          _PaymentMethodsTab(placeId: widget.placeId),
          _QueriesTab(placeId: widget.placeId),
        ],
      ),
    );
  }
}

// ── Overview ─────────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final String placeId;
  const _OverviewTab({required this.placeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: BookingService.streamForPlace(placeId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AdminLoader();
        }
        final bookings = snap.data ?? const [];
        final stats = BookingStats.from(bookings);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Bookings Overview',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _StatTile(
                  label: 'Total',
                  value: '${stats.total}',
                  color: Colors.white70),
              _StatTile(
                  label: 'Pending',
                  value: '${stats.pending}',
                  color: const Color(0xFFFF9800)),
              _StatTile(
                  label: 'Confirmed',
                  value: '${stats.confirmed}',
                  color: const Color(0xFF14FFEC)),
              _StatTile(
                  label: 'Completed',
                  value: '${stats.completed}',
                  color: const Color(0xFF00C853)),
              _StatTile(
                  label: 'Cancelled',
                  value: '${stats.cancelled}',
                  color: const Color(0xFFCF6679)),
              _StatTile(
                  label: 'Paid via M-Pesa',
                  value: '${stats.paidViaMpesa}',
                  color: const Color(0xFF00C853)),
              _StatTile(
                  label: 'Estimated Revenue',
                  value: stats.revenue.toStringAsFixed(0),
                  color: const Color(0xFFFFD600)),
            ]),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
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

// ── Place Details ────────────────────────────────────────────────────────────
class _PlaceDetailsTab extends StatefulWidget {
  final String placeId;
  final String placeName;
  final AdminApiService apiService;
  const _PlaceDetailsTab({
    required this.placeId,
    required this.placeName,
    required this.apiService,
  });

  @override
  State<_PlaceDetailsTab> createState() => _PlaceDetailsTabState();
}

class _PlaceDetailsTabState extends State<_PlaceDetailsTab> {
  bool _loading = false;
  String? _error;

  Future<void> _openWizard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiService.getPlaceById(widget.placeId),
        widget.apiService.getCities(),
        widget.apiService.getCategoryTree(),
      ]);
      if (!mounted) return;
      setState(() => _loading = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdminPlaceWizardScreen(
          apiService: widget.apiService,
          cities: results[1] as List<CityModel>,
          categories: results[2] as List<CategoryModel>,
          existingPlace: results[0] as PlaceModel,
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load place details: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_location_alt_rounded,
                color: Color(0xFF14FFEC), size: 48),
            const SizedBox(height: 16),
            Text('Edit ${widget.placeName}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Update photos, description, pricing, booking settings and everything else about this place.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFCF6679), fontSize: 12)),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _loading ? null : _openWizard,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF0A1128)))
                  : const Icon(Icons.edit_rounded, size: 16),
              label: Text(_loading ? 'Loading…' : 'Edit Place Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14FFEC),
                foregroundColor: const Color(0xFF0A1128),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payment Methods ──────────────────────────────────────────────────────────
class _PaymentMethodsTab extends StatefulWidget {
  final String placeId;
  const _PaymentMethodsTab({required this.placeId});

  @override
  State<_PaymentMethodsTab> createState() => _PaymentMethodsTabState();
}

class _PaymentMethodsTabState extends State<_PaymentMethodsTab> {
  bool _loading = true;
  bool _saving = false;
  List<PaymentMethodModel> _allMethods = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      PaymentMethodsService.getActive(),
      PlaceDetailsService.getPlaceDetails(widget.placeId),
    ]);
    if (!mounted) return;
    final methods = results[0] as List<PaymentMethodModel>;
    final details = results[1] as Map<String, dynamic>?;
    final existing = List<String>.from(
        details?['paymentMethods'] as List<dynamic>? ?? const []);
    setState(() {
      _allMethods = methods;
      _selectedIds
        ..clear()
        ..addAll(existing);
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await PlaceDetailsService.savePaymentMethods(
        widget.placeId, _selectedIds.toList());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payment methods updated.'),
        backgroundColor: Color(0xFF0D7377),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminLoader();
    if (_allMethods.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.payments_outlined,
        title: 'No payment methods configured',
        body:
            'Ask a MainAdmin to add payment methods in the system-wide catalogue first.',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accepted Payment Methods',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Choose which of the platform\'s configured payment methods this place accepts.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _allMethods.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = _allMethods[i];
                final selected = _selectedIds.contains(m.id);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedIds.add(m.id);
                    } else {
                      _selectedIds.remove(m.id);
                    }
                  }),
                  activeColor: const Color(0xFF14FFEC),
                  checkColor: const Color(0xFF0A1128),
                  tileColor: const Color(0xFF111827),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  title: Text(m.name,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text(PaymentMethodModel.typeLabel(m.type),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14FFEC),
                foregroundColor: const Color(0xFF0A1128),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Queries ───────────────────────────────────────────────────────────────
class _QueriesTab extends StatelessWidget {
  final String placeId;
  const _QueriesTab({required this.placeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlaceQueryModel>>(
      stream: PlaceQueryService.streamForPlace(placeId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AdminLoader();
        }
        final queries = snap.data ?? const <PlaceQueryModel>[];
        if (queries.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.question_answer_outlined,
            title: 'No questions yet',
            body: 'Tourist questions about this place will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: queries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _QueryTile(query: queries[i]),
        );
      },
    );
  }
}

class _QueryTile extends StatefulWidget {
  final PlaceQueryModel query;
  const _QueryTile({required this.query});

  @override
  State<_QueryTile> createState() => _QueryTileState();
}

class _QueryTileState extends State<_QueryTile> {
  final _replyCtrl = TextEditingController();
  bool _replying = false;
  bool _sending = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final reply = _replyCtrl.text.trim();
    if (reply.isEmpty) return;
    setState(() => _sending = true);
    final me = FirebaseAuth.instance.currentUser;
    await PlaceQueryService.reply(
      queryId: widget.query.id,
      reply: reply,
      repliedBy: me?.email ?? me?.uid ?? '',
    );
    if (mounted) {
      setState(() {
        _sending = false;
        _replying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final answered = q.status == PlaceQueryStatus.answered;
    final statusColor =
        answered ? const Color(0xFF00C853) : const Color(0xFFFF9800);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(q.userEmail,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(answered ? 'ANSWERED' : 'OPEN',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(q.message,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (answered && q.adminReply != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Your reply: ${q.adminReply}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ] else if (_replying) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _replyCtrl,
              maxLines: 3,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Type your reply…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _sending ? null : _sendReply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14FFEC),
                  foregroundColor: const Color(0xFF0A1128),
                ),
                child: Text(_sending ? 'Sending…' : 'Send Reply'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _replying = true),
                icon: const Icon(Icons.reply_rounded,
                    size: 16, color: Color(0xFF14FFEC)),
                label: const Text('Reply',
                    style: TextStyle(color: Color(0xFF14FFEC))),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
