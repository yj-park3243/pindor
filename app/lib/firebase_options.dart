// File generated based on FlutterFire configuration.
// Project: pins-488a8

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform is not supported.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAfZRLwpdvOFx_EhIefvt2T3TX05ZC8X2w',
    appId: '1:391322938059:android:aba8a85507c3e820f4494e',
    messagingSenderId: '391322938059',
    projectId: 'pins-488a8',
    storageBucket: 'pins-488a8.firebasestorage.app',
    androidClientId: '391322938059-9dvosholo0nf9au1f74o6s6lcmrlekju.apps.googleusercontent.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBx002T-XCQuNOsUo0azC6-uQxejKz2EP0',
    appId: '1:391322938059:ios:f57882af58a03e0bf4494e',
    messagingSenderId: '391322938059',
    projectId: 'pins-488a8',
    storageBucket: 'pins-488a8.firebasestorage.app',
    iosBundleId: 'kr.pins',
    iosClientId: '391322938059-2rle7rqcpfgeac2qmagmivhb3fs9nqj9.apps.googleusercontent.com',
  );

}