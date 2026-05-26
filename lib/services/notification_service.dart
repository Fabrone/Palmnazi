import 'dart:async';
//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/models/admin_request_model.dart';
import 'package:palmnazi/services/rbac_service.dart';
import 'package:flutter/material.dart' show Color;

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _log    = Logger(
    printer: PrettyPrinter(
      methodCount:      0,
      errorMethodCount: 8,
      lineLength:       100,
      colors:           true,
      printEmojis:      true,
    ),
  );

  // ── Notification channel IDs ───────────────────────────────────────────────
  static const _channelAdminRequests = AndroidNotificationChannel(
    'admin_requests',
    'Admin Role Requests',
    description: 'Notifications for incoming admin role requests.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _channelRequestDecisions = AndroidNotificationChannel(
    'request_decisions',
    'Role Request Decisions',
    description: 'Notifications about the outcome of your admin role request.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // ── Notification IDs ───────────────────────────────────────────────────────
  static const int _idNewRequest  = 1001;
  static const int _idDecision    = 1002;

  // ── Active Firestore stream subscriptions ─────────────────────────────────
  static StreamSubscription<List<AdminRequest>>? _adminRequestsSub;
  static StreamSubscription<AdminRequest?>?      _userRequestSub;

  static bool _adminListenerActive = false;

  // Track IDs already seen to avoid re-notifying on the same request
  static final Set<String> _seenRequestIds = {};
  // Track the last known status of the user's own request
  static AdminRequestStatus? _lastKnownStatus;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialize — call once at app start, before runApp()
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    _log.i('🔔 NotificationService.initialize');

    // Android init — uses the launcher icon as notification icon
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS / macOS init — requests permission at first notification
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission:  true,
      requestBadgePermission:  true,
      requestSoundPermission:  true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS:     darwinSettings,
      macOS:   darwinSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channels
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_channelAdminRequests);
    await androidPlugin?.createNotificationChannel(_channelRequestDecisions);

    // Request permission on Android 13+
    await androidPlugin?.requestNotificationsPermission();

    _log.i('✅ NotificationService.initialize: Complete');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start listening for incoming admin requests (call for MainAdmin users)
  // ─────────────────────────────────────────────────────────────────────────
  static void startAdminRequestsListener() {
    if (_adminListenerActive) {
      _log.d('🔔 NotificationService.startAdminRequestsListener: already active — skipping duplicate attach');
      return;
    }
    _adminListenerActive = true;
    _log.i('🔔 NotificationService.startAdminRequestsListener');

    _adminRequestsSub?.cancel();
    _seenRequestIds.clear();

    bool isFirstDelivery = true;

    _adminRequestsSub = RbacService.pendingRequestsStream().listen(
      (requests) {
        if (isFirstDelivery) {
          // Seed seen set silently — no notifications for pre-existing requests
          for (final r in requests) {
            _seenRequestIds.add(r.id);
          }
          isFirstDelivery = false;
          return;
        }

        // Any request whose ID is NOT in the seen set is genuinely new
        for (final req in requests) {
          if (!_seenRequestIds.contains(req.id)) {
            _seenRequestIds.add(req.id);
            _showAdminNewRequestNotification(req);
          }
        }
      },
      onError: (e) => _log.w('⚠️ NotificationService: admin stream error — $e'),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start listening to the user's own request (call for Tourist users)
  // ─────────────────────────────────────────────────────────────────────────
  static void startUserRequestListener(String userId) {
    _log.i('🔔 NotificationService.startUserRequestListener: userId=$userId');

    _userRequestSub?.cancel();
    _lastKnownStatus = null;
    bool isFirstDelivery = true;

    _userRequestSub = RbacService.userRequestStream(userId).listen(
      (request) {
        if (request == null) return;

        if (isFirstDelivery) {
          _lastKnownStatus = request.status;
          isFirstDelivery  = false;
          return;
        }

        // Only notify when the status actually changes
        if (request.status != _lastKnownStatus) {
          _lastKnownStatus = request.status;

          if (request.isAccepted) {
            _showRequestAcceptedNotification(request.grantedRole ?? 'Admin');
          } else if (request.isDenied) {
            _showRequestDeniedNotification(
                request.denialReason ?? 'No reason provided.');
          }
        }
      },
      onError: (e) =>
          _log.w('⚠️ NotificationService: user request stream error — $e'),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stop all listeners (e.g. on sign-out)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> stopAllListeners() async {
    await _adminRequestsSub?.cancel();
    await _userRequestSub?.cancel();
    _adminRequestsSub  = null;
    _userRequestSub    = null;
    _adminListenerActive = false; // reset so the next sign-in can re-attach
    _seenRequestIds.clear();
    _lastKnownStatus   = null;
    _log.i('🔔 NotificationService.stopAllListeners: Stopped');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private notification display helpers
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _showAdminNewRequestNotification(AdminRequest req) async {
    _log.i('🔔 NotificationService: New admin request from ${req.userEmail}');
    try {
      await _plugin.show(
        id: _idNewRequest,
        title: '📋 New Admin Role Request',
        body: '${req.userEmail} has applied for an admin role (${req.facilityName}).',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelAdminRequests.id,
            _channelAdminRequests.name,
            channelDescription: _channelAdminRequests.description,
            importance:         Importance.high,
            priority:           Priority.high,
            playSound:          true,
            enableVibration:    true,
            styleInformation:   BigTextStyleInformation(
              'User: ${req.userEmail}\nFacility: ${req.facilityName}\n'
              'Services: ${req.servicesOffered.join(', ')}',
              summaryText: 'Admin role request',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      _log.w('⚠️ NotificationService._showAdminNewRequestNotification: $e');
    }
  }

  static Future<void> _showRequestAcceptedNotification(String grantedRole) async {
    _log.i('🔔 NotificationService: Request accepted — role=$grantedRole');
    try {
      await _plugin.show(
        id: _idDecision,
        title: '🎉 Admin Role Granted!',
        body: 'Congratulations! Your request has been approved. '
              'You have been assigned the $grantedRole role.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelRequestDecisions.id,
            _channelRequestDecisions.name,
            channelDescription: _channelRequestDecisions.description,
            importance:         Importance.high,
            priority:           Priority.high,
            playSound:          true,
            enableVibration:    true,
            color:              const Color(0xFF14FFEC),
            styleInformation:   BigTextStyleInformation(
              'Your admin role request has been reviewed and approved. '
              'You now have $grantedRole access. '
              'Please restart the app to apply your new permissions.',
              summaryText: 'Role request approved',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      _log.w('⚠️ NotificationService._showRequestAcceptedNotification: $e');
    }
  }

  static Future<void> _showRequestDeniedNotification(String reason) async {
    _log.i('🔔 NotificationService: Request denied — reason=$reason');
    try {
      await _plugin.show(
        id: _idDecision,
        title: '❌ Admin Role Request Declined',
        body: 'Your admin role request was not approved at this time.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelRequestDecisions.id,
            _channelRequestDecisions.name,
            channelDescription: _channelRequestDecisions.description,
            importance:         Importance.high,
            priority:           Priority.high,
            playSound:          true,
            enableVibration:    true,
            styleInformation:   BigTextStyleInformation(
              'Your admin role request has been reviewed and declined.\n\n'
              'Reason: $reason\n\n'
              'You may submit a new request from your Account screen.',
              summaryText: 'Role request declined',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      _log.w('⚠️ NotificationService._showRequestDeniedNotification: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Notification tap handler
  // ─────────────────────────────────────────────────────────────────────────
  static void _onNotificationTap(NotificationResponse response) {
    _log.i('🔔 NotificationService: Tapped — payload=${response.payload}');
    // Navigation on tap can be added here via a global navigator key if needed.
  }
}