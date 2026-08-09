import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'horizon_maintenance_automation.dart';
import 'treasury_service.dart';

/// Автоматически материализует просроченные регулярные операции Treasury.
///
/// Запускается один раз при старте приложения и повторно, когда приложение
/// возвращается из background. [TreasuryService.processRecurringPayments]
/// идемпотентен по due-date: generated transaction получает детерминированный
/// id, а recurring anchor после обработки сдвигается вперёд.
///
/// Sandbox сюда намеренно не входит: песочница не должна менять свои данные
/// из-за lifecycle основного приложения.
class RecurringPaymentAutomation with WidgetsBindingObserver {
  RecurringPaymentAutomation({
    TreasuryService? treasury,
    DateTime Function()? now,
    this.minInterval = const Duration(minutes: 5),
  })  : _treasury = treasury ?? TreasuryService(),
        _now = now ?? DateTime.now;

  static final RecurringPaymentAutomation shared = RecurringPaymentAutomation();

  final TreasuryService _treasury;
  final DateTime Function() _now;
  final Duration minInterval;

  Future<void>? _inFlight;
  DateTime? _lastCompletedAt;
  bool _observing = false;

  /// Подключает lifecycle observer и сразу выполняет первый проход.
  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(runNow(force: true));
  }

  void stop() {
    if (!_observing) return;
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(runNow());
    }
  }

  /// Single-flight + throttling защищают от нескольких resume-событий подряд.
  /// Ошибки не роняют запуск WesiOS: Treasury останется доступен, а следующий
  /// resume попробует материализацию ещё раз.
  Future<void> runNow({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;

    final completedAt = _lastCompletedAt;
    if (!force &&
        completedAt != null &&
        _now().difference(completedAt) < minInterval) {
      return Future<void>.value();
    }

    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<void> _run() async {
    try {
      await _treasury.processRecurringPayments();
      // Maintenance is intentionally independent from opening Forecast UI:
      // issued-forecast ledger, monthly learning and engine championship keep
      // advancing on ordinary app launch/resume.
      await HorizonMaintenanceAutomation.shared.runNow();
      _lastCompletedAt = _now();
    } catch (error, stackTrace) {
      debugPrint('Recurring payments automation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _inFlight = null;
    }
  }
}
