import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';

class TreasuryForecastScreen extends StatefulWidget {
  const TreasuryForecastScreen({super.key});

  @override
  State<TreasuryForecastScreen> createState() => _TreasuryForecastScreenState();
}

class _TreasuryForecastScreenState extends State<TreasuryForecastScreen> {
  final TreasuryService _service = TreasuryService();

  List<ForecastPoint> _data = [];
  List<TransactionModel> _transactions = [];
  Map<String, double> _categoryBreakdown = {};
  bool _isLoading = true;
  bool _chartBusy = false; // только график, не весь экран

  bool _showP10P90 = true;
  bool _showConfidenceBands = true;
  bool _showTrendLine = true;
  int _forecastDays = 30;
  String _selectedChart = 'forecast';
  String _currency = 'rub';

  String get _sym => _currency == 'rub' ? '₽' : '\$';

  String _fmt(double v) {
    if (v.abs() >= 1000) return '$_sym${(v / 1000).toStringAsFixed(1)}k';
    return '$_sym${v.toStringAsFixed(0)}';
  }

  @override
  void initState() {
    super.initState();
    _loadData(full: true);
  }

  Future<void> _loadData({bool full = false}) async {
    if (full) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _chartBusy = true);
    }

    final forecast = await _service.generateForecast(days: _forecastDays);
    final txs = await _service.getAllTransactions();

    final breakdown = <String, double>{};
    for (final tx in txs) {
      final cat = tx.category ?? 'uncategorized'.w;
      breakdown[cat] = (breakdown[cat] ?? 0) +
          (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    final data = <ForecastPoint>[];
    final now = DateTime.now();
    double runningBalance = 0;

    for (final tx in txs.where(
        (t) => t.date.isBefore(now.subtract(const Duration(days: 30))))) {
      runningBalance +=
          tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    for (int i = 30; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayTxs = txs.where((t) =>
          t.date.year == day.year &&
          t.date.month == day.month &&
          t.date.day == day.day);
      double dayNet = 0;
      for (final tx in dayTxs) {
        dayNet +=
            tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      runningBalance += dayNet;
      data.add(ForecastPoint(
        day: 30 - i,
        p10: runningBalance * 0.97,
        p50: runningBalance,
        p90: runningBalance * 1.03,
        actual: runningBalance,
        isForecast: false,
      ));
    }

    final p10 = forecast['p10'] ?? [];
    final p50 = forecast['p50'] ?? [];
    final p90 = forecast['p90'] ?? [];

    for (int i = 0; i < p50.length; i++) {
      data.add(ForecastPoint(
        day: 31 + i,
        p10: p10.isNotEmpty ? p10[i] : p50[i] * 0.9,
        p50: p50[i],
        p90: p90.isNotEmpty ? p90[i] : p50[i] * 1.1,
        isForecast: true,
      ));
    }

    if (!mounted) return;
    setState(() {
      _data = data;
      _transactions = txs;
      _categoryBreakdown = breakdown;
      _isLoading = false;
      _chartBusy = false;
    });
  }

  void _changePeriod(int days) {
    if (_forecastDays == days) return;
    setState(() => _forecastDays = days);
    _loadData(full: false); // без полноэкранного лоадера
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accentOrange.withOpacity(0.5)),
        ),
      );
    }

    final forecast = _data.where((d) => d.isForecast).toList();
    final last = forecast.isNotEmpty ? forecast.last : null;
    final first = forecast.isNotEmpty ? forecast.first : null;
    final growth = (last != null && first != null && first.p50 != 0)
        ? ((last.p50 - first.p50) / first.p50 * 100)
        : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text('wesi_forecast_title'.w),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(full: false),
          ),
          const SizedBox(width: 120),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: _stats(last, growth)),
              _currencyToggle(),
            ],
          ),
          const SizedBox(height: 16),
          _periodChips(),
          const SizedBox(height: 12),
          // График: плавная смена без сброса всего экрана
          AnimatedOpacity(
            opacity: _chartBusy ? 0.45 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: _forecastChart(),
          ),
          const SizedBox(height: 16),
          _controls(),
          const SizedBox(height: 24),
          if (_categoryBreakdown.isNotEmpty) _breakdown(),
          const SizedBox(height: 24),
          _anomalies(),
        ],
      ),
    );
  }

  Widget _currencyToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _curBtn('rub', '₽'),
        _curBtn('usd', '\$'),
      ],
    );
  }

  Widget _curBtn(String code, String label) {
    final sel = _currency == code;
    return GestureDetector(
      onTap: () => setState(() => _currency = code),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? AppTheme.accentOrange.withOpacity(0.2)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel
                  ? AppTheme.accentOrange.withOpacity(0.5)
                  : AppTheme.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? AppTheme.accentOrange : AppTheme.textMuted,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _stats(ForecastPoint? last, double growth) {
    return Row(
      children: [
        _stat(
          'P50',
          last != null ? _fmt(last.p50) : '—',
          AppTheme.accentOrange,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P50 — медианный сценарий (50% вероятность)'
                : 'P50 — median scenario (50% probability)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        _stat(
          'P10',
          last != null ? _fmt(last.p10) : '—',
          AppTheme.accentRed,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P10 — пессимистичный сценарий (10% хуже)'
                : 'P10 — worst-case (10th percentile)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        _stat(
          'P90',
          last != null ? _fmt(last.p90) : '—',
          AppTheme.accentGreen,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P90 — оптимистичный сценарий (90% лучше)'
                : 'P90 — best-case (90th percentile)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color, Widget tip) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 4),
                tip,
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _periodChips() {
    return Wrap(
      spacing: 6,
      children: [7, 14, 30, 60, 90].map((d) {
        final sel = _forecastDays == d;
        return GestureDetector(
          onTap: () => _changePeriod(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.accentOrange.withOpacity(0.2)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: sel
                      ? AppTheme.accentOrange.withOpacity(0.5)
                      : AppTheme.glassBorder),
            ),
            child: Text(
              '$d дн.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                color:
                    sel ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _forecastChart() {
    if (_data.isEmpty) return const SizedBox(height: 300);

    final history = _data.where((d) => !d.isForecast).toList();
    final forecast = _data.where((d) => d.isForecast).toList();
    final minY =
        _data.map((d) => d.p10).reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY =
        _data.map((d) => d.p90).reduce((a, b) => a > b ? a : b) * 1.05;

    return Container(
      height: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (v, _) => Text(_fmt(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (_data.length / 6).clamp(1, 30).toDouble(),
                getTitlesWidget: (v, _) {
                  final i = v.toInt().clamp(0, _data.length - 1);
                  final day = DateTime.now().subtract(
                      Duration(days: 30 - _data[i].day.clamp(0, 30)));
                  // Для прогноза — дата вперёд
                  final d = _data[i].isForecast
                      ? DateTime.now()
                          .add(Duration(days: _data[i].day - 30))
                      : day;
                  return Text(
                    '${d.day}.${d.month}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 9),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (_data.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            if (_showP10P90 && _showConfidenceBands) ...[
              LineChartBarData(
                spots: forecast
                    .map((d) => FlSpot(d.day.toDouble(), d.p90))
                    .toList(),
                isCurved: true,
                color: Colors.transparent,
                barWidth: 0,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.accentOrange.withOpacity(0.08),
                ),
              ),
              if (_showTrendLine)
                LineChartBarData(
                  spots: forecast
                      .map((d) => FlSpot(d.day.toDouble(), d.p90))
                      .toList(),
                  isCurved: true,
                  color: AppTheme.accentOrange.withOpacity(0.3),
                  barWidth: 1.2,
                  dashArray: [4, 4],
                  dotData: const FlDotData(show: false),
                ),
              LineChartBarData(
                spots: forecast
                    .map((d) => FlSpot(d.day.toDouble(), d.p10))
                    .toList(),
                isCurved: true,
                color: AppTheme.accentOrange.withOpacity(0.3),
                barWidth: 1.2,
                dashArray: [4, 4],
                dotData: const FlDotData(show: false),
              ),
            ],
            LineChartBarData(
              spots: forecast
                  .map((d) => FlSpot(d.day.toDouble(), d.p50))
                  .toList(),
              isCurved: true,
              color: AppTheme.accentOrange,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: history
                  .map((d) =>
                      FlSpot(d.day.toDouble(), d.actual ?? d.p50))
                  .toList(),
              isCurved: true,
              color: Colors.white.withOpacity(0.75),
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      ),
    );
  }

  Widget _controls() {
    return Wrap(
      spacing: 8,
      children: [
        _toggle('Диапазон P10–P90', _showP10P90,
            (v) => setState(() => _showP10P90 = v)),
        _toggle('Полосы доверия', _showConfidenceBands,
            (v) => setState(() => _showConfidenceBands = v)),
        _toggle('Линия тренда', _showTrendLine,
            (v) => setState(() => _showTrendLine = v)),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? AppTheme.accentOrange.withOpacity(0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value
                  ? AppTheme.accentOrange.withOpacity(0.4)
                  : AppTheme.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: value ? AppTheme.accentOrange : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _breakdown() {
    final sorted = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('category_breakdown'.w,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        ...sorted.take(5).map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppTheme.textSecondary))),
                  Text(_fmt(e.value.abs()),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: e.value >= 0
                              ? AppTheme.accentGreen
                              : AppTheme.accentRed)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _anomalies() {
    final anomalies = _transactions.where((t) => t.isAnomaly).toList();
    if (anomalies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WesiLocale.isRussian
              ? 'Аномалии (${anomalies.length})'
              : 'Anomalies (${anomalies.length})',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentRed),
        ),
        const SizedBox(height: 8),
        ...anomalies.map((a) => Text(
              '• ${a.title}: ${_fmt(a.amount)}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            )),
      ],
    );
  }
}

class ForecastPoint {
  final int day;
  final double p10;
  final double p50;
  final double p90;
  final double? actual;
  final bool isForecast;

  ForecastPoint({
    required this.day,
    required this.p10,
    required this.p50,
    required this.p90,
    this.actual,
    required this.isForecast,
  });
}
