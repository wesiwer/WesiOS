import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'pocketbase_transport.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_journal.dart';
import 'sync_recovery_guard.dart';
import 'sync_transport.dart';

/// Автоматический обмен между устройствами.
///
/// Есть два независимых повода для синхронизации:
/// 1. локальная правка — после короткой тишины отправляем её на сервер;
/// 2. изменение сервера — раз в секунду читаем только лёгкую ревизию и
///    запускаем полный обмен, только если ревизия изменилась.
class SyncAuto {
  static const Duration quiet = Duration(milliseconds: 300);
  static const Duration remotePollEvery = Duration(seconds: 1);
  static const Duration retryAfter = Duration(seconds: 15);
  static const int manualStabilizationPasses = 4;

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

  /// Epoch жизненного цикла автоматики. Отмена Timer недостаточна: уже
  /// начавшийся HTTP callback может вернуться после logout/account switch.
  static int _generation = 0;

  static final _SyncLifecycleObserver _lifecycle = _SyncLifecycleObserver();

  static void start() {
    if (SyncRecoveryGuard.active) {
      stop(force: true);
      return;
    }
    if (_listening) return;
    _generation++;
    _listening = true;
    SyncJournal.localChanges.addListener(_onLocalChange);
    WidgetsBinding.instance.addObserver(_lifecycle);
    running.value = true;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      remotePollEvery,
      (_) => unawaited(_pollRemote()),
    );
    unawaited(_pollRemote());
  }

  /// Реальная остановка синхронизации.
  ///
  /// Помимо таймеров немедленно инвалидирует и уже запущенный SyncEngine.run().
  /// Раньше полный проход мог продолжать fetch/apply/push в промежутке между
  /// нажатием «Выйти» и фактическим clearSession(). Это оставляло небольшое,
  /// но реальное окно, где старый аккаунт ещё менял локальную/серверную базу.
  static void stop({bool force = true}) {
    if (!force && SyncEndpoint.enabled && SyncEndpoint.isConnected) return;

    _generation++;
    SyncEngine.invalidateActiveRun();

    if (_listening) {
      SyncJournal.localChanges.removeListener(_onLocalChange);
      WidgetsBinding.instance.removeObserver(_lifecycle);
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
    if (!_listening || !SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      return;
    }
    pending.value = true;
    _schedule(quiet);
  }

  static void _schedule(Duration after) {
    _localTimer?.cancel();
    final generation = _generation;
    _localTimer = Timer(after, () {
      if (!_listening || generation != _generation) return;
      unawaited(_runAuto(generation: generation));
    });
  }

  static bool _quickRetry(String? code) =>
      code == 'LOCAL_CHANGED_DURING_SYNC' || code == 'BUSY';

  static bool _lifecycleEnded(String? code) =>
      code == 'CANCELLED' || code == 'SESSION_CHANGED';

  static void _onResumed() {
    if (!_listening || !SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      return;
    }
    _nextProbeAt = null;
    _probeFailures = 0;
    if (pending.value) _schedule(Duration.zero);
    unawaited(_pollRemote(force: true));
  }

  static Future<SyncReport> _runAuto({int? generation}) async {
    bool stale() =>
        generation != null && (generation != _generation || !_listening);

    if (stale()) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('CANCELLED', 'Синхронизация остановлена'),
      );
    }
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      return SyncReport(
        at: DateTime.now(),
        failure:
            const SyncFailure('NOT_SIGNED_IN', 'Синхронизация не подключена'),
      );
    }

    if (SyncEngine.busy.value) {
      if (!stale()) _schedule(quiet);
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('BUSY', 'Синхронизация уже идёт'),
      );
    }

    SyncReport report;
    try {
      report = await SyncEngine.run();
    } catch (_) {
      if (!stale()) _schedule(retryAfter);
      return SyncReport(
        at: DateTime.now(),
        failure:
            const SyncFailure('NETWORK', 'Не удалось выполнить синхронизацию'),
      );
    }

    if (stale()) return report;

    if (report.ok) {
      pending.value = false;
      // Revision после pull здесь намеренно не читается: watermark принимает
      // только revision, наблюдавшуюся ДО соответствующего полного прохода.
    } else {
      final code = report.firstFailure?.code;
      if (_quickRetry(code)) {
        // Optimistic concurrency did exactly what it should: it noticed that
        // the user changed a row after the merge snapshot and refused to apply
        // or send a stale plan. This is not a network failure. Keep the local
        // change pending and recompute almost immediately.
        pending.value = true;
        _schedule(quiet);
      } else if (!_lifecycleEnded(code)) {
        _schedule(retryAfter);
      }
    }
    return report;
  }

  static Future<void> _pollRemote({bool force = false}) async {
    final generation = _generation;
    bool stale() => generation != _generation || !_listening;

    if (stale() || _probeBusy || SyncEngine.busy.value) return;
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConnected) {
      _remoteRevision = null;
      _sessionFingerprint = null;
      return;
    }

    final nextAllowed = _nextProbeAt;
    if (!force && nextAllowed != null && DateTime.now().isBefore(nextAllowed)) {
      return;
    }

    final session = SyncEndpoint.session;
    final fingerprint =
        '${session?['userId']}|${session?['sessionId']}|${session?['token']}';
    if (_sessionFingerprint != fingerprint) {
      _sessionFingerprint = fingerprint;
      _remoteRevision = null;
      _probeFailures = 0;
      _nextProbeAt = null;
    }

    _probeBusy = true;
    try {
      final result = await PocketBaseTransport.fromSettings().revision();
      if (stale()) return;
      if (result.failure != null) {
        _registerProbeFailure();
        return;
      }

      _probeFailures = 0;
      _nextProbeAt = null;
      final observedRevision = result.value!;

      if (_remoteRevision != null && observedRevision == _remoteRevision) {
        return;
      }

      final report = await _runAuto(generation: generation);
      if (stale()) return;
      if (report.ok) {
        _acceptObservedRevision(observedRevision);
      } else {
        final code = report.firstFailure?.code;
        if (!_lifecycleEnded(code) && !_quickRetry(code)) {
          _registerProbeFailure();
        }
      }
    } finally {
      if (generation == _generation) _probeBusy = false;
    }
  }

  static void _registerProbeFailure() {
    _probeFailures = (_probeFailures + 1).clamp(1, 4).toInt();
    final seconds = 1 << _probeFailures;
    _nextProbeAt = DateTime.now().add(Duration(seconds: seconds));
  }

  static void _acceptObservedRevision(String revision) {
    _remoteRevision = revision;
    _probeFailures = 0;
    _nextProbeAt = null;
  }

  /// Принудительный обмен до устойчивого локального snapshot и server revision.
  ///
  /// Manual Sync делает несколько ограниченных проходов. Изменение записи во
  /// время merge — ожидаемый optimistic conflict, а не окончательная ошибка:
  /// даём UI/локальному watcher 300 мс успокоиться и пересчитываем план. При
  /// этом реальные network/apply/policy ошибки по-прежнему возвращаются сразу.
  static Future<SyncReport> now() async {
    _localTimer?.cancel();

    if (SyncRecoveryGuard.active) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure(
          'RECOVERY_LOCKED',
          'Сначала завершите безопасный перенос локальных данных',
        ),
      );
    }

    if (!SyncEndpoint.isConnected) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure(
          'NOT_SIGNED_IN',
          'Сначала войдите в синхронизацию',
        ),
      );
    }

    for (var i = 0; i < 20 && SyncEngine.busy.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // Если через две секунды engine всё ещё занят, не запускаем второй проход
    // поверх первого. Это лучше явного BUSY, чем параллельный merge одного box.
    if (SyncEngine.busy.value) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure('BUSY', 'Синхронизация уже идёт'),
      );
    }

    final session = SyncEndpoint.session;
    final sessionFingerprint =
        '${session?['userId']}|${session?['sessionId']}|${session?['token']}';
    bool sessionChanged() {
      final current = SyncEndpoint.session;
      return sessionFingerprint !=
          '${current?['userId']}|${current?['sessionId']}|${current?['token']}';
    }

    SyncReport? lastSuccessful;
    String? lastObservedBefore;
    String? lastRetryReason;

    for (var pass = 0; pass < manualStabilizationPasses; pass++) {
      if (sessionChanged()) {
        return SyncReport(
          at: DateTime.now(),
          collections: lastSuccessful?.collections ?? const [],
          failure: const SyncFailure(
            'SESSION_CHANGED',
            'Сеанс изменился во время синхронизации',
          ),
        );
      }

      final before = await PocketBaseTransport.fromSettings().revision();
      if (sessionChanged()) {
        return SyncReport(
          at: DateTime.now(),
          collections: lastSuccessful?.collections ?? const [],
          failure: const SyncFailure(
            'SESSION_CHANGED',
            'Сеанс изменился во время синхронизации',
          ),
        );
      }
      if (before.failure != null) {
        final failed = SyncReport(
          at: DateTime.now(),
          collections: lastSuccessful?.collections ?? const [],
          failure: before.failure,
        );
        SyncEngine.lastReport.value = failed;
        return failed;
      }
      lastObservedBefore = before.value!;

      final report = await SyncEngine.run();
      if (!report.ok) {
        final code = report.firstFailure?.code;
        if (code == 'LOCAL_CHANGED_DURING_SYNC' || code == 'BUSY') {
          // Do not surface a transient optimistic conflict from the button.
          // Keep the edit pending and give the user/Hive watcher a short quiet
          // window before rebuilding both local and remote snapshots.
          pending.value = true;
          lastRetryReason = code == 'BUSY' ? 'busy' : 'local';
          if (pass + 1 < manualStabilizationPasses) {
            await Future<void>.delayed(quiet);
            continue;
          }
          break;
        }
        return report;
      }
      if (sessionChanged()) return report;
      lastSuccessful = report;
      pending.value = false;

      final after = await PocketBaseTransport.fromSettings().revision();
      if (sessionChanged()) {
        return SyncReport(
          at: DateTime.now(),
          collections: report.collections,
          failure: const SyncFailure(
            'SESSION_CHANGED',
            'Сеанс изменился во время синхронизации',
          ),
        );
      }
      if (after.failure != null) {
        final failed = SyncReport(
          at: DateTime.now(),
          collections: report.collections,
          failure: after.failure,
        );
        SyncEngine.lastReport.value = failed;
        return failed;
      }

      if (after.value == lastObservedBefore) {
        _acceptObservedRevision(after.value!);
        return report;
      }

      // Server changed while the full exchange was running. The revision seen
      // before that exchange has been consumed, but the newer revision must
      // trigger another stabilization pass.
      _acceptObservedRevision(lastObservedBefore);
      lastRetryReason = 'remote';
    }

    final SyncFailure failure;
    if (lastRetryReason == 'local') {
      failure = const SyncFailure(
        'LOCAL_UNSTABLE',
        'Локальные данные продолжали меняться во время синхронизации. Повторите Sync после завершения правок',
      );
      pending.value = true;
    } else if (lastRetryReason == 'busy') {
      failure = const SyncFailure(
        'BUSY',
        'Другой проход синхронизации не завершился. Повторите Sync',
      );
    } else {
      failure = const SyncFailure(
        'REMOTE_UNSTABLE',
        'Сервер продолжал меняться во время синхронизации. Повторите Sync',
      );
    }

    final unstable = SyncReport(
      at: DateTime.now(),
      collections: lastSuccessful?.collections ?? const [],
      failure: failure,
    );
    SyncEngine.lastReport.value = unstable;
    return unstable;
  }

  @visibleForTesting
  static void reset() {
    stop(force: true);
    pending.value = false;
  }
}

class _SyncLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) SyncAuto._onResumed();
  }
}
