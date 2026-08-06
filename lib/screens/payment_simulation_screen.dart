import 'dart:async';

import 'package:flutter/material.dart';
import 'package:palmnazi/models/payment_method_model.dart';
import 'package:palmnazi/services/app_settings_controller.dart';
import 'package:palmnazi/services/app_strings.dart';
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
      setState(() => _error = context.tr('payment_sim_error_invalid_phone'));
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
              context.tr('payment_sim_mpesa_not_completed');
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
        title: Text(
            '${context.tr('payment_sim_appbar_title_prefix')} ${widget.method.name}',
            style: TextStyle(color: _P.textPri, fontSize: 16)),
        iconTheme: IconThemeData(color: _P.textPri),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_stage) {
            _Stage.input => _buildInputStage(),
            _Stage.sending =>
              _buildBusyStage(context.tr('payment_sim_stage_sending')),
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
              style: TextStyle(color: _P.textMute, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_amountLabel,
              style: TextStyle(
                  color: _P.textPri,
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
            _noteBox(context.tr('payment_sim_note_sandbox_mode')),
          ],
        ],
      ),
    );
  }

  String _confirmLabelForType() {
    switch (widget.method.type) {
      case PaymentMethodType.mpesa:
        return context.tr('payment_sim_btn_send_stk');
      case PaymentMethodType.card:
        return context.tr('payment_sim_btn_pay_now');
      case PaymentMethodType.paypal:
        return context.tr('payment_sim_btn_continue_paypal');
      case PaymentMethodType.bankTransfer:
        return context.tr('payment_sim_btn_made_transfer');
      case PaymentMethodType.cash:
        return context.tr('payment_sim_btn_confirm_cash');
      case PaymentMethodType.other:
        return context.tr('payment_sim_btn_confirm_payment');
    }
  }

  List<Widget> _inputFieldsForType() {
    final config = widget.method.config;
    switch (widget.method.type) {
      case PaymentMethodType.mpesa:
        final paybillText = config['paybillNumber'] != null
            ? '${context.tr('payment_sim_paybill_label')} ${config['paybillNumber']}'
            : context.tr('payment_sim_configured_paybill');
        return [
          Text(context.tr('payment_sim_label_mpesa_phone'),
              style: TextStyle(color: _P.textSec, fontSize: 13)),
          const SizedBox(height: 8),
          _field(_phoneCtrl, context.tr('payment_sim_hint_phone'),
              TextInputType.phone),
          const SizedBox(height: 12),
          _noteBox(
              '${context.tr('payment_sim_note_stk_prefix')} $paybillText ${context.tr('payment_sim_note_stk_suffix')}'),
        ];
      case PaymentMethodType.card:
        return [
          Text(context.tr('payment_sim_label_card_details'),
              style: TextStyle(color: _P.textSec, fontSize: 13)),
          const SizedBox(height: 8),
          _field(_cardNumberCtrl, context.tr('payment_sim_hint_card_number'),
              TextInputType.number),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _field(
                    _cardExpiryCtrl,
                    context.tr('payment_sim_hint_expiry'),
                    TextInputType.datetime)),
            const SizedBox(width: 10),
            Expanded(
                child: _field(_cardCvvCtrl, context.tr('payment_sim_hint_cvv'),
                    TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _noteBox(context.tr('payment_sim_note_card_demo')),
        ];
      case PaymentMethodType.paypal:
        return [
          _noteBox(
              '${context.tr('payment_sim_note_paypal_prefix')} ${config['merchantEmail'] ?? context.tr('payment_sim_configured_merchant')}.'),
        ];
      case PaymentMethodType.bankTransfer:
        return [
          Text(context.tr('payment_sim_label_transfer_instructions'),
              style: TextStyle(color: _P.textSec, fontSize: 13)),
          const SizedBox(height: 8),
          _infoTile(context.tr('payment_sim_field_bank'),
              config['bankName'] ?? context.tr('payment_sim_not_configured')),
          _infoTile(
              context.tr('payment_sim_field_account_number'),
              config['accountNumber'] ??
                  context.tr('payment_sim_not_configured')),
          _infoTile(
              context.tr('payment_sim_field_account_name'),
              config['accountName'] ??
                  context.tr('payment_sim_not_configured')),
        ];
      case PaymentMethodType.cash:
        return [
          _noteBox(
              '${context.tr('payment_sim_note_cash_prefix')} ${widget.placeName} ${context.tr('payment_sim_note_cash_suffix')}'),
        ];
      case PaymentMethodType.other:
        return [
          _noteBox(
              '${context.tr('payment_sim_note_other_prefix')} ${widget.placeName}.'),
        ];
    }
  }

  Widget _field(TextEditingController ctrl, String hint, TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: TextStyle(color: _P.textPri),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _P.textMute),
        filled: true,
        fillColor: _P.overlay(0.06),
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
                  style: TextStyle(color: _P.textMute, fontSize: 12))),
          Expanded(
            child:
                Text(value, style: TextStyle(color: _P.textPri, fontSize: 13)),
          ),
        ]),
      );

  Widget _noteBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _P.overlay(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: _P.textMute, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(color: _P.textMute, fontSize: 12, height: 1.4)),
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
              style: TextStyle(color: _P.textSec, fontSize: 14),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _processingMessage() {
    switch (widget.method.type) {
      case PaymentMethodType.card:
        return context.tr('payment_sim_processing_card');
      case PaymentMethodType.paypal:
        return context.tr('payment_sim_processing_paypal');
      case PaymentMethodType.bankTransfer:
        return context.tr('payment_sim_processing_bank');
      case PaymentMethodType.cash:
        return context.tr('payment_sim_processing_cash');
      default:
        return context.tr('payment_sim_processing_default');
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
          Text(
            context.tr('payment_sim_waiting_instructions'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _P.textSec, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${context.tr('payment_sim_sent_to_prefix')} ${_phoneCtrl.text.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(color: _P.textMute, fontSize: 12),
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
            child: Text(context.tr('payment_sim_btn_check_now')),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _retryMpesa,
            child: Text(context.tr('payment_sim_btn_cancel_back'),
                style: TextStyle(color: _P.textMute)),
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
              Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.tr('payment_sim_success_title'),
                      style: TextStyle(
                          color: _P.textPri,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              if (_mpesaReceiptNumber != null)
                Text(
                    '${context.tr('payment_sim_receipt_prefix')} $_mpesaReceiptNumber',
                    style: TextStyle(
                        color: _P.textSec, fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('payment_sim_sandbox_transaction_note'),
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 12),
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
            child: Text(context.tr('payment_sim_btn_continue'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
              Row(children: [
                const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.tr('payment_sim_failed_title'),
                      style: TextStyle(
                          color: _P.textPri,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _error ?? context.tr('payment_sim_failed_default_message'),
                style: TextStyle(color: _P.textSec, fontSize: 13, height: 1.5),
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
            child: Text(context.tr('payment_sim_btn_try_again'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const PaymentOutcome(success: false)),
            child: Text(context.tr('payment_sim_btn_back_out'),
                style: TextStyle(color: _P.textMute)),
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
              Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.tr('payment_sim_done_title'),
                      style: TextStyle(
                          color: _P.textPri,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _completionMessage(),
                style: TextStyle(color: _P.textSec, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('payment_sim_demo_note'),
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 12),
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
            child: Text(context.tr('payment_sim_btn_continue'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _completionMessage() {
    final cardGatewayText = widget.method.config['publishableKey'] != null
        ? context.tr('payment_sim_configured_card_gateway')
        : context.tr('payment_sim_card_gateway_not_configured');
    final merchantText = widget.method.config['merchantEmail'] ??
        context.tr('payment_sim_configured_merchant');
    switch (widget.method.type) {
      case PaymentMethodType.card:
        return '${context.tr('payment_sim_completion_card_prefix')} $_amountLabel ${context.tr('payment_sim_completion_card_via')} $cardGatewayText.';
      case PaymentMethodType.paypal:
        return '${context.tr('payment_sim_completion_paypal_prefix')} $_amountLabel ${context.tr('payment_sim_completion_paypal_middle')} $merchantText.';
      case PaymentMethodType.bankTransfer:
        return '${context.tr('payment_sim_completion_bank_prefix')} $_amountLabel ${context.tr('payment_sim_completion_bank_suffix')}';
      case PaymentMethodType.cash:
        return '${context.tr('payment_sim_completion_cash_prefix')} $_amountLabel ${context.tr('payment_sim_completion_cash_middle')} ${widget.placeName} ${context.tr('payment_sim_note_cash_suffix')}';
      default:
        return '${context.tr('payment_sim_completion_default_prefix')} $_amountLabel ${context.tr('payment_sim_completion_default_middle')} ${widget.placeName}.';
    }
  }
}
