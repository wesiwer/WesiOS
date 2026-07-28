import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction_model.dart';
import 'anomaly_engine.dart';
import 'forecast_engine.dart';
import 'recurring_engine.dart';

/// Wesi Treasury Service — управление финансами, аномалиями, прогнозами.
///
/// Статистика (прогноз, аномалии, регулярные платежи) вынесена в общие
/// движки ([ForecastEngine], [AnomalyEngine], [RecurringEngine]), которые
/// использует и [TreasuryService], и SandboxService — так гарантируется,
/// что поведение у них идентично, а данные при этом изолированы (разные
/// Hive-боксы).
class TreasuryService {
  static const String _boxName = 'wesios_treasury';
  Box<TransactionModel>? _box;

  Future<Box<TransactionModel>> get _treasuryBox async {
    _box ??= await Hive.openBox<TransactionModel>(_boxName);
    return _box!;
  }

  // ========== CRUD ==========

  Future<void> addTransaction(TransactionModel tx) async {
    final box = await _treasuryBox;
    await box.put(tx.id, tx);
  }

  Future<void> deleteTransaction(String id) async {
    final box = await _treasuryBox;
    await box.delete(id);
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final box = await _treasuryBox;
    return box.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<TransactionModel>> getTransactionsByType(TransactionType type) async {
    final all = await getAllTransactions();
    return all.where((t) => t.type == type).toList();
  }

  // ========== BALANCE ==========

  Future<double> getCurrentBalance() async {
    final all = await getAllTransactions();
    double balance = 0;
    for (final tx in all) {
      balance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }
    return balance;
  }

  Future<Map<String, double>> getBalanceBreakdown() async {
    final all = await getAllTransactions();
    double income = 0, expense = 0;
    for (final tx in all) {
      if (tx.type == TransactionType.income) {
        income += tx.amount;
      } else {
        expense += tx.amount;
      }
    }
    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  // ========== ANOMALY DETECTION ==========

  Future<List<TransactionModel>> detectAnomalies() async {
    return AnomalyEngine.detect(await getAllTransactions());
  }

  // ========== RECURRING PAYMENTS ==========

  Future<List<TransactionModel>> getRecurringPayments() async {
    final all = await getAllTransactions();
    return all.where((t) => t.isRecurring).toList();
  }

  /// Материализует все просроченные регулярные платежи в отдельные
  /// транзакции и сдвигает «якорь» (дату) регулярной записи вперёд.
  ///
  /// Раньше проверка due-даты сравнивалась с ИСХОДНОЙ датой создания записи,
  /// которая никогда не обновлялась — при повторном вызове платёж
  /// пересоздавался бы бесконечно. Теперь после срабатывания дата регулярной
  /// транзакции переносится на дату последнего проведённого платежа.
  Future<void> processRecurringPayments() async {
    final recurring = await getRecurringPayments();
    final now = DateTime.now();

    for (final tx in recurring) {
      final period = tx.recurringPeriod;
      if (period == null) continue;

      var anchor = tx;
      var guard = 0;
      // Обрабатываем все просроченные периоды за один вызов — иначе платёж
      // «застрянет» на первом же пропущенном разе.
      while (RecurringEngine.isDue(anchor, now) && guard < 366) {
        final due = RecurringEngine.advance(anchor.date, period);
        await addTransaction(TransactionModel(
          id: '${tx.id}_${due.millisecondsSinceEpoch}',
          title: tx.title,
          amount: tx.amount,
          type: tx.type,
          date: due,
          category: tx.category,
          description:
              tx.description == null ? null : 'Recurring: ${tx.description}',
          isRecurring: false,
        ));
        anchor = anchor.copyWith(date: due);
        guard++;
      }
      if (guard > 0) {
        await addTransaction(anchor); // сдвигаем якорь исходной записи
      }
    }
  }

  // ========== FORECAST ==========

  Future<ForecastResult> generateForecast({int days = 30}) async {
    final all = await getAllTransactions();
    final balance = await getCurrentBalance();
    return ForecastEngine.generate(
      transactions: all,
      currentBalance: balance,
      days: days,
    );
  }

  // ========== DEMO DATA (kept but NOT auto-called from forecast screen) ==========

  Future<void> generateDemoData() async {
    final box = await _treasuryBox;
    if (box.isNotEmpty) return;

    final now = DateTime.now();
    final random = Random();

    final categories = ['Software', 'Marketing', 'Office', 'Salaries', 'Freelance', 'Investments'];

    // Generate 60 days of history
    for (int i = 60; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));

      // Daily income (freelance, sales)
      if (random.nextDouble() > 0.3) {
        await addTransaction(TransactionModel(
          id: 'inc_$i',
          title: 'Income #$i',
          amount: 1000 + random.nextInt(4000).toDouble(),
          type: TransactionType.income,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }

      // Daily expenses
      if (random.nextDouble() > 0.2) {
        final amount = 100 + random.nextInt(900).toDouble();
        await addTransaction(TransactionModel(
          id: 'exp_$i',
          title: 'Expense #$i',
          amount: amount,
          type: TransactionType.expense,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }
    }

    // Add some anomalies
    await addTransaction(TransactionModel(
      id: 'anomaly_1',
      title: 'Emergency Server Repair',
      amount: 15000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 5)),
      category: 'Infrastructure',
      isAnomaly: true,
      zScore: 3.2,
    ));

    // Add recurring
    await addTransaction(TransactionModel(
      id: 'recurring_salary',
      title: 'Monthly Salary',
      amount: 5000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 15)),
      category: 'Salaries',
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
    ));
  }
}
