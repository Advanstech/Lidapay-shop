import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Generated based on android/app/google-services.json for project `lidapay-68d41`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDWU43AhoShTJlkrq6DPq6ajvgk-mhJe1M',
    appId: '1:864151944445:android:5f80b8163e104b8d06d294',
    messagingSenderId: '864151944445',
    projectId: 'lidapay-68d41',
    storageBucket: 'lidapay-68d41.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDWU43AhoShTJlkrq6DPq6ajvgk-mhJe1M',
    appId: '1:864151944445:ios:5f80b8163e104b8d06d294',
    messagingSenderId: '864151944445',
    projectId: 'lidapay-68d41',
    storageBucket: 'lidapay-68d41.firebasestorage.app',
    iosBundleId: 'com.advansistechnologies.lidapay',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDWU43AhoShTJlkrq6DPq6ajvgk-mhJe1M',
    appId: '1:864151944445:web:5f80b8163e104b8d06d294',
    messagingSenderId: '864151944445',
    projectId: 'lidapay-68d41',
    storageBucket: 'lidapay-68d41.firebasestorage.app',
  );
}
