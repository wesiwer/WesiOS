import 'dart:async';

import 'package:flutter/foundation.dart';

import 'forecast_engine.dart';
import 'horizon_business_context.dart';
import 'horizon_engine_competition.dart';
import 'horizon_learning_service.dart';
import 'horizon_prediction_registry.dart';
import 'treasury_service.dart';

/// Background production maintenance for Wesi Horizon.
///
/// Called from the existing lifecycle automation after recurring cash has been
/// reconciled. It is single-flight, throttled, fail-soft and does not require
/// the Forecast screen to be opened.
class HorizonMaintenanceAutomation {
  HorizonMaintenanceAutomation({
    TreasuryService? treasury,
    DateTime Function()? now,
    this.minInterval = const Duration(hours: 6),
  })  : _treasury = treasury ?? TreasuryService(),
        _now = now ?? DateTime.now;

  static final HorizonMaintenanceAutomation shared =
      HorizonMaintenanceAutomation();

  final TreasuryService _treasury;
  final DateTime Function() _now;
  final Duration minInterval;
  Future<void>? _inFlight;
  DateTime? _lastCompletedAt;

  Future<void> runNow({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final last = _lastCompletedAt;
    if (!force && last != null && _now().difference(last) < minInterval) {
      return Future<void>.value();
    }
    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final now = _now();
      final today = DateTime(now.year, now.month, now.day);
      final transactions = await _treasury.getAllTransactions();
      final balance = await _treasury.getCurrentBalance();
      final calibration = await HorizonLearningService.load();
      const auditDays = 180;
      final context = await HorizonBusinessContextService.load(
        transactions: transactions,
        days: auditDays,
        now: today,
      );
      final audit = ForecastEngine.generate(
        transactions: transactions,
        currentBalance: balance,
        days: auditDays,
        paths: ForecastEngine.pathsForHorizon(auditDays, 1600),
        seed: 42,
        asOf: today,
        calibration: calibration,
        businessEvents: context.events,
        accounts: context.accounts,
      );
      if (!audit.insufficientData && audit.p50.isNotEmpty) {
        await HorizonPredictionRegistry.recordBaseForecast(
          forecast: audit,
          currentBalance: balance,
          calibration: calibration,
          now: today,
        );
      }
      await HorizonLearningService.updateIfDue(
        transactions: transactions,
        currentBalance: balance,
        now: today,
      );
      await HorizonEngineCompetitionService.evaluateIfDue(
        transactions: transactions,
        currentBalance: balance,
        now: today,
      );
      _lastCompletedAt = now;
    } catch (error, stackTrace) {
      debugPrint('Horizon maintenance failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _inFlight = null;
    }
  }
}
