import 'dart:math';

import '../models/transaction_model.dart';
import 'forecast_engine.dart';
import 'horizon_calibration.dart';

class HorizonStressCase {
  final String key;
  final String labelRu;
  final String labelEn;
  final WhatIfScenario scenario;

  const HorizonStressCase({
    required this.key,
    required this.labelRu,
    required this.labelEn,
    required this.scenario,
  });
}

/// Default scenario package is part of the model contract, not a UI preset.
class HorizonScenarioService {
  HorizonScenarioService._();

  static List<HorizonStressCase> stressLibrary({
    required double currentBalance,
    required double dailyVolatility,
  }) {
    final shock = max(
      dailyVolatility * 6,
      max(5000.0, currentBalance.abs() * 0.12),
    );
    return [
      const HorizonStressCase(
        key: 'income-down-30',
        labelRu: 'Доход −30% на 2 месяца',
        labelEn: 'Income −30% for 2 months',
        scenario: WhatIfScenario(
          incomeMultiplier: 0.70,
          incomeMultiplierDays: 60,
        ),
      ),
      const HorizonStressCase(
        key: 'incoming-delay-30',
        labelRu: 'Входящие задержаны на 30 дней',
        labelEn: 'Incoming cash delayed by 30 days',
        scenario: WhatIfScenario(incomeDelayDays: 30),
      ),
      HorizonStressCase(
        key: 'unexpected-expense',
        labelRu: 'Крупный внезапный расход',
        labelEn: 'Large unexpected expense',
        scenario: WhatIfScenario(oneOffExpenseShock: shock),
      ),
      const HorizonStressCase(
        key: 'main-source-loss',
        labelRu: 'Потеря главного источника на 2 месяца',
        labelEn: 'Main source lost for 2 months',
        scenario: WhatIfScenario(mainIncomeLossDays: 60),
      ),
    ];
  }

  static WhatIfScenario defaultStress({
    required double currentBalance,
    required double dailyVolatility,
  }) {
    var result = WhatIfScenario.none;
    for (final stress in stressLibrary(
      currentBalance: currentBalance,
      dailyVolatility: dailyVolatility,
    )) {
      result = result.merge(stress.scenario);
    }
    return result;
  }

  static Future<List<ForecastScenarioSummary>> buildDefaultPackage({
    required ForecastResult base,
    required List<TransactionModel> transactions,
    required double currentBalance,
    required int days,
    required HorizonCalibrationProfile calibration,
    List<HorizonCashEvent> businessEvents = const [],
    List<AccountLiquiditySnapshot> accounts = const [],
    Map<String, double> recurringReliability = const {},
  }) async {
    if (base.p50.isEmpty) return const [];

    final definitions = <({
      String key,
      String ru,
      String en,
      WhatIfScenario scenario,
    })>[
      (
        key: 'base',
        ru: 'Базовый',
        en: 'Base',
        scenario: WhatIfScenario.none,
      ),
      (
        key: 'conservative',
        ru: 'Консервативный',
        en: 'Conservative',
        scenario: const WhatIfScenario(
          incomeMultiplier: 0.85,
          expenseMultiplier: 1.08,
        ),
      ),
      (
        key: 'aggressive',
        ru: 'Агрессивный',
        en: 'Aggressive',
        scenario: const WhatIfScenario(
          incomeMultiplier: 1.15,
          expenseMultiplier: 0.97,
        ),
      ),
      (
        key: 'stress',
        ru: 'Стресс',
        en: 'Stress',
        scenario: defaultStress(
          currentBalance: currentBalance,
          dailyVolatility: base.dailyVolatility,
        ),
      ),
    ];

    final summaries = <ForecastScenarioSummary>[];
    for (final definition in definitions) {
      final result = definition.key == 'base'
          ? base
          : ForecastEngine.generate(
              transactions: transactions,
              currentBalance: currentBalance,
              days: days,
              paths: max(500, min(1500, ForecastEngine.pathsForHorizon(days, 1500))),
              seed: 42,
              whatIf: definition.scenario,
              calibration: calibration,
              businessEvents: businessEvents,
              accounts: accounts,
              recurringReliability: recurringReliability,
            );
      summaries.add(ForecastScenarioSummary(
        key: definition.key,
        labelRu: definition.ru,
        labelEn: definition.en,
        endingP50: result.p50.isEmpty ? currentBalance : result.p50.last,
        minimumP10: result.p10.isEmpty ? currentBalance : result.p10.reduce(min),
        maximumGapRisk: result.maximumGapRisk,
        runwayDays: result.runwayDays,
      ));
    }
    return summaries;
  }

  static WhatIfRiskDelta riskDelta({
    required ForecastResult base,
    required ForecastResult scenario,
  }) =>
      WhatIfRiskDelta(
        baseMaximumRisk: base.maximumGapRisk,
        scenarioMaximumRisk: scenario.maximumGapRisk,
        baseRunwayDays: base.runwayDays,
        scenarioRunwayDays: scenario.runwayDays,
      );
}
