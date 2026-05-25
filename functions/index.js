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
const admin      = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();
const db = admin.firestore();

// ── Email transport ───────────────────────────────────────────────────────────
const transporter = nodemailer.createTransport({
  host:   process.env.EMAIL_HOST,
  port:   Number(process.env.EMAIL_PORT ?? 465),
  secure: process.env.EMAIL_SECURE !== 'false',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

const FROM = `"${process.env.EMAIL_FROM_NAME ?? 'App'}" <${process.env.EMAIL_USER}>`;

// ── OTP config ────────────────────────────────────────────────────────────────
const OTP_DIGITS    = 6;
const OTP_TTL_MS    = 10 * 60 * 1000;
const MAX_ATTEMPTS  = 5;
const RATE_LIMIT_MS = 60 * 1000;

function generateOtp() {
  return String(Math.floor(Math.random() * Math.pow(10, OTP_DIGITS)))
    .padStart(OTP_DIGITS, '0');
}

function otpDocRef(uid) {
  return db.collection('_mfa_otps').doc(uid);
}

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

// ── SEND OTP ──────────────────────────────────────────────────────────────────
exports.mfaSendOtp = functions.https.onRequest(async (req, res) => {
  applyCors(req, res);

  // Respond to the browser CORS preflight immediately.
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  // ── Auth ────────────────────────────────────────────────────────────────────
  let decoded;
  try {
    decoded = await requireAuth(req);
  } catch (err) {
    sendError(res, err);
    return;
  }

  const uid = decoded.uid;

  // The Dart client sends: {"data": {"email": "..."}}
  // Unpack the "data" wrapper added by _callFunctionViaHttp.
  const data  = req.body?.data ?? req.body ?? {};
  const email = (data.email ?? decoded.email ?? '').trim().toLowerCase();

  if (!email) {
    sendError(res, new functions.https.HttpsError('invalid-argument', 'email is required.'));
    return;
  }

  // ── Rate limiting ────────────────────────────────────────────────────────────
  const existing = await otpDocRef(uid).get();
  if (existing.exists) {
    const sentAt = existing.data().sentAt?.toMillis() ?? 0;
    if (Date.now() - sentAt < RATE_LIMIT_MS) {
      sendError(res, new functions.https.HttpsError(
        'resource-exhausted',
        'Please wait before requesting another code.',
      ));
      return;
    }
  }

  // ── Generate and store OTP ────────────────────────────────────────────────
  const otp = generateOtp();
  await otpDocRef(uid).set({
    otp,
    email,
    sentAt:    admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + OTP_TTL_MS),
    attempts:  0,
  });

  // ── Send email ────────────────────────────────────────────────────────────
  try {
    await transporter.sendMail({
      from:    FROM,
      to:      email,
      subject: 'Your verification code',
      text:    `Your one-time code is: ${otp}\n\nIt expires in 10 minutes. Do not share it.`,
      html: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto">
          <h2 style="color:#1E3A5F">Email Verification</h2>
          <p>Use the code below to enable two-factor authentication.</p>
          <div style="
            font-size:36px;letter-spacing:12px;font-weight:bold;
            background:#f4f4f4;border-radius:8px;padding:20px;
            text-align:center;color:#1E3A5F;margin:24px 0
          ">${otp}</div>
          <p style="color:#888;font-size:13px">
            This code expires in <strong>10 minutes</strong>.<br>
            If you did not request this, you can safely ignore this email.
          </p>
        </div>
      `,
    });
  } catch (mailErr) {
    console.error('mfaSendOtp: sendMail failed —', mailErr);
    // Clean up the stored OTP so the user can retry without rate-limit penalty.
    await otpDocRef(uid).delete().catch(() => {});
    sendError(res, new functions.https.HttpsError(
      'internal',
      'Failed to send email. Please try again.',
    ));
    return;
  }

  console.log(`mfaSendOtp: OTP sent to ${email} for uid ${uid}`);
  // Success shape: {"result": {...}} matches the Dart parser's expectations.
  res.status(200).json({ result: { message: 'OTP sent.' } });
});

// ── VERIFY OTP ────────────────────────────────────────────────────────────────
exports.mfaVerifyOtp = functions.https.onRequest(async (req, res) => {
  applyCors(req, res);

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  let decoded;
  try {
    decoded = await requireAuth(req);
  } catch (err) {
    sendError(res, err);
    return;
  }

  const uid  = decoded.uid;
  const data = req.body?.data ?? req.body ?? {};
  const otp  = (data.otp ?? '').trim();

  if (!otp || otp.length !== OTP_DIGITS) {
    sendError(res, new functions.https.HttpsError('invalid-argument', 'Invalid OTP format.'));
    return;
  }

  const docRef  = otpDocRef(uid);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    sendError(res, new functions.https.HttpsError(
      'not-found',
      'No pending OTP. Please request a new code.',
    ));
    return;
  }

  const stored = docSnap.data();

  if (stored.expiresAt.toMillis() < Date.now()) {
    await docRef.delete();
    sendError(res, new functions.https.HttpsError(
      'deadline-exceeded',
      'Code has expired. Please request a new one.',
    ));
    return;
  }

  if ((stored.attempts ?? 0) >= MAX_ATTEMPTS) {
    await docRef.delete();
    sendError(res, new functions.https.HttpsError(
      'resource-exhausted',
      'Too many incorrect attempts. Please request a new code.',
    ));
    return;
  }

  if (stored.otp !== otp) {
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    const remaining = MAX_ATTEMPTS - (stored.attempts + 1);
    sendError(res, new functions.https.HttpsError(
      'invalid-argument',
      `Incorrect code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`,
    ));
    return;
  }

  // Success
  const batch = db.batch();
  batch.delete(docRef);
  batch.set(
    db.collection('Users').doc(uid),
    { mfaEnabled: true, mfaEnabledAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
  await batch.commit();

  console.log(`mfaVerifyOtp: MFA enabled for uid ${uid}`);
  res.status(200).json({ result: { message: 'MFA enabled.', mfaEnabled: true } });
});

// ── DISABLE MFA ───────────────────────────────────────────────────────────────
exports.mfaDisable = functions.https.onRequest(async (req, res) => {
  applyCors(req, res);

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  let decoded;
  try {
    decoded = await requireAuth(req);
  } catch (err) {
    sendError(res, err);
    return;
  }

  const uid = decoded.uid;

  await db.collection('Users').doc(uid).set(
    { mfaEnabled: false, mfaDisabledAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
  await otpDocRef(uid).delete().catch(() => {});

  console.log(`mfaDisable: MFA disabled for uid ${uid}`);
  res.status(200).json({ result: { message: 'MFA disabled.', mfaEnabled: false } });
});