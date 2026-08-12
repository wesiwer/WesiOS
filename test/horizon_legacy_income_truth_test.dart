import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';

void main() {
  final today = DateTime(2026, 8, 9);

  test('legacy auto-generated recurring income is not treated as actual cash', () {
    final parent = TransactionModel(
      id: 'client-retainer',
      title: 'Client retainer',
      amount: 10000,
      type: TransactionType.income,
      date: today,
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
    );
    final legacyChild = TransactionModel(
      id: 'client-retainer_${today.subtract(const Duration(days: 30)).millisecondsSinceEpoch}',
      title: 'Client retainer',
      amount: 10000,
      type: TransactionType.income,
      date: today.subtract(const Duration(days: 30)),
    );

    // Current balance of 10k intentionally excludes the legacy synthetic
    // child. Historical reconstruction must not subtract that child again.
    final reconstructed = ForecastBacktest.balanceOn(
      today.subtract(const Duration(days: 60)),
      [parent, legacyChild],
      10000,
      currentDate: today,
    );
    expect(reconstructed, 10000);

    final accountSource =
        File('lib/features/treasury/services/account_service.dart')
            .readAsStringSync();
    expect(accountSource, contains('actualForBalance'));
    expect(accountSource, contains('legacyAutoIncome'));
  });
}
