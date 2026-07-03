import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PushNotificationService
//
// Client half of booking push notifications. The actual "push to someone
// else's device" step can only happen server-side — see functions/index.js
// (onBookingCreated / onBookingStatusChanged), which reads the fcmToken this
// service writes onto Users/{uid} and calls admin.messaging().send(...).
//
// This service:
//   1. Requests notification permission.
//   2. Keeps Users/{uid}.fcmToken current for whoever is signed in.
//   3. Shows a local notification when a push arrives while the app is in
//      the foreground (FCM does this automatically for background/terminated
//      apps when the payload includes a `notification` block, which our
//      Cloud Functions always send).
//
// Android: works once functions are deployed and google-services.json is in
// place (already required for Firebase generally).
// Web: requires a VAPID key from Firebase Console → Project Settings →
// Cloud Messaging → Web configuration → "Web Push certificates" — see
// _webVapidKey below. Without it, web push tokens can't be obtained; the
// rest of the app is unaffected.
// ─────────────────────────────────────────────────────────────────────────────

/// Must be a top-level (or static) function per FCM's isolate requirements.
/// Intentionally minimal: Android/iOS/Web already auto-display the
/// `notification` block our Cloud Functions send even when the app isn't in
/// the foreground, so there's nothing else to do here today. This exists to
/// satisfy FirebaseMessaging.onBackgroundMessage's setup requirement and is
/// the place to add custom handling if a future payload needs it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService._();

  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'bookings',
    'Booking Updates',
    description: 'Notifications about new bookings and booking status changes.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // ── PLACEHOLDER — requires configuration ──────────────────────────────────
  // Generate this in Firebase Console → Project Settings → Cloud Messaging →
  // Web configuration → "Web Push certificates". Only needed for web push;
  // Android/iOS tokens don't use it.
  static const String _webVapidKey = 'REPLACE_WITH_FIREBASE_CONSOLE_VAPID_KEY';

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      ),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      _log.w('⚠️ PushNotificationService: permission request failed — $e');
    }

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Keep the token current for whoever is signed in, including token
    // rotation while the app stays open.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _registerToken(user.uid);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _saveToken(uid, token);
    });

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) await _registerToken(currentUid);

    _log.i('🔔 PushNotificationService.initialize: Complete');
  }

  static Future<void> _registerToken(String uid) async {
    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey:
                  _webVapidKey.startsWith('REPLACE_') ? null : _webVapidKey,
            )
          : await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(uid, token);
    } catch (e) {
      _log.w('⚠️ PushNotificationService: could not obtain FCM token — $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) {
    return FirebaseFirestore.instance.collection('Users').doc(uid).set(
      {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
