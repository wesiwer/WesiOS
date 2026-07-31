import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/firebase_config_service.dart';
import 'core/services/exchange_rate_service.dart';
import 'features/treasury/models/transaction_model.dart';
import 'features/tasks/models/task_model.dart';
import 'features/treasury/models/account_model.dart';
import 'features/knowledge/models/article_model.dart';
import 'features/knowledge/services/knowledge_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/app_icon_service.dart';
import 'core/theme/app_theme.dart';
import 'app.dart';
import 'core/services/currency_service.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(900, 600),
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(false);
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await Hive.initFlutter();

  Hive.registerAdapter(TransactionModelAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(RecurringPeriodAdapter());
  Hive.registerAdapter(TaskStatusAdapter());
  Hive.registerAdapter(TaskPriorityAdapter());
  Hive.registerAdapter(SubTaskAdapter());
  Hive.registerAdapter(TaskModelAdapter());
  Hive.registerAdapter(AccountKindAdapter());
  Hive.registerAdapter(AccountModelAdapter());
  Hive.registerAdapter(ArticleSectionAdapter());
  Hive.registerAdapter(ArticleModelAdapter());
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');

  CurrencyService.loadPrivacyMode();
  ThemeNotifier.load();
  AppIconService.load();

  // Auto-иконка: при смене темы переключаем activity-alias на Android.
  ThemeNotifier.instance.addListener(() {
    AppIconService.apply();
  });

  ExchangeRateService.refresh();
  AppUpdateService.check();
  KnowledgeService.seed();

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
