import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_explainability.dart';

void main() {
  test('probabilistic business event is attributed once, not as fake committed remainder',
      () {
    final now = DateTime(2026, 8, 9);
    const forecast = ForecastResult(
      p10: [95000, 105000],
      p50: [100000, 120000],
      p90: [105000, 140000],
      trendPerDay: 0,
      dailyVolatility: 100,
      historyDaysSpan: 120,
      simulatedPaths: 1000,
      insufficientData: false,
      seasonalityApplied: true,
      committedNetByDay: [0, 0],
      uncertainMedianByDay: [0, 0],
    );

    final result = HorizonExplainabilityService.build(
      forecast: forecast,
      transactions: const [],
      businessEvents: [
        HorizonCashEvent(
          title: 'CRM deal',
          amount: 40000,
          date: now.add(const Duration(days: 2)),
          probability: .5,
          committed: false,
          source: 'crm',
        ),
      ],
      now: now,
    );

    final crm = result.where((e) => e.day == 2 && e.source == 'crm').toList();
    expect(crm, hasLength(1));
    expect(crm.single.impact, 20000);
    expect(
      result.any((e) => e.day == 2 && e.source == 'committed-cash'),
      isFalse,
    );
    expect(
      result.any((e) =>
          e.day == 2 &&
          e.source == 'distribution-attribution' &&
          e.impact.abs() > 1),
      isFalse,
    );
  });
}
