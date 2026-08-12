import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

TransactionModel _tx({
  required String id,
  required DateTime date,
  required double amount,
  required TransactionType type,
  String category = 'services',
  bool recurring = false,
  RecurringPeriod? period,
}) =>
    TransactionModel(
      id: id,
      title: id,
      amount: amount,
      type: type,
      date: date,
      category: category,
      isRecurring: recurring,
      recurringPeriod: period,
    );

void main() {
  final now = DateTime(2026, 8, 9);

  List<TransactionModel> smallOperatingHistory() {
    final history = <TransactionModel>[];
    for (var ago = 90; ago >= 1; ago--) {
      history.add(_tx(
        id: 'inc-$ago',
        date: now.subtract(Duration(days: ago)),
        amount: 300,
        type: TransactionType.income,
        category: 'services',
      ));
      history.add(_tx(
        id: 'exp-$ago',
        date: now.subtract(Duration(days: ago)),
        amount: 250,
        type: TransactionType.expense,
        category: 'operations',
      ));
    }
    return history;
  }

  test('main-source stress can hit a dominant CRM/business source', () {
    final history = smallOperatingHistory();
    final event = HorizonCashEvent(
      title: 'Large client deal',
      amount: 100000,
      date: now.add(const Duration(days: 10)),
      probability: 1,
      committed: false,
      source: 'crm',
      riskSource: 'crm:client-a',
    );

    final base = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 220,
      seed: 42,
      asOf: now,
      businessEvents: [event],
    );
    final stress = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 220,
      seed: 42,
      asOf: now,
      businessEvents: [event],
      whatIf: const WhatIfScenario(mainIncomeLossDays: 60),
    );

    expect(base.p50[9] - stress.p50[9], greaterThan(70000),
        reason:
            'The dominant business source must be the one removed by main-source stress.');
  });

  test('main-source stress can hit dominant recurring income', () {
    final history = smallOperatingHistory();
    final recurring = _tx(
      id: 'major-retainer',
      date: now,
      amount: 50000,
      type: TransactionType.income,
      category: 'services',
      recurring: true,
      period: RecurringPeriod.monthly,
    );
    history.add(recurring);

    ForecastResult run(WhatIfScenario scenario) => ForecastEngine.generate(
          transactions: history,
          currentBalance: 60000,
          days: 70,
          paths: 220,
          seed: 42,
          asOf: now,
          recurringReliability: const {'major-retainer': 1.0},
          whatIf: scenario,
        );

    final base = run(WhatIfScenario.none);
    final stress = run(const WhatIfScenario(mainIncomeLossDays: 60));

    // First future monthly occurrence is within ~31 days. The 85% loss of a
    // 50k retainer must dominate the small statistical operating stream.
    final largestDifference = List<double>.generate(
      60,
      (i) => base.p50[i] - stress.p50[i],
    ).reduce((a, b) => a > b ? a : b);
    expect(largestDifference, greaterThan(35000));
  });
}
