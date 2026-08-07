import 'package:flutter/material.dart';
import 'package:palmnazi/services/app_settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RC — the app's one shared brand palette.
//
// Originally defined inline in landing_page.dart; extracted here so
// lib/widgets/main_app_bar.dart (PalmnaziNavBar) can share the exact same
// tokens landing_page.dart uses, instead of a third, divergent color set.
// Colors are getters rather than `static const` specifically so every call
// site reacts to a theme change without being individually rewritten —
// screens just need one `context.tr(...)` or `AppSettingsScope.of(context)`
// call in their build tree to register as a dependent and rebuild when
// settings change.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class RC {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  static Color get navy =>
      _isDark ? const Color(0xFF121F2E) : const Color(0xFFF5F7FA);
  static Color get deepBlue =>
      _isDark ? const Color(0xFF1C2E42) : const Color(0xFFE8EDF2);
  static Color get surface =>
      _isDark ? const Color(0xFF23374D) : const Color(0xFFFFFFFF);
  static Color get surfaceHi =>
      _isDark ? const Color(0xFF2C4258) : const Color(0xFFEFF3F7);

  // Brand accents — intentionally identical in both modes.
  static const Color teal = Color(0xFF3FA9C4);
  static const Color tealMid = Color(0xFF2C8598);
  static const Color tealDark = Color(0xFF1D5F6E);
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldMid = Color(0xFFC49A2C);
  static const Color goldDark = Color(0xFF8C6D1F);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color emerald = Color(0xFF00C98A);

  static Color get textPri =>
      _isDark ? const Color.fromARGB(255, 162, 133, 133) : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? const Color(0xFFC7D6E3) : const Color(0xFF3D4F60);
  static Color get textMute =>
      _isDark ? const Color(0xFF7C93A8) : const Color(0xFF6B7C8C);

  static const LinearGradient tealGrad =
      LinearGradient(colors: [teal, tealDark]);
  static const LinearGradient goldGrad =
      LinearGradient(colors: [gold, goldMid]);
  static LinearGradient get heroGrad => _isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC121F2E), Color(0xBB1C2E42), Color(0xDD24384E)],
          stops: [0.0, 0.45, 1.0],
        )
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.90),
            const Color(0xFFE8EDF2).withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.45, 1.0],
        );

  /// Subtle fill for input/button backgrounds that used to be a flat
  /// `Colors.white.withValues(alpha: x)` — invisible once the surface
  /// behind it turns light. Black in light mode keeps the same "faint tint
  /// over the surface" effect in both modes.
  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}
