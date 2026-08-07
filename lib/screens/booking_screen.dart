import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:palmnazi/models/booking_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/models/place_payment_instruction_model.dart';
import 'package:palmnazi/models/menu_item_model.dart';
import 'package:palmnazi/models/room_model.dart';
import 'package:palmnazi/screens/my_bookings_screen.dart';
import 'package:palmnazi/screens/payment_simulation_screen.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/booking_service.dart';
import 'package:palmnazi/services/menu_service.dart';
import 'package:palmnazi/services/place_payment_service.dart';
import 'package:palmnazi/services/room_service.dart';
import 'package:palmnazi/services/service_type_style.dart';
import 'package:palmnazi/widgets/main_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookingScreen
//
// Tourist-facing booking form, opened from PlaceDetailsScreen's "Book Now"
// button. Requires the user to be signed in (enforced by the caller, which
// routes to AuthScreen first if not).
//
// Two modes:
//  - Single-service (legacy): lets the tourist pick one nested service (a
//    room, menu item, or show — whichever applies to this place's category)
//    from `serviceOptions`, exactly as before. Used whenever `servicesByType`
//    is not supplied (or empty) by the caller.
//  - Cart (Phase 5C): when `servicesByType` is supplied, the tourist builds a
//    cart of one or more services (potentially spanning several types — e.g.
//    a room AND a dining item from the same place) via "Add another service
//    from this place", each with its own date(s)/guest count, and checks out
//    in one go via `BookingService.createGroup`.
//
// Payment: M-Pesa keeps its existing real Daraja sandbox round-trip via
// PaymentSimulationScreen. Any other method shows the place's own
// PlacePaymentInstructions plus a payment-reference text field; on submit,
// `BookingService.submitPaymentProof` is called for each created booking so
// its status becomes `paymentSubmitted` right away.
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

/// One entry in a multi-service booking cart — see BookingScreen's class
/// doc. Each entry carries its own date(s) and guest count independently of
/// every other entry in the cart.
class _BookingCartItem {
  final String type; // 'rooms' | 'menuItems' | 'shows' | 'exhibitions'
  final Map<String, dynamic> item;
  DateTime requestedDate;
  DateTime? checkOutDate;
  int guests;

  _BookingCartItem({
    required this.type,
    required this.item,
    required this.requestedDate,
    required this.guests,
  }) : checkOutDate = null;

  bool get isAccommodation => type == 'rooms';
  String get name => item['name'] as String? ?? 'Untitled';
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

  /// Pre-selects `serviceOptions[initialServiceIndex]` on open — set when
  /// arriving from ServiceDetailScreen's "Book This" CTA, where the tourist
  /// already picked a specific item rather than choosing from the list here.
  final int? initialServiceIndex;

  /// Every service this place offers, across every type it offers (rooms,
  /// menuItems, shows, exhibitions), keyed by type — powers the cart-based
  /// "Add another service from this place" flow. Null/empty falls back to
  /// the legacy single-service picker built from [serviceOptions] alone.
  final Map<String, List<Map<String, dynamic>>>? servicesByType;

  const BookingScreen({
    super.key,
    required this.place,
    required this.city,
    this.serviceOptions = const [],
    this.serviceLabel = '',
    this.serviceType = '',
    this.paymentMethods = const [],
    this.initialServiceIndex,
    this.servicesByType,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _requestedDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _checkOutDate;
  int _guests = 1;
  final _notesCtrl = TextEditingController();
  final _paymentProofCtrl = TextEditingController();
  int? _selectedServiceIndex;
  String? _selectedPaymentMethodId;
  bool _saving = false;
  String? _error;

  // ── Multi-service cart (Phase 5C) ─────────────────────────────────────
  final List<_BookingCartItem> _cart = [];

  bool get _hasServicesByType => widget.servicesByType?.isNotEmpty ?? false;

  // ── Live catalog sync ──────────────────────────────────────────────────
  // Once a service is picked, we subscribe to its live Firestore doc so a
  // price/availability edit the admin makes while this form is open shows up
  // here instead of silently going stale — see RoomService.streamOne /
  // MenuService.streamItem. `_livePriceChanged` flags the "Updated by host"
  // notice; it only fires once the *live* price actually differs from the
  // price captured when the service was first selected. Only wired up for
  // the legacy single-service path — cart entries don't live-sync.
  StreamSubscription<dynamic>? _liveServiceSub;
  Map<String, dynamic>? _liveServiceData;
  double? _initialUnitPrice;
  bool _livePriceChanged = false;

  bool get _isAccommodation => widget.serviceType == 'rooms';

  Map<String, dynamic>? get _selectedService => _selectedServiceIndex != null &&
          _selectedServiceIndex! < widget.serviceOptions.length
      ? widget.serviceOptions[_selectedServiceIndex!]
      : null;

  /// The static snapshot merged with whatever the live stream has picked up
  /// — falls back to the static snapshot until the first live event arrives.
  Map<String, dynamic>? get _effectiveService =>
      _liveServiceData ?? _selectedService;

  EstimatedPrice? get _priceEstimate => estimateBookingTotal(
        placeMinPrice: widget.place.pricing?.min,
        placeCurrency: widget.place.pricing?.currency,
        service: _effectiveService,
        serviceType: widget.serviceType,
        guests: _guests,
        checkIn: _requestedDate,
        checkOut: _checkOutDate,
      );

  PaymentMethodModel? get _selectedPaymentMethod => widget.paymentMethods
      .where((m) => m.id == _selectedPaymentMethodId)
      .firstOrNull;

  bool get _isMpesaSelected =>
      _selectedPaymentMethod?.type == PaymentMethodType.mpesa;

  List<EstimatedPrice?> get _cartEstimates => _cart
      .map((c) => estimateBookingTotal(
            placeMinPrice: widget.place.pricing?.min,
            placeCurrency: widget.place.pricing?.currency,
            service: c.item,
            serviceType: c.type,
            guests: c.guests,
            checkIn: c.requestedDate,
            checkOut: c.checkOutDate,
          ))
      .toList();

  double get _cartTotal =>
      _cartEstimates.fold<double>(0.0, (sum, e) => sum + (e?.amount ?? 0));

  String get _cartCurrency {
    for (final e in _cartEstimates) {
      if (e != null) return e.currency;
    }
    return widget.place.pricing?.currency ?? 'KES';
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialServiceIndex;
    if (_hasServicesByType) {
      // Cart mode: seed the cart with whatever item the caller pre-selected
      // (arriving from ServiceDetailScreen's "Book This" CTA), if any.
      if (initial != null &&
          initial >= 0 &&
          initial < widget.serviceOptions.length &&
          widget.serviceType.isNotEmpty) {
        _cart.add(_BookingCartItem(
          type: widget.serviceType,
          item: widget.serviceOptions[initial],
          requestedDate: _requestedDate,
          guests: _guests,
        ));
      }
    } else if (initial != null &&
        initial >= 0 &&
        initial < widget.serviceOptions.length) {
      _selectedServiceIndex = initial;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _subscribeToLiveService());
    }
  }

  void _selectService(int index) {
    setState(() {
      _selectedServiceIndex = index;
      _liveServiceData = null;
      _livePriceChanged = false;
      _initialUnitPrice = null;
    });
    _subscribeToLiveService();
  }

  void _subscribeToLiveService() {
    _liveServiceSub?.cancel();
    _liveServiceSub = null;

    final service = _selectedService;
    final id = service?['id'] as String?;
    if (id == null) return;

    _initialUnitPrice = widget.serviceType == 'rooms'
        ? (service?['basePrice'] as num?)?.toDouble()
        : (service?['price'] as num?)?.toDouble();

    if (widget.serviceType == 'rooms') {
      _liveServiceSub = RoomService.streamOne(id).listen((room) {
        if (!mounted || room == null) return;
        _onLiveServiceUpdate(room.toCreateMap(), room.basePrice);
      });
    } else if (widget.serviceType == 'menuItems') {
      _liveServiceSub = MenuService.streamItem(id).listen((item) {
        if (!mounted || item == null) return;
        _onLiveServiceUpdate(item.toCreateMap(), item.price);
      });
    }
  }

  void _onLiveServiceUpdate(Map<String, dynamic> data, double livePrice) {
    setState(() {
      _liveServiceData = {..._selectedService ?? {}, ...data};
      if (_initialUnitPrice != null && livePrice != _initialUnitPrice) {
        _livePriceChanged = true;
      }
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _paymentProofCtrl.dispose();
    _liveServiceSub?.cancel();
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

  // ── Cart helpers (Phase 5C) ─────────────────────────────────────────────

  bool _alreadyInCart(String type, Map<String, dynamic> item) {
    final itemId = item['id'];
    return _cart.any((c) {
      if (c.type != type) return false;
      if (itemId != null && c.item['id'] != null) {
        return c.item['id'] == itemId;
      }
      return identical(c.item, item);
    });
  }

  void _addToCart(String type, Map<String, dynamic> item) {
    setState(() {
      _cart.add(_BookingCartItem(
        type: type,
        item: item,
        requestedDate: _requestedDate,
        guests: _guests,
      ));
    });
  }

  Future<void> _pickCartDate(int index, {required bool isCheckOut}) async {
    final entry = _cart[index];
    final initial = isCheckOut
        ? (entry.checkOutDate ??
            entry.requestedDate.add(const Duration(days: 1)))
        : entry.requestedDate;
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
        entry.checkOutDate = picked;
      } else {
        entry.requestedDate = picked;
        if (entry.checkOutDate != null &&
            !entry.checkOutDate!.isAfter(picked)) {
          entry.checkOutDate = null;
        }
      }
    });
  }

  void _openAddServiceSheet() {
    final servicesByType = widget.servicesByType ?? const {};
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _P.deepNavy,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            final grouped = <String, List<Map<String, dynamic>>>{};
            for (final type in servicesByType.keys) {
              final available = (servicesByType[type] ?? const [])
                  .where((item) => !_alreadyInCart(type, item))
                  .toList();
              if (available.isNotEmpty) grouped[type] = available;
            }
            if (grouped.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Every service from this place is already in your cart.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _P.textMute),
                  ),
                ),
              );
            }
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text('Add a service',
                    style: TextStyle(
                        color: _P.textPri,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                for (final type in grouped.keys) ...[
                  Text(
                    ServiceTypeStyle.forItemType(type).label,
                    style: TextStyle(
                        color: _P.textMute,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 8),
                  ...grouped[type]!.map((item) {
                    final style = ServiceTypeStyle.forItemType(type);
                    final name = item['name'] as String? ?? 'Untitled';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: _P.overlay(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: style.accent.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        leading: Icon(style.icon, color: style.accent),
                        title: Text(name, style: TextStyle(color: _P.textPri)),
                        onTap: () {
                          _addToCart(type, item);
                          Navigator.of(sheetCtx).pop();
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // ── Submit dispatch ──────────────────────────────────────────────────────

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = context.tr('booking_error_signin'));
      return;
    }
    if (_cart.isNotEmpty) {
      await _submitCart(user);
    } else {
      await _submitSingle(user);
    }
  }

  /// Legacy single-service submit path — unchanged behaviour for a place
  /// with only one service type (or reached via the old direct single-
  /// service flow), aside from the new non-M-Pesa payment-proof step.
  Future<void> _submitSingle(User user) async {
    if (_isAccommodation && _checkOutDate == null) {
      setState(() => _error = context.tr('booking_error_select_checkout'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final selectedService = _effectiveService;
    final selectedPayment = _selectedPaymentMethod;
    final isMpesa = selectedPayment?.type == PaymentMethodType.mpesa;

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

      // M-Pesa is a real Daraja sandbox round-trip via PaymentSimulationScreen
      // — untouched. Every other method skips that screen entirely and uses
      // the place's own PlacePaymentInstructions + reference text below.
      var paymentSimulated = false;
      String? mpesaReceiptNumber;
      String? mpesaTransactionRef;
      if (selectedPayment != null && isMpesa && estimate != null) {
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

      String? proofText;
      if (selectedPayment != null && !isMpesa) {
        proofText = _paymentProofCtrl.text.trim();
        if (proofText.isEmpty) {
          setState(() {
            _error = 'Please enter a payment reference before submitting.';
            _saving = false;
          });
          return;
        }
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

      if (selectedPayment != null && !isMpesa && proofText != null) {
        await BookingService.submitPaymentProof(bookingId, text: proofText);
      }

      if (mounted) _showSuccess([bookingId], serviceName: serviceName);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Booking failed: $e';
          _saving = false;
        });
      }
    }
  }

  /// Cart submit path (Phase 5C) — builds one BookingModel per cart entry
  /// and writes them all together via BookingService.createGroup, sharing a
  /// generated bookingGroupId. Runs the same hasConflict guard per entry.
  Future<void> _submitCart(User user) async {
    if (_cart.any((c) => c.isAccommodation && c.checkOutDate == null)) {
      setState(() => _error = context.tr('booking_error_select_checkout'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final selectedPayment = _selectedPaymentMethod;
    final isMpesa = selectedPayment?.type == PaymentMethodType.mpesa;

    try {
      for (final c in _cart) {
        final serviceName = c.item['name'] as String?;
        if (serviceName == null) continue;
        final conflict = await BookingService.hasConflict(
          placeId: widget.place.id,
          serviceName: serviceName,
          requestedDate: c.requestedDate,
          checkOutDate: c.isAccommodation ? c.checkOutDate : null,
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

      final estimates = _cartEstimates;
      final totalAmount = _cartTotal;
      final currency = _cartCurrency;

      var paymentSimulated = false;
      String? mpesaReceiptNumber;
      String? mpesaTransactionRef;
      if (selectedPayment != null && isMpesa && totalAmount > 0) {
        if (!mounted) return;
        final outcome = await Navigator.of(context).push<PaymentOutcome>(
          MaterialPageRoute(
            builder: (_) => PaymentSimulationScreen(
              method: selectedPayment,
              amount: totalAmount,
              currency: currency,
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

      String? proofText;
      if (selectedPayment != null && !isMpesa) {
        proofText = _paymentProofCtrl.text.trim();
        if (proofText.isEmpty) {
          setState(() {
            _error = 'Please enter a payment reference before submitting.';
            _saving = false;
          });
          return;
        }
      }

      final bookings = <BookingModel>[];
      for (var i = 0; i < _cart.length; i++) {
        final c = _cart[i];
        final estimate = i < estimates.length ? estimates[i] : null;
        bookings.add(BookingModel(
          id: '',
          placeId: widget.place.id,
          placeName: widget.place.name,
          cityId: widget.city.id,
          cityName: widget.city.name,
          firebaseUid: user.uid,
          userEmail: user.email ?? '',
          serviceType: c.type,
          serviceName: c.item['name'] as String?,
          serviceId: c.item['id'] as String?,
          requestedDate: c.requestedDate,
          checkOutDate: c.isAccommodation ? c.checkOutDate : null,
          numberOfGuests: c.guests,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          paymentMethodId: selectedPayment?.id,
          paymentMethodName: selectedPayment?.name,
          paymentSimulated: paymentSimulated,
          mpesaReceiptNumber: mpesaReceiptNumber,
          mpesaTransactionRef: mpesaTransactionRef,
          totalAmount: estimate?.amount,
          currency: estimate?.currency,
          cancellationPolicy: widget.place.bookingSettings?.cancellationPolicy,
        ));
      }

      final ids = await BookingService.createGroup(bookings);

      if (selectedPayment != null && !isMpesa && proofText != null) {
        for (final id in ids) {
          await BookingService.submitPaymentProof(id, text: proofText);
        }
      }

      if (mounted) _showSuccess(ids);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Booking failed: $e';
          _saving = false;
        });
      }
    }
  }

  void _showSuccess(List<String> bookingIds, {String? serviceName}) {
    // A truncated, uppercased tail of the Firestore doc id — short enough to
    // read aloud or write down at a front desk, while the full id (kept
    // underneath, copyable) remains available for exact lookup.
    final primaryId = bookingIds.first;
    final shortRef = primaryId.length > 8
        ? primaryId.substring(primaryId.length - 8).toUpperCase()
        : primaryId.toUpperCase();
    final isGroup = bookingIds.length > 1;

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
            if (isGroup) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.layers_rounded, size: 16, color: _P.aquaBright),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${bookingIds.length} services booked',
                      style: TextStyle(
                          color: _P.textPri, fontWeight: FontWeight.w600)),
                ),
              ]),
            ] else if (serviceName != null) ...[
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
                    Clipboard.setData(ClipboardData(text: primaryId));
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
      appBar: PalmnaziNavBar(
        compact: true,
        showBack: true,
        title: '${context.tr('booking_appbar_prefix')} ${widget.place.name}',
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final form = _formColumn(context);
          final summary = _summaryColumn(context);

          if (!wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [form, const SizedBox(height: 24), summary],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 28),
                  Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [summary],
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _formColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],

        // ── Service selection ─────────────────────────────────────────
        if (_hasServicesByType) ...[
          _buildCartSection(context),
          const SizedBox(height: 20),
        ] else if (widget.serviceOptions.isNotEmpty) ...[
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
              final spicyLevel = (e.value['spicyLevel'] as num?)?.toInt() ?? 0;
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
              onTap: () => _selectService(e.key),
            );
          }),
          const SizedBox(height: 20),
        ],

        // ── Dates / Guests ───────────────────────────────────────────
        // In cart mode, every cart entry carries its own date(s)/guest
        // count (rendered inside _buildCartSection above) — no global
        // date/guest picker is shown.
        if (!_hasServicesByType) ...[
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
                    color: selected ? _P.textPri : _P.textSec, fontSize: 12),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // ── Place payment instructions + proof (non-M-Pesa only) ──────
        if (_selectedPaymentMethod != null && !_isMpesaSelected) ...[
          _buildPaymentProofSection(context),
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
      ],
    );
  }

  // ── Cart section (Phase 5C) ───────────────────────────────────────────
  Widget _buildCartSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Your services'),
        const SizedBox(height: 10),
        if (_cart.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _P.overlay(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _P.overlay(0.12)),
            ),
            child: Text(
              'No services added yet — add one below to get started.',
              style: TextStyle(color: _P.textMute, fontSize: 13),
            ),
          )
        else
          ..._cart
              .asMap()
              .entries
              .map((e) => _buildCartRow(context, e.key, e.value)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openAddServiceSheet,
          icon: Icon(Icons.add_rounded, color: _P.aquaBright),
          label: Text('Add another service from this place',
              style: TextStyle(color: _P.aquaBright)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _P.aquaBright.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildCartRow(BuildContext context, int index, _BookingCartItem c) {
    final style = ServiceTypeStyle.forItemType(c.type);
    final estimate = estimateBookingTotal(
      placeMinPrice: widget.place.pricing?.min,
      placeCurrency: widget.place.pricing?.currency,
      service: c.item,
      serviceType: c.type,
      guests: c.guests,
      checkIn: c.requestedDate,
      checkOut: c.checkOutDate,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _P.overlay(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(style.icon, size: 16, color: style.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.name,
                  style: TextStyle(
                      color: _P.textPri, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(style.label,
                  style: TextStyle(
                      color: style.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: _P.textMute),
              tooltip: 'Remove',
              onPressed: () => setState(() => _cart.removeAt(index)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _DatePickerTile(
                label: c.isAccommodation ? 'Check-in' : 'Date',
                date: c.requestedDate,
                onTap: () => _pickCartDate(index, isCheckOut: false),
              ),
            ),
            if (c.isAccommodation) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _DatePickerTile(
                  label: 'Check-out',
                  date: c.checkOutDate,
                  onTap: () => _pickCartDate(index, isCheckOut: true),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text('Guests', style: TextStyle(color: _P.textMute, fontSize: 12)),
            const Spacer(),
            _StepperButton(
              icon: Icons.remove_rounded,
              onTap: c.guests > 1 ? () => setState(() => c.guests--) : null,
            ),
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text('${c.guests}', style: TextStyle(color: _P.textPri)),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              onTap: () => setState(() => c.guests++),
            ),
          ]),
          if (estimate != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${estimate.currency} ${estimate.unitPrice.toStringAsFixed(0)} × ${estimate.multiplier} ${estimate.unitLabel}',
                    style: TextStyle(color: _P.textSec, fontSize: 12),
                  ),
                ),
                Text(
                  '${estimate.currency} ${estimate.amount.toStringAsFixed(0)}',
                  style:
                      TextStyle(color: _P.textPri, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Payment proof section (non-M-Pesa) ────────────────────────────────
  Widget _buildPaymentProofSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _P.overlay(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _P.aquaBright.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: _P.aquaBright),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Payment instructions from ${widget.place.name}',
                style: TextStyle(
                    color: _P.textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          StreamBuilder<List<PlacePaymentInstructionModel>>(
            stream: PlacePaymentService.streamForPlace(widget.place.id),
            builder: (context, snap) {
              if (!snap.hasData) {
                return Text('Loading payment instructions…',
                    style: TextStyle(color: _P.textMute, fontSize: 12));
              }
              final match = snap.data!
                  .where((i) =>
                      i.paymentMethodId == _selectedPaymentMethodId &&
                      i.isActive)
                  .toList();
              if (match.isEmpty) {
                return Text(
                  'This place has not published instructions for '
                  '${_selectedPaymentMethod?.name ?? 'this method'} yet — '
                  'please contact them directly, or add a reference below '
                  'once you have paid.',
                  style: TextStyle(color: _P.textMute, fontSize: 12),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: match
                    .map((i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(i.instructions,
                              style: TextStyle(
                                  color: _P.textSec,
                                  fontSize: 13,
                                  height: 1.4)),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentProofCtrl,
            style: TextStyle(color: _P.textPri),
            decoration: InputDecoration(
              labelText: 'Payment reference',
              hintText: 'e.g. M-Pesa code, bank transfer reference…',
              labelStyle: TextStyle(color: _P.textMute),
              hintStyle: TextStyle(color: _P.textMute),
              filled: true,
              fillColor: _P.overlay(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live, itemized price summary + submit ─────────────────────────────
  Widget _summaryColumn(BuildContext context) {
    if (_hasServicesByType) return _cartSummaryColumn(context);

    final estimate = _priceEstimate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _P.overlay(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _P.overlay(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.receipt_long_rounded, color: _P.aquaBright, size: 20),
            const SizedBox(width: 8),
            Text(context.tr('booking_estimated_total'),
                style: TextStyle(
                    color: _P.textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          if (estimate != null) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(
                    '${estimate.amount}-${estimate.unitPrice}-${estimate.multiplier}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${estimate.currency} ${estimate.unitPrice.toStringAsFixed(0)} × ${estimate.multiplier} ${estimate.unitLabel}',
                        style: TextStyle(color: _P.textSec, fontSize: 13),
                      ),
                      Text(
                        '${estimate.currency} ${estimate.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: _P.textPri,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_livePriceChanged) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Updated by host — the price above just changed.',
                      style: TextStyle(
                          color: Colors.amber.shade200, fontSize: 11.5),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              context.tr('booking_estimate_disclaimer'),
              style: TextStyle(color: _P.textMute, fontSize: 11),
            ),
          ] else
            Text(
              context.tr('booking_select_option'),
              style: TextStyle(color: _P.textMute, fontSize: 13),
            ),
          const SizedBox(height: 20),
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
    );
  }

  Widget _cartSummaryColumn(BuildContext context) {
    final estimates = _cartEstimates;
    final total = _cartTotal;
    final currency = _cartCurrency;
    final hasPricing = estimates.any((e) => e != null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _P.overlay(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _P.overlay(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.receipt_long_rounded, color: _P.aquaBright, size: 20),
            const SizedBox(width: 8),
            Text(context.tr('booking_estimated_total'),
                style: TextStyle(
                    color: _P.textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          if (_cart.isEmpty)
            Text('Add at least one service to see pricing.',
                style: TextStyle(color: _P.textMute, fontSize: 13))
          else if (hasPricing) ...[
            ..._cart.asMap().entries.map((e) {
              final est = e.key < estimates.length ? estimates[e.key] : null;
              if (est == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(e.value.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _P.textSec, fontSize: 12)),
                    ),
                    Text('${est.currency} ${est.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: _P.textPri,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
            Divider(color: _P.overlay(0.12), height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: TextStyle(
                        color: _P.textPri, fontWeight: FontWeight.bold)),
                Text('$currency ${total.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: _P.textPri,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('booking_estimate_disclaimer'),
              style: TextStyle(color: _P.textMute, fontSize: 11),
            ),
          ] else
            Text(
              context.tr('booking_select_option'),
              style: TextStyle(color: _P.textMute, fontSize: 13),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || _cart.isEmpty) ? null : _submit,
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
