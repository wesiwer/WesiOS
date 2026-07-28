import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction_model.dart';
import 'treasury_service.dart';

/// Wesi Sandbox — изолированная среда для тестирования финансовых сценариев.
///
/// Намеренно дублирует TreasuryService: работает с отдельным Hive-боксом,
/// чтобы можно было крутить вымышленные сценарии без риска для реальных данных.
class SandboxService {
  static const String _boxName = 'wesios_sandbox';
  Box<TransactionModel>? _box;

  Future<Box<TransactionModel>> get _sandboxBox async {
    _box ??= await Hive.openBox<TransactionModel>(_boxName);
    return _box!;
  }

  // ========== CRUD ==========

  Future<void> addTransaction(TransactionModel tx) async {
    final box = await _sandboxBox;
    await box.put(tx.id, tx);
  }

  Future<void> deleteTransaction(String id) async {
    final box = await _sandboxBox;
    await box.delete(id);
  }

  Future<void> clearAll() async {
    final box = await _sandboxBox;
    await box.clear();
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final box = await _sandboxBox;
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

  // ========== ANOMALY DETECTION ==========

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

  // ========== FORECAST (sandbox-local, non-linear) ==========

  Future<Map<String, List<double>>> generateForecast({int days = 30}) async {
    final all = await getAllTransactions();
    if (all.isEmpty) return {'p10': [], 'p50': [], 'p90': []};

    final dailyNet = <double>[];
    final byDay = <DateTime, double>{};

    for (final tx in all) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      byDay[day] = (byDay[day] ?? 0) +
          (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    final sortedDays = byDay.keys.toList()..sort();
    for (final day in sortedDays) {
      dailyNet.add(byDay[day]!);
    }

    if (dailyNet.isEmpty) return {'p10': [], 'p50': [], 'p90': []};

    final mean = dailyNet.reduce((a, b) => a + b) / dailyNet.length;
    final variance =
        dailyNet.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            dailyNet.length;
    final stdDev = sqrt(variance);

    final recent =
        dailyNet.length > 14 ? dailyNet.sublist(dailyNet.length - 14) : dailyNet;
    final recentMean = recent.reduce((a, b) => a + b) / recent.length;
    double slope = 0;
    if (recent.length >= 3) {
      final n = recent.length;
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (int i = 0; i < n; i++) {
        sumX += i;
        sumY += recent[i];
        sumXY += i * recent[i];
        sumX2 += i * i;
      }
      final denom = n * sumX2 - sumX * sumX;
      if (denom != 0) slope = (n * sumXY - sumX * sumY) / denom;
    }

    final drift = 0.6 * mean + 0.4 * recentMean;
    final currentBalance = await getCurrentBalance();
    final p10 = <double>[];
    final p50 = <double>[];
    final p90 = <double>[];

    double balP50 = currentBalance;
    final rng = Random(42);

    for (int i = 1; i <= days; i++) {
      final decay = exp(-i / (days * 1.5));
      final dayDrift = drift + slope * decay;
      final noise = (rng.nextDouble() - 0.5) * stdDev * 0.15;
      final spread = stdDev * sqrt(i.toDouble()) * (1.0 + 0.1 * sin(i / 7.0));

      balP50 += dayDrift + noise;
      p10.add(balP50 - 1.28 * spread);
      p50.add(balP50);
      p90.add(balP50 + 1.28 * spread);
    }

    return {'p10': p10, 'p50': p50, 'p90': p90};
  }

  // ========== SCENARIO GENERATORS ==========

  Future<void> generateStartupScenario() async {
    await clearAll();
    final now = DateTime.now();
    final random = Random();

    await addTransaction(TransactionModel(
      id: 'sandbox_seed',
      title: 'Seed Investment',
      amount: 500000,
      type: TransactionType.income,
      date: now.subtract(const Duration(days: 90)),
      category: 'Investment',
    ));

    for (int i = 90; i >= 0; i -= 30) {
      await addTransaction(TransactionModel(
        id: 'sandbox_burn_$i',
        title: 'Monthly Burn',
        amount: 15000 + random.nextInt(5000).toDouble(),
        type: TransactionType.expense,
        date: now.subtract(Duration(days: i)),
        category: 'Operations',
      ));
    }

    for (int i = 60; i >= 0; i -= 15) {
      await addTransaction(TransactionModel(
        id: 'sandbox_rev_$i',
        title: 'MRR Revenue',
        amount: 2000 + random.nextInt(3000).toDouble(),
        type: TransactionType.income,
        date: now.subtract(Duration(days: i)),
        category: 'Revenue',
      ));
    }
  }

  Future<void> generateFreelancerScenario() async {
    await clearAll();
    final now = DateTime.now();
    final random = Random();

    for (int i = 60; i >= 0; i -= random.nextInt(5) + 2) {
      await addTransaction(TransactionModel(
        id: 'sandbox_fl_$i',
        title: 'Client Project #${random.nextInt(20)}',
        amount: 500 + random.nextInt(2500).toDouble(),
        type: TransactionType.income,
        date: now.subtract(Duration(days: i)),
        category: 'Freelance',
      ));
    }

    for (int i = 60; i >= 0; i -= random.nextInt(7) + 3) {
      await addTransaction(TransactionModel(
        id: 'sandbox_fle_$i',
        title: 'Business Expense',
        amount: 50 + random.nextInt(300).toDouble(),
        type: TransactionType.expense,
        date: now.subtract(Duration(days: i)),
        category: 'Expenses',
      ));
    }
  }

  Future<void> generateCrisisScenario() async {
    await clearAll();
    final now = DateTime.now();
    final random = Random();

    for (int i = 90; i >= 30; i--) {
      if (random.nextDouble() > 0.7) {
        await addTransaction(TransactionModel(
          id: 'sandbox_norm_$i',
          title: 'Regular Expense',
          amount: 100 + random.nextInt(200).toDouble(),
          type: TransactionType.expense,
          date: now.subtract(Duration(days: i)),
          category: 'Operations',
        ));
      }
    }

    await addTransaction(TransactionModel(
      id: 'sandbox_crisis_1',
      title: 'Emergency Legal Fees',
      amount: 50000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 20)),
      category: 'Legal',
      isAnomaly: true,
      zScore: 4.5,
    ));

    await addTransaction(TransactionModel(
      id: 'sandbox_crisis_2',
      title: 'Server Ransomware Recovery',
      amount: 35000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 15)),
      category: 'Security',
      isAnomaly: true,
      zScore: 3.8,
    ));

    await addTransaction(TransactionModel(
      id: 'sandbox_crisis_3',
      title: 'Client Churn — Refunds',
      amount: 25000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 10)),
      category: 'Refunds',
      isAnomaly: true,
      zScore: 3.2,
    ));
  }

  /// Копирует реальные данные с уникальными sandbox-id, чтобы не было коллизий
  Future<void> cloneFromReal() async {
    await clearAll();
    final realService = TreasuryService();
    final realTxs = await realService.getAllTransactions();
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (final tx in realTxs) {
      await addTransaction(tx.copyWith(
        id: 'sandbox_clone_${ts}_${tx.id}',
      ));
    }
  }
}
