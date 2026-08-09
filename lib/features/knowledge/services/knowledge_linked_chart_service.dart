import '../../analytics/services/analytics_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/treasury_service.dart';

class KnowledgeLinkedChartData {
  final List<double> values;
  final List<String> labels;

  const KnowledgeLinkedChartData({
    required this.values,
    required this.labels,
  });

  static const empty = KnowledgeLinkedChartData(values: [], labels: []);
}

/// Источники данных для inline charts в Knowledge Base.
///
/// В старой реализации linked charts с `source=forecast/analytics/treasury`
/// рисовали жёстко прошитые demo-массивы. Здесь все три источника читают те
/// же реальные сервисы, что Treasury/Analytics UI.
class KnowledgeLinkedChartService {
  KnowledgeLinkedChartService({
    TreasuryService? treasury,
    AnalyticsService? analytics,
    DateTime Function()? now,
  })  : _treasury = treasury ?? TreasuryService(),
        _analytics = analytics ?? AnalyticsService(),
        _now = now ?? DateTime.now;

  final TreasuryService _treasury;
  final AnalyticsService _analytics;
  final DateTime Function() _now;

  Future<KnowledgeLinkedChartData> load(String source) async {
    switch (source.trim().toLowerCase()) {
      case 'forecast':
        return _forecastData();
      case 'analytics':
        return _analyticsData();
      case 'treasury':
        return _treasuryData();
      default:
        return KnowledgeLinkedChartData.empty;
    }
  }

  Future<KnowledgeLinkedChartData> _forecastData() async {
    final result = await _treasury.generateForecast(days: 30);
    final series = result.p50;
    if (result.insufficientData || series.isEmpty) {
      return KnowledgeLinkedChartData.empty;
    }

    const desired = 8;
    final indexes = <int>[];
    if (series.length <= desired) {
      indexes.addAll(List<int>.generate(series.length, (i) => i));
    } else {
      for (var i = 0; i < desired; i++) {
        final index = ((series.length - 1) * i / (desired - 1)).round();
        if (indexes.isEmpty || indexes.last != index) indexes.add(index);
      }
    }

    return KnowledgeLinkedChartData(
      values: indexes.map((i) => series[i]).toList(),
      labels: indexes.map((i) => 'D${i + 1}').toList(),
    );
  }

  Future<KnowledgeLinkedChartData> _analyticsData() async {
    final snapshot = await _analytics.build(periodDays: 30);
    final rows = snapshot.topExpenseCategories;
    if (rows.isEmpty) return KnowledgeLinkedChartData.empty;
    return KnowledgeLinkedChartData(
      values: rows.map((e) => e.value).toList(),
      labels: rows.map((e) => e.key).toList(),
    );
  }

  Future<KnowledgeLinkedChartData> _treasuryData() async {
    final transactions = await _treasury.getAllTransactions();
    if (transactions.isEmpty) return KnowledgeLinkedChartData.empty;

    final now = _now();
    final months = <DateTime>[];
    for (var offset = 6; offset >= 0; offset--) {
      months.add(DateTime(now.year, now.month - offset));
    }

    final values = <double>[];
    for (final month in months) {
      double net = 0;
      for (final tx in transactions) {
        if (tx.date.year != month.year || tx.date.month != month.month)
          continue;
        net += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      values.add(net);
    }

    return KnowledgeLinkedChartData(
      values: values,
      labels: months
          .map((m) =>
              '${m.month.toString().padLeft(2, '0')}.${(m.year % 100).toString().padLeft(2, '0')}')
          .toList(),
    );
  }
}
