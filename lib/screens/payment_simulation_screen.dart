import 'dart:async';

import 'package:flutter/material.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/services/mpesa_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentSimulationScreen
//
// Walks a tourist through paying for a booking with the PaymentMethod they
// chose. M-Pesa is wired to Safaricom's Daraja SANDBOX STK Push — a real
// prompt goes out and Safaricom's own test harness resolves it a few seconds
// later; no real phone or money is involved, but it is a genuine gateway
// round-trip (see MpesaService / functions/index.js). Card, PayPal, bank
// transfer, and cash remain pure UI simulations using the placeholder
// gateway config an admin entered on the Payment Methods screen, since those
// gateways aren't integrated yet.
//
// Pops a [PaymentOutcome] when the tourist finishes or backs out.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
}

/// Result of a payment attempt. [mpesaReceiptNumber]/[mpesaTransactionRef]
/// are only ever set for a real (M-Pesa) success — every other method is
/// still a simulation and carries neither.
class PaymentOutcome {
  final bool success;
  final String? mpesaReceiptNumber;
  final String? mpesaTransactionRef;

  const PaymentOutcome({
    required this.success,
    this.mpesaReceiptNumber,
    this.mpesaTransactionRef,
  });
}

enum _Stage { input, sending, waiting, success, failed, processing, done }

class PaymentSimulationScreen extends StatefulWidget {
  final PaymentMethodModel method;
  final double amount;
  final String currency;
  final String placeName;

  const PaymentSimulationScreen({
    super.key,
    required this.method,
    required this.amount,
    required this.currency,
    required this.placeName,
  });

  @override
  State<PaymentSimulationScreen> createState() =>
      _PaymentSimulationScreenState();
}

class _PaymentSimulationScreenState extends State<PaymentSimulationScreen> {
  _Stage _stage = _Stage.input;
  String? _error;

  final _phoneCtrl = TextEditingController(text: '07');
  final _cardNumberCtrl = TextEditingController();
  final _cardExpiryCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();

  // ── M-Pesa real-flow state ─────────────────────────────────────────────
  String? _transactionRef;
  StreamSubscription<Map<String, dynamic>?>? _txSub;
  String? _mpesaReceiptNumber;

  bool get _isMpesa => widget.method.type == PaymentMethodType.mpesa;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isMpesa) {
      await _confirmMpesa();
    } else {
      await _confirmSimulated();
    }
  }

  // ── Real M-Pesa STK push ───────────────────────────────────────────────
  Future<void> _confirmMpesa() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter a valid Safaricom number.');
      return;
    }
    setState(() {
      _error = null;
      _stage = _Stage.sending;
    });

    final ref = MpesaService.newTransactionRef();
    _transactionRef = ref;

    try {
      await MpesaService.initiate(
        transactionRef: ref,
        phoneNumber: phone,
        amount: widget.amount,
        placeName: widget.placeName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error = e.toString();
      });
      return;
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.waiting);

    _txSub = MpesaService.watchTransaction(ref).listen((data) {
      if (!mounted || data == null) return;
      final status = data['status'] as String?;
      if (status == 'success') {
        setState(() {
          _mpesaReceiptNumber = data['mpesaReceiptNumber'] as String?;
          _stage = _Stage.success;
        });
        _txSub?.cancel();
      } else if (status == 'failed') {
        setState(() {
          _error = data['resultDesc'] as String? ??
              'The M-Pesa request was not completed.';
          _stage = _Stage.failed;
        });
        _txSub?.cancel();
      }
    });
  }

  Future<void> _checkNow() async {
    final ref = _transactionRef;
    if (ref == null) return;
    await MpesaService.queryStatus(ref);
  }

  void _retryMpesa() {
    _txSub?.cancel();
    setState(() {
      _stage = _Stage.input;
      _error = null;
      _transactionRef = null;
    });
  }

  // ── Non-M-Pesa simulation ──────────────────────────────────────────────
  Future<void> _confirmSimulated() async {
    setState(() => _stage = _Stage.processing);
    await Future.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _stage = _Stage.done);
  }

  String get _amountLabel =>
      '${widget.currency} ${widget.amount.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final canGoBack = _stage == _Stage.input || _stage == _Stage.failed;
    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: AppBar(
        backgroundColor: _P.deepNavy,
        automaticallyImplyLeading: canGoBack,
        title: Text('Pay with ${widget.method.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_stage) {
            _Stage.input => _buildInputStage(),
            _Stage.sending =>
              _buildBusyStage('Sending STK push to your phone…'),
            _Stage.waiting => _buildWaitingStage(),
            _Stage.success => _buildMpesaSuccessStage(),
            _Stage.failed => _buildMpesaFailedStage(),
            _Stage.processing => _buildBusyStage(_processingMessage()),
            _Stage.done => _buildDoneStage(),
          },
        ),
      ),
    );
  }

  // ── Amount banner (shown on every stage) ──────────────────────────────────
  Widget _amountBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: _P.aqua.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _P.aqua.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Text(widget.placeName,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_amountLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  // ── Input stage — differs per payment method type ─────────────────────────
  Widget _buildInputStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amountBanner(),
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
          ..._inputFieldsForType(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: _P.aquaBright,
              foregroundColor: _P.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_confirmLabelForType(),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          if (_isMpesa) ...[
            const SizedBox(height: 12),
            _noteBox(
                'Sandbox mode — this sends a real Daraja STK push request, but Safaricom\'s own test harness resolves it automatically. No real phone or money is involved.'),
          ],
        ],
      ),
    );
  }

  String _confirmLabelForType() {
    switch (widget.method.type) {
      case PaymentMethodType.mpesa:
        return 'Send STK Push';
      case PaymentMethodType.card:
        return 'Pay Now';
      case PaymentMethodType.paypal:
        return 'Continue to PayPal';
      case PaymentMethodType.bankTransfer:
        return "I've Made the Transfer";
      case PaymentMethodType.cash:
        return 'Confirm — Pay on Arrival';
      case PaymentMethodType.other:
        return 'Confirm Payment';
    }
  }

  List<Widget> _inputFieldsForType() {
    final config = widget.method.config;
    switch (widget.method.type) {
      case PaymentMethodType.mpesa:
        return [
          const Text('M-Pesa Phone Number',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          _field(_phoneCtrl, '07XX XXX XXX', TextInputType.phone),
          const SizedBox(height: 12),
          _noteBox(
              'An STK push will be sent to this number for ${config['paybillNumber'] != null ? 'Paybill ${config['paybillNumber']}' : 'the configured paybill'} (sandbox shortcode is used under the hood).'),
        ];
      case PaymentMethodType.card:
        return [
          const Text('Card Details',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          _field(_cardNumberCtrl, 'Card Number', TextInputType.number),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child:
                    _field(_cardExpiryCtrl, 'MM/YY', TextInputType.datetime)),
            const SizedBox(width: 10),
            Expanded(child: _field(_cardCvvCtrl, 'CVV', TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _noteBox('Card details are never sent anywhere in this demo.'),
        ];
      case PaymentMethodType.paypal:
        return [
          _noteBox(
              'You would be redirected to PayPal to sign in and approve payment to ${config['merchantEmail'] ?? 'the configured merchant account'}.'),
        ];
      case PaymentMethodType.bankTransfer:
        return [
          const Text('Transfer Instructions',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          _infoTile('Bank', config['bankName'] ?? 'Not yet configured'),
          _infoTile('Account Number',
              config['accountNumber'] ?? 'Not yet configured'),
          _infoTile(
              'Account Name', config['accountName'] ?? 'Not yet configured'),
        ];
      case PaymentMethodType.cash:
        return [
          _noteBox('Pay in cash directly at ${widget.placeName} upon arrival.'),
        ];
      case PaymentMethodType.other:
        return [
          _noteBox(
              'Payment will be arranged directly with ${widget.placeName}.'),
        ];
    }
  }

  Widget _field(TextEditingController ctrl, String hint, TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 12))),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ]),
      );

  Widget _noteBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4)),
          ),
        ]),
      );

  // ── Busy stage (shared) ────────────────────────────────────────────────
  Widget _buildBusyStage(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _P.aquaBright),
          const SizedBox(height: 20),
          Text(message,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _processingMessage() {
    switch (widget.method.type) {
      case PaymentMethodType.card:
        return 'Processing card payment…';
      case PaymentMethodType.paypal:
        return 'Redirecting to PayPal…';
      case PaymentMethodType.bankTransfer:
        return 'Recording your transfer…';
      case PaymentMethodType.cash:
        return 'Confirming arrangement…';
      default:
        return 'Processing…';
    }
  }

  // ── M-Pesa: waiting for the STK push to be resolved ────────────────────
  Widget _buildWaitingStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amountBanner(),
          const Center(child: CircularProgressIndicator(color: _P.aquaBright)),
          const SizedBox(height: 20),
          const Text(
            'Check your phone and enter your M-Pesa PIN to complete this payment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'Sent to ${_phoneCtrl.text.trim()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _checkNow,
            style: OutlinedButton.styleFrom(
              foregroundColor: _P.aquaBright,
              side: const BorderSide(color: _P.aquaBright),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("I've entered my PIN — check now"),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _retryMpesa,
            child: const Text('Cancel and go back',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ── M-Pesa: succeeded for real ──────────────────────────────────────────
  Widget _buildMpesaSuccessStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amountBanner(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text('M-Pesa payment received',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              if (_mpesaReceiptNumber != null)
                Text('Receipt: $_mpesaReceiptNumber',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sandbox transaction — this ran against Safaricom\'s Daraja test environment. No real money moved.',
                      style:
                          TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              PaymentOutcome(
                success: true,
                mpesaReceiptNumber: _mpesaReceiptNumber,
                mpesaTransactionRef: _transactionRef,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _P.aquaBright,
              foregroundColor: _P.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── M-Pesa: failed / cancelled ────────────────────────────────────────
  Widget _buildMpesaFailedStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amountBanner(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.cancel_rounded, color: Colors.redAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Payment not completed',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _error ?? 'The M-Pesa request was cancelled or timed out.',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _retryMpesa,
            style: ElevatedButton.styleFrom(
              backgroundColor: _P.aquaBright,
              foregroundColor: _P.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Try Again',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const PaymentOutcome(success: false)),
            child: const Text('Back out of booking',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ── Non-M-Pesa: done (simulated) ────────────────────────────────────────
  Widget _buildDoneStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amountBanner(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Payment flow complete (simulated)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _completionMessage(),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a demonstration only. No real money has moved and no live payment gateway was contacted.',
                      style:
                          TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(const PaymentOutcome(success: true)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _P.aquaBright,
              foregroundColor: _P.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _completionMessage() {
    switch (widget.method.type) {
      case PaymentMethodType.card:
        return 'In a live integration, this card would be charged $_amountLabel via ${widget.method.config['publishableKey'] != null ? 'the configured card gateway' : 'a card gateway (not yet configured)'}.';
      case PaymentMethodType.paypal:
        return 'In a live integration, you would have approved a $_amountLabel payment on PayPal to ${widget.method.config['merchantEmail'] ?? 'the configured merchant account'}.';
      case PaymentMethodType.bankTransfer:
        return 'Your booking will be held pending manual confirmation that $_amountLabel was transferred to the account shown.';
      case PaymentMethodType.cash:
        return 'Your booking is recorded — please pay $_amountLabel in cash at ${widget.placeName} upon arrival.';
      default:
        return 'Your booking is recorded — payment arrangements for $_amountLabel will be confirmed directly with ${widget.placeName}.';
    }
  }
}
