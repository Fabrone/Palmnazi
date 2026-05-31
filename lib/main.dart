import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:palmnazi/firebase_options.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/landing_page.dart';
import 'package:palmnazi/services/api_client.dart';
import 'package:palmnazi/services/firebase_email_link_service.dart';
import 'package:palmnazi/services/firebase_session_service.dart';
import 'package:palmnazi/services/notification_service.dart';

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
// ─────────────────────────────────────────────────────────────────────────────
class PalmnaziApp extends StatelessWidget {
  const PalmnaziApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      ],

      // ── Theme ──────────────────────────────────────────────────────────────
      theme: ThemeData(
        primarySwatch: Colors.teal,
        primaryColor: const Color(0xFF00897B),
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        fontFamily: 'Poppins',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
          displayMedium: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.0,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: Colors.white70,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Colors.white60,
            height: 1.4,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 8,
          ),
        ),
      ),

      home: const LandingPage(),
    );
  }
}