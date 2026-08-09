import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overdue expected cash remains visible but loses false certainty', () {
    final source =
        File('lib/features/treasury/services/horizon_business_context.dart')
            .readAsStringSync();

    expect(source, contains('if (!due.isAfter(today))'));
    expect(source, contains("code: 'crm-overdue-\${deal.id}'"));
    expect(source, contains('final decay = exp(-overdueDays / 45.0)'));
    expect(source, contains('probability = (probability * decay)'));
    expect(source, contains('committed = false;'));
    expect(source, contains('eventDate = today.add(const Duration(days: 1))'));

    expect(source,
        contains('final missedIncoming = overdue && parsed.signedAmount > 0;'));
    expect(source, contains('min(parsed.probability, 0.65)'));
    expect(source, contains('committed: missedIncoming ? false : parsed.committed'));
  });

  test('fallback uncertainty learns from actual non-recurring history only', () {
    final source = File('lib/features/treasury/services/forecast_engine.dart')
        .readAsStringSync();
    expect(
      source,
      contains('final fallbackDailyVolatility = _fallbackDailyVolatility(\n      history: nonRecurring,'),
    );
  });
}
