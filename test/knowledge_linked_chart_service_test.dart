import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/analytics/services/analytics_service.dart';
import 'package:wesios/features/knowledge/services/knowledge_linked_chart_service.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

class _FakeTreasury extends TreasuryService {
  _FakeTreasury({this.forecast, this.transactions = const []});

  final ForecastResult? forecast;
  final List<TransactionModel> transactions;

  @override
  Future<ForecastResult> generateForecast({
    int days = 30,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0.0,
  }) async {
    return forecast ?? ForecastResult.empty();
  }

  @override
  Future<List<TransactionModel>> getAllTransactions() async => transactions;
}

class _FakeAnalytics extends AnalyticsService {
  _FakeAnalytics(this.snapshot);
  final AnalyticsSnapshot snapshot;

  @override
  Future<AnalyticsSnapshot> build({required int periodDays}) async => snapshot;
}

void main() {
  test('forecast linked chart samples real P50 values', () async {
    final forecast = ForecastResult(
      p10: List<double>.generate(30, (i) => i.toDouble()),
      p50: List<double>.generate(30, (i) => 1000 + i * 10),
      p90: List<double>.generate(30, (i) => 2000 + i * 10),
      trendPerDay: 10,
      dailyVolatility: 5,
      historyDaysSpan: 60,
      simulatedPaths: 1000,
      insufficientData: false,
      seasonalityApplied: true,
    );
    final service = KnowledgeLinkedChartService(
      treasury: _FakeTreasury(forecast: forecast),
    );

    final data = await service.load('forecast');
    expect(data.values.length, 8);
    expect(data.labels.first, 'D1');
    expect(data.labels.last, 'D30');
    expect(data.values.first, 1000);
    expect(data.values.last, 1290);
  });

  test('analytics linked chart uses real expense category totals', () async {
    final from = DateTime(2026, 8, 1);
    final snapshot = AnalyticsSnapshot(
      income: const Kpi(0, 0),
      expense: const Kpi(3000, 0),
      net: const Kpi(-3000, 0),
      operations: const Kpi(2, 0),
      months: const [],
      topExpenseCategories: const [
        MapEntry('Ads', 2000),
        MapEntry('Software', 1000),
      ],
      topIncomeCategories: const [],
      averageIncomeTicket: 0,
      burnPerDay: 100,
      runwayDays: 20,
      tasksDone: 0,
      tasksOverdue: 0,
      tasksTotal: 0,
      from: from,
      to: DateTime(2026, 8, 30),
    );
    final service = KnowledgeLinkedChartService(
      analytics: _FakeAnalytics(snapshot),
    );

    final data = await service.load('analytics');
    expect(data.labels, ['Ads', 'Software']);
    expect(data.values, [2000, 1000]);
  });

  test('treasury linked chart aggregates monthly signed net', () async {
    final transactions = [
      TransactionModel(
        id: 'july-income',
        title: 'Sale',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime(2026, 7, 5),
      ),
      TransactionModel(
        id: 'july-expense',
        title: 'Ads',
        amount: 1200,
        type: TransactionType.expense,
        date: DateTime(2026, 7, 15),
      ),
      TransactionModel(
        id: 'aug-expense',
        title: 'Server',
        amount: 800,
        type: TransactionType.expense,
        date: DateTime(2026, 8, 2),
      ),
    ];
    final service = KnowledgeLinkedChartService(
      treasury: _FakeTreasury(transactions: transactions),
      now: () => DateTime(2026, 8, 9),
    );

    final data = await service.load('treasury');
    expect(data.labels.length, 7);
    expect(data.labels[data.labels.length - 2], '07.26');
    expect(data.labels.last, '08.26');
    expect(data.values[data.values.length - 2], 3800);
    expect(data.values.last, -800);
  });

  test('unknown or unavailable source returns an empty chart', () async {
    final service = KnowledgeLinkedChartService(
      treasury: _FakeTreasury(),
    );
    expect((await service.load('forecast')).values, isEmpty);
    expect((await service.load('unknown')).values, isEmpty);
  });
}
