import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction_model.dart';
import 'anomaly_engine.dart';
import 'forecast_engine.dart';
import 'recurring_engine.dart';
import 'treasury_service.dart';

/// Wesi Sandbox — изолированная среда для тестирования финансовых сценариев.
///
/// Намеренно дублирует TreasuryService на уровне сервиса/хранилища: работает
/// с отдельным Hive-боксом, чтобы можно было крутить вымышленные сценарии без
/// риска для реальных данных. При этом вся статистика (прогноз, аномалии,
/// регулярные платежи) идёт через ТЕ ЖЕ общие движки, что и у Treasury
/// ([ForecastEngine], [AnomalyEngine], [RecurringEngine]) — поведение
/// гарантированно идентично, различаются только данные.
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
  // Идентично TreasuryService — общая логика через RecurringEngine.

  Future<List<TransactionModel>> getRecurringPayments() async {
    final all = await getAllTransactions();
    return all.where((t) => t.isRecurring).toList();
  }

  Future<void> processRecurringPayments() async {
    final recurring = await getRecurringPayments();
    final now = DateTime.now();

    for (final tx in recurring) {
      final period = tx.recurringPeriod;
      if (period == null) continue;

      var anchor = tx;
      var guard = 0;
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
        await addTransaction(anchor);
      }
    }
  }

  // ========== FORECAST ==========

  Future<ForecastResult> generateForecast({
    int days = 30,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0.0,
  }) async {
    final all = await getAllTransactions();
    final balance = await getCurrentBalance();
    return ForecastEngine.generate(
      transactions: all,
      currentBalance: balance,
      whatIf: whatIf,
      annualDiscountRate: annualDiscountRate,
      days: days,
    );
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
