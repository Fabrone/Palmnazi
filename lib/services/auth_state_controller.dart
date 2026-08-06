import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthStateController
//
// App-wide, reactive Firebase Auth sign-in state. Owned once at the root (see
// main.dart) and exposed down the tree via AuthStateScope so any screen's nav
// bar can reflect the live session instead of a one-shot check taken at
// initState — the bug this fixes: several screens rendered "Sign In / Get
// Started" even while signed in because they never re-read auth state after
// the first frame.
// ─────────────────────────────────────────────────────────────────────────────
class AuthStateController extends ChangeNotifier {
  AuthStateController._internal() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  static final AuthStateController instance = AuthStateController._internal();

  late final StreamSubscription<User?> _sub;

  User? _user = FirebaseAuth.instance.currentUser;

  bool get isSignedIn => _user != null;
  User? get user => _user;
  String? get displayEmail => _user?.email;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthStateScope
//
// InheritedNotifier so any widget can do `AuthStateScope.of(context).isSignedIn`
// and rebuild automatically whenever Firebase Auth's session changes.
// ─────────────────────────────────────────────────────────────────────────────
class AuthStateScope extends InheritedNotifier<AuthStateController> {
  const AuthStateScope({
    super.key,
    required AuthStateController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthStateController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthStateScope>();
    assert(scope != null, 'No AuthStateScope found in context');
    return scope!.notifier!;
  }
}
