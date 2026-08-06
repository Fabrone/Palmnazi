import 'package:flutter/material.dart';
import 'package:palmnazi/services/booking_notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationBell
//
// Mounted in PalmnaziNavBar's signed-in slot. Shows an unread-count badge fed
// by BookingNotificationService.unreadCountStream, and opens a dropdown panel
// listing recent booking notifications (new booking → admins, status change →
// tourist) on tap. Tapping an entry marks it read; entries render whether
// read or not, most-recent first.
// ─────────────────────────────────────────────────────────────────────────────
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = BookingNotificationService.currentUid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: BookingNotificationService.unreadCountStream(uid),
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return _BellButton(unread: unread, uid: uid);
      },
    );
  }
}

class _BellButton extends StatelessWidget {
  final int unread;
  final String uid;

  const _BellButton({required this.unread, required this.uid});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      offset: const Offset(0, 44),
      color: const Color(0xFF102436),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 340,
            child: _NotificationPanel(uid: uid),
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_rounded,
                color: Colors.white70, size: 22),
            if (unread > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF6461),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xFF071829), width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  final String uid;

  const _NotificationPanel({required this.uid});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: StreamBuilder<List<BookingNotificationModel>>(
        stream: BookingNotificationService.streamForUser(uid),
        builder: (context, snap) {
          final items = snap.data ?? const [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('Notifications',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Text('No notifications yet.',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    itemBuilder: (context, i) =>
                        _NotificationTile(item: items[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final BookingNotificationModel item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          item.read ? null : () => BookingNotificationService.markRead(item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.read ? Colors.transparent : const Color(0xFF00E5FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight:
                              item.read ? FontWeight.w500 : FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(item.body,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
