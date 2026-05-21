import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AppAuthBootstrap extends ChangeNotifier {
  AppAuthBootstrap._() {
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null) {
      _ready = true;
    }
    _subscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _currentUser = user;
      if (user != null) {
        _ready = true;
        _pendingNullReadyTimer?.cancel();
        _pendingNullReadyTimer = null;
      } else {
        _pendingNullReadyTimer ??= Timer(
          const Duration(milliseconds: 1200),
          () {
            _ready = true;
            notifyListeners();
          },
        );
      }
      notifyListeners();
    });
  }

  static final AppAuthBootstrap instance = AppAuthBootstrap._();

  StreamSubscription<User?>? _subscription;
  Timer? _pendingNullReadyTimer;
  bool _ready = false;
  User? _currentUser;

  bool get ready => _ready;
  User? get currentUser => _currentUser;

  @override
  void dispose() {
    _pendingNullReadyTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
