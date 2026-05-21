import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:apps/services/app_firestore.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handled by OS tray notification for background/terminated states.
}

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;
  String? _activeUid;
  String? _activeToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      if (token.trim().isEmpty) return;
      final previousToken = _activeToken;
      _activeToken = token.trim();
      final uid = _activeUid;
      if (uid == null || uid.isEmpty) return;
      if (previousToken != null &&
          previousToken.isNotEmpty &&
          previousToken != _activeToken) {
        await _deleteTokenDoc(uid: uid, token: previousToken);
      }
      await _saveTokenDoc(uid: uid, token: _activeToken!);
    });

    // Optional hook point for future deep-link handling.
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});
    await _messaging.getInitialMessage();

    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? user) async {
    final nextUid = user?.uid.trim() ?? '';
    final oldUid = _activeUid;
    final oldToken = _activeToken;

    // On sign-out, Firestore rules often block deletes because auth becomes null.
    // We keep token cleanup to authenticated transitions (uid switch / token refresh).
    final isSigningOut = nextUid.isEmpty;
    if (oldUid != null &&
        oldUid.isNotEmpty &&
        oldToken != null &&
        oldToken.isNotEmpty &&
        (!isSigningOut && nextUid != oldUid)) {
      await _deleteTokenDoc(uid: oldUid, token: oldToken);
    }

    if (nextUid.isEmpty) {
      _activeUid = null;
      _activeToken = null;
      return;
    }
    _activeUid = nextUid;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final status = settings.authorizationStatus;
      if (status == AuthorizationStatus.denied) {
        return;
      }
    } catch (_) {
      return;
    }

    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    _activeToken = token;
    await _saveTokenDoc(uid: nextUid, token: token);
  }

  Future<String?> _resolveToken() async {
    try {
      if (kIsWeb) {
        const webVapidKey = String.fromEnvironment('WEB_PUSH_CERTIFICATE_KEY');
        if (webVapidKey.isNotEmpty) {
          return await _messaging.getToken(vapidKey: webVapidKey);
        }
        return await _messaging.getToken();
      }
      return await _messaging.getToken();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Push token resolve failed: $error');
      }
      return null;
    }
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  Future<void> _saveTokenDoc({
    required String uid,
    required String token,
  }) async {
    try {
      await AppFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
            'token': token,
            'platform': _platformLabel(),
            'updatedAt': FieldValue.serverTimestamp(),
            'enabled': true,
          }, SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Save FCM token failed for $uid: $error');
      }
    }
  }

  Future<void> _deleteTokenDoc({
    required String uid,
    required String token,
  }) async {
    try {
      await AppFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .delete();
    } on FirebaseException catch (error) {
      // Expected in some sign-out/session-expired flows depending on rules.
      if (error.code != 'permission-denied' && kDebugMode) {
        debugPrint('Delete FCM token failed for $uid: $error');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Delete FCM token failed for $uid: $error');
      }
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _initialized = false;
  }
}
