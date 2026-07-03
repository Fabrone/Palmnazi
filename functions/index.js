// index.js  — Cloud Functions v7 / Firebase Admin ^13
//
// WHY onRequest INSTEAD OF onCall
// ────────────────────────────────
// functions.https.onCall relies on the Firebase Functions client SDK
// (firebase/functions JS module) to inject the auth token into the request.
// On Flutter Web, an IndexedDB OperationError from concurrent Firestore/Auth
// writes corrupts the JS firebase/auth module's internal token cache.
// The Firebase Functions client SDK reads from that same corrupted cache, so
// it sends the Cloud Function request with no Authorization header →
// context.auth = null → 'unauthenticated'.
//
// The Flutter Dart layer bypasses this by calling functions directly via
// HTTP POST with Authorization: Bearer <idToken>, where the token is
// obtained from user.getIdToken(true) — a direct HTTPS call to Firebase Auth
// REST API that is completely independent of the JS auth module's state.
//
// onCall functions handled by Firebase's server-side SDK also use the same
// JS auth module internally for CORS context inspection, which can be equally
// affected. Using onRequest + admin.auth().verifyIdToken() is a hard separation
// from the JS auth state machine: the Admin SDK verifies the token
// cryptographically and never touches the client's IndexedDB or localStorage.
//
// CORS
// ────
// onRequest functions require explicit CORS handling.
// We allow the Authorization header so browsers (Flutter Web) can send Bearer
// tokens on cross-origin requests without the header being stripped.

const functions  = require('firebase-functions');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const admin      = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ── CORS helper ───────────────────────────────────────────────────────────────
//
// WHY WE SET Access-Control-Allow-Headers: Authorization
// ───────────────────────────────────────────────────────
// When a Flutter Web app makes a cross-origin HTTP POST that includes an
// Authorization header, the browser first sends a CORS preflight (OPTIONS).
// The server must explicitly list "Authorization" in Access-Control-Allow-Headers
// or the browser silently drops the header from the actual POST request.
// Dropping the header means the server receives no token → 401.
//
// onCall functions set this header automatically for requests made via the
// Firebase SDK (httpsCallable), but for direct HTTP calls from Flutter Web
// we must set it ourselves.
function applyCors(req, res) {
  // Allow the specific origin that made the request, or * for public functions.
  const origin = req.headers.origin || '*';
  res.set('Access-Control-Allow-Origin',  origin);
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Max-Age',       '3600');
}

// ── Auth helper ───────────────────────────────────────────────────────────────
//
// Extracts and verifies the Firebase ID token from the Authorization header.
// Returns the decoded token claims on success, or throws an HttpsError on
// failure so callers can re-use the same error-response shape as onCall.
//
// WHY admin.auth().verifyIdToken() INSTEAD OF context.auth
// ─────────────────────────────────────────────────────────
// This function runs entirely in the Firebase Admin SDK layer on the server.
// It makes a direct call to Google's public key endpoint to cryptographically
// verify the JWT signature and expiry — it has NO dependency on the client's
// IndexedDB, localStorage, or JS auth module state. A valid token from
// user.getIdToken(true) on the Dart side will always pass this check.
async function requireAuth(req) {
  const authHeader = req.headers['authorization'] ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Missing or malformed Authorization header.',
    );
  }
  const idToken = authHeader.slice(7); // strip "Bearer "
  try {
    return await admin.auth().verifyIdToken(idToken);
  } catch (err) {
    console.error('requireAuth: verifyIdToken failed —', err.code, err.message);
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Your session has expired. Please sign in again.',
    );
  }
}

// ── Unified error responder ───────────────────────────────────────────────────
//
// Converts a functions.https.HttpsError into the JSON shape that the Dart
// _callFunctionViaHttp() parser expects:
//   {"error": {"status": "UNAUTHENTICATED", "message": "..."}}
//
// HTTP status mapping follows the Firebase Functions SDK convention so that
// the Dart client can re-use its existing FirebaseFunctionsException mapper.
function sendError(res, httpsError) {
  const statusMap = {
    'ok':                200,
    'cancelled':         499,
    'unknown':           500,
    'invalid-argument':  400,
    'deadline-exceeded': 504,
    'not-found':         404,
    'already-exists':    409,
    'permission-denied': 403,
    'resource-exhausted':429,
    'failed-precondition':400,
    'aborted':           409,
    'out-of-range':      400,
    'unimplemented':     501,
    'internal':          500,
    'unavailable':       503,
    'data-loss':         500,
    'unauthenticated':   401,
  };
  const httpStatus = statusMap[httpsError.code] ?? 500;
  res.status(httpStatus).json({
    error: {
      status:  httpsError.code.toUpperCase().replace(/-/g, '_'),
      message: httpsError.message,
    },
  });
}

// ── Booking push notifications ───────────────────────────────────────────────
//
// These are Firestore-triggered (v2 API) rather than onRequest — nothing on
// the client calls them directly. The Flutter app only writes fcmToken onto
// each user's Users/{uid} doc (see push_notification_service.dart); sending
// the actual push has to happen server-side since a client can't push to
// another user's device.
//
// STATUS_LABELS mirrors BookingModel.statusLabel on the Dart side — keep
// them in sync if that ever changes.
const STATUS_LABELS = {
  pending:   'Pending',
  confirmed: 'Confirmed',
  cancelled: 'Cancelled',
  completed: 'Completed',
};

async function sendPushToUid(uid, notification, data) {
  if (!uid) return;
  const userDoc = await db.collection('Users').doc(uid).get();
  const token = userDoc.data()?.fcmToken;
  if (!token) return;
  try {
    await admin.messaging().send({ token, notification, data });
  } catch (err) {
    console.error(`sendPushToUid: failed for uid=${uid} —`, err.code, err.message);
  }
}

async function sendPushToAdmins(notification, data) {
  const snap = await db.collection('Users').where('role', 'in', ['Admin', 'MainAdmin']).get();
  const tokens = snap.docs.map((d) => d.data().fcmToken).filter(Boolean);
  if (tokens.length === 0) return;
  try {
    await admin.messaging().sendEachForMulticast({ tokens, notification, data });
  } catch (err) {
    console.error('sendPushToAdmins: failed —', err.code, err.message);
  }
}

// New booking → notify every Admin/MainAdmin with an fcmToken on file.
exports.onBookingCreated = onDocumentCreated('Bookings/{bookingId}', async (event) => {
  const booking = event.data.data();
  const serviceNote = booking.serviceName ? ` — ${booking.serviceName}` : '';
  await sendPushToAdmins(
    {
      title: '📅 New Booking Request',
      body: `${booking.userEmail || 'A tourist'} requested "${booking.placeName}"${serviceNote}.`,
    },
    { type: 'booking_created', bookingId: event.params.bookingId },
  );
});

// Booking status change → notify the tourist who made it.
exports.onBookingStatusChanged = onDocumentUpdated('Bookings/{bookingId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();
  if (before.status === after.status) return;

  const label = STATUS_LABELS[after.status] || after.status;
  await sendPushToUid(
    after.firebaseUid,
    {
      title: `Booking ${label}`,
      body: `Your booking for "${after.placeName}" is now ${label.toLowerCase()}.`,
    },
    { type: 'booking_status_changed', bookingId: event.params.bookingId, status: after.status },
  );
});

// ── M-Pesa (Daraja) — SANDBOX STK Push ───────────────────────────────────────
//
// Sandbox only. Safaricom's test environment uses a fixed test shortcode
// (174379) and shared test passkey unless MPESA_SHORTCODE/MPESA_PASSKEY
// override them, and its own test harness "presses the PIN" server-side a
// few seconds after the push — no real phone or money is involved.
//
// Flow:
//   1. Client calls initiateMpesaPayment with a client-generated
//      transactionRef (a pre-allocated Transactions/{id} doc id), a phone
//      number, and an amount. This function gets a Daraja OAuth token and
//      sends the STK push, then writes Transactions/{transactionRef} with
//      status 'pending'.
//   2. Safaricom calls mpesaCallback (public URL, no auth — it can't send our
//      Firebase ID tokens) once the customer enters their PIN or cancels.
//      That function resolves the matching Transaction to 'success'/'failed'.
//   3. The client streams Transactions/{transactionRef} directly from
//      Firestore to see the result the moment it lands. queryMpesaStatus is a
//      manual fallback for when Safaricom's sandbox callback is delayed/lost.
//
// Credentials live in functions/.env (MPESA_*) — same protection level as the
// existing EMAIL_* vars above. See that file for what needs to be filled in.
const MPESA_BASE_URL = 'https://sandbox.safaricom.co.ke';

function mpesaTimestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return (
    d.getFullYear().toString() +
    pad(d.getMonth() + 1) +
    pad(d.getDate()) +
    pad(d.getHours()) +
    pad(d.getMinutes()) +
    pad(d.getSeconds())
  );
}

async function getMpesaAccessToken() {
  const key = process.env.MPESA_CONSUMER_KEY;
  const secret = process.env.MPESA_CONSUMER_SECRET;
  if (!key || !secret) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'M-Pesa is not configured on the server (missing MPESA_CONSUMER_KEY/MPESA_CONSUMER_SECRET).',
    );
  }
  const auth = Buffer.from(`${key}:${secret}`).toString('base64');
  const resp = await fetch(`${MPESA_BASE_URL}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${auth}` },
  });
  if (!resp.ok) {
    console.error('getMpesaAccessToken: OAuth failed —', resp.status, await resp.text());
    throw new functions.https.HttpsError('unavailable', 'Could not reach M-Pesa. Please try again shortly.');
  }
  const json = await resp.json();
  return json.access_token;
}

// Normalises common Kenyan phone formats to Safaricom's expected 2547XXXXXXXX
// / 2541XXXXXXXX shape (handles 07.., +2547.., 2547.., 7...).
function normalizeMpesaPhone(raw) {
  let phone = (raw || '').toString().replace(/[\s+-]/g, '');
  if (phone.startsWith('0')) phone = `254${phone.slice(1)}`;
  else if (phone.startsWith('7') || phone.startsWith('1')) phone = `254${phone}`;
  return phone;
}

exports.initiateMpesaPayment = functions.https.onRequest(async (req, res) => {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  let decoded;
  try {
    decoded = await requireAuth(req);
  } catch (err) {
    sendError(res, err);
    return;
  }

  const data = req.body?.data ?? req.body ?? {};
  const transactionRef = (data.transactionRef ?? '').toString().trim();
  const phoneNumber = normalizeMpesaPhone(data.phoneNumber);
  const amount = Math.round(Number(data.amount));
  const placeName = (data.placeName ?? 'Palmnazi Booking').toString();

  if (!transactionRef) {
    sendError(res, new functions.https.HttpsError('invalid-argument', 'transactionRef is required.'));
    return;
  }
  if (!/^254(7|1)\d{8}$/.test(phoneNumber)) {
    sendError(res, new functions.https.HttpsError(
      'invalid-argument',
      'Enter a valid Safaricom number, e.g. 0712345678.',
    ));
    return;
  }
  if (!Number.isFinite(amount) || amount < 1) {
    sendError(res, new functions.https.HttpsError('invalid-argument', 'Invalid amount.'));
    return;
  }

  const shortcode = process.env.MPESA_SHORTCODE || '174379';
  const passkey = process.env.MPESA_PASSKEY;
  const callbackUrl = process.env.MPESA_CALLBACK_URL;
  if (!passkey || !callbackUrl) {
    sendError(res, new functions.https.HttpsError(
      'failed-precondition',
      'M-Pesa is not fully configured on the server (missing MPESA_PASSKEY/MPESA_CALLBACK_URL).',
    ));
    return;
  }

  try {
    const token = await getMpesaAccessToken();
    const timestamp = mpesaTimestamp();
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

    const stkResp = await fetch(`${MPESA_BASE_URL}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: amount,
        PartyA: phoneNumber,
        PartyB: shortcode,
        PhoneNumber: phoneNumber,
        CallBackURL: callbackUrl,
        AccountReference: transactionRef.slice(0, 12),
        TransactionDesc: placeName.slice(0, 13) || 'Booking',
      }),
    });

    const stkJson = await stkResp.json();

    if (!stkResp.ok || stkJson.ResponseCode !== '0') {
      console.error('initiateMpesaPayment: STK push rejected —', stkJson);
      await db.collection('Transactions').doc(transactionRef).set({
        firebaseUid: decoded.uid,
        method: 'mpesa',
        phoneNumber,
        amount,
        currency: 'KES',
        status: 'failed',
        resultDesc: stkJson.errorMessage || stkJson.ResponseDescription || 'STK push failed.',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      sendError(res, new functions.https.HttpsError(
        'internal',
        stkJson.errorMessage || stkJson.ResponseDescription || 'M-Pesa rejected the request.',
      ));
      return;
    }

    await db.collection('Transactions').doc(transactionRef).set({
      firebaseUid: decoded.uid,
      method: 'mpesa',
      phoneNumber,
      amount,
      currency: 'KES',
      checkoutRequestId: stkJson.CheckoutRequestID,
      merchantRequestId: stkJson.MerchantRequestID,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`initiateMpesaPayment: STK push sent — ref=${transactionRef} checkoutRequestId=${stkJson.CheckoutRequestID}`);
    res.status(200).json({
      result: {
        checkoutRequestId: stkJson.CheckoutRequestID,
        merchantRequestId: stkJson.MerchantRequestID,
      },
    });
  } catch (err) {
    if (err instanceof functions.https.HttpsError) {
      sendError(res, err);
      return;
    }
    console.error('initiateMpesaPayment: unexpected error —', err);
    sendError(res, new functions.https.HttpsError('internal', 'Could not initiate M-Pesa payment.'));
  }
});

// Public callback — Safaricom posts here once the customer enters their PIN
// (or cancels/times out). No auth is possible here: Safaricom can't send our
// Firebase ID tokens. The CheckoutRequestID it echoes back is the only link
// to a Transactions doc, so this only ever updates an already-known doc —
// it never creates bookings or moves anything on its own authority.
exports.mpesaCallback = functions.https.onRequest(async (req, res) => {
  const stkCallback = req.body?.Body?.stkCallback;
  if (!stkCallback) {
    res.status(200).json({ ResultCode: 0, ResultDesc: 'Ignored — no stkCallback body.' });
    return;
  }

  const { CheckoutRequestID, ResultCode, ResultDesc } = stkCallback;
  console.log(`mpesaCallback: CheckoutRequestID=${CheckoutRequestID} ResultCode=${ResultCode}`);

  const snap = await db.collection('Transactions')
    .where('checkoutRequestId', '==', CheckoutRequestID)
    .limit(1)
    .get();

  if (snap.empty) {
    console.warn(`mpesaCallback: no Transaction found for CheckoutRequestID=${CheckoutRequestID}`);
    res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
    return;
  }

  const doc = snap.docs[0];
  const update = {
    resultDesc: ResultDesc,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (ResultCode === 0) {
    const items = stkCallback.CallbackMetadata?.Item ?? [];
    const findVal = (name) => items.find((i) => i.Name === name)?.Value;
    update.status = 'success';
    update.mpesaReceiptNumber = findVal('MpesaReceiptNumber');
    update.amountConfirmed = findVal('Amount');
    update.transactionDate = findVal('TransactionDate');
  } else {
    update.status = 'failed';
  }

  await doc.ref.set(update, { merge: true });

  // Ack Safaricom so it stops retrying the callback.
  res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
});

// Manual fallback for when Safaricom's async callback is delayed or lost
// (occasionally flaky on the sandbox) — lets the client actively ask
// "did it happen yet?" via the STK Push Query API.
exports.queryMpesaStatus = functions.https.onRequest(async (req, res) => {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  let decoded;
  try {
    decoded = await requireAuth(req);
  } catch (err) {
    sendError(res, err);
    return;
  }

  const data = req.body?.data ?? req.body ?? {};
  const transactionRef = (data.transactionRef ?? '').toString().trim();
  if (!transactionRef) {
    sendError(res, new functions.https.HttpsError('invalid-argument', 'transactionRef is required.'));
    return;
  }

  const txRef = db.collection('Transactions').doc(transactionRef);
  const txDoc = await txRef.get();
  if (!txDoc.exists || txDoc.data().firebaseUid !== decoded.uid) {
    sendError(res, new functions.https.HttpsError('not-found', 'Transaction not found.'));
    return;
  }

  const tx = txDoc.data();
  if (tx.status !== 'pending') {
    res.status(200).json({
      result: { status: tx.status, mpesaReceiptNumber: tx.mpesaReceiptNumber ?? null },
    });
    return;
  }

  try {
    const shortcode = process.env.MPESA_SHORTCODE || '174379';
    const passkey = process.env.MPESA_PASSKEY;
    const token = await getMpesaAccessToken();
    const timestamp = mpesaTimestamp();
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

    const queryResp = await fetch(`${MPESA_BASE_URL}/mpesa/stkpushquery/v1/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        CheckoutRequestID: tx.checkoutRequestId,
      }),
    });
    const queryJson = await queryResp.json();

    if (String(queryJson.ResultCode) === '0') {
      await txRef.set({
        status: 'success',
        resultDesc: queryJson.ResultDesc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      res.status(200).json({ result: { status: 'success' } });
    } else if (queryJson.ResultCode !== undefined) {
      await txRef.set({
        status: 'failed',
        resultDesc: queryJson.ResultDesc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      res.status(200).json({ result: { status: 'failed', resultDesc: queryJson.ResultDesc } });
    } else {
      // Still awaiting the customer's PIN entry.
      res.status(200).json({ result: { status: 'pending' } });
    }
  } catch (err) {
    console.error('queryMpesaStatus: error —', err);
    res.status(200).json({ result: { status: 'pending' } });
  }
});