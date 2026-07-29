import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:palmnazi/firebase_options.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/firebase_email_link_service.dart';
import 'package:palmnazi/services/firebase_session_service.dart';
import 'package:palmnazi/services/notification_service.dart';
import 'package:palmnazi/services/push_notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global notifier — fires whenever an incoming email sign-in / verification
/// link is handled successfully.  The AuthScreen listens to this to navigate
/// to LandingPage without needing to know about app_links directly.
final ValueNotifier<EmailLinkResult?> emailLinkResultNotifier =
    ValueNotifier(null);

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.primeSessionCache();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseSessionService.init();
  ApiClient.onSessionExpired = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)),
      (route) => false,
    );
  };

  await NotificationService.initialize();
  await PushNotificationService.initialize();

  // ── Email-link deep-link handler (app_links) ──────────────────────────────
  // Handles both cold-start links (app launched via email link) and warm
  // links (app already running in background).
  final appLinks = AppLinks();

  // Cold-start: the link that launched the app from a terminated state.
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) {
    _handleEmailLink(initialUri.toString());
  }

  // Warm: stream of links while the app is running.
  appLinks.uriLinkStream.listen((uri) {
    _handleEmailLink(uri.toString());
  });
  // ─────────────────────────────────────────────────────────────────────────

  // Set system UI overlay style.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PalmnaziApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// EMAIL LINK HANDLER
// ─────────────────────────────────────────────────────────────────────────────
/// Called for every incoming deep / universal link.
/// Delegates to FirebaseEmailLinkService; on success it updates the notifier
/// so any listening screen (AuthScreen) can react accordingly.
Future<void> _handleEmailLink(String link) async {
  final EmailLinkResult? result =
      await FirebaseEmailLinkService.handleIncomingLink(link);
  if (result == null) return; // not an email sign-in link
  emailLinkResultNotifier.value = result;
  if (result.isSuccess) {
    // Navigate to LandingPage regardless of which screen is visible.
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT WIDGET
//
// Owns the single AppSettingsController instance for the app's lifetime,
// loads its persisted theme/font/language on first frame, and rebuilds
// MaterialApp whenever a setting changes (see AppSettingsScope, changed from
// Account → Settings). Screens read the active language via
// `context.tr(key)` (see app_strings.dart) and the active colors via
// `Theme.of(context)`.
// ─────────────────────────────────────────────────────────────────────────────
class PalmnaziApp extends StatefulWidget {
  const PalmnaziApp({super.key});

  @override
  State<PalmnaziApp> createState() => _PalmnaziAppState();
}

class _PalmnaziAppState extends State<PalmnaziApp> {
  final AppSettingsController _settings = AppSettingsController();

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  // ── Shared brand palette, mirrored light/dark ─────────────────────────────
  static const _teal = Color(0xFF00897B);

  ThemeData _buildTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final scaffoldBg =
        isDark ? const Color(0xFF0A0E21) : const Color(0xFFF5F7FA);
    final surface = isDark ? const Color(0xFF121F2E) : const Color(0xFFFFFFFF);
    final textPrimary = isDark ? Colors.white : const Color(0xFF121F2E);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF4A5A6A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF7C93A8);

    final base = TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        letterSpacing: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        letterSpacing: 1.0,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: textSecondary, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, color: textMuted, height: 1.4),
    );

    return ThemeData(
      brightness: brightness,
      primarySwatch: Colors.teal,
      primaryColor: _teal,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _teal,
        brightness: brightness,
        surface: surface,
      ),
      textTheme: base,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final lightBase = _buildTheme(brightness: Brightness.light);
        final darkBase = _buildTheme(brightness: Brightness.dark);

        return AppSettingsScope(
          controller: _settings,
          child: MaterialApp(
            title: 'Palmnazi Resort Cities',
            debugShowCheckedModeBanner: false,

            navigatorKey: navigatorKey,

            localizationsDelegates: const [
              FlutterQuillLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            supportedLocales: const [
              Locale('en', 'US'),
              Locale('sw', 'TZ'),
            ],
            locale: _settings.locale,

            // ── Theme ──────────────────────────────────────────────────────
            theme: lightBase.copyWith(
              textTheme: _settings.fontChoice.textTheme(lightBase.textTheme),
            ),
            darkTheme: darkBase.copyWith(
              textTheme: _settings.fontChoice.textTheme(darkBase.textTheme),
            ),
            themeMode: _settings.themeMode,

            home: const LandingPage(),
          ),
        );
      },
    );
  }
}
