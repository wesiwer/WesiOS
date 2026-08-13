import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_journal.dart';
import 'sync_transport.dart';

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

  /// Останавливает автоматический обмен.
  ///
  /// Пока подтверждённая сессия активна и синхронизация включена, обычный
  /// `stop()` не должен случайно выключить обмен. Старый LoginScreen делал
  /// именно это для каждого non-owner сразу после успешного MFA-входа.
  /// Настоящее выключение сначала ставит SyncEndpoint.enabled=false; внутренний
  /// rebind/logout может использовать [force].
  static void stop({bool force = false}) {
    if (!force && SyncEndpoint.enabled && SyncEndpoint.isConnected) return;
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
        if (report.ok) {
          _remoteRevision = revision;
        } else {
          _registerProbeFailure();
        }
        return;
      }

      if (revision == _remoteRevision) return;

      // Watermark меняем только ПОСЛЕ успешного полного обмена. Если сеть
      // оборвалась между проверкой и загрузкой данных, следующий tick снова
      // увидит расхождение и повторит попытку, а не забудет изменение.
      final report = await _runAuto();
      if (report.ok) {
        await _captureRemoteRevision(fallback: revision);
      } else {
        _registerProbeFailure();
      }
    } finally {
      _probeBusy = false;
    }
  }

  static void _registerProbeFailure() {
    _probeFailures = (_probeFailures + 1).clamp(1, 4).toInt();
    final seconds = 1 << _probeFailures; // 2, 4, 8, 16
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
    stop(force: true);
    pending.value = false;
  }
}
