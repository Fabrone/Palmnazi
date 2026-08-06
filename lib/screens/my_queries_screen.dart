import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/place_query_model.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/place_query_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyQueriesScreen
//
// Lists the signed-in tourist's own questions about places (Firestore
// PlaceQueries collection, filtered by firebaseUid via Firestore security
// rules) and any admin reply. Reachable from AccountScreen. Read-only — a
// tourist asks a new question from place_details_screen.dart's "Ask a
// Question" / "Enquire" action, not from here.
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

class MyQueriesScreen extends StatelessWidget {
  const MyQueriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: AppBar(
        backgroundColor: _P.deepNavy,
        title: Text(context.tr('account_my_queries'),
            style: TextStyle(color: _P.textPri)),
        iconTheme: IconThemeData(color: _P.textPri),
      ),
      body: uid == null
          ? Center(
              child: Text(context.tr('my_queries_signin_required'),
                  style: TextStyle(color: _P.textMute)))
          : StreamBuilder<List<PlaceQueryModel>>(
              stream: PlaceQueryService.streamForUser(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _P.aquaBright));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                        '${context.tr('my_queries_error_load_prefix')} ${snap.error}',
                        style: TextStyle(color: _P.textMute)),
                  );
                }
                final queries = snap.data ?? const <PlaceQueryModel>[];
                if (queries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.tr('my_queries_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _P.textMute),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: queries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _QueryCard(query: queries[i]),
                );
              },
            ),
    );
  }
}

class _QueryCard extends StatelessWidget {
  final PlaceQueryModel query;
  const _QueryCard({required this.query});

  @override
  Widget build(BuildContext context) {
    final answered = query.status == PlaceQueryStatus.answered;
    final statusColor = answered ? Colors.greenAccent : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _P.overlay(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(query.placeName,
                  style: TextStyle(
                      color: _P.textPri,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                answered
                    ? context.tr('my_queries_status_answered')
                    : context.tr('my_queries_status_pending'),
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(query.message,
              style: TextStyle(color: _P.textSec, fontSize: 13)),
          if (answered && query.adminReply != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.reply_rounded,
                      size: 16, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(query.adminReply!,
                        style: TextStyle(color: _P.textPri, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
