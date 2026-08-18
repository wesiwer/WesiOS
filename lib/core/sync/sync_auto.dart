import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

  /// Ручной Sync должен закончиться на согласованном снимке, а не просто
  /// выполнить один проход. Первый проход может сам изменить сервер своими
  /// upload-ами, поэтому обычно достаточно двух. Несколько дополнительных
  /// проходов оставляют запас на одновременную работу другого устройства.
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

  /// Epoch жизненного цикла автоматики.
  ///
  /// Отмена Timer недостаточна: HTTP revision(), уже начавшийся до logout,
  /// может вернуться после stop() и продолжить старый callback. Generation
  /// делает любой такой результат протухшим. Это особенно важно при быстром
  /// logout -> login другого сотрудника: старый poll не имеет права принять
  /// watermark или сбросить `_probeBusy` уже новой сессии.
  static int _generation = 0;

  static final _SyncLifecycleObserver _lifecycle = _SyncLifecycleObserver();

  /// Начать следить. Повторный вызов ничего не ломает.
  static void start() {
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
    // Не ждём первую секунду: после старта сразу ставим/проверяем watermark.
    unawaited(_pollRemote());
  }

  /// Останавливает автоматический обмен.
  ///
  /// `stop()` означает реальную остановку. Раньше default был защищённым
  /// no-op при активной сессии из-за старого LoginScreen, который ошибочно
  /// вызывал stop сразу после MFA-входа. Login flow уже сериализован и больше
  /// этого не делает, а сохранение старого default ломало настоящий logout:
  /// TeamService вызывал stop(), но polling продолжал жить.
  ///
  /// [force]=false оставлен только как явный opt-in для старого защитного
  /// поведения, если оно когда-нибудь понадобится конкретному caller.
  static void stop({bool force = true}) {
    if (!force && SyncEndpoint.enabled && SyncEndpoint.isConnected) return;

    // Инвалидируем in-flight callbacks ДО отмены таймеров/листенеров.
    _generation++;
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

  /// Мобильная ОС может заморозить Timer.periodic в фоне. При возврате в
  /// приложение проверяем сервер сразу и сбрасываем сетевой backoff: изменение
  /// на другом устройстве не должно ждать 16 секунд только потому, что этот
  /// телефон раньше был офлайн.
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
    bool stale() => generation != null &&
        (generation != _generation || !_listening);

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

    // Сам SyncEngine мог закончиться уже после logout/account switch. Его
    // network side-effects отменить задним числом нельзя, но старый lifecycle
    // больше не имеет права менять pending/backoff/watermark новой сессии.
    if (stale()) return report;

    if (report.ok) {
      pending.value = false;
      // ВАЖНО: не читаем revision после полного прохода и не принимаем её как
      // watermark. Между последним fetch и таким чтением другое устройство
      // может записать новые данные. Тогда мы запомнили бы уже новую revision,
      // хотя этих данных локально ещё нет, и следующий poll навсегда счёл бы
      // устройство актуальным. Watermark принимает только [_pollRemote] — ту
      // revision, которую он наблюдал ДО запуска полного pull.
    } else {
      _schedule(retryAfter);
    }
    return report;
  }

  /// Лёгкая проверка: изменилось ли вообще что-нибудь на сервере.
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

      // Ключевой инвариант: watermark — это revision, увиденная ДО pull.
      // После успешного прохода сохраняем именно её. Если сервер изменился в
      // середине прохода (даже через 1 мс после последнего fetch), следующий
      // poll увидит более новую revision и гарантированно запустит ещё один
      // обмен. Поэтому изменение нельзя «перепрыгнуть» пост-синхронным чтением.
      final report = await _runAuto(generation: generation);
      if (stale()) return;
      if (report.ok) {
        _acceptObservedRevision(observedRevision);
      } else if (report.failure?.code != 'CANCELLED') {
        _registerProbeFailure();
      }
    } finally {
      // Старый callback не должен сбросить busy нового lifecycle, если между
      // await-ами успели stop() + start().
      if (generation == _generation) _probeBusy = false;
    }
  }

  static void _registerProbeFailure() {
    _probeFailures = (_probeFailures + 1).clamp(1, 4).toInt();
    final seconds = 1 << _probeFailures; // 2, 4, 8, 16
    _nextProbeAt = DateTime.now().add(Duration(seconds: seconds));
  }

  static void _acceptObservedRevision(String revision) {
    _remoteRevision = revision;
    _probeFailures = 0;
    _nextProbeAt = null;
  }

  /// Принудительный обмен.
  ///
  /// Ручная кнопка означает «сверь сейчас и верни успех только на устойчивом
  /// снимке». Для этого каждый проход ограждается revision до и после него.
  /// Если они различаются, в момент обмена сервер менялся (в том числе из-за
  /// наших upload-ов), поэтому повторяем проход. Так после зелёного результата
  /// локальное состояние соответствует серверному состоянию, наблюдавшемуся
  /// на границе завершения Sync.
  static Future<SyncReport> now() async {
    _localTimer?.cancel();

    if (!SyncEndpoint.isConnected) {
      return SyncReport(
        at: DateTime.now(),
        failure: const SyncFailure(
          'NOT_SIGNED_IN',
          'Сначала войдите в синхронизацию',
        ),
      );
    }

    // Если автоматический проход уже заканчивается, коротко ждём его вместо
    // того, чтобы возвращать пользователю бесполезное «BUSY».
    for (var i = 0; i < 20 && SyncEngine.busy.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    SyncReport? lastSuccessful;
    String? lastObservedBefore;

    for (var pass = 0; pass < manualStabilizationPasses; pass++) {
      final before = await PocketBaseTransport.fromSettings().revision();
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
      if (!report.ok) return report;
      lastSuccessful = report;
      pending.value = false;

      final after = await PocketBaseTransport.fromSettings().revision();
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

      // Сохраняем только revision, которая была известна ДО текущего pull.
      // Более новая `after` пока не считается применённой: следующий проход
      // обязан скачать всё, что появилось между двумя revision-чтениями.
      _acceptObservedRevision(lastObservedBefore);
    }

    final unstable = SyncReport(
      at: DateTime.now(),
      collections: lastSuccessful?.collections ?? const [],
      failure: const SyncFailure(
        'REMOTE_UNSTABLE',
        'Сервер продолжал меняться во время синхронизации. Повторите Sync',
      ),
    );
    SyncEngine.lastReport.value = unstable;
    return unstable;
  }

  /// Только для тестов.
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
