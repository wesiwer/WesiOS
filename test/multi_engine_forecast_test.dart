import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/multi_engine_forecast.dart';

ForecastResult _result({
  required List<double> p10,
  required List<double> p50,
  required List<double> p90,
}) {
  return ForecastResult(
    p10: p10,
    p50: p50,
    p90: p90,
    trendPerDay: 0,
    dailyVolatility: 0,
    historyDaysSpan: 30,
    simulatedPaths: 0,
    insufficientData: false,
    seasonalityApplied: false,
  );
}

void main() {
  group('combineForecastResults', () {
    test('averages elementwise across all available engines', () {
      final a = _result(p10: [90, 80], p50: [100, 100], p90: [110, 120]);
      final b = _result(p10: [70, 60], p50: [80, 90], p90: [90, 100]);

      final combined = combineForecastResults([a, b]);

      expect(combined, isNotNull);
      expect(combined!.p50, [90.0, 95.0]);
      expect(combined.p10, [80.0, 70.0]);
      expect(combined.p90, [100.0, 110.0]);
    });

    test('skips unavailable (null) engines instead of treating them as zero',
        () {
      final a = _result(p10: [90], p50: [100], p90: [110]);

      final combined = combineForecastResults([a, null]);

      expect(combined, isNotNull);
      // Если бы null считался нулём, p50 было бы 50, а не 100.
      expect(combined!.p50, [100.0]);
    });

    test('returns null when no engine produced a result', () {
      expect(combineForecastResults([null, null]), isNull);
    });

    test('returns null on mismatched series lengths rather than crashing',
        () {
      final a = _result(p10: [1, 2], p50: [1, 2], p90: [1, 2]);
      final b = _result(p10: [1], p50: [1], p90: [1]);

      expect(combineForecastResults([a, b]), isNull);
    });
  });

  group('RiskEstimate.derive', () {
    test('flags runwayDays on the first day the median goes negative', () {
      final risk = RiskEstimate.derive([-10, -5, 5], [0, -2, 8], [10, 1, 11]);
      expect(risk.runwayDays, 2); // день 2 (1-indexed): p50 = -2
    });

    test('null runwayDays when the median never goes negative', () {
      final risk = RiskEstimate.derive([5, 6], [10, 11], [15, 16]);
      expect(risk.runwayDays, isNull);
    });

    test('zero spread (p10==p50==p90) still yields a crisp 0/1 probability, '
        'no NaN or divide-by-zero', () {
      final risk = RiskEstimate.derive([-5, 5], [-5, 5], [-5, 5]);
      expect(risk.belowZero[0], 1.0);
      expect(risk.belowZero[1], 0.0);
    });

    test('belowZeroProbability is higher when P50 sits closer to zero '
        'relative to the same spread', () {
      // Одинаковый разброс (P90-P10 = 120) в обоих случаях — отличается
      // только то, насколько P50 далёк от нуля.
      final riskNearZero = RiskEstimate.derive([-50], [10], [70]);
      final riskFarFromZero = RiskEstimate.derive([40], [100], [160]);
      expect(riskNearZero.belowZero[0], greaterThan(riskFarFromZero.belowZero[0]));
    });
  });
}
