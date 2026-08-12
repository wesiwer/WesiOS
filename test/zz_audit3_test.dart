import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/history_series.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

/// История на графике и старт прогноза обязаны сходиться: иначе линия
/// делает скачок ровно там, где факт переходит в предсказание.
void main() {
  TransactionModel tx(String id, double amount, TransactionType type, DateTime date) =>
      TransactionModel(id: id, title: id, amount: amount, type: type, date: date);

  double total(List<TransactionModel> txs) => txs.fold<double>(
      0, (s, t) => t.type == TransactionType.income ? s + t.amount : s - t.amount);

  test('операция в первый день окна не считается дважды', () {
    final now = DateTime(2026, 3, 1, 15, 0);
    final txs = [
      // Ровно на границе окна и раньше текущего времени суток — прежняя
      // формула засчитывала её и «до окна», и «внутри окна».
      tx('утренняя', 1000, TransactionType.income, DateTime(2026, 1, 30, 9, 0)),
      tx('внутри', 500, TransactionType.income, DateTime(2026, 2, 10, 12, 0)),
      tx('старая', 700, TransactionType.income, DateTime(2025, 12, 1, 12, 0)),
    ];

    final history = buildHistorySeries(transactions: txs, now: now, windowDays: 30);
    final start = TreasuryService.balanceOnDay(now, txs, total(txs));
    expect(history.last.balance, start);
  });

  test('операция, датированная будущим, не поднимает сегодняшний баланс', () {
    final now = DateTime(2026, 3, 1, 15, 0);
    final txs = [
      tx('прошлое', 1000, TransactionType.income, DateTime(2026, 2, 1, 12, 0)),
      tx('будущее', 5000, TransactionType.income, DateTime(2026, 4, 1, 12, 0)),
    ];
    final history = buildHistorySeries(transactions: txs, now: now, windowDays: 30);
    final start = TreasuryService.balanceOnDay(now, txs, total(txs));
    expect(history.last.balance, 1000);
    expect(start, 1000);
  });

  test('окно длиной в неделю даёт восемь точек: семь дней плюс сегодня', () {
    final now = DateTime(2026, 3, 1, 15, 0);
    final history = buildHistorySeries(transactions: [], now: now, windowDays: 7);
    expect(history.length, 8);
    expect(history.last.date, DateTime(2026, 3, 1));
  });
}
