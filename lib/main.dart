import 'dart:async';
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
import 'features/team/models/employee_model.dart';
import 'features/team/models/team_permissions.dart';
import 'features/knowledge/services/knowledge_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/app_icon_service.dart';
import 'core/services/quote_mind_charge_service.dart';
import 'core/theme/app_theme.dart';
import 'app.dart';
import 'core/services/currency_service.dart';
import 'core/services/firebase_rest_service.dart';
import 'core/services/github_auth_service.dart';
import 'core/services/github_release_download.dart';
import 'core/services/secrets_service.dart';
import 'core/sync/sync_engine.dart';
import 'features/chats/models/chat_message.dart';
import 'features/chats/services/message_store.dart';
import 'features/team/services/team_service.dart';

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
  Hive.registerAdapter(TeamPermissionsAdapter());
  Hive.registerAdapter(EmployeeModelAdapter());
  Hive.registerAdapter(MessageKindAdapter());
  Hive.registerAdapter(DeliveryStateAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');
  await Hive.openBox<EmployeeModel>(TeamService.boxName);
  await MessageStore.open();

  // Журнал изменений подписывается на боксы до того, как человек что-то
  // поменяет. Подписка, поставленная позже, пропустила бы правки, сделанные
  // до неё, и они выглядели бы как «не менялось никогда» — то есть проиграли
  // бы любому спору с сервером и тихо стёрлись бы чужой копией.
  unawaited(SyncEngine.runOnLaunch());

  CurrencyService.loadPrivacyMode();
  ThemeNotifier.load();
  AppIconService.load();
  QuoteMindChargeService.load();
  // Ключи от внешних сервисов: сперва поднимаем локальную копию (работает
  // без сети), затем в фоне тянем свежие из облака. Человек при этом не
  // вводит ничего — в том и смысл.
  SecretsService.loadCached();
  SecretsService.sync();
  // Вход в GitHub меняет то, что вообще доступно скачать: до входа закрытый
  // репозиторий отвечает 404 и приложение это запоминает, чтобы не долбиться
  // впустую. После входа накопленное надо забыть — иначе оно продолжит
  // считать, что скачать нечего.
  GitHubAuthService.revision.addListener(GitHubReleaseDownload.forget);

  // При входе и выходе набор ключей меняется вместе с аккаунтом.
  FirebaseRestService.revision.addListener(() {
    if (FirebaseRestService.isSignedIn) {
      SecretsService.sync();
    } else {
      SecretsService.forget();
    }
  });

  // Иконка запуска НАМЕРЕННО не переключается вместе с темой.
  //
  // Смена activity-alias на Android — это setComponentEnabledSetting, а он
  // убирает задачу приложения из списка недавних даже с DONT_KILL_APP:
  // DONT_KILL_APP бережёт процесс, но не задачу. Нативная часть уже
  // откладывает смену до onPause, и всё равно получалось так, что после
  // переключения темы приложение «вылетало и заходило заново».
  //
  // В режиме «auto» нужная иконка ставится на СЛЕДУЮЩЕМ запуске — там
  // перезапуск задачи никому не виден (см. AppIconService.load).

  ExchangeRateService.refresh();
  // Сначала читаем маркер ошибки от bat (если OTA на Windows упала),
  // потом обычная проверка обновлений.
  await AppUpdateService.consumePendingInstallError();
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
