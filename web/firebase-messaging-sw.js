// firebase-messaging-sw.js
//
// Background/terminated-tab push handler for Flutter Web. Firebase Cloud
// Messaging requires this file to live at the web root (same origin, no
// subpath) so the browser can register it as a service worker.
//
// The config values below are the same public web config already shipped in
// lib/firebase_options.dart (Firebase web config values are not secret —
// access is governed by Firestore/Storage security rules, not by hiding
// these ids). No action needed here.
//
// This is registered automatically by firebase_messaging's web plugin; you
// do not need to add a <script> tag for it in web/index.html.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA-OwuhtX8cNYCGhFB9f5j5HCoNp12xpm0',
  appId: '1:33305405962:web:43892855cd598b68e44df3',
  messagingSenderId: '33305405962',
  projectId: 'palmnazi-5259e',
  authDomain: 'palmnazi-5259e.firebaseapp.com',
  storageBucket: 'palmnazi-5259e.firebasestorage.app',
});

const messaging = firebase.messaging();

// Shows a notification when a push arrives while no tab has focus. Messages
// sent with a `notification` payload (as our Cloud Functions do — see
// functions/index.js onBookingCreated / onBookingStatusChanged) are usually
// auto-displayed by the browser already; this handler covers data-only
// messages and gives us control over the notification's appearance.
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Palmnazi';
  const body = payload.notification?.body || '';
  self.registration.showNotification(title, {
    body,
    icon: '/favicon.png',
    data: payload.data,
  });
});
