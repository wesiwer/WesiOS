import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

void main() {
  final now = DateTime(2026, 8, 9);

  test('account liquidity projects recurring expense on its actual account', () {
    final recurring = TransactionModel(
      id: 'account-rent',
      title: 'Office rent',
      amount: 8000,
      type: TransactionType.expense,
      date: now,
      category: 'rent',
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
      accountId: 'operating',
    );

    final result = ForecastEngine.generate(
      transactions: [recurring],
      currentBalance: 10000,
      days: 45,
      paths: 120,
      seed: 42,
      asOf: now,
      accounts: const [
        AccountLiquiditySnapshot(
          accountId: 'operating',
          name: 'Operating',
          balance: 10000,
          minimumBalance: 5000,
          currency: 'rub',
        ),
      ],
    );

    final risk = result.accountLiquidityRisks.single;
    expect(risk.riskDay, isNotNull,
        reason:
            'An 8k monthly recurring expense must create a local shortfall from a 10k account with a 5k minimum.');
    expect(risk.riskDay!, inInclusiveRange(25, 35));
  });

  test('uncertain business income multiplier is applied to CRM/Vault events', () {
    final event = HorizonCashEvent(
      title: 'Pipeline cash',
      amount: 100000,
      date: now.add(const Duration(days: 10)),
      probability: 1,
      committed: false,
      source: 'crm',
      riskSource: 'crm:client',
    );
    ForecastResult run(WhatIfScenario whatIf) => ForecastEngine.generate(
          transactions: const [],
          currentBalance: 10000,
          days: 30,
          paths: 120,
          seed: 42,
          asOf: now,
          businessEvents: [event],
          whatIf: whatIf,
        );

    final base = run(WhatIfScenario.none);
    final conservative = run(const WhatIfScenario(
      incomeMultiplier: .7,
      incomeMultiplierDays: 30,
    ));
    expect(base.p50[9] - conservative.p50[9], greaterThan(25000));
  });
}
