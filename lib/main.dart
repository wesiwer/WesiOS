import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/services/firebase_config_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive (Offline-First)
  await Hive.initFlutter();
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');

  final configService = FirebaseConfigService();
  final isConfigured = await configService.isConfigured();

  if (isConfigured) {
    try {
      final config = await configService.getConfig();
      // Only init if we have the required fields
      if (config['apiKey'] != null &&
          config['appId'] != null &&
          config['projectId'] != null &&
          config['messagingSenderId'] != null) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config['apiKey']!,
            appId: config['appId']!,
            messagingSenderId: config['messagingSenderId']!,
            projectId: config['projectId']!,
            authDomain: config['authDomain'],
            storageBucket: config['storageBucket'],
            measurementId: config['measurementId'],
          ),
        );
      }
    } catch (e) {
      debugPrint('Firebase init from saved config failed: $e');
    }
  } else {
    // Fallback: try default init on mobile/web if google-services exists
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await Firebase.initializeApp();
      } else if (kIsWeb) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('Firebase default init skipped/failed: $e');
    }
  }

  runApp(WesiOSApp(isFirstRun: !isConfigured));
}
