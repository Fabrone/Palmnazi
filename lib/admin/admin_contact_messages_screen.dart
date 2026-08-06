import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/contact_message_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
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
              error:
                  '${context.tr('admin_contact_messages_error_load_prefix')} ${snap.error}',
              onRetry: () {},
            );
          }
          final messages = snap.data ?? const <ContactMessageModel>[];
          if (messages.isEmpty) {
            return AdminEmptyState(
              icon: Icons.mail_outline_rounded,
              title: context.tr('admin_contact_messages_empty_title'),
              body: context.tr('admin_contact_messages_empty_body'),
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
        color: AdC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdC.overlay(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  color: AdC.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message.name,
                    style: TextStyle(
                        color: AdC.textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Text(_formatDate(message.createdAt),
                  style: TextStyle(color: AdC.textMute, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.email_outlined, color: AdC.textMute, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(message.email,
                    style: TextStyle(color: AdC.textMute, fontSize: 12)),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: AdC.textMute, size: 16),
                tooltip:
                    context.tr('admin_contact_messages_copy_email_tooltip'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.email));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            context.tr('admin_contact_messages_email_copied'))),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message.message,
              style: TextStyle(color: AdC.textSec, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
