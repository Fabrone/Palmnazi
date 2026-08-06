import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppFontChoice
//
// Curated list of selectable font families, shown in Account → Settings.
// `apply` builds the TextTheme via google_fonts so the whole app can switch
// without bundling font asset files.
// ─────────────────────────────────────────────────────────────────────────────
enum AppFontChoice {
  poppins('Poppins'),
  roboto('Roboto'),
  openSans('Open Sans'),
  lato('Lato'),
  nunito('Nunito'),
  montserrat('Montserrat'),
  merriweather('Merriweather');

  final String label;
  const AppFontChoice(this.label);

  static AppFontChoice fromName(String? name) => AppFontChoice.values
      .firstWhere((f) => f.name == name, orElse: () => AppFontChoice.poppins);

  /// Renders [label] in its own font — used for live previews in the font
  /// picker so a user can see each style before selecting it.
  TextStyle previewTextStyle({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) =>
      GoogleFonts.getFont(label,
          fontSize: fontSize, fontWeight: fontWeight, color: color);

  TextTheme textTheme(TextTheme base) {
    switch (this) {
      case AppFontChoice.poppins:
        return GoogleFonts.poppinsTextTheme(base);
      case AppFontChoice.roboto:
        return GoogleFonts.robotoTextTheme(base);
      case AppFontChoice.openSans:
        return GoogleFonts.openSansTextTheme(base);
      case AppFontChoice.lato:
        return GoogleFonts.latoTextTheme(base);
      case AppFontChoice.nunito:
        return GoogleFonts.nunitoTextTheme(base);
      case AppFontChoice.montserrat:
        return GoogleFonts.montserratTextTheme(base);
      case AppFontChoice.merriweather:
        return GoogleFonts.merriweatherTextTheme(base);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsController
//
// App-wide, persisted user preferences: theme mode, font choice, and
// language. Owned once at the root (see main.dart) and exposed down the
// tree via AppSettingsScope so any screen can read or change it.
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsController extends ChangeNotifier {
  AppSettingsController._internal();

  /// Single instance for the app's lifetime — lets non-context code (e.g.
  /// the shared RC color palette in landing_page.dart) read the resolved
  /// brightness without needing a BuildContext.
  static final AppSettingsController instance =
      AppSettingsController._internal();

  static const _kThemeModeKey = 'pn_theme_mode';
  static const _kFontKey = 'pn_font_choice';
  static const _kLocaleKey = 'pn_locale';

  ThemeMode _themeMode = ThemeMode.dark;
  AppFontChoice _fontChoice = AppFontChoice.poppins;
  Locale _locale = const Locale('en');

  /// Set once per frame by the root widget's build (which has a
  /// BuildContext to resolve ThemeMode.system against MediaQuery). Read by
  /// RC's getters so every existing `RC.xxx` call site across the app
  /// reacts to theme changes without being individually rewritten.
  Brightness resolvedBrightness = Brightness.dark;

  ThemeMode get themeMode => _themeMode;
  AppFontChoice get fontChoice => _fontChoice;
  Locale get locale => _locale;
  bool get isSwahili => _locale.languageCode == 'sw';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_kThemeModeKey);
    _themeMode = switch (modeStr) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _fontChoice = AppFontChoice.fromName(prefs.getString(_kFontKey));
    _locale = Locale(prefs.getString(_kLocaleKey) ?? 'en');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setFontChoice(AppFontChoice choice) async {
    if (choice == _fontChoice) return;
    _fontChoice = choice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontKey, choice.name);
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsScope
//
// InheritedNotifier so any widget can do
// `AppSettingsScope.of(context).setThemeMode(...)` without a state-management
// package. Rebuilds dependents whenever the controller calls notifyListeners.
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found in context');
    return scope!.notifier!;
  }
}
