import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';

/// Wesi Treasury Forecast — полноценный аналитический дашборд
/// с Monte-Carlo прогнозом, множеством графиков и анимациями
class TreasuryForecastScreen extends StatefulWidget {
  const TreasuryForecastScreen({super.key});

  @override
  State<TreasuryForecastScreen> createState() => _TreasuryForecastScreenState();
}

class _TreasuryForecastScreenState extends State<TreasuryForecastScreen>
    with TickerProviderStateMixin {
  final TreasuryService _service = TreasuryService();

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Data
  List<ForecastPoint> _data = [];
  List<TransactionModel> _transactions = [];
  Map<String, double> _categoryBreakdown = {};
  bool _isLoading = true;

  // Customization
  bool _showP10P90 = true;
  bool _showConfidenceBands = true;
  bool _showTrendLine = true;
  int _forecastDays = 30;
  String _selectedChart = 'forecast'; // forecast, breakdown, trend, heatmap

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _service.generateDemoData();
    final forecast = await _service.generateForecast(days: _forecastDays);
    final txs = await _service.getAllTransactions();

    // Build category breakdown
    final breakdown = <String, double>{};
    for (final tx in txs) {
      final cat = tx.category ?? 'Other';
      breakdown[cat] = (breakdown[cat] ?? 0) + (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    // Build forecast points
    final data = <ForecastPoint>[];
    final now = DateTime.now();
    double runningBalance = 0;

    // Calculate starting balance (before history window)
    for (final tx in txs.where((t) => t.date.isBefore(now.subtract(const Duration(days: 30))))) {
      runningBalance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    // History points
    for (int i = 30; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayTxs = txs.where((t) {
        return t.date.year == day.year && t.date.month == day.month && t.date.day == day.day;
      });
      double dayNet = 0;
      for (final tx in dayTxs) {
        dayNet += tx.type == TransactionType.income ? tx.amount : -tx.amount;
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

    // Forecast points
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

    setState(() {
      _data = data;
      _transactions = txs;
      _categoryBreakdown = breakdown;
      _isLoading = false;
    });

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _refreshForecast() async {
    setState(() => _isLoading = true);
    _fadeController.reset();
    _slideController.reset();
    await _loadData();
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
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(AppTheme.accentOrange.withOpacity(0.5)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Wesi Treasury Forecast',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Running Monte-Carlo simulation...',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    backgroundColor: AppTheme.surfaceLight,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accentOrange),
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
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
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: CustomScrollView(
            slivers: [
              // Header
              SliverAppBar(
                backgroundColor: AppTheme.background.withOpacity(0.9),
                elevation: 0,
                pinned: true,
                expandedHeight: 140,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.textPrimary),
                    onPressed: _refreshForecast,
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Wesi Treasury Forecast',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.carbonDark.withOpacity(0.6),
                          AppTheme.background,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Stats Cards
                    _buildStatsCards(last, first, growth),
                    const SizedBox(height: 24),
                    // Chart Selector
                    _buildChartSelector(),
                    const SizedBox(height: 20),
                    // Main Chart
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: _buildMainChart(),
                    ),
                    const SizedBox(height: 24),
                    // Controls
                    _buildControls(),
                    const SizedBox(height: 24),
                    // Category Breakdown
                    _buildCategoryBreakdown(),
                    const SizedBox(height: 24),
                    // Anomaly List
                    _buildAnomalySection(),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards(ForecastPoint? last, ForecastPoint? first, double growth) {
    return Row(
      children: [
        _buildStatCard(
          'P50 in $_forecastDays days',
          last != null ? '\$${last.p50.toStringAsFixed(0)}' : '—',
          growth >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
          '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          'P10 (Worst)',
          last != null ? '\$${last.p10.toStringAsFixed(0)}' : '—',
          AppTheme.accentRed.withOpacity(0.8),
          'Lower bound',
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          'P90 (Best)',
          last != null ? '\$${last.p90.toStringAsFixed(0)}' : '—',
          AppTheme.accentGreen.withOpacity(0.8),
          'Upper bound',
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, String sub) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surface.withOpacity(0.6),
              AppTheme.surface.withOpacity(0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSelector() {
    final charts = [
      ('forecast', 'Forecast', Icons.show_chart),
      ('breakdown', 'Breakdown', Icons.pie_chart_outline),
      ('trend', 'Trend', Icons.trending_up),
      ('heatmap', 'Heatmap', Icons.grid_on),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: charts.map((chart) {
          final isSelected = _selectedChart == chart.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _selectedChart = chart.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            AppTheme.accentOrange.withOpacity(0.2),
                            AppTheme.accentOrange.withOpacity(0.05),
                          ],
                        )
                      : null,
                    color: isSelected ? null : AppTheme.surface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                        ? AppTheme.accentOrange.withOpacity(0.5)
                        : AppTheme.glassBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        chart.$3,
                        size: 16,
                        color: isSelected ? AppTheme.accentOrange : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        chart.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppTheme.accentOrange : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMainChart() {
    switch (_selectedChart) {
      case 'breakdown':
        return _buildBreakdownChart();
      case 'trend':
        return _buildTrendChart();
      case 'heatmap':
        return _buildHeatmap();
      default:
        return _buildForecastChart();
    }
  }

  Widget _buildForecastChart() {
    final history = _data.where((d) => !d.isForecast).toList();
    final forecast = _data.where((d) => d.isForecast).toList();

    if (_data.isEmpty) return const SizedBox.shrink();

    final minY = _data.map((d) => d.p10).reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = _data.map((d) => d.p90).reduce((a, b) => a > b ? a : b) * 1.05;

    return Container(
      key: const ValueKey('forecast'),
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder, width: 1),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 55,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '\$${(value / 1000).toStringAsFixed(0)}k',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
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
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
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
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppTheme.carbonDark.withOpacity(0.95),
              tooltipBorder: BorderSide(color: AppTheme.accentOrange.withOpacity(0.4)),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final point = _data[spot.x.toInt()];
                  final isF = point.isForecast ? ' (forecast)' : '';
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
            if (_showP10P90 && _showConfidenceBands) ...[
              _buildAreaBar(forecast, minY),
              _buildLineBar(forecast, (d) => d.p90, AppTheme.accentOrange.withOpacity(0.3), [4, 4]),
              _buildLineBar(forecast, (d) => d.p10, AppTheme.accentOrange.withOpacity(0.3), [4, 4]),
            ],
            _buildLineBar(forecast, (d) => d.p50, AppTheme.accentOrange, null,
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
            _buildLineBar(history, (d) => d.actual ?? d.p50, Colors.white.withOpacity(0.8), null),
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
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                  labelResolver: (_) => 'Today',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildLineBar(
    List<ForecastPoint> points,
    double Function(ForecastPoint) getY,
    Color color,
    List<int>? dashArray, {
    FlDotData? dotData,
  }) {
    return LineChartBarData(
      spots: points.map((d) => FlSpot(d.day.toDouble(), getY(d))).toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: dashArray != null ? 1.5 : 2.5,
      dotData: dotData ?? const FlDotData(show: false),
      dashArray: dashArray,
    );
  }

  LineChartBarData _buildAreaBar(List<ForecastPoint> forecast, double minY) {
    return LineChartBarData(
      spots: forecast.map((d) => FlSpot(d.day.toDouble(), d.p90)).toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: AppTheme.accentOrange.withOpacity(0.06),
        cutOffY: minY,
        applyCutOffY: true,
      ),
    );
  }

  Widget _buildBreakdownChart() {
    if (_categoryBreakdown.isEmpty) return const SizedBox.shrink();

    final sorted = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final total = sorted.map((e) => e.value.abs()).reduce((a, b) => a + b);

    final colors = [
      AppTheme.accentOrange,
      const Color(0xFF60A5FA),
      const Color(0xFFA78BFA),
      AppTheme.accentGreen,
      const Color(0xFFF87171),
      const Color(0xFFFCD34D),
      const Color(0xFF818CF8),
    ];

    return Container(
      key: const ValueKey('breakdown'),
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  final percent = (e.value.abs() / total * 100);
                  return PieChartSectionData(
                    color: colors[i % colors.length].withOpacity(0.8),
                    value: e.value.abs(),
                    title: '${percent.toStringAsFixed(0)}%',
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '\$${e.value.abs().toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    // Simple bar chart showing daily net
    final dailyNet = <int, double>{};
    for (final tx in _transactions) {
      final day = tx.date.day;
      dailyNet[day] = (dailyNet[day] ?? 0) + (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    final sortedDays = dailyNet.keys.toList()..sort();
    final maxVal = dailyNet.values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    return Container(
      key: const ValueKey('trend'),
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: BarChart(
        BarChartData(
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
                getTitlesWidget: (value, meta) => Text(
                  '\$${(value / 1000).toStringAsFixed(0)}k',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text(
                  'D${value.toInt() + 1}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: sortedDays.asMap().entries.map((entry) {
            final i = entry.key;
            final day = entry.value;
            final val = dailyNet[day] ?? 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color: val >= 0 ? AppTheme.accentGreen.withOpacity(0.7) : AppTheme.accentRed.withOpacity(0.7),
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          maxY: maxVal * 1.2,
          minY: -maxVal * 1.2,
        ),
      ),
    );
  }

  Widget _buildHeatmap() {
    // Weekly heatmap
    final weekData = <int, List<double>>{};
    for (int w = 0; w < 4; w++) weekData[w] = [];

    for (final tx in _transactions) {
      final week = (tx.date.day - 1) ~/ 7;
      if (week < 4) {
        weekData[week]!.add(tx.type == TransactionType.income ? tx.amount : -tx.amount);
      }
    }

    return Container(
      key: const ValueKey('heatmap'),
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Activity Heatmap',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: weekData.entries.map((entry) {
                final week = entry.key;
                final values = entry.value;
                final total = values.isEmpty ? 0 : values.reduce((a, b) => a + b);
                final intensity = values.isEmpty ? 0 : (total.abs() / 5000).clamp(0.0, 1.0);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  AppTheme.accentOrange.withOpacity(intensity * 0.8),
                                  AppTheme.accentOrange.withOpacity(intensity * 0.2),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.accentOrange.withOpacity(intensity * 0.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'W${week + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          '\$${total.abs().toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Display Options',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToggleChip('P10-P90 Range', _showP10P90, (v) => setState(() => _showP10P90 = v)),
              _buildToggleChip('Confidence Bands', _showConfidenceBands, (v) => setState(() => _showConfidenceBands = v)),
              _buildToggleChip('Trend Line', _showTrendLine, (v) => setState(() => _showTrendLine = v)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Forecast Period',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [7, 14, 30, 60, 90].map((days) {
              final isSelected = _forecastDays == days;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _forecastDays = days;
                        _isLoading = true;
                      });
                      _loadData();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.accentOrange.withOpacity(0.15) : AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                            ? AppTheme.accentOrange.withOpacity(0.5)
                            : AppTheme.glassBorder,
                        ),
                      ),
                      child: Text(
                        '$days days',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppTheme.accentOrange : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, bool value, ValueChanged<bool> onChanged) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: value ? AppTheme.accentOrange.withOpacity(0.15) : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value ? AppTheme.accentOrange.withOpacity(0.4) : AppTheme.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? AppTheme.accentOrange : Colors.transparent,
                  border: Border.all(
                    color: value ? AppTheme.accentOrange : AppTheme.textMuted,
                    width: 2,
                  ),
                ),
                child: value
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: value ? AppTheme.accentOrange : AppTheme.textSecondary,
                  fontWeight: value ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    if (_categoryBreakdown.isEmpty) return const SizedBox.shrink();

    final sorted = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category Breakdown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...sorted.take(5).map((entry) {
          final isPositive = entry.value >= 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${isPositive ? '+' : ''}\$${entry.value.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isPositive ? AppTheme.accentGreen : AppTheme.accentRed,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAnomalySection() {
    final anomalies = _transactions.where((t) => t.isAnomaly).toList();
    if (anomalies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber, color: AppTheme.accentRed.withOpacity(0.8), size: 18),
            const SizedBox(width: 8),
            Text(
              'Detected Anomalies (${anomalies.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentRed.withOpacity(0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...anomalies.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentRed.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentRed.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.accentRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Z-Score: ${a.zScore?.toStringAsFixed(2)} | \$${a.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
