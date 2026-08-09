import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/recurring_payment_automation.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

class _CountingTreasuryService extends TreasuryService {
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<void> processRecurringPayments() async {
    calls++;
    final pending = gate;
    if (pending != null) await pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('throttles repeated automatic runs and retries after interval', () async {
    final treasury = _CountingTreasuryService();
    var now = DateTime(2026, 8, 9, 10);
    final automation = RecurringPaymentAutomation(
      treasury: treasury,
      now: () => now,
      minInterval: const Duration(minutes: 5),
    );

    await automation.runNow(force: true);
    expect(treasury.calls, 1);

    await automation.runNow();
    expect(treasury.calls, 1, reason: 'resume storm must be throttled');

    now = now.add(const Duration(minutes: 6));
    await automation.runNow();
    expect(treasury.calls, 2);
  });

  test('multiple triggers share one in-flight materialization', () async {
    final treasury = _CountingTreasuryService()..gate = Completer<void>();
    final automation = RecurringPaymentAutomation(
      treasury: treasury,
      minInterval: Duration.zero,
    );

    final first = automation.runNow(force: true);
    final second = automation.runNow(force: true);

    expect(identical(first, second), isTrue);
    expect(treasury.calls, 1);

    treasury.gate!.complete();
    await Future.wait([first, second]);
    expect(treasury.calls, 1);
  });
}
