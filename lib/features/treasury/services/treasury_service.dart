import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction_model.dart';
import 'transaction_model.dart';

/// Wesi Treasury Service — управление финансами, аномалиями, прогнозами
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
      if (tx.type == TransactionType.income) income += tx.amount;
      else expense += tx.amount;
    }
    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  // ========== ANOMALY DETECTION (Z-Score) ==========

  Future<List<TransactionModel>> detectAnomalies() async {
    final all = await getAllTransactions();
    if (all.length < 4) return [];

    final expenses = all.where((t) => t.type == TransactionType.expense).toList();
    if (expenses.length < 4) return [];

    final amounts = expenses.map((e) => e.amount).toList();
    final mean = amounts.reduce((a, b) => a + b) / amounts.length;
    final variance = amounts.map((a) => pow(a - mean, 2)).reduce((a, b) => a + b) / amounts.length;
    final stdDev = sqrt(variance);

    if (stdDev == 0) return [];

    final anomalies = <TransactionModel>[];
    for (final tx in expenses) {
      final zScore = (tx.amount - mean) / stdDev;
      if (zScore.abs() > 2.0) {
        anomalies.add(tx.copyWith(isAnomaly: true, zScore: zScore));
      }
    }
    return anomalies;
  }

  // ========== RECURRING PAYMENTS ==========

  Future<List<TransactionModel>> getRecurringPayments() async {
    final all = await getAllTransactions();
    return all.where((t) => t.isRecurring).toList();
  }

  Future<void> processRecurringPayments() async {
    final recurring = await getRecurringPayments();
    final now = DateTime.now();

    for (final tx in recurring) {
      if (_shouldProcess(tx, now)) {
        final newTx = TransactionModel(
          id: '${tx.id}_\${now.millisecondsSinceEpoch}',
          title: tx.title,
          amount: tx.amount,
          type: tx.type,
          date: now,
          category: tx.category,
          description: 'Recurring: \${tx.description}',
          isRecurring: false,
        );
        await addTransaction(newTx);
      }
    }
  }

  bool _shouldProcess(TransactionModel tx, DateTime now) {
    if (tx.recurringPeriod == null) return false;
    final lastDate = tx.date;
    switch (tx.recurringPeriod!) {
      case RecurringPeriod.daily:
        return now.difference(lastDate).inDays >= 1;
      case RecurringPeriod.weekly:
        return now.difference(lastDate).inDays >= 7;
      case RecurringPeriod.monthly:
        return now.month != lastDate.month || now.year != lastDate.year;
      case RecurringPeriod.yearly:
        return now.year != lastDate.year;
    }
  }

  // ========== FORECAST (Monte-Carlo inspired) ==========

  Future<Map<String, List<double>>> generateForecast({int days = 30}) async {
    final all = await getAllTransactions();
    if (all.isEmpty) return {'p10': [], 'p50': [], 'p90': []};

    final dailyNet = <double>[];
    final byDay = <DateTime, double>{};

    for (final tx in all) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      byDay[day] = (byDay[day] ?? 0) + (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    final sortedDays = byDay.keys.toList()..sort();
    for (final day in sortedDays) {
      dailyNet.add(byDay[day]!);
    }

    if (dailyNet.isEmpty) return {'p10': [], 'p50': [], 'p90': []};

    final mean = dailyNet.reduce((a, b) => a + b) / dailyNet.length;
    final variance = dailyNet.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / dailyNet.length;
    final stdDev = sqrt(variance);

    final currentBalance = await getCurrentBalance();
    final p10 = <double>[];
    final p50 = <double>[];
    final p90 = <double>[];

    for (int i = 1; i <= days; i++) {
      final spread = stdDev * sqrt(i.toDouble());
      p10.add(currentBalance + (mean * i) - (1.28 * spread));
      p50.add(currentBalance + (mean * i));
      p90.add(currentBalance + (mean * i) + (1.28 * spread));
    }

    return {'p10': p10, 'p50': p50, 'p90': p90};
  }

  // ========== DEMO DATA ==========

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
          id: 'inc_\$i',
          title: 'Income #\$i',
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
          id: 'exp_\$i',
          title: 'Expense #\$i',
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
