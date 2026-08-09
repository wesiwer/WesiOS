import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/recurring_engine.dart';

TransactionModel _tx({
  required String id,
  required DateTime date,
  required double amount,
  required TransactionType type,
  bool recurring = false,
  RecurringPeriod? period,
}) =>
    TransactionModel(
      id: id,
      title: 'Recurring salary',
      amount: amount,
      type: type,
      date: date,
      category: 'services',
      isRecurring: recurring,
      recurringPeriod: period,
    );

void main() {
  final now = DateTime(2026, 8, 9);

  test('schedule rows cannot manufacture high statistical confidence', () {
    final parent = _tx(
      id: 'rec-income',
      date: now,
      amount: 10000,
      type: TransactionType.income,
      recurring: true,
      period: RecurringPeriod.monthly,
    );
    final history = <TransactionModel>[parent];
    for (var i = 1; i <= 50; i++) {
      history.add(_tx(
        id: 'rec-income_${now.subtract(Duration(days: i * 3)).millisecondsSinceEpoch}',
        date: now.subtract(Duration(days: i * 3)),
        amount: 10000,
        type: TransactionType.income,
      ));
    }

    final result = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 120,
      seed: 42,
      asOf: now,
    );

    expect(result.insufficientData, isFalse,
        reason: 'Known recurring cash allows a forecast, but not fake evidence.');
    expect(result.confidence, ForecastConfidence.low);
    expect(result.seasonalityApplied, isFalse);
  });

  test('advanced recurring income with no real receipts is not committed cash',
      () {
    final parent = _tx(
      id: 'monthly-client',
      date: now,
      amount: 12000,
      type: TransactionType.income,
      recurring: true,
      period: RecurringPeriod.monthly,
    );

    final result = ForecastEngine.generate(
      transactions: [parent],
      currentBalance: 30000,
      days: 70,
      paths: 180,
      seed: 42,
      asOf: now,
    );

    final next = RecurringEngine.advance(now, RecurringPeriod.monthly);
    final offset = DateTime(next.year, next.month, next.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    expect(offset, greaterThan(0));
    expect(result.committedNetByDay[offset - 1], 0,
        reason:
            'An expected client payment without execution evidence must remain uncertain.');
  });

  test('probabilistic business cash lowers known-cash share', () {
    final expense = _tx(
      id: 'monthly-rent',
      date: now,
      amount: 10000,
      type: TransactionType.expense,
      recurring: true,
      period: RecurringPeriod.monthly,
    );
    final result = ForecastEngine.generate(
      transactions: [expense],
      currentBalance: 100000,
      days: 60,
      paths: 150,
      seed: 42,
      asOf: now,
      businessEvents: [
        HorizonCashEvent(
          title: 'Uncertain CRM deal',
          amount: 40000,
          date: now.add(const Duration(days: 20)),
          probability: .5,
          committed: false,
          source: 'crm',
        ),
      ],
    );

    expect(result.knownCashShare, greaterThan(0));
    expect(result.knownCashShare, lessThan(1),
        reason:
            'Probability-weighted business cash belongs in the unknown denominator.');
  });

  test('runtime wiring never auto-posts recurring income as actual cash', () {
    final treasury =
        File('lib/features/treasury/services/treasury_service.dart')
            .readAsStringSync();
    expect(treasury, contains('if (tx.type == TransactionType.expense)'));
    expect(treasury, contains('Income is NOT auto-posted as actual cash'));

    final context =
        File('lib/features/treasury/services/horizon_business_context.dart')
            .readAsStringSync();
    expect(context, contains('context-crm-unavailable'));
    expect(context, contains('context-vault-unavailable'));
    expect(context, contains('context-tasks-unavailable'));
    expect(context, contains('context-accounts-unavailable'));
  });
}
