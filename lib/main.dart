import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase: only initialize on mobile/web where google-services / options exist.
  // On Windows desktop this would crash without firebase_options.dart.
  try {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      await Firebase.initializeApp();
    } else if (kIsWeb) {
      await Firebase.initializeApp();
    }
    // Desktop (Windows/macOS/Linux) — skip for now until firebase_options generated
  } catch (e) {
    debugPrint('Firebase init skipped/failed: $e');
  }

  // Initialize Hive (Offline-First)
  await Hive.initFlutter();
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');

  runApp(const WesiOSApp());
}
