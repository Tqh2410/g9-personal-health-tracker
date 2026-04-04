import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBojEUWLZL9O8qIVO-jlnnj6pusNYMPJdY',
    appId: '1:93165388661:web:personal-health-diary',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    authDomain: 'personal-health-diary.firebaseapp.com',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBojEUWLZL9O8qIVO-jlnnj6pusNYMPJdY',
    appId: '1:93165388661:android:c5b4d19b551178975e093c',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBDdVfRw6oz56PE-F_sgV2c4lBcKjPe-SI',
    appId: '1:93165388661:ios:dde61a7ffbbbaef75e093c',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    iosBundleId: 'com.example.personalHealthDiary',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBDdVfRw6oz56PE-F_sgV2c4lBcKjPe-SI',
    appId: '1:93165388661:ios:dde61a7ffbbbaef75e093c',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    iosBundleId: 'com.example.personalHealthDiary',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBojEUWLZL9O8qIVO-jlnnj6pusNYMPJdY',
    appId: '1:93165388661:web:personal-health-diary',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyBojEUWLZL9O8qIVO-jlnnj6pusNYMPJdY',
    appId: '1:93165388661:web:personal-health-diary',
    messagingSenderId: '93165388661',
    projectId: 'personal-health-diary',
    storageBucket: 'personal-health-diary.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions is not supported for this platform.',
        );
    }
  }
}
