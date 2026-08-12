import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';

TransactionModel _tx({
  required String id,
  required DateTime date,
  required double amount,
  required TransactionType type,
}) =>
    TransactionModel(
      id: id,
      title: id,
      amount: amount,
      type: type,
      date: date,
    );

void main() {
  final today = DateTime(2026, 8, 9);

  test('historical reconstruction ignores transactions scheduled after current balance date',
      () {
    final txs = [
      _tx(
        id: 'real-yesterday',
        date: today.subtract(const Duration(days: 1)),
        amount: 100,
        type: TransactionType.income,
      ),
      _tx(
        id: 'future-sale',
        date: today.add(const Duration(days: 5)),
        amount: 10000,
        type: TransactionType.income,
      ),
      _tx(
        id: 'future-rent',
        date: today.add(const Duration(days: 7)),
        amount: 8000,
        type: TransactionType.expense,
      ),
    ];

    // Current actual balance contains only yesterday's +100. Future schedules
    // have not happened and must not be subtracted from historical balance.
    expect(
      ForecastBacktest.balanceOn(
        today.subtract(const Duration(days: 1)),
        txs,
        100,
        currentDate: today,
      ),
      100,
    );
    expect(
      ForecastBacktest.balanceOn(
        today.subtract(const Duration(days: 2)),
        txs,
        100,
        currentDate: today,
      ),
      0,
    );
  });

  test('current account summary source excludes future-dated operations', () {
    final source = File('lib/features/treasury/services/account_service.dart')
        .readAsStringSync();
    expect(source, contains('DateTime? asOf'));
    expect(source, contains('!t.date.isAfter(cutoff)'));

    final treasury =
        File('lib/features/treasury/services/treasury_service.dart')
            .readAsStringSync();
    expect(treasury, contains('.where((tx) => !tx.date.isAfter(now))'));
  });
}
