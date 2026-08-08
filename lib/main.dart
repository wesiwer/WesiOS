import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/feedback/wesi_haptics.dart';
import 'core/notifications/notification_watcher.dart';
import 'core/notifications/wesi_notifications.dart';
import 'core/security/session_service.dart';
import 'core/services/app_icon_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/currency_service.dart';
import 'core/services/exchange_rate_service.dart';
import 'core/services/firebase_rest_service.dart';
import 'core/services/github_auth_service.dart';
import 'core/services/github_release_download.dart';
import 'core/services/quote_mind_charge_service.dart';
import 'core/services/secrets_service.dart';
import 'core/sync/sync_auto.dart';
import 'core/sync/sync_endpoint.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/app_theme.dart';
import 'features/chats/models/chat_message.dart';
import 'features/chats/models/chat_thread.dart';
import 'features/chats/services/chat_service.dart';
import 'features/chats/services/message_store.dart';
import 'features/knowledge/models/article_model.dart';
import 'features/knowledge/services/knowledge_service.dart';
import 'features/tasks/models/task_model.dart';
import 'features/team/models/employee_model.dart';
import 'features/team/models/team_permissions.dart';
import 'features/team/services/employee_documents_service.dart';
import 'features/team/services/team_service.dart';
import 'features/treasury/models/account_model.dart';
import 'features/treasury/models/transaction_model.dart';

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
  Hive.registerAdapter(ChatThreadAdapter());
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');
  await Hive.openBox(EmployeeDocumentsService.boxName);
  await Hive.openBox<EmployeeModel>(TeamService.boxName);
  await MessageStore.open();
  await ChatService.open();

  // Auth token + revocable session id live in OS-protected storage, not Hive.
  // This also performs a one-time migration from old plaintext `sync_session`.
  await SyncEndpoint.initializeSession();
  await TeamService.forgetUnrememberedSession();

  // A remembered login is accepted locally only when it contains the new
  // server-side revocable WesiOS session id. Start heartbeat immediately so
  // deletion/revocation is detected even while the splash screen is visible.
  if (TeamService.current != null && SyncEndpoint.isConnected) {
    SessionService.startHeartbeat();
    if (TeamService.isOwnerSession) {
      unawaited(SyncEngine.runOnLaunch());
      SyncAuto.start();
    } else {
      SyncAuto.stop();
    }
  } else {
    SessionService.stopHeartbeat();
    SyncAuto.stop();
  }

  unawaited(WesiNotifications.init());
  unawaited(WesiHaptics.warmUp());
  NotificationWatcher.start();

  CurrencyService.loadPrivacyMode();
  ThemeNotifier.load();
  AppIconService.load();
  QuoteMindChargeService.load();
  SecretsService.loadCached();
  SecretsService.sync();
  GitHubAuthService.revision.addListener(GitHubReleaseDownload.forget);

  FirebaseRestService.revision.addListener(() {
    if (FirebaseRestService.isSignedIn) {
      SecretsService.sync();
    } else {
      SecretsService.forget();
    }
  });

  ExchangeRateService.refresh();
  await AppUpdateService.consumePendingInstallError();
  AppUpdateService.check();
  KnowledgeService.seed();

  // Firebase configuration ships with the application. Employees must never
  // be asked to paste apiKey/appId/projectId manually.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase native init skipped/failed: $e');
  }

  runApp(const WesiOSApp());
}
