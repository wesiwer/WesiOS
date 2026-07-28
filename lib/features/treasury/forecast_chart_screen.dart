import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import 'services/treasury_service.dart';
import 'services/forecast_engine.dart';
import 'models/transaction_model.dart';

class TreasuryForecastScreen extends StatefulWidget {
  const TreasuryForecastScreen({super.key});

  @override
  State<TreasuryForecastScreen> createState() => _TreasuryForecastScreenState();
}

class _TreasuryForecastScreenState extends State<TreasuryForecastScreen> {
  final TreasuryService _service = TreasuryService();

  ForecastResult _forecast = ForecastResult.empty();
  List<ForecastPoint> _data = [];
  List<TransactionModel> _anomalies = [];
  Map<String, double> _categoryBreakdown = {};
  bool _isLoading = true;
  bool _chartBusy = false; // только график, не весь экран

  // Смысл каждого переключателя разведён однозначно:
  // — P10–P90 — пунктирные границы диапазона;
  // — доверительные интервалы — заливка между ними;
  // — линия тренда — медианная (P50) линия.
  bool _showP10P90 = true;
  bool _showConfidenceBands = true;
  bool _showTrendLine = true;
  int _forecastDays = 30;
  int _historyWindowDays = 30;
  DateTimeRange? _customRange;
  String _selectedChart = 'forecast';
  String _currency = CurrencyService.current;

  /// Фон графика — сплошной цвет, каким контейнер реально рендерится
  /// (surface@0.4 поверх background). Нужен, чтобы «стереть» лишнюю заливку
  /// под P10 и получить полосу ровно между P10 и P90, а не до низа графика.
  static final Color _chartBg = Color.alphaBlend(
    AppTheme.surface.withOpacity(0.4),
    AppTheme.background,
  );

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
    // detectAnomalies() возвращает копии с выставленным isAnomaly — этот флаг
    // никогда не пишется обратно в Hive, поэтому `txs`/`tx.isAnomaly` его не
    // содержит для реально обнаруженных (не «зашитых» в демо-данных) случаев.
    // Берём список отдельно, как это уже правильно делают Treasury/Sandbox.
    final anomalies = await _service.detectAnomalies();

    final breakdown = <String, double>{};
    for (final tx in txs) {
      final cat = tx.category ?? 'uncategorized'.w;
      breakdown[cat] = (breakdown[cat] ?? 0) +
          (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    // История на графике масштабируется вместе с горизонтом прогноза —
    // 90-дневный прогноз без контекста истории тяжелее оценить на глаз.
    final historyWindowDays = _forecastDays.clamp(30, 90);

    final data = <ForecastPoint>[];
    final now = DateTime.now();
    double runningBalance = 0;

    for (final tx in txs.where((t) =>
        t.date.isBefore(now.subtract(Duration(days: historyWindowDays))))) {
      runningBalance +=
          tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    for (int i = historyWindowDays; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayTxs = txs.where((t) =>
          t.date.year == day.year &&
          t.date.month == day.month &&
          t.date.day == day.day);
      double dayNet = 0;
      for (final tx in dayTxs) {
        dayNet += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      runningBalance += dayNet;
      // История — факт, а не оценка: p10/p50/p90 совпадают с фактическим
      // балансом (раньше здесь была фиктивная полоса ±3%, вводившая в
      // заблуждение — история не имеет доверительного интервала).
      data.add(ForecastPoint(
        day: historyWindowDays - i,
        p10: runningBalance,
        p50: runningBalance,
        p90: runningBalance,
        actual: runningBalance,
        isForecast: false,
      ));
    }

    for (int i = 0; i < forecast.p50.length; i++) {
      data.add(ForecastPoint(
        day: historyWindowDays + 1 + i,
        p10: forecast.p10.isNotEmpty ? forecast.p10[i] : forecast.p50[i],
        p50: forecast.p50[i],
        p90: forecast.p90.isNotEmpty ? forecast.p90[i] : forecast.p50[i],
        isForecast: true,
      ));
    }

    if (!mounted) return;
    setState(() {
      _forecast = forecast;
      _data = data;
      _anomalies = anomalies;
      _categoryBreakdown = breakdown;
      _historyWindowDays = historyWindowDays;
      _currency = CurrencyService.current;
      _isLoading = false;
      _chartBusy = false;
    });
  }

  Future<void> _cycleCurrency() async {
    final codes = CurrencyService.codes;
    final i = codes.indexOf(_currency);
    final next = codes[(i + 1) % codes.length];
    await CurrencyService.set(next);
    setState(() => _currency = next);
  }

  void _changePeriod(int days) {
    final hadRange = _customRange != null;
    if (_forecastDays == days && !hadRange) return;
    setState(() {
      _forecastDays = days;
      _customRange = null;
    });
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

    if (_forecast.insufficientData) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text('wesi_forecast_title'.w),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.query_stats,
                    size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  'insufficient_data'.w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'insufficient_data_hint'.w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final forecastPoints = _data.where((d) => d.isForecast).toList();
    final last = forecastPoints.isNotEmpty ? forecastPoints.last : null;
    final first = forecastPoints.isNotEmpty ? forecastPoints.first : null;
    final growth = (last != null && first != null && first.p50 != 0)
        ? ((last.p50 - first.p50) / first.p50.abs() * 100)
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
              const SizedBox(width: 8),
              _currencyBadge(),
            ],
          ),
          const SizedBox(height: 8),
          _diagnostics(),
          const SizedBox(height: 12),
          _chartModeTabs(),
          const SizedBox(height: 10),
          _periodChips(),
          const SizedBox(height: 12),
          // График: плавная смена без сброса всего экрана
          AnimatedOpacity(
            opacity: _chartBusy ? 0.45 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: _chartForMode(),
          ),
          const SizedBox(height: 16),
          Text('display_options'.w,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          _controls(),
          const SizedBox(height: 24),
          if (_categoryBreakdown.isNotEmpty) _breakdown(),
          const SizedBox(height: 24),
          _anomaliesSection(),
        ],
      ),
    );
  }

  Widget _currencyBadge() {
    return GestureDetector(
      onTap: _cycleCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(
          '${CurrencyService.symbol} ${_currency.toUpperCase()}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentOrange,
          ),
        ),
      ),
    );
  }

  /// Прозрачность про то, на чём построен прогноз — сколько истории,
  /// сколько траекторий симулировано, учтена ли сезонность по дню недели.
  Widget _diagnostics() {
    final daysLabel =
        'based_on_history'.w.replaceAll('{days}', '${_forecast.historyDaysSpan}');
    final pathsLabel =
        'monte_carlo_paths'.w.replaceAll('{n}', '${_forecast.simulatedPaths}');
    final seasonLabel =
        _forecast.seasonalityApplied ? 'seasonality_on'.w : 'seasonality_off'.w;
    return Text(
      '$daysLabel · $pathsLabel · $seasonLabel',
      style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withOpacity(0.8)),
    );
  }

  Widget _stats(ForecastPoint? last, double growth) {
    return Row(
      children: [
        _stat(
          'P50',
          last != null ? CurrencyService.format(last.p50) : '—',
          AppTheme.accentOrange,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P50 — медианный сценарий (50% вероятность)'
                : 'P50 — median scenario (50% probability)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
          growth: growth,
        ),
        const SizedBox(width: 8),
        _stat(
          'P10',
          last != null ? CurrencyService.format(last.p10) : '—',
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
          last != null ? CurrencyService.format(last.p90) : '—',
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

  Widget _stat(String label, String value, Color color, Widget tip,
      {double? growth}) {
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
            if (growth != null) ...[
              const SizedBox(height: 2),
              Text(
                '${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(1)}% ${'growth_over_period'.w}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: growth >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...[7, 14, 30, 60, 90].map((d) {
          final sel = _customRange == null && _forecastDays == d;
          return _periodChip(
            label: '$d ${'days'.w}',
            selected: sel,
            onTap: () => _changePeriod(d),
          );
        }),
        // Ручной диапазон датами — вместо только фиксированных chips
        _periodChip(
          label: _customRange == null
              ? 'custom_range'.w
              : '${_fmtDate(_customRange!.start)} — ${_fmtDate(_customRange!.end)}',
          selected: _customRange != null,
          icon: Icons.calendar_month,
          onTap: _pickCustomRange,
        ),
      ],
    );
  }

  Widget _periodChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentOrange.withOpacity(0.2)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? AppTheme.accentOrange.withOpacity(0.5)
                  : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color:
                      selected ? AppTheme.accentOrange : AppTheme.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color:
                    selected ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickCustomRange() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: start,
      lastDate: start.add(const Duration(days: 730)),
      initialDateRange: _customRange ??
          DateTimeRange(
              start: start, end: start.add(Duration(days: _forecastDays))),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accentOrange,
            onPrimary: AppTheme.background,
            surface: AppTheme.surface,
            onSurface: AppTheme.textPrimary,
          ),
          scaffoldBackgroundColor: AppTheme.background,
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final days = picked.duration.inDays.clamp(1, 365);
    setState(() => _customRange = picked);
    if (days == _forecastDays) return;
    setState(() => _forecastDays = days);
    _loadData(full: false); // без полноэкранного лоадера
  }

  Widget _forecastChart() {
    if (_data.isEmpty) return const SizedBox(height: 300);

    final history = _data.where((d) => !d.isForecast).toList();
    final forecast = _data.where((d) => d.isForecast).toList();

    final allY = <double>[
      for (final d in _data) ...[d.p10, d.p50, d.p90],
    ];
    final rawMin = allY.reduce((a, b) => a < b ? a : b);
    final rawMax = allY.reduce((a, b) => a > b ? a : b);
    final pad = (rawMax - rawMin).abs() * 0.08 + 1;
    final minY = rawMin - pad;
    final maxY = rawMax + pad;

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
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
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
                  final day = DateTime.now().subtract(Duration(
                      days: _historyWindowDays -
                          _data[i].day.clamp(0, _historyWindowDays)));
                  // Для прогноза — дата вперёд
                  final d = _data[i].isForecast
                      ? DateTime.now()
                          .add(Duration(days: _data[i].day - _historyWindowDays))
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
            // Заливка П10–П90: рисуем P90 с заливкой вниз, затем «стираем»
            // цветом фона всё ниже P10 — так полоса ограничена именно
            // диапазоном P10–P90, а не тянется до низа графика.
            if (_showConfidenceBands) ...[
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
              LineChartBarData(
                spots: forecast
                    .map((d) => FlSpot(d.day.toDouble(), d.p10))
                    .toList(),
                isCurved: true,
                color: Colors.transparent,
                barWidth: 0,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: _chartBg),
              ),
            ],
            if (_showP10P90) ...[
              LineChartBarData(
                spots: forecast
                    .map((d) => FlSpot(d.day.toDouble(), d.p90))
                    .toList(),
                isCurved: true,
                color: AppTheme.accentOrange.withOpacity(0.3),
                barWidth: 1.2,
                dashArray: const [4, 4],
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: forecast
                    .map((d) => FlSpot(d.day.toDouble(), d.p10))
                    .toList(),
                isCurved: true,
                color: AppTheme.accentOrange.withOpacity(0.3),
                barWidth: 1.2,
                dashArray: const [4, 4],
                dotData: const FlDotData(show: false),
              ),
            ],
            if (_showTrendLine)
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
                  .map((d) => FlSpot(d.day.toDouble(), d.actual ?? d.p50))
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

  // ===== Режимы графика: прогноз / структура / тренд / сезонность =====

  Widget _chartModeTabs() {
    const modes = ['forecast', 'breakdown', 'trend', 'heatmap'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: modes.map((m) {
        final sel = _selectedChart == m;
        return GestureDetector(
          // Только смена содержимого графика, экран не перестраивается
          onTap: () => setState(() => _selectedChart = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              m.w,
              style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                color: sel ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _chartForMode() {
    switch (_selectedChart) {
      case 'breakdown':
        return _categoryChart();
      case 'trend':
        return _trendChart();
      case 'heatmap':
        return _seasonalityChart();
      default:
        return _forecastChart();
    }
  }

  Widget _chartFrame({required Widget child}) {
    return Container(
      height: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: child,
    );
  }

  /// Столбики по категориям: доход зелёный, расход красный.
  Widget _categoryChart() {
    if (_categoryBreakdown.isEmpty) {
      return _chartFrame(
        child: Center(
          child: Text('no_transactions'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final entries = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = entries.take(8).toList();
    final values = top.map((e) => e.value).toList();
    // Ось по фактическим данным: если все категории одного знака,
    // не растягиваем шкалу симметрично на пустую половину.
    final hi = values.reduce((a, b) => a > b ? a : b);
    final lo = values.reduce((a, b) => a < b ? a : b);
    final pad = (hi - lo).abs() * 0.15 + 1;

    return _chartFrame(
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (hi > 0 ? hi : 0) + pad,
          minY: (lo < 0 ? lo : 0) - pad,
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
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= top.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      top[i].key.length > 8
                          ? '${top[i].key.substring(0, 7)}…'
                          : top[i].key,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 9),
                    ),
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
          barGroups: [
            for (int i = 0; i < top.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: top[i].value,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color: top[i].value >= 0
                        ? AppTheme.accentGreen
                        : AppTheme.accentRed,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Дневная динамика нетто за историю — «куда двигались» деньги.
  Widget _trendChart() {
    final history = _data.where((d) => !d.isForecast).toList();
    if (history.length < 2) {
      return _chartFrame(
        child: Center(
          child: Text('no_transactions'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 1; i < history.length; i++) {
      final delta = (history[i].actual ?? history[i].p50) -
          (history[i - 1].actual ?? history[i - 1].p50);
      spots.add(FlSpot(history[i].day.toDouble(), delta));
    }

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15) + 1;

    return _chartFrame(
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
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (history.length / 6).clamp(1, 30).toDouble(),
                getTitlesWidget: (v, _) {
                  final d = DateTime.now().subtract(Duration(
                      days: _historyWindowDays -
                          v.toInt().clamp(0, _historyWindowDays)));
                  return Text('${d.day}.${d.month}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 9));
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY - pad,
          maxY: maxY + pad,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.accentOrange,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accentOrange.withOpacity(0.10),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      ),
    );
  }

  /// Сезонность по дню недели — прямой побочный продукт нового движка
  /// прогноза: показывает, какие дни недели обычно «тяжелее» или «легче».
  Widget _seasonalityChart() {
    if (!_forecast.seasonalityApplied || _forecast.weekdayFactor.isEmpty) {
      return _chartFrame(
        child: Center(
          child: Text('seasonality_off'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final labels = WesiLocale.isRussian
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final values = _forecast.weekdayFactor;
    final maxAbs =
        values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b) + 1;

    return _chartFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('weekly_activity_heatmap'.w,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAbs,
                minY: -maxAbs,
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
                      getTitlesWidget: (v, _) => Text(
                          CurrencyService.format(v),
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(labels[i],
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 10));
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (int i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i],
                          width: 22,
                          borderRadius: BorderRadius.circular(4),
                          color: values[i] >= 0
                              ? AppTheme.accentGreen
                              : AppTheme.accentRed,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Wrap(
      spacing: 8,
      children: [
        _toggle('p10_p90_range'.w, _showP10P90,
            (v) => setState(() => _showP10P90 = v)),
        _toggle('confidence_bands'.w, _showConfidenceBands,
            (v) => setState(() => _showConfidenceBands = v)),
        _toggle('trend_line'.w, _showTrendLine,
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
                  Text(CurrencyService.format(e.value.abs()),
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

  Widget _anomaliesSection() {
    if (_anomalies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WesiLocale.isRussian
              ? 'Аномалии (${_anomalies.length})'
              : 'Anomalies (${_anomalies.length})',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentRed),
        ),
        const SizedBox(height: 8),
        ..._anomalies.map((a) => Text(
              '• ${a.title}: ${CurrencyService.format(a.amount)}',
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
