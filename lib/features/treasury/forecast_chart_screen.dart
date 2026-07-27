import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import 'models/transaction_model.dart';
import 'services/treasury_service.dart';

/// Экран прогноза Treasury с графиком P10/P50/P90
/// 
/// Отображает:
/// - Исторические данные (факт)
/// - Прогноз P50 (медиана)
/// - Диапазон P10-P90 (доверительный интервал)
class TreasuryForecastScreen extends StatefulWidget {
  const TreasuryForecastScreen({super.key});

  @override
  State<TreasuryForecastScreen> createState() => _TreasuryForecastScreenState();
}

class _TreasuryForecastScreenState extends State<TreasuryForecastScreen> {
  bool _showP10P90 = true;
  int _forecastDays = 30;
  final TreasuryService _service = TreasuryService();
  List<ForecastPoint> _data = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    await _service.generateDemoData();
    final forecast = await _service.generateForecast(days: _forecastDays);
    final txs = await _service.getAllTransactions();

    // Build history + forecast points
    final data = <ForecastPoint>[];
    final now = DateTime.now();

    // History: last 30 days
    final historyTxs = txs.where((t) => t.date.isAfter(now.subtract(const Duration(days: 30)))).toList();
    final dailyBalance = <DateTime, double>{};
    double runningBalance = 0;

    for (final tx in txs.where((t) => t.date.isBefore(now.subtract(const Duration(days: 30))))) {
      runningBalance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    for (int i = 30; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayTxs = historyTxs.where((t) =>
        t.date.year == day.year && t.date.month == day.month && t.date.day == day.day
      );
      double dayNet = 0;
      for (final tx in dayTxs) {
        dayNet += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      runningBalance += dayNet;
      dailyBalance[day] = runningBalance;
    }

    final sortedDays = dailyBalance.keys.toList()..sort();
    int dayIndex = 0;
    for (final day in sortedDays) {
      data.add(ForecastPoint(
        day: dayIndex++,
        p10: dailyBalance[day]! * 0.98,
        p50: dailyBalance[day]!,
        p90: dailyBalance[day]! * 1.02,
        actual: dailyBalance[day],
        isForecast: false,
      ));
    }

    // Forecast
    final p10 = forecast['p10'] ?? [];
    final p50 = forecast['p50'] ?? [];
    final p90 = forecast['p90'] ?? [];

    for (int i = 0; i < p50.length; i++) {
      data.add(ForecastPoint(
        day: dayIndex + i,
        p10: p10[i],
        p50: p50[i],
        p90: p90[i],
        isForecast: true,
      ));
    }

    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.accentOrange.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text('Generating forecast...', style: TextStyle(color: AppTheme.textMuted)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Header
          _buildHeader(),
          // Chart
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildChart(),
            ),
          ),
          // Legend & Controls
          _buildControls(),
          // Stats cards
          Expanded(
            flex: 2,
            child: _buildStatsCards(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.carbonDark.withOpacity(0.8),
            AppTheme.background,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              ),
              const SizedBox(width: 8),
              const Text(
                'Treasury Forecast',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Monte-Carlo прогноз: P10 / P50 / P90',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final history = _data.where((d) => !d.isForecast).toList();
    final forecast = _data.where((d) => d.isForecast).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5000,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '\$${(value / 1000).toStringAsFixed(0)}k',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 10,
                getTitlesWidget: (value, meta) {
                  return Text(
                    'D${value.toInt()}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: _data.length.toDouble() - 1,
          minY: _data.map((d) => d.p10).reduce((a, b) => a < b ? a : b) * 0.9,
          maxY: _data.map((d) => d.p90).reduce((a, b) => a > b ? a : b) * 1.1,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => AppTheme.carbonDark.withOpacity(0.9),
              tooltipBorder: BorderSide(color: AppTheme.accentOrange.withOpacity(0.5)),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final point = _data[spot.x.toInt()];
                  final isF = point.isForecast ? ' (прогноз)' : '';
                  return LineTooltipItem(
                    'P50: \$${point.p50.toStringAsFixed(0)}$isF',
                    const TextStyle(
                      color: AppTheme.accentOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            // P10-P90 range (filled area)
            if (_showP10P90)
              LineChartBarData(
                spots: forecast.map((d) => FlSpot(d.day.toDouble(), d.p90)).toList(),
                isCurved: true,
                curveSmoothness: 0.3,
                color: Colors.transparent,
                barWidth: 0,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.accentOrange.withOpacity(0.08),
                  cutOffY: forecast.map((d) => d.p10).reduce((a, b) => a < b ? a : b),
                  applyCutOffY: true,
                ),
              ),
            // P90 line
            if (_showP10P90)
              LineChartBarData(
                spots: forecast.map((d) => FlSpot(d.day.toDouble(), d.p90)).toList(),
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppTheme.accentOrange.withOpacity(0.3),
                barWidth: 1,
                dotData: const FlDotData(show: false),
                dashArray: [4, 4],
              ),
            // P10 line
            if (_showP10P90)
              LineChartBarData(
                spots: forecast.map((d) => FlSpot(d.day.toDouble(), d.p10)).toList(),
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppTheme.accentOrange.withOpacity(0.3),
                barWidth: 1,
                dotData: const FlDotData(show: false),
                dashArray: [4, 4],
              ),
            // P50 line (forecast)
            LineChartBarData(
              spots: forecast.map((d) => FlSpot(d.day.toDouble(), d.p50)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppTheme.accentOrange,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: AppTheme.accentOrange,
                  strokeWidth: 2,
                  strokeColor: AppTheme.background,
                ),
              ),
            ),
            // Historical actual
            LineChartBarData(
              spots: history.map((d) => FlSpot(d.day.toDouble(), d.actual ?? d.p50)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: Colors.white.withOpacity(0.8),
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: history.length.toDouble() - 1,
                color: AppTheme.textMuted.withOpacity(0.5),
                strokeWidth: 1,
                dashArray: [6, 4],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                  labelResolver: (line) => 'Сегодня',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          // P10/P90 toggle
          _buildToggleChip(
            label: 'P10-P90',
            isActive: _showP10P90,
            onTap: () => setState(() => _showP10P90 = !_showP10P90),
          ),
          const SizedBox(width: 12),
          // Forecast period selector
          _buildPeriodChip('30д', 30),
          const SizedBox(width: 8),
          _buildPeriodChip('60д', 60),
          const SizedBox(width: 8),
          _buildPeriodChip('90д', 90),
          const Spacer(),
          // Legend
          Row(
            children: [
              _buildLegendDot(AppTheme.accentOrange, 'P50 прогноз'),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.white.withOpacity(0.8), 'Факт'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentOrange.withOpacity(0.2) : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppTheme.accentOrange.withOpacity(0.5) : AppTheme.glassBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppTheme.accentOrange : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, int days) {
    final isSelected = _forecastDays == days;
    return GestureDetector(
      onTap: () => setState(() => _forecastDays = days),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceLight : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.textPrimary.withOpacity(0.3) : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final forecast = _data.where((d) => d.isForecast).toList();
    final last = forecast.last;
    final first = forecast.first;
    final growth = ((last.p50 - first.p50) / first.p50 * 100);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        children: [
          _buildStatCard(
            label: 'P50 через $_forecastDays дн',
            value: '\$${last.p50.toStringAsFixed(0)}',
            sub: '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
            isPositive: growth >= 0,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            label: 'P10 (нижняя граница)',
            value: '\$${last.p10.toStringAsFixed(0)}',
            sub: 'Worst case',
            isPositive: null,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            label: 'P90 (верхняя граница)',
            value: '\$${last.p90.toStringAsFixed(0)}',
            sub: 'Best case',
            isPositive: null,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String sub,
    bool? isPositive,
  }) {
    Color subColor;
    if (isPositive == null) {
      subColor = AppTheme.textMuted;
    } else if (isPositive) {
      subColor = const Color(0xFF4ADE80);
    } else {
      subColor = const Color(0xFFF87171);
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color: subColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Модель точки прогноза
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
