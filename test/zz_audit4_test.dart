import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/multi_engine_forecast.dart';

void main() {
  test('внешний движок вернул p50, но не вернул p10/p90', () {
    // Так выглядит ответ, где Python отдал только медиану.
    expect(
      () => RiskEstimate.derive(const [], const [100, 90, 80], const []),
      returnsNormally,
      reason: 'неполный ответ движка не должен ронять экран прогноза',
    );
  });
}
