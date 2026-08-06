import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ServiceTypeStyle
//
// Single source of truth for the visual identity of each nested-item service
// type (rooms, dining, entertainment, cultural). Consumed by
// place_details_screen.dart's service cards/tab indicator and by
// service_detail_screen.dart, so every surface agrees on "what dining looks
// like" instead of each widget picking its own flat color.
// ─────────────────────────────────────────────────────────────────────────────
enum ServiceKind { rooms, dining, entertainment, cultural }

class ServiceTypeStyle {
  final ServiceKind kind;
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color accent;

  const ServiceTypeStyle({
    required this.kind,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.accent,
  });

  LinearGradient get linearGradient => LinearGradient(
        colors: gradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const _rooms = ServiceTypeStyle(
    kind: ServiceKind.rooms,
    label: 'Rooms',
    icon: Icons.bed_rounded,
    gradient: [Color(0xFFE8A33D), Color(0xFFB6672A)],
    accent: Color(0xFFE8A33D),
  );

  static const _dining = ServiceTypeStyle(
    kind: ServiceKind.dining,
    label: 'Dining',
    icon: Icons.restaurant_rounded,
    gradient: [Color(0xFFEF6461), Color(0xFFC4356F)],
    accent: Color(0xFFEF6461),
  );

  static const _entertainment = ServiceTypeStyle(
    kind: ServiceKind.entertainment,
    label: 'Entertainment',
    icon: Icons.theater_comedy_rounded,
    gradient: [Color(0xFF8E6FF7), Color(0xFF4B32A8)],
    accent: Color(0xFF8E6FF7),
  );

  static const _cultural = ServiceTypeStyle(
    kind: ServiceKind.cultural,
    label: 'Cultural',
    icon: Icons.museum_rounded,
    gradient: [Color(0xFF2FBF9F), Color(0xFF0E8272)],
    accent: Color(0xFF2FBF9F),
  );

  /// Maps the app's existing `serviceType`/`itemType` strings (rooms,
  /// menuItems, shows, exhibitions, artifacts — see
  /// place_details_screen.dart's `_isAccommodationType`/`_isDiningType`/etc.)
  /// to a style. Defaults to cultural for anything unrecognized, since that
  /// was the effective default flat style before this change.
  static ServiceTypeStyle forItemType(String itemType) {
    switch (itemType) {
      case 'rooms':
        return _rooms;
      case 'menuItems':
        return _dining;
      case 'shows':
        return _entertainment;
      case 'exhibitions':
      case 'artifacts':
        return _cultural;
      default:
        return _cultural;
    }
  }
}
