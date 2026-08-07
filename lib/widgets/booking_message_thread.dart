import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/services/booking_message_service.dart';
import 'package:palmnazi/theme/rc_palette.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingMessageThread
//
// Reusable two-way chat panel mounted on a single booking, in both
// my_bookings_screen.dart (tourist side) and admin_bookings_screen.dart
// (admin side) — same widget, `isAdmin` just controls which side "my
// messages" render on and what role gets stamped on a sent message.
// ─────────────────────────────────────────────────────────────────────────────
class BookingMessageThread extends StatefulWidget {
  final String bookingId;
  final bool isAdmin;

  const BookingMessageThread({
    super.key,
    required this.bookingId,
    required this.isAdmin,
  });

  @override
  State<BookingMessageThread> createState() => _BookingMessageThreadState();
}

class _BookingMessageThreadState extends State<BookingMessageThread> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await BookingMessageService.send(widget.bookingId,
          text: text, isAdmin: widget.isAdmin);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      decoration: BoxDecoration(
        color: RC.overlay(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RC.overlay(0.10)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: StreamBuilder<List<BookingMessageModel>>(
              stream: BookingMessageService.stream(widget.bookingId),
              builder: (context, snap) {
                final messages = snap.data ?? const <BookingMessageModel>[];
                if (messages.isEmpty) {
                  return Center(
                    child: Text('No messages yet — say hello.',
                        style: TextStyle(color: RC.textMute, fontSize: 12)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final mine = m.senderUid == myUid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: const BoxConstraints(maxWidth: 260),
                        decoration: BoxDecoration(
                          color: mine
                              ? RC.gold.withValues(alpha: 0.18)
                              : RC.overlay(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.senderRole == 'admin' ? 'Host' : 'Tourist',
                              style: TextStyle(
                                  color: RC.textMute,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(m.text,
                                style:
                                    TextStyle(color: RC.textPri, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1, color: RC.overlay(0.10)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: RC.textPri, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(color: RC.textMute),
                    isDense: true,
                    filled: true,
                    fillColor: RC.overlay(0.06),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _sending
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: RC.gold),
                      )
                    : Icon(Icons.send_rounded, color: RC.gold),
                onPressed: _sending ? null : _send,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
