// Web-only Firebase configuration for the operator console.
// Public client config copied from fluterFront/lib/firebase_options.dart.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAvzOHlhLnUpDxQKQPqj4H_cpmECpNiEO4',
    appId: '1:1088534743968:web:6933bcab8c61fc8bd7f2c5',
    messagingSenderId: '1088534743968',
    projectId: 'tfg-carecoins',
    authDomain: 'tfg-carecoins.firebaseapp.com',
    storageBucket: 'tfg-carecoins.firebasestorage.app',
    measurementId: 'G-FE0YM7LRQM',
  );
}
