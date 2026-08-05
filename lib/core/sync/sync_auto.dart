import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_journal.dart';

/// Обмен сам, как только что-то изменилось.
///
/// **Почему с задержкой, а не мгновенно.** Одно действие человека — это
/// почти никогда не одна запись. Создание сотрудника пишет карточку, потом
/// занимает логин; правка операции трогает и её, и счёт. Обмен на каждое
/// такое событие означал бы пять запросов подряд там, где нужен один, — и
/// это на сервере с одним ядром, куда смотрят все сотрудники сразу.
///
/// Поэтому: изменение сдвигает таймер, и обмен уходит через [quiet] после
/// **последнего** из них. Человек правит форму — таймер отодвигается;
/// закончил — через пару секунд всё уехало.
///
/// **Почему считаются только свои правки.** Приехавшее с сервера тоже
/// пишется в те же боксы. Считать всё подряд значило бы: применили чужое →
/// сработал автозапуск → снова обмен → снова применили → и так по кругу,
/// без единой правки от человека. Отличает их [SyncJournal.localChanges].
class SyncAuto {
  /// Сколько ждать тишины перед отправкой.
  ///
  /// Две секунды: достаточно, чтобы склеить одно действие человека в один
  /// обмен, и незаметно на глаз.
  static const Duration quiet = Duration(seconds: 2);

  /// Через сколько повторить, если обмен не удался.
  ///
  /// Не бесконечно и не сразу: связи может не быть минутами, и долбиться в
  /// неё каждые две секунды — верный способ посадить батарею.
  static const Duration retryAfter = Duration(minutes: 2);

  static final ValueNotifier<bool> running = ValueNotifier<bool>(false);

  static Timer? _timer;
  static bool _listening = false;

  /// Есть ли неотправленные правки — по ним показывается «ждёт отправки».
  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);

  /// Начать следить. Повторный вызов ничего не ломает.
  static void start() {
    if (_listening) return;
    _listening = true;
    SyncJournal.localChanges.addListener(_onLocalChange);
    running.value = true;
  }

  static void stop() {
    if (!_listening) return;
    SyncJournal.localChanges.removeListener(_onLocalChange);
    _listening = false;
    _timer?.cancel();
    _timer = null;
    pending.value = false;
    running.value = false;
  }

  static void _onLocalChange() {
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConfigured) return;
    pending.value = true;
    _schedule(quiet);
  }

  static void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _run);
  }

  static Future<void> _run() async {
    if (!SyncEndpoint.enabled || !SyncEndpoint.isConfigured) {
      pending.value = false;
      return;
    }
    // Проход уже идёт — не мешаем, попробуем ещё раз после тишины.
    if (SyncEngine.busy.value) {
      _schedule(quiet);
      return;
    }

    SyncReport report;
    try {
      report = await SyncEngine.run();
    } catch (_) {
      _schedule(retryAfter);
      return;
    }

    if (report.ok) {
      pending.value = false;
    } else {
      // Не получилось — правки остаются неотправленными, и это видно.
      // Молча забыть про них было бы худшим вариантом: человек считал бы,
      // что всё уехало.
      _schedule(retryAfter);
    }
  }

  /// Отправить прямо сейчас, не дожидаясь тишины.
  static Future<void> now() async {
    _timer?.cancel();
    await _run();
  }

  /// Только для тестов.
  @visibleForTesting
  static void reset() {
    stop();
    pending.value = false;
  }
}
