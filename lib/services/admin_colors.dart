import 'package:flutter/material.dart';
import 'package:palmnazi/services/app_settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdC — shared admin-section color palette
//
// Nearly every screen under lib/admin/ grew its own copy of the same dark
// navy/teal palette as local `const _kSurface = Color(0xFF111827)` /
// `const _kTeal = Color(0xFF14FFEC)` style top-level constants (or, in
// admin_dashboard.dart, inline hex literals). Centralizing them here as
// theme-reactive getters (same technique as RC in landing_page.dart and AC
// in app_colors.dart) lets every admin screen that migrates to `AdC.xxx`
// react to a theme change automatically. Brand accent colors stay constant
// across modes; only background/surface roles swap.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AdC {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  // Backgrounds / surfaces
  static Color get bg =>
      _isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF5F7FA);
  static Color get surface =>
      _isDark ? const Color(0xFF111827) : const Color(0xFFFFFFFF);

  // Brand accents — intentionally identical in both modes.
  static const Color teal = Color(0xFF14FFEC);
  static const Color tealDark = Color(0xFF0D7377);
  static const Color orange = Color(0xFFFF9800);
  static const Color red = Color(0xFFCF6679);
  static const Color green = Color(0xFF00C853);
  static const Color gold = Color(0xFFD4AF37);
  static const Color blue = Color(0xFF2196F3);

  // Text on AdC.surface / AdC.bg
  static Color get textPri =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? Colors.white70 : const Color(0xFF3D4F60);
  static Color get textMute =>
      _isDark ? Colors.white38 : const Color(0xFF7C93A8);

  /// Subtle fill for input/button backgrounds that used to be a flat
  /// `Colors.white.withValues(alpha: x)` — that overlay is invisible (near
  /// white-on-white) once the surface behind it turns light. Using black in
  /// light mode keeps the same "faint tint over the surface" effect in both
  /// modes.
  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}
