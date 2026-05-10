import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform. '
          'Run flutterfire configure for iOS/macOS/Windows support.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCT-LFOxFnQJI7QrxUE1ZzqQVbYp7o1Umc',
    appId: '1:486417428487:android:480e3e57a0624c77293aa2',
    messagingSenderId: '486417428487',
    projectId: 'myapp-e5237',
    storageBucket: 'myapp-e5237.firebasestorage.app',
    databaseURL:
        'https://myapp-e5237-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD6gXLQsxiQ55ytoZmsgpwTfezWbMomn4Y',
    authDomain: 'budisciplink.web.app',
    projectId: 'myapp-e5237',
    storageBucket: 'myapp-e5237.firebasestorage.app',
    messagingSenderId: '486417428487',
    appId: '1:486417428487:web:4d97c48e7a5ceace293aa2',
  );
}
