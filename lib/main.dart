import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/firebase_config_service.dart';
import 'features/treasury/models/transaction_model.dart';
import 'app.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop: сразу на весь экран (maximize), без true-fullscreen
  // (true fullscreen прячет панель задач и глючит на Windows)
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(900, 600),
      fullScreen: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(false);
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await Hive.initFlutter();

  Hive.registerAdapter(TransactionModelAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(RecurringPeriodAdapter());
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');

  final configService = FirebaseConfigService();
  final isConfigured = await configService.isConfigured();

  if (isConfigured) {
    try {
      final config = await configService.getConfig();
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
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase default init skipped/failed: $e');
    }
  }

  runApp(WesiOSApp(isFirstRun: !isConfigured));
}
