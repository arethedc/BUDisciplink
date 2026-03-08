
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD6gXLQsxiQ55ytoZmsgpwTfezWbMomn4Y',
    authDomain: 'myapp-e5237.firebaseapp.com',
    projectId: 'myapp-e5237',
    storageBucket: 'myapp-e5237.firebasestorage.app',
    messagingSenderId: '486417428487',
    appId: '1:486417428487:web:bfd953553bcf5d49293aa2',
  );
}
