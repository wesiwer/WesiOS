import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
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
import 'core/sync/sync_audit_extensions.dart';
import 'core/sync/sync_business_extensions.dart';
import 'core/sync/sync_auto.dart';
import 'core/sync/sync_endpoint.dart';
import 'core/sync/sync_engine.dart';
import 'core/sync/sync_feature_extensions.dart';
import 'core/sync/sync_recovery.dart';
import 'core/sync/sync_transaction_anchor_fix.dart';
import 'core/theme/app_theme.dart';
import 'features/chats/models/chat_message.dart';
import 'features/chats/models/chat_thread.dart';
import 'features/chats/services/chat_service.dart';
import 'features/chats/services/message_store.dart';
import 'features/knowledge/models/article_model.dart';
import 'features/knowledge/services/knowledge_service.dart';
import 'features/organizations/models/inter_org_transfer_model.dart';
import 'features/organizations/models/organization_access_grant.dart';
import 'features/organizations/models/organization_model.dart';
import 'features/organizations/models/transaction_audit_model.dart';
import 'features/organizations/services/inter_org_transfer_service.dart';
import 'features/organizations/services/organization_migration_service.dart';
import 'features/tasks/models/task_model.dart';
import 'features/team/models/employee_model.dart';
import 'features/team/models/team_permissions.dart';
import 'features/team/services/employee_documents_service.dart';
import 'features/team/services/team_service.dart';
import 'features/time_center/services/time_notification_scheduler.dart';
import 'features/time_center/services/time_schedule_automation.dart';
import 'features/treasury/models/account_model.dart';
import 'features/treasury/models/transaction_model.dart';
import 'features/treasury/services/recurring_payment_automation.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Запуск идёт под присмотром.
  //
  // Всё, что здесь происходит, случается ДО первого кадра, поэтому любое
  // исключение раньше оставляло человека наедине с чёрным окном: ни текста,
  // ни кода ошибки, ни намёка, куда смотреть. Именно так выглядела поломка
  // чтения старых записей — приложение просто не открывалось.
  //
  // Теперь сбой запуска показывается на экране. Он всё равно означает, что
  // работать нельзя, но разница между «не запускается» и «не запускается
  // вот из-за этого» — это разница между вечером в догадках и одним
  // сообщением с понятной причиной.
  try {
    if (!await _bootstrap(arguments)) return;
  } catch (error, stack) {
    debugPrint('Запуск не удался: $error\n$stack');
    runApp(_StartupFailureApp(error: error, stack: stack));
    return;
  }

  runApp(const WesiOSApp());
}

/// Подготовка приложения. Возвращает false, если запускаться не нужно.
Future<bool> _bootstrap(List<String> arguments) async {
  if (await TimeNotificationScheduler.handleLaunchArguments(arguments)) {
    return false;
  }

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

  // On Windows hive_flutter defaults to the user's Documents known folder.
  // That folder can be redirected or unavailable even though Windows still
  // reports a path for it. Keeping the database there therefore makes startup
  // depend on a user-facing shell folder that WesiOS does not control.
  //
  // Store Windows Hive data in LOCALAPPDATA instead. Before switching, copy
  // only WesiOS boxes from the legacy Documents location when it is readable.
  // A broken legacy folder must never prevent a clean startup.
  if (!kIsWeb && Platform.isWindows) {
    final separator = Platform.pathSeparator;
    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    final Directory hiveDirectory;
    if (localAppData != null && localAppData.isNotEmpty) {
      hiveDirectory = Directory(
        '$localAppData${separator}WesiOS${separator}hive',
      );
    } else {
      final supportDirectory = await getApplicationSupportDirectory();
      hiveDirectory = Directory('${supportDirectory.path}${separator}hive');
    }
    await hiveDirectory.create(recursive: true);

    try {
      final legacyDirectory = await getApplicationDocumentsDirectory();
      if (await legacyDirectory.exists()) {
        await for (final entity in legacyDirectory.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.path.split(separator).last;
          if (!name.startsWith('wesios_') || !name.endsWith('.hive')) {
            continue;
          }
          final target = File('${hiveDirectory.path}$separator$name');
          if (!await target.exists()) {
            await entity.copy(target.path);
          }
        }
      }
    } catch (error, stack) {
      debugPrint('Legacy Hive migration skipped: $error\n$stack');
    }

    Hive.init(hiveDirectory.path);
  } else {
    await Hive.initFlutter();
  }

  Hive.registerAdapter(TransactionModelAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(RecurringPeriodAdapter());
  Hive.registerAdapter(TransactionSourceAdapter());
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
  Hive.registerAdapter(OrganizationStatusAdapter());
  Hive.registerAdapter(OrganizationModelAdapter());
  Hive.registerAdapter(OrganizationAccessGrantAdapter());
  Hive.registerAdapter(InterOrgTransferTypeAdapter());
  Hive.registerAdapter(InterOrgTransferModelAdapter());
  Hive.registerAdapter(TransactionAuditModelAdapter());

  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');
  await Hive.openBox(EmployeeDocumentsService.boxName);
  await Hive.openBox<EmployeeModel>(TeamService.boxName);
  await MessageStore.open();
  await ChatService.open();

  // Org v1 runs before any Treasury automation. It is idempotent and only
  // backfills ownership missing on pre-org records; existing tagged data is
  // never rewritten.
  await OrganizationMigrationService.runV1();

  // A transfer journal is written before either financial leg. Complete any
  // interrupted create/cancel before recurring/Horizon can read the ledger.
  await InterOrgTransferService.recoverPending();

  RecurringPaymentAutomation.shared.start();
  TimeScheduleAutomation.shared.start();

  await SyncEndpoint.initializeSession();
  await TeamService.forgetUnrememberedSession();
  SyncTransactionAnchorFix.install();
  await SyncFeatureExtensions.install();
  SyncAuditExtensions.install();
  SyncBusinessExtensions.install();

  // Existing mobile installations may contain business rows created while
  // cloud synchronization was unhealthy. Arm the persistent recovery lock
  // before any startup pull can read authoritative server rows into the phone.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SyncRecovery.armMigrationIfNeeded();
  }

  if (TeamService.current != null && SyncEndpoint.isConnected) {
    SessionService.startHeartbeat();
    // Every authenticated employee participates in synchronization. The
    // server gateway applies module/org/row permissions; owner-only sync here
    // previously made Tasks/Profile/avatars appear local on employee devices.
    unawaited(SyncEngine.runOnLaunch());
    SyncAuto.start();
  } else {
    SessionService.stopHeartbeat();
    SyncAuto.stop();
  }

  unawaited(WesiNotifications.init());
  unawaited(WesiHaptics.warmUp());
  NotificationWatcher.start();

  CurrencyService.loadPrivacyMode();
  ThemeNotifier.load();
  ThemeNotifier.instance.addListener(AppIconService.apply);
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

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase native init skipped/failed: $e');
  }

  return true;
}

/// Экран вместо чёрного окна, когда запуск не удался.
///
/// Намеренно не зависит ни от темы, ни от локализации, ни от чего-либо
/// ещё, что само могло не загрузиться: единственная его задача — показать
/// причину, когда всё остальное уже сломано.
class _StartupFailureApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;

  const _StartupFailureApp({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0E11),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WesiOS не смог запуститься',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Данные на устройстве не тронуты. Покажите этот текст — '
                  'по нему видно, что именно не открылось.',
                  style: TextStyle(color: Color(0xFFA0A0AC), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error\n\n$stack',
                      style: const TextStyle(
                        color: Color(0xFFE0E0E6),
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
