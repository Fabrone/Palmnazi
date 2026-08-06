import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/booking_screen.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/service_type_style.dart';
import 'package:palmnazi/widgets/main_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ServiceDetailScreen
//
// Single-item view for a tappable service card on place_details_screen.dart
// (a room, menu item, show, exhibition, or artifact — same raw
// Map<String, dynamic> shape place_details_screen already passes into
// BookingScreen's `serviceOptions`, so no new data plumbing is needed). Shows
// the item's photos, description, and tags at full size, styled per its
// ServiceTypeStyle, with a primary CTA that opens BookingScreen with this
// item pre-selected.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  static Color get deepBlue =>
      _isDark ? const Color(0xFF071829) : const Color(0xFFE8EDF2);
  static Color get textPri => _isDark ? Colors.white : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? Colors.white70 : const Color(0xFF3D4F60);

  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

class ServiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> item;
  final String
      itemType; // 'rooms' | 'menuItems' | 'shows' | 'exhibitions' | 'artifacts'
  final PlaceModel place;
  final CityModel city;
  final List<PaymentMethodModel> paymentMethods;
  final List<Map<String, dynamic>> serviceOptions;
  final String serviceLabel;

  const ServiceDetailScreen({
    super.key,
    required this.item,
    required this.itemType,
    required this.place,
    required this.city,
    this.paymentMethods = const [],
    this.serviceOptions = const [],
    this.serviceLabel = '',
  });

  String get _name => item['name'] as String? ?? 'Untitled';
  String? get _description => item['description'] as String?;
  List<String> get _images =>
      (item['images'] as List?)?.whereType<String>().toList() ?? const [];
  List<String> get _amenities =>
      (item['amenities'] as List?)?.whereType<String>().toList() ??
      (item['ingredients'] as List?)?.whereType<String>().toList() ??
      const [];
  bool get _isAvailable => item['isAvailable'] as bool? ?? true;

  double? get _price => itemType == 'rooms'
      ? (item['basePrice'] as num?)?.toDouble()
      : (item['price'] as num?)?.toDouble();
  String get _currency => item['currency'] as String? ?? 'KES';

  @override
  Widget build(BuildContext context) {
    final style = ServiceTypeStyle.forItemType(itemType);

    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: PalmnaziNavBar(compact: true, showBack: true, title: _name),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _gallery(style),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: style.linearGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(style.icon, size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(style.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    if (!_isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Currently unavailable',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text(_name,
                      style: TextStyle(
                          color: _P.textPri,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  if (_price != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$_currency ${_price!.toStringAsFixed(0)}'
                      '${itemType == 'rooms' ? ' / night' : ''}',
                      style: TextStyle(
                          color: style.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (_description != null && _description!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(_description!,
                        style: TextStyle(
                            color: _P.textSec, fontSize: 14, height: 1.5)),
                  ],
                  if (_amenities.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('What\'s included',
                        style: TextStyle(
                            color: _P.textPri,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _amenities
                          .map((a) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _P.overlay(0.06),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _P.overlay(0.12)),
                                ),
                                child: Text(a,
                                    style: TextStyle(
                                        color: _P.textSec, fontSize: 12)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _bookThis(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: style.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                          'Book This ${style.label.substring(0, style.label.length - (style.label.endsWith('s') ? 1 : 0))}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gallery(ServiceTypeStyle style) {
    if (_images.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(gradient: style.linearGradient),
          child: Center(
            child: Icon(style.icon, size: 56, color: Colors.white70),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: PageView.builder(
        itemCount: _images.length,
        itemBuilder: (context, i) => Image.network(
          _images[i],
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(gradient: style.linearGradient),
            child: Center(
              child: Icon(style.icon, size: 56, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  void _bookThis(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)));
      return;
    }
    final preselectedIndex =
        serviceOptions.indexWhere((s) => s['id'] == item['id']);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          place: place,
          city: city,
          serviceOptions: serviceOptions.isNotEmpty ? serviceOptions : [item],
          serviceLabel: serviceLabel,
          serviceType: itemType,
          paymentMethods: paymentMethods,
          initialServiceIndex: preselectedIndex >= 0 ? preselectedIndex : 0,
        ),
      ),
    );
  }
}
