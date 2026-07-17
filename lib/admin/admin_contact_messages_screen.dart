import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/contact_message_model.dart';
import 'package:palmnazi/services/contact_message_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminContactMessagesScreen
//
// Read-only inbox for the landing page footer's "Contact Us" submissions
// (Firestore ContactMessages collection). Visible only to MainAdmin —
// routing guard lives in AdminDashboard, and firestore.rules restricts read
// access the same way. No reply workflow in this pass; an admin who wants to
// respond copies the sender's email and replies externally.
// ─────────────────────────────────────────────────────────────────────────────

const _kSurface = Color(0xFF111827);
const _kGold = Color(0xFFD4AF37);

class AdminContactMessagesScreen extends StatelessWidget {
  const AdminContactMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isNarrow = mq.size.width < 480;
    final hPad = isNarrow ? 12.0 : 24.0;
    final vPad = isNarrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: StreamBuilder<List<ContactMessageModel>>(
        stream: ContactMessageService.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AdminLoader();
          }
          if (snap.hasError) {
            return AdminErrorView(
              error: 'Could not load messages: ${snap.error}',
              onRetry: () {},
            );
          }
          final messages = snap.data ?? const <ContactMessageModel>[];
          if (messages.isEmpty) {
            return const AdminEmptyState(
              icon: Icons.mail_outline_rounded,
              title: 'No messages yet',
              body:
                  'Submissions from the landing page\'s "Contact Us" form will '
                  'show up here.',
            );
          }
          return ListView.separated(
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _MessageCard(message: messages[i]),
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final ContactMessageModel message;
  const _MessageCard({required this.message});

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: _kGold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Text(_formatDate(message.createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.email_outlined, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(message.email,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: Colors.white38, size: 16),
                tooltip: 'Copy email',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.email));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email copied')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message.message,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
