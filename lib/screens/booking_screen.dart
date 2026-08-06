import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/models/menu_item_model.dart';
import 'package:palmnazi/models/room_model.dart';
import 'package:palmnazi/screens/my_bookings_screen.dart';
import 'package:palmnazi/screens/payment_simulation_screen.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingScreen
//
// Tourist-facing booking form, opened from PlaceDetailsScreen's "Book Now"
// button. Requires the user to be signed in (enforced by the caller, which
// routes to AuthScreen first if not).
//
// Optionally lets the tourist pick a specific nested service (a room, menu
// item, or show — whichever applies to this place's category) and an
// accepted payment method, both sourced from Firestore (Place_details /
// PaymentMethods) by the caller and passed in here.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static bool get _isDark =>
      AppSettingsController.instance.resolvedBrightness == Brightness.dark;

  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static Color get deepNavy =>
      _isDark ? const Color(0xFF01263F) : const Color(0xFFF5F7FA);
  static Color get deepBlue =>
      _isDark ? const Color(0xFF071829) : const Color(0xFFE8EDF2);

  static Color get textPri => _isDark ? Colors.white : const Color(0xFF121F2E);
  static Color get textSec =>
      _isDark ? Colors.white70 : const Color(0xFF3D4F60);
  static Color get textMute =>
      _isDark ? Colors.white38 : const Color(0xFF7C93A8);

  /// Subtle fill for input/button backgrounds that used to be a flat
  /// `Colors.white.withValues(alpha: x)` — invisible once the surface
  /// behind it turns light.
  static Color overlay(double alpha) =>
      (_isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

class BookingScreen extends StatefulWidget {
  final PlaceModel place;
  final CityModel city;

  /// Nested items this place offers (rooms / menu items / shows), if any.
  /// Each map has at least a 'name' key; label describes what kind they are
  /// (e.g. "Room", "Menu Item", "Show") for the picker's UI copy.
  final List<Map<String, dynamic>> serviceOptions;
  final String serviceLabel;
  final String serviceType; // 'rooms' | 'menuItems' | 'shows' | ''

  final List<PaymentMethodModel> paymentMethods;

  const BookingScreen({
    super.key,
    required this.place,
    required this.city,
    this.serviceOptions = const [],
    this.serviceLabel = '',
    this.serviceType = '',
    this.paymentMethods = const [],
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _requestedDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _checkOutDate;
  int _guests = 1;
  final _notesCtrl = TextEditingController();
  int? _selectedServiceIndex;
  String? _selectedPaymentMethodId;
  bool _saving = false;
  String? _error;

  bool get _isAccommodation => widget.serviceType == 'rooms';

  Map<String, dynamic>? get _selectedService => _selectedServiceIndex != null &&
          _selectedServiceIndex! < widget.serviceOptions.length
      ? widget.serviceOptions[_selectedServiceIndex!]
      : null;

  EstimatedPrice? get _priceEstimate => estimateBookingTotal(
        placeMinPrice: widget.place.pricing?.min,
        placeCurrency: widget.place.pricing?.currency,
        service: _selectedService,
        serviceType: widget.serviceType,
        guests: _guests,
        checkIn: _requestedDate,
        checkOut: _checkOutDate,
      );

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isCheckOut}) async {
    final initial = isCheckOut
        ? (_checkOutDate ?? _requestedDate.add(const Duration(days: 1)))
        : _requestedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: _P.aquaBright,
            surface: _P.deepNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckOut) {
        _checkOutDate = picked;
      } else {
        _requestedDate = picked;
        if (_checkOutDate != null && !_checkOutDate!.isAfter(picked)) {
          _checkOutDate = null;
        }
      }
    });
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = context.tr('booking_error_signin'));
      return;
    }
    if (_isAccommodation && _checkOutDate == null) {
      setState(() => _error = context.tr('booking_error_select_checkout'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final selectedService = _selectedService;
    final selectedPayment = widget.paymentMethods
        .where((m) => m.id == _selectedPaymentMethodId)
        .firstOrNull;

    try {
      // Same-resource double-booking guard — only meaningful when a specific
      // named service (room/menu item/show) was picked.
      final serviceName = selectedService?['name'] as String?;
      if (serviceName != null) {
        final conflict = await BookingService.hasConflict(
          placeId: widget.place.id,
          serviceName: serviceName,
          requestedDate: _requestedDate,
          checkOutDate: _isAccommodation ? _checkOutDate : null,
        );
        if (conflict) {
          if (mounted) {
            setState(() {
              _error =
                  '"$serviceName" ${context.tr('booking_error_conflict_suffix')}';
              _saving = false;
            });
          }
          return;
        }
      }

      final estimate = _priceEstimate;

      // Walk through a payment-method-specific flow before finalising — only
      // when there's both a chosen method and an amount to show. M-Pesa is a
      // real Daraja sandbox round-trip; every other method is a simulation.
      // See PaymentSimulationScreen.
      var paymentSimulated = false;
      String? mpesaReceiptNumber;
      String? mpesaTransactionRef;
      if (selectedPayment != null && estimate != null) {
        if (!mounted) return;
        final outcome = await Navigator.of(context).push<PaymentOutcome>(
          MaterialPageRoute(
            builder: (_) => PaymentSimulationScreen(
              method: selectedPayment,
              amount: estimate.amount,
              currency: estimate.currency,
              placeName: widget.place.name,
            ),
          ),
        );
        if (outcome == null || !outcome.success) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        mpesaReceiptNumber = outcome.mpesaReceiptNumber;
        mpesaTransactionRef = outcome.mpesaTransactionRef;
        paymentSimulated = mpesaReceiptNumber == null;
      }

      final booking = BookingModel(
        id: '',
        placeId: widget.place.id,
        placeName: widget.place.name,
        cityId: widget.city.id,
        cityName: widget.city.name,
        firebaseUid: user.uid,
        userEmail: user.email ?? '',
        serviceType: widget.serviceType.isNotEmpty ? widget.serviceType : null,
        serviceName: serviceName,
        serviceId: selectedService?['id'] as String?,
        requestedDate: _requestedDate,
        checkOutDate: _isAccommodation ? _checkOutDate : null,
        numberOfGuests: _guests,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        paymentMethodId: selectedPayment?.id,
        paymentMethodName: selectedPayment?.name,
        paymentSimulated: paymentSimulated,
        mpesaReceiptNumber: mpesaReceiptNumber,
        mpesaTransactionRef: mpesaTransactionRef,
        totalAmount: estimate?.amount,
        currency: estimate?.currency,
        cancellationPolicy: widget.place.bookingSettings?.cancellationPolicy,
      );
      final bookingId = await BookingService.create(booking);
      if (mounted) _showSuccess(bookingId, serviceName);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Booking failed: $e';
          _saving = false;
        });
      }
    }
  }

  void _showSuccess(String bookingId, String? serviceName) {
    // A truncated, uppercased tail of the Firestore doc id — short enough to
    // read aloud or write down at a front desk, while the full id (kept
    // underneath, copyable) remains available for exact lookup.
    final shortRef = bookingId.length > 8
        ? bookingId.substring(bookingId.length - 8).toUpperCase()
        : bookingId.toUpperCase();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _P.deepNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          const SizedBox(width: 10),
          Text(context.tr('booking_success_title'),
              style: TextStyle(color: _P.textPri)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.tr('booking_success_prefix')} "${widget.place.name}" '
              '${context.tr('booking_success_suffix')}',
              style: TextStyle(color: _P.textSec),
            ),
            if (serviceName != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.room_service_outlined,
                    size: 16, color: _P.aquaBright),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(serviceName,
                      style: TextStyle(
                          color: _P.textPri, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            Text(context.tr('booking_success_reference_label'),
                style: TextStyle(
                    color: _P.textMute,
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _P.overlay(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _P.overlay(0.12)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(shortRef,
                      style: TextStyle(
                          color: _P.aquaBright,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: 18, color: _P.textMute),
                  tooltip: context.tr('booking_success_copy_reference'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: bookingId));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text(context.tr('booking_success_reference_copied')),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(context.tr('booking_success_reference_hint'),
                style:
                    TextStyle(color: _P.textMute, fontSize: 12, height: 1.4)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(true); // booking screen
            },
            child: Text(context.tr('common_done'),
                style: TextStyle(color: _P.textMute)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _P.aquaBright),
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(true); // booking screen
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
              );
            },
            child: Text(context.tr('booking_button_view_my_bookings'),
                style: TextStyle(color: _P.deepNavy)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: AppBar(
        backgroundColor: _P.deepNavy,
        title: Text(
            '${context.tr('booking_appbar_prefix')} ${widget.place.name}',
            style: TextStyle(color: _P.textPri, fontSize: 16)),
        iconTheme: IconThemeData(color: _P.textPri),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            ],

            // ── Service selection ─────────────────────────────────────────
            if (widget.serviceOptions.isNotEmpty) ...[
              _sectionLabel(widget.serviceLabel.isNotEmpty
                  ? '${context.tr('booking_select_prefix')} ${widget.serviceLabel}'
                  : context.tr('booking_select_option')),
              const SizedBox(height: 10),
              ...widget.serviceOptions.asMap().entries.map((e) {
                final selected = _selectedServiceIndex == e.key;
                final name = e.value['name'] as String? ??
                    '${context.tr('booking_option_prefix')} ${e.key + 1}';
                String? subtitle;
                if (_isAccommodation) {
                  final bedsSummary = RoomModel.bedsSummaryFromMap(e.value);
                  final size = e.value['sizeSquareMeters'];
                  final parts = <String>[
                    if (bedsSummary.isNotEmpty) bedsSummary,
                    if (size != null) '$size m²',
                  ];
                  subtitle = parts.isEmpty ? null : parts.join(' · ');
                } else if (widget.serviceType == 'menuItems') {
                  final dietary = MenuItemModel.dietarySummaryFromMap(e.value);
                  final spicyLevel =
                      (e.value['spicyLevel'] as num?)?.toInt() ?? 0;
                  final parts = <String>[
                    if (dietary.isNotEmpty) dietary,
                    if (spicyLevel > 0) '🌶️' * spicyLevel,
                  ];
                  subtitle = parts.isEmpty ? null : parts.join(' · ');
                }
                return _SelectableTile(
                  title: name,
                  subtitle: subtitle,
                  selected: selected,
                  onTap: () => setState(() => _selectedServiceIndex = e.key),
                );
              }),
              const SizedBox(height: 20),
            ],

            // ── Dates ────────────────────────────────────────────────────
            _sectionLabel(_isAccommodation
                ? context.tr('booking_section_checkin_checkout')
                : context.tr('booking_section_preferred_date')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _DatePickerTile(
                  label: _isAccommodation
                      ? context.tr('booking_label_checkin')
                      : context.tr('booking_label_date'),
                  date: _requestedDate,
                  onTap: () => _pickDate(isCheckOut: false),
                ),
              ),
              if (_isAccommodation) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerTile(
                    label: context.tr('booking_label_checkout'),
                    date: _checkOutDate,
                    onTap: () => _pickDate(isCheckOut: true),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // ── Guests ───────────────────────────────────────────────────
            _sectionLabel(context.tr('booking_section_guests')),
            const SizedBox(height: 10),
            Row(children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: _guests > 1 ? () => setState(() => _guests--) : null,
              ),
              Container(
                width: 56,
                alignment: Alignment.center,
                child: Text('$_guests',
                    style: TextStyle(color: _P.textPri, fontSize: 18)),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: () => setState(() => _guests++),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Price estimate ───────────────────────────────────────────
            if (_priceEstimate != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _P.aqua.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _P.aqua.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: _P.aquaBright, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('booking_estimated_total'),
                        style: TextStyle(color: _P.textSec, fontSize: 13)),
                  ),
                  Text(
                    '${_priceEstimate!.currency} ${_priceEstimate!.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: _P.textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.tr('booking_estimate_disclaimer'),
                  style: TextStyle(color: _P.textMute, fontSize: 11),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Payment method ───────────────────────────────────────────
            if (widget.paymentMethods.isNotEmpty) ...[
              _sectionLabel(context.tr('booking_section_payment_method')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.paymentMethods.map((m) {
                  final selected = _selectedPaymentMethodId == m.id;
                  return ChoiceChip(
                    label: Text(m.name),
                    avatar: m.icon != null && m.icon!.isNotEmpty
                        ? Text(m.icon!, style: const TextStyle(fontSize: 12))
                        : null,
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _selectedPaymentMethodId = m.id),
                    selectedColor: _P.aqua.withValues(alpha: 0.35),
                    backgroundColor: _P.overlay(0.08),
                    labelStyle: TextStyle(
                        color: selected ? _P.textPri : _P.textSec,
                        fontSize: 12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // ── Notes ────────────────────────────────────────────────────
            _sectionLabel(context.tr('booking_section_special_requests')),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: TextStyle(color: _P.textPri),
              decoration: InputDecoration(
                hintText: context.tr('booking_notes_hint'),
                hintStyle: TextStyle(color: _P.textMute),
                filled: true,
                fillColor: _P.overlay(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _P.aquaBright,
                  foregroundColor: _P.deepNavy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _P.deepNavy))
                    : Text(context.tr('booking_button_request'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(
          color: _P.textPri, fontSize: 15, fontWeight: FontWeight.bold));
}

class _SelectableTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _SelectableTile(
      {required this.title,
      this.subtitle,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? _P.aqua.withValues(alpha: 0.25) : _P.overlay(0.06),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: selected ? _P.aquaBright : _P.overlay(0.15)),
          ),
          child: Row(children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? _P.aquaBright : _P.textMute,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: _P.textPri)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(color: _P.textMute, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ]),
        ),
      );
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DatePickerTile(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _P.overlay(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _P.overlay(0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: _P.aquaBright),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(color: _P.textMute, fontSize: 11)),
                  Text(
                    date != null
                        ? '${date!.day}/${date!.month}/${date!.year}'
                        : context.tr('booking_label_select'),
                    style: TextStyle(color: _P.textPri, fontSize: 13),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap != null ? _P.overlay(0.10) : _P.overlay(0.03),
            border: Border.all(color: _P.overlay(0.15)),
          ),
          child: Icon(icon,
              size: 18, color: onTap != null ? _P.textPri : _P.textMute),
        ),
      );
}
