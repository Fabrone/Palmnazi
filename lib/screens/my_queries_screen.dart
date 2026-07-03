import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/place_query_model.dart';
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
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
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
        title:
            const Text('My Questions', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: uid == null
          ? const Center(
              child: Text('Sign in to view your questions.',
                  style: TextStyle(color: Colors.white54)))
          : StreamBuilder<List<PlaceQueryModel>>(
              stream: PlaceQueryService.streamForUser(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _P.aquaBright));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load questions: ${snap.error}',
                        style: const TextStyle(color: Colors.white54)),
                  );
                }
                final queries = snap.data ?? const <PlaceQueryModel>[];
                if (queries.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No questions yet. Tap "Enquire" on a place to ask one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
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
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(query.placeName,
                  style: const TextStyle(
                      color: Colors.white,
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
                answered ? 'ANSWERED' : 'PENDING',
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(query.message,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
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
