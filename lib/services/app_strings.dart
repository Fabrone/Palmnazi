import 'package:flutter/material.dart';
import 'package:palmnazi/services/app_settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppStrings
//
// Lightweight English/Swahili dictionary — deliberately NOT flutter gen-l10n/
// ARB, since this app has no existing intl codegen pipeline. Every UI string
// gets a semantic key here; screens look it up via `context.tr(key)`, which
// reads the active language from AppSettingsScope. Falls back to the English
// value (or the raw key, so a missing translation is visible rather than
// crashing) when a key or language is unmatched.
//
// This dictionary currently covers the Settings section and Account screen —
// the first screens wired up for full bilingual support. Extend the maps
// below when converting additional screens; the lookup pattern doesn't
// change.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppStrings {
  static const Map<String, String> _en = {
    // Settings section
    'settings_title': 'Settings',
    'settings_appearance': 'APPEARANCE',
    'settings_theme': 'Theme',
    'settings_theme_dark': 'Dark',
    'settings_theme_light': 'Light',
    'settings_theme_system': 'System Default',
    'settings_font': 'Font Style',
    'settings_font_subtitle': 'Choose how text is displayed across the app',
    'settings_language': 'LANGUAGE',
    'settings_language_label': 'App Language',
    'settings_language_english': 'English',
    'settings_language_swahili': 'Kiswahili',

    // Account screen
    'my_account': 'My Account',
    'account_bookings_section': 'BOOKINGS',
    'account_my_bookings': 'My Bookings',
    'account_my_bookings_sub': 'View and manage your booking requests',
    'account_my_queries': 'My Questions',
    'account_my_queries_sub': 'Questions you\'ve asked about places',
    'account_my_favorites': 'My Favorites',
    'account_my_favorites_sub': 'Places you\'ve saved',
    'account_place_admin_panel': 'Place Admin Panel',
    'account_place_admin_panel_sub':
        'Manage bookings, queries and details for your place',
    'account_admin_console': 'Admin Console',
    'account_admin_console_sub':
        'Full system management — places, bookings, reports',
    'account_security_section': 'SECURITY',
    'account_phone_mfa': 'Phone Two-Factor Auth',
    'account_phone_mfa_enabled_sub':
        'Enabled — an SMS code is required at each sign-in',
    'account_phone_mfa_disabled_sub':
        'Disabled — adds a phone SMS verification step at sign-in',
    'account_admin_access_section': 'ADMIN ACCESS',
    'account_sign_out': 'Sign Out',
  };

  static const Map<String, String> _sw = {
    // Settings section
    'settings_title': 'Mipangilio',
    'settings_appearance': 'MUONEKANO',
    'settings_theme': 'Mandhari',
    'settings_theme_dark': 'Giza',
    'settings_theme_light': 'Mwanga',
    'settings_theme_system': 'Chaguo-msingi la Mfumo',
    'settings_font': 'Aina ya Herufi',
    'settings_font_subtitle':
        'Chagua jinsi maandishi yanavyoonekana katika programu',
    'settings_language': 'LUGHA',
    'settings_language_label': 'Lugha ya Programu',
    'settings_language_english': 'Kiingereza',
    'settings_language_swahili': 'Kiswahili',

    // Account screen
    'my_account': 'Akaunti Yangu',
    'account_bookings_section': 'UHIFADHI',
    'account_my_bookings': 'Uhifadhi Wangu',
    'account_my_bookings_sub': 'Angalia na simamia maombi yako ya uhifadhi',
    'account_my_queries': 'Maswali Yangu',
    'account_my_queries_sub': 'Maswali uliyouliza kuhusu maeneo',
    'account_my_favorites': 'Vipendwa Vyangu',
    'account_my_favorites_sub': 'Maeneo uliyoyahifadhi',
    'account_place_admin_panel': 'Dashibodi ya Msimamizi wa Eneo',
    'account_place_admin_panel_sub':
        'Simamia uhifadhi, maswali na maelezo ya eneo lako',
    'account_admin_console': 'Dashibodi ya Msimamizi',
    'account_admin_console_sub':
        'Usimamizi kamili wa mfumo — maeneo, uhifadhi, ripoti',
    'account_security_section': 'USALAMA',
    'account_phone_mfa': 'Uthibitisho wa Hatua Mbili kwa Simu',
    'account_phone_mfa_enabled_sub':
        'Imewashwa — nambari ya SMS inahitajika kila unapoingia',
    'account_phone_mfa_disabled_sub':
        'Imezimwa — huongeza hatua ya uthibitisho wa SMS wakati wa kuingia',
    'account_admin_access_section': 'UFIKIAJI WA USIMAMIZI',
    'account_sign_out': 'Toka Kwenye Akaunti',
  };

  static String of(BuildContext context, String key) {
    final isSwahili = AppSettingsScope.of(context).isSwahili;
    if (isSwahili) return _sw[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }
}

extension AppStringsX on BuildContext {
  /// Looks up [key] in the active language (English/Swahili), falling back
  /// to English then the raw key if untranslated.
  String tr(String key) => AppStrings.of(this, key);
}
