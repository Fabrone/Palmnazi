import 'package:flutter/material.dart';
import 'package:palmnazi/services/app_settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AC — shared "auth/account" color palette
//
// auth_screen.dart and account_screen.dart both grew their own dark-only
// hex literals (Color(0xFF14FFEC), Color(0xFF1E3A5F), …) independently of
// the RC palette in landing_page.dart. Centralizing them here as
// theme-reactive getters (same pattern as RC — see landing_page.dart) lets
// every existing call site that gets migrated to `AC.xxx` react to a theme
// change automatically. Brand accent colors stay constant across modes;
// only background/surface/text roles swap.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AC {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  // Backgrounds / surfaces
  static Color get navyDeep =>
      _isDark ? const Color(0xFF0A1128) : const Color(0xFFF5F7FA);
  static Color get surface =>
      _isDark ? const Color(0xFF1E3A5F) : const Color(0xFFFFFFFF);

  // Brand accents — intentionally identical in both modes.
  static const Color teal = Color(0xFF14FFEC);
  static const Color tealDark = Color(0xFF0D7377);
  static const Color coral = Color(0xFFCF6679);
  static const Color errorRed = Color(0xFFB00020);
  static const Color orange = Color(0xFFFF9800);
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB300);

  // Text on AC.surface / AC.navyDeep
  static Color get textPri =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? Colors.white70 : const Color(0xFF3D4F60);
  static Color get textMute =>
      _isDark ? Colors.white38 : const Color(0xFF7C93A8);

  /// The "0xFF1E3A5F → 0xFF0A1128" hero/card gradient used on auth_screen's
  /// backgrounds.
  static List<Color> get heroGradient =>
      _isDark ? [surface, navyDeep] : [surface, const Color(0xFFE8EDF2)];

  /// Subtle fill for input/button backgrounds that used to be a flat
  /// `Colors.white.withValues(alpha: x)` — invisible once the surface
  /// behind it turns light. Black in light mode keeps the same "faint tint
  /// over the surface" effect in both modes.
  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}
