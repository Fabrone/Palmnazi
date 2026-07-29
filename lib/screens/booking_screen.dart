import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/screens/my_bookings_screen.dart';
import 'package:palmnazi/screens/payment_simulation_screen.dart';
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
  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
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
          colorScheme: const ColorScheme.dark(
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
      setState(() => _error = 'You must be signed in to book.');
      return;
    }
    if (_isAccommodation && _checkOutDate == null) {
      setState(() => _error = 'Select a check-out date.');
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
              _error = '"$serviceName" is already booked for that date. '
                  'Pick a different date or option.';
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
      await BookingService.create(booking);
      if (mounted) _showSuccess();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Booking failed: $e';
          _saving = false;
        });
      }
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _P.deepNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          SizedBox(width: 10),
          Text('Booking requested', style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          'Your booking request for "${widget.place.name}" has been sent. '
          'You\'ll see its status under My Bookings.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(true); // booking screen
            },
            child: const Text('Done', style: TextStyle(color: Colors.white54)),
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
            child: const Text('View My Bookings',
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
        title: Text('Book ${widget.place.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
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
                  ? 'Select a ${widget.serviceLabel}'
                  : 'Select an option'),
              const SizedBox(height: 10),
              ...widget.serviceOptions.asMap().entries.map((e) {
                final selected = _selectedServiceIndex == e.key;
                final name =
                    e.value['name'] as String? ?? 'Option ${e.key + 1}';
                return _SelectableTile(
                  title: name,
                  selected: selected,
                  onTap: () => setState(() => _selectedServiceIndex = e.key),
                );
              }),
              const SizedBox(height: 20),
            ],

            // ── Dates ────────────────────────────────────────────────────
            _sectionLabel(
                _isAccommodation ? 'Check-in / Check-out' : 'Preferred Date'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _DatePickerTile(
                  label: _isAccommodation ? 'Check-in' : 'Date',
                  date: _requestedDate,
                  onTap: () => _pickDate(isCheckOut: false),
                ),
              ),
              if (_isAccommodation) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerTile(
                    label: 'Check-out',
                    date: _checkOutDate,
                    onTap: () => _pickDate(isCheckOut: true),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // ── Guests ───────────────────────────────────────────────────
            _sectionLabel('Number of Guests'),
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
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
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
                  const Expanded(
                    child: Text('Estimated Total',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  Text(
                    '${_priceEstimate!.currency} ${_priceEstimate!.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Estimate only — the final amount is confirmed by the place.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Payment method ───────────────────────────────────────────
            if (widget.paymentMethods.isNotEmpty) ...[
              _sectionLabel('Payment Method'),
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
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // ── Notes ────────────────────────────────────────────────────
            _sectionLabel('Special Requests (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Any special requirements…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _P.deepNavy))
                    : const Text('Request Booking',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
}

class _SelectableTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  const _SelectableTile(
      {required this.title, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? _P.aqua.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? _P.aquaBright
                    : Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? _P.aquaBright : Colors.white38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white)),
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
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                  Text(
                    date != null
                        ? '${date!.day}/${date!.month}/${date!.year}'
                        : 'Select',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
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
            color: onTap != null
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon,
              size: 18, color: onTap != null ? Colors.white : Colors.white24),
        ),
      );
}
