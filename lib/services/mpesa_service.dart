import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MpesaService
//
// Client half of the Safaricom Daraja SANDBOX STK Push integration. Calls the
// initiateMpesaPayment / queryMpesaStatus Cloud Functions (functions/index.js)
// directly via HTTP POST with a Bearer ID token, matching the onRequest
// pattern already used elsewhere in this app — Flutter Web's onCall path can
// silently drop the auth token (see the WHY comment atop functions/index.js).
//
// The actual payment result arrives asynchronously via Safaricom's callback,
// which the mpesaCallback Cloud Function writes onto
// Transactions/{transactionRef}; watchTransaction() streams that doc so the
// UI updates the moment it lands, without polling.
// ─────────────────────────────────────────────────────────────────────────────

class MpesaException implements Exception {
  final String message;
  MpesaException(this.message);

  @override
  String toString() => message;
}

class MpesaService {
  MpesaService._();

  static final Logger _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );

  static const String _projectId = 'palmnazi-5259e';
  static const String _region = 'us-central1';

  static String _functionUrl(String name) =>
      'https://$_region-$_projectId.cloudfunctions.net/$name';

  /// Pre-allocates a Transactions/{id} document id the client controls, so
  /// the STK push's AccountReference and the Firestore doc it writes to can
  /// be linked before either the push or the doc exists.
  static String newTransactionRef() =>
      FirebaseFirestore.instance.collection('Transactions').doc().id;

  /// Sends the STK push. Throws [MpesaException] with a user-facing message
  /// on failure. On success, the result lands asynchronously — see
  /// [watchTransaction].
  static Future<void> initiate({
    required String transactionRef,
    required String phoneNumber,
    required double amount,
    required String placeName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw MpesaException('You must be signed in.');
    final idToken = await user.getIdToken(true);

    http.Response resp;
    try {
      resp = await http.post(
        Uri.parse(_functionUrl('initiateMpesaPayment')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {
            'transactionRef': transactionRef,
            'phoneNumber': phoneNumber,
            'amount': amount,
            'placeName': placeName,
          },
        }),
      );
    } catch (e) {
      _log.w('⚠️ MpesaService.initiate: network error — $e');
      throw MpesaException(
          'Could not reach the payment server. Check your connection and try again.');
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      _log.i('📲 MpesaService.initiate: STK push sent — ref=$transactionRef');
      return;
    }

    String message = 'Could not start the M-Pesa payment. Please try again.';
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      message = body['error']?['message'] as String? ?? message;
    } catch (_) {}
    _log.w('⚠️ MpesaService.initiate: ${resp.statusCode} — $message');
    throw MpesaException(message);
  }

  /// Best-effort poll for when Safaricom's async callback is delayed or lost
  /// (occasionally flaky on the sandbox). Safe to call repeatedly — errors
  /// are swallowed since [watchTransaction] remains the source of truth.
  static Future<void> queryStatus(String transactionRef) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse(_functionUrl('queryMpesaStatus')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'transactionRef': transactionRef},
        }),
      );
    } catch (e) {
      _log.w('⚠️ MpesaService.queryStatus: $e');
    }
  }

  /// Live status of a Transactions/{transactionRef} doc. Fields of interest:
  /// status ('pending' | 'success' | 'failed'), mpesaReceiptNumber, resultDesc.
  static Stream<Map<String, dynamic>?> watchTransaction(String transactionRef) {
    return FirebaseFirestore.instance
        .collection('Transactions')
        .doc(transactionRef)
        .snapshots()
        .map((doc) => doc.data());
  }
}
