from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Patch anchor not found in {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# ------------------------------------------------------------------ SyncAuto
Path('lib/core/sync/sync_auto.dart').write_text(r'''import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_journal.dart';

/// Автоматический обмен между устройствами.
///
/// Есть два независимых повода для синхронизации:
/// 1. локальная правка — после короткой тишины отправляем её на сервер;
/// 2. изменение сервера — раз в секунду читаем только лёгкую ревизию и
///    запускаем полный обмен, только если ревизия изменилась.
///
/// Так второй компьютер узнаёт о продаже с телефона без перезапуска, но
/// сервер не получает семь полных запросов по всем коллекциям каждую секунду.
class SyncAuto {
  /// Локальные действия часто пишут несколько связанных записей подряд.
  /// 300 мс склеивают их в один обмен и при этом почти не ощущаются.
  static const Duration quiet = Duration(milliseconds: 300);

  /// Частота лёгкой проверки серверной ревизии.
  static const Duration remotePollEvery = Duration(seconds: 1);

  /// Повтор полного обмена после ошибки. Проверка ревизии имеет собственный
  /// экспоненциальный backoff, поэтому офлайн-устройство не долбит сеть.
  static const Duration retryAfter = Duration(seconds: 15);

  static final ValueNotifier<bool> running = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);

  static Timer? _localTimer;
  static Timer? _pollTimer;
  static bool _listening = false;
  static bool _probeBusy = false;
  static String? _remoteRevision;
  static String? _sessionFingerprint;
  static int _probeFailures = 0;
  static DateTime? _nextProbeAt;

  /// Начать следить. Повторный вызов ничего не ломает.
  static void start() {
    if (_listening) return;
    _listening = true;
    SyncJournal.localChanges.addListener(_onLocalChange);
    running.value = true;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      remotePollEvery,
      (_) => unawaited(_pollRemote()),
    );
    // Не ждём первую секунду: после старта сразу ставим/проверяем watermark.
    unawaited(_pollRemote());
  }

  static void stop() {
    if (_listening) {
      SyncJournal.localChanges.removeListener(_onLocalChange);
    }
    _listening = false;
    _localTimer?.cancel();
    _pollTimer?.cancel();
    _localTimer = null;
    _pollTimer = null;
    _probeBusy = false;
    _remoteRevision = null;
    _sessionFingerprint = null;
    _probeFailures = 0;
    _nextProbeAt = null;
    pending.value = false;
    running.value = false;
  }

  static void _onLocalChange() {
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConnected) return;
    pending.value = true;
    _schedule(quiet);
  }

  static void _schedule(Duration after) {
    _localTimer?.cancel();
    _localTimer = Timer(after, () => unawaited(_runAuto()));
  }

  static Future<SyncReport> _runAuto() async {
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('NOT_SIGNED_IN', 'Синхронизация не подключена'),
      );
    }

    if (SyncEngine.busy.value) {
      _schedule(quiet);
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('BUSY', 'Синхронизация уже идёт'),
      );
    }

    SyncReport report;
    try {
      report = await SyncEngine.run();
    } catch (_) {
      _schedule(retryAfter);
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('NETWORK', 'Не удалось выполнить синхронизацию'),
      );
    }

    if (report.ok) {
      pending.value = false;
      await _captureRemoteRevision();
    } else {
      _schedule(retryAfter);
    }
    return report;
  }

  /// Лёгкая проверка: изменилось ли вообще что-нибудь на сервере.
  static Future<void> _pollRemote() async {
    if (_probeBusy || SyncEngine.busy.value) return;
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      _remoteRevision = null;
      _sessionFingerprint = null;
      return;
    }

    final nextAllowed = _nextProbeAt;
    if (nextAllowed != null && DateTime.now().isBefore(nextAllowed)) return;

    final session = SyncEndpoint.session;
    final fingerprint = '${session?['userId']}|${session?['token']}';
    if (_sessionFingerprint != fingerprint) {
      _sessionFingerprint = fingerprint;
      _remoteRevision = null;
      _probeFailures = 0;
      _nextProbeAt = null;
    }

    _probeBusy = true;
    try {
      final result = await PocketBaseTransport.fromSettings().revision();
      if (result.failure != null) {
        _registerProbeFailure();
        return;
      }

      _probeFailures = 0;
      _nextProbeAt = null;
      final revision = result.value!;

      // runOnLaunch уже сделал полный обмен — его результат можно принять
      // как исходную точку и не повторять тот же проход через секунду.
      if (_remoteRevision == null) {
        if (SyncEngine.lastReport.value?.ok == true) {
          _remoteRevision = revision;
          return;
        }

        final report = await _runAuto();
        if (report.ok) _remoteRevision = revision;
        return;
      }

      if (revision == _remoteRevision) return;

      // Watermark меняем только ПОСЛЕ успешного полного обмена. Если сеть
      // оборвалась между проверкой и загрузкой данных, следующий tick снова
      // увидит расхождение и повторит попытку, а не забудет изменение.
      final report = await _runAuto();
      if (report.ok) {
        await _captureRemoteRevision(fallback: revision);
      }
    } finally {
      _probeBusy = false;
    }
  }

  static void _registerProbeFailure() {
    _probeFailures = (_probeFailures + 1).clamp(1, 6);
    final seconds = 1 << _probeFailures; // 2, 4, 8, 16, 32, 64
    _nextProbeAt = DateTime.now().add(Duration(seconds: seconds));
  }

  static Future<void> _captureRemoteRevision({String? fallback}) async {
    if (!SyncEndpoint.isConnected) return;
    final result = await PocketBaseTransport.fromSettings().revision();
    if (result.failure == null) {
      _remoteRevision = result.value;
      _probeFailures = 0;
      _nextProbeAt = null;
    } else if (fallback != null) {
      _remoteRevision = fallback;
    }
  }

  /// Принудительный обмен. Работает даже если автоматический обмен временно
  /// выключен: ручная кнопка должна означать именно «сделай сейчас».
  static Future<SyncReport> now() async {
    _localTimer?.cancel();

    if (!SyncEndpoint.isConnected) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('NOT_SIGNED_IN', 'Сначала войдите в синхронизацию'),
      );
    }

    // Если автоматический проход уже заканчивается, коротко ждём его вместо
    // того, чтобы возвращать пользователю бесполезное «BUSY».
    for (var i = 0; i < 20 && SyncEngine.busy.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final report = await SyncEngine.run();
    if (report.ok) {
      pending.value = false;
      await _captureRemoteRevision();
    }
    return report;
  }

  /// Только для тестов.
  @visibleForTesting
  static void reset() {
    stop();
    pending.value = false;
  }
}
''', encoding='utf-8')

# ------------------------------------------------------ PocketBase revision
replace_once(
    'lib/core/sync/pocketbase_transport.dart',
    "  @override\n  Future<SyncResult<int>> push(\n",
    r'''  /// Самая свежая системная ревизия серверных записей текущего пользователя.
  ///
  /// Возвращается только одна запись и только три маленьких поля. Этот запрос
  /// можно делать раз в секунду: полный payload операций/статей не скачивается.
  Future<SyncResult<String>> revision() async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    final res = await _send(
      'GET',
      '/api/collections/$collectionName/records',
      query: const {
        'perPage': '1',
        'page': '1',
        'sort': '-updated,-id',
        'fields': 'id,updated,stamp',
      },
    );
    if (res.failure != null) return SyncResult.fail(res.failure!);
    return SyncResult.ok(revisionFromResponse(res.value!));
  }

  /// Чистый разбор вынесен отдельно для регрессионного теста.
  static String revisionFromResponse(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final updated = '${first['updated'] ?? first['stamp'] ?? ''}';
    return '$id|$updated';
  }

  @override
  Future<SyncResult<int>> push(
'''
)

# ------------------------------------------------ service revision callbacks
replace_once(
    'lib/core/sync/sync_codec.dart',
    "import '../../features/chats/models/chat_thread.dart';\n",
    "import '../../features/chats/models/chat_thread.dart';\n"
    "import '../../features/chats/services/chat_service.dart';\n"
    "import '../../features/chats/services/message_store.dart';\n"
    "import '../../features/knowledge/services/knowledge_service.dart';\n"
    "import '../../features/tasks/services/task_service.dart';\n"
    "import '../../features/team/services/team_service.dart';\n"
    "import '../../features/treasury/services/account_service.dart';\n"
    "import '../../features/treasury/services/treasury_service.dart';\n"
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "  Future<void> afterUpload(Iterable<String> ids) async {}\n}\n",
    "  Future<void> afterUpload(Iterable<String> ids) async {}\n\n"
    "  /// Сообщить открытому интерфейсу, что чужие данные уже применены.\n"
    "  /// Вызывается один раз на коллекцию за проход, а не на каждую запись.\n"
    "  void notifyChanged() {}\n}\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class TransactionsSync extends SyncCollection<TransactionModel> {\n",
    "class TransactionsSync extends SyncCollection<TransactionModel> {\n"
    "  @override\n"
    "  void notifyChanged() => TreasuryService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class AccountsSync extends SyncCollection<AccountModel> {\n",
    "class AccountsSync extends SyncCollection<AccountModel> {\n"
    "  @override\n"
    "  void notifyChanged() => AccountService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class TasksSync extends SyncCollection<TaskModel> {\n",
    "class TasksSync extends SyncCollection<TaskModel> {\n"
    "  @override\n"
    "  void notifyChanged() => TaskService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class ArticlesSync extends SyncCollection<ArticleModel> {\n",
    "class ArticlesSync extends SyncCollection<ArticleModel> {\n"
    "  @override\n"
    "  void notifyChanged() => KnowledgeService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class EmployeesSync extends SyncCollection<EmployeeModel> {\n",
    "class EmployeesSync extends SyncCollection<EmployeeModel> {\n"
    "  @override\n"
    "  void notifyChanged() => TeamService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class ChatsSync extends SyncCollection<ChatThread> {\n",
    "class ChatsSync extends SyncCollection<ChatThread> {\n"
    "  @override\n"
    "  void notifyChanged() => ChatService.revision.value++;\n\n",
)
replace_once(
    'lib/core/sync/sync_codec.dart',
    "class MessagesSync extends SyncCollection<ChatMessage> {\n",
    "class MessagesSync extends SyncCollection<ChatMessage> {\n"
    "  @override\n"
    "  void notifyChanged() {\n"
    "    MessageStore.revision.value++;\n"
    "    ChatService.revision.value++;\n"
    "  }\n\n",
)

# Один UI-сигнал на коллекцию после применения серверных записей.
replace_once(
    'lib/core/sync/sync_engine.dart',
    "    if (plan.toUpload.isEmpty) {\n      return SyncCollectionReport(collection: c.name, applied: applied);\n    }\n",
    "    if (applied > 0) c.notifyChanged();\n\n"
    "    if (plan.toUpload.isEmpty) {\n      return SyncCollectionReport(collection: c.name, applied: applied);\n    }\n",
)

# ------------------------------------------------------------- clock style
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    "  static const _styleKey = 'clock_style';\n\n",
    "  static const _styleKey = 'clock_style';\n"
    "  static final ValueNotifier<int> styleRevision = ValueNotifier<int>(0);\n\n",
)
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    "      );\n    } catch (_) {}\n  }\n\n  @override\n  State<WesiClock> createState()",
    "      );\n      styleRevision.value++;\n    } catch (_) {}\n  }\n\n  @override\n  State<WesiClock> createState()",
)
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    "    _style = widget.forceStyle ?? WesiClock.savedStyle;\n    _timer = Timer.periodic",
    "    _style = widget.forceStyle ?? WesiClock.savedStyle;\n"
    "    WesiClock.styleRevision.addListener(_reloadStyle);\n"
    "    _timer = Timer.periodic",
)
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    "  @override\n  void dispose() {\n    _timer?.cancel();\n    super.dispose();\n  }\n",
    "  void _reloadStyle() {\n"
    "    final next = widget.forceStyle ?? WesiClock.savedStyle;\n"
    "    if (mounted && next != _style) setState(() => _style = next);\n"
    "  }\n\n"
    "  Future<void> _toggleStyle() async {\n"
    "    if (widget.forceStyle != null) return;\n"
    "    final next = _style == ClockStyle.digital\n"
    "        ? ClockStyle.analog\n"
    "        : ClockStyle.digital;\n"
    "    await WesiClock.setStyle(next);\n"
    "  }\n\n"
    "  @override\n"
    "  void dispose() {\n"
    "    WesiClock.styleRevision.removeListener(_reloadStyle);\n"
    "    _timer?.cancel();\n"
    "    super.dispose();\n"
    "  }\n",
)
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    "            Icon(\n              _style == ClockStyle.digital\n                  ? Icons.schedule\n                  : Icons.watch_later_outlined,\n              size: large ? 16 : 12,\n              color: AppTheme.accent,\n            ),\n",
    "            Tooltip(\n"
    "              message: ru\n"
    "                  ? 'Переключить цифровые / стрелочные часы'\n"
    "                  : 'Switch digital / analog clock',\n"
    "              child: InkResponse(\n"
    "                onTap: widget.forceStyle == null ? _toggleStyle : null,\n"
    "                radius: large ? 22 : 18,\n"
    "                child: Padding(\n"
    "                  padding: const EdgeInsets.all(3),\n"
    "                  child: Icon(\n"
    "                    _style == ClockStyle.digital\n"
    "                        ? Icons.schedule\n"
    "                        : Icons.watch_later_outlined,\n"
    "                    size: large ? 16 : 12,\n"
    "                    color: AppTheme.accent,\n"
    "                  ),\n"
    "                ),\n"
    "              ),\n"
    "            ),\n",
)

# --------------------------------------------------------------- Home UI
replace_once(
    'lib/features/home/home_screen.dart',
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/foundation.dart';\n"
    "import 'package:flutter/material.dart';\n",
)
replace_once(
    'lib/features/home/home_screen.dart',
    "import '../../core/services/currency_service.dart';\n",
    "import '../../core/services/currency_service.dart';\n"
    "import '../../core/sync/sync_auto.dart';\n"
    "import '../../core/sync/sync_engine.dart';\n",
)
replace_once(
    'lib/features/home/home_screen.dart',
    "  Map<String, double> _breakdown = const {};\n",
    "  Map<String, double> _breakdown = const {};\n"
    "  bool _syncing = false;\n"
    "  double _bottomSyncOverscroll = 0;\n\n"
    "  bool get _isDesktop => !kIsWeb &&\n"
    "      (defaultTargetPlatform == TargetPlatform.windows ||\n"
    "          defaultTargetPlatform == TargetPlatform.macOS ||\n"
    "          defaultTargetPlatform == TargetPlatform.linux);\n\n"
    "  bool get _isMobile => !kIsWeb &&\n"
    "      (defaultTargetPlatform == TargetPlatform.android ||\n"
    "          defaultTargetPlatform == TargetPlatform.iOS);\n",
)
replace_once(
    'lib/features/home/home_screen.dart',
    "  @override\n  Widget build(BuildContext context) {\n    return SafeArea(\n      child: CustomScrollView(\n",
    "  Future<void> _syncNow() async {\n"
    "    if (_syncing || SyncEngine.busy.value) return;\n"
    "    setState(() => _syncing = true);\n"
    "    final report = await SyncAuto.now();\n"
    "    await _loadBalance();\n"
    "    if (!mounted) return;\n"
    "    setState(() => _syncing = false);\n"
    "    ScaffoldMessenger.of(context)\n"
    "      ..hideCurrentSnackBar()\n"
    "      ..showSnackBar(\n"
    "        SnackBar(\n"
    "          content: Text(report.describe(russian: WesiLocale.isRussian)),\n"
    "          behavior: SnackBarBehavior.floating,\n"
    "          duration: const Duration(seconds: 2),\n"
    "        ),\n"
    "      );\n"
    "  }\n\n"
    "  bool _onScrollNotification(ScrollNotification notification) {\n"
    "    if (!_isMobile || _syncing) return false;\n"
    "    if (notification is OverscrollNotification &&\n"
    "        notification.metrics.extentAfter <= 0.5 &&\n"
    "        notification.overscroll > 0) {\n"
    "      _bottomSyncOverscroll += notification.overscroll;\n"
    "      if (_bottomSyncOverscroll >= 72) {\n"
    "        _bottomSyncOverscroll = 0;\n"
    "        WesiFeedback.select();\n"
    "        _syncNow();\n"
    "      }\n"
    "    } else if (notification is ScrollEndNotification) {\n"
    "      _bottomSyncOverscroll = 0;\n"
    "    }\n"
    "    return false;\n"
    "  }\n\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    return SafeArea(\n"
    "      child: NotificationListener<ScrollNotification>(\n"
    "        onNotification: _onScrollNotification,\n"
    "        child: CustomScrollView(\n"
    "          physics: const AlwaysScrollableScrollPhysics(),\n",
)
# Close NotificationListener after CustomScrollView.
replace_once(
    'lib/features/home/home_screen.dart',
    "        ],\n      ),\n    );\n  }\n\n  Future<void> _showAddTransaction",
    "          ],\n        ),\n      ),\n    );\n  }\n\n  Future<void> _showAddTransaction",
)
# Desktop-only sync button immediately next to the notifications bell.
replace_once(
    'lib/features/home/home_screen.dart',
    "                          const AlertsBell(size: 28),\n                          const SizedBox(width: 6),\n",
    "                          if (_isDesktop) ...[\n"
    "                            Tooltip(\n"
    "                              message: WesiLocale.isRussian\n"
    "                                  ? 'Синхронизировать сейчас'\n"
    "                                  : 'Sync now',\n"
    "                              child: _HoverIconButton(\n"
    "                                icon: _syncing\n"
    "                                    ? Icons.sync_disabled\n"
    "                                    : Icons.sync,\n"
    "                                onTap: _syncNow,\n"
    "                              ),\n"
    "                            ),\n"
    "                            const SizedBox(width: 6),\n"
    "                          ],\n"
    "                          const AlertsBell(size: 28),\n"
    "                          const SizedBox(width: 6),\n",
)

# --------------------------------------------------------------- version
replace_once('pubspec.yaml', 'version: 0.19.1+45\n', 'version: 0.19.1+46\n')

# --------------------------------------------------------------- tests
Path('test/live_sync_revision_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/pocketbase_transport.dart';

void main() {
  group('PocketBaseTransport.revisionFromResponse', () {
    test('uses newest record id and PocketBase updated field', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {
            'id': 'abc123',
            'updated': '2026-08-07 06:00:01.123Z',
            'stamp': '2026-08-07T06:00:00Z',
          },
        ],
      });
      expect(revision, 'abc123|2026-08-07 06:00:01.123Z');
    });

    test('empty server has stable watermark', () {
      expect(PocketBaseTransport.revisionFromResponse({'items': []}), 'empty');
    });

    test('falls back to sync stamp for older server response', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {'id': 'old', 'stamp': '2026-08-07T06:00:00Z'},
        ],
      });
      expect(revision, 'old|2026-08-07T06:00:00Z');
    });
  });
}
''', encoding='utf-8')

print('Live sync patch applied successfully')
