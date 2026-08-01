import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../tasks/services/task_service.dart';
import '../treasury/services/treasury_service.dart';
import 'services/analytics_service.dart';

/// Аналитика — сводная картина бизнеса: деньги, работа, тенденции.
///
/// Отличие от Treasury: там «что произошло», здесь «что это значит».
/// Поэтому все числа даны в сравнении с предыдущим периодом такой же длины —
/// голая сумма за месяц не говорит, хорошо это или плохо.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final AnalyticsService _service = AnalyticsService();

  static const List<int> _periods = [7, 30, 90, 180, 365];

  int _periodDays = 30;
  AnalyticsSnapshot? _data;
  bool _loading = true;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
    // Вкладка живёт в IndexedStack: без подписок цифры замерли бы на том,
    // что было при первом открытии приложения.
    TreasuryService.revision.addListener(_load);
    TaskService.revision.addListener(_load);
  }

  @override
  void dispose() {
    TreasuryService.revision.removeListener(_load);
    TaskService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _service.build(periodDays: _periodDays);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _setPeriod(int days) async {
    if (days == _periodDays) return;
    setState(() => _periodDays = days);
    await _load();
  }

  String _periodLabel(int days) {
    if (days < 365) return '$days ${_ru ? 'дн.' : 'd'}';
    return _ru ? '1 год' : '1 year';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _loading || d == null
            ? Center(
                child: CircularProgressIndicator(
                    color: AppTheme.accentOrange.withOpacity(0.5)))
            : ListView(
                padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 12, 16, 32),
                children: [
                  WesiTitle(_ru ? 'Аналитика' : 'Analytics'),
                  SizedBox(height: 4),
                  Text(
                    _ru
                        ? 'Сводная картина: деньги, работа, тенденции'
                        : 'The big picture: money, work, trends',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  _periodChips(),
                  const SizedBox(height: 18),
                  if (d.isEmpty)
                    _emptyState()
                  else ...[
                    _kpiGrid(d),
                    const SizedBox(height: 18),
                    _trendCard(d),
                    const SizedBox(height: 18),
                    _healthCard(d),
                    const SizedBox(height: 18),
                    _categoriesCard(d),
                    const SizedBox(height: 18),
                    _tasksCard(d),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _periodChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _periods.map((d) {
          final sel = d == _periodDays;
          return GestureDetector(
            onTap: () => _setPeriod(d),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? AppTheme.accentOrange.withOpacity(0.16)
                    : AppTheme.surface.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel
                        ? AppTheme.accentOrange.withOpacity(0.5)
                        : AppTheme.glassBorder),
              ),
              child: Text(
                _periodLabel(d),
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

  Widget _emptyState() => _card(
        child: Column(
          children: [
            Icon(Icons.insights, size: 34, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text(
              _ru ? 'Пока нечего анализировать' : 'Nothing to analyse yet',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            SizedBox(height: 6),
            Text(
              _ru
                  ? 'Добавьте операции в «Финансы» или задачи — аналитика '
                      'соберётся сама.'
                  : 'Add operations in Finance or some tasks — analytics '
                      'builds itself.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      );

  Widget _kpiGrid(AnalyticsSnapshot d) {
    final tiles = <Widget>[
      _kpiTile(_ru ? 'Доходы' : 'Income', d.income, AppTheme.accentGreen,
          money: true),
      _kpiTile(_ru ? 'Расходы' : 'Expenses', d.expense, AppTheme.accentRed,
          money: true, higherIsBetter: false),
      _kpiTile(_ru ? 'Чистый' : 'Net', d.net, AppTheme.accentOrange,
          money: true),
      _kpiTile(_ru ? 'Операций' : 'Operations', d.operations,
          const Color(0xFF38BDF8),
          money: false),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 560 ? 4 : 2;
        const gap = 12.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles.map((t) => SizedBox(width: width, child: t)).toList(),
        );
      },
    );
  }

  Widget _kpiTile(String label, Kpi kpi, Color color,
      {required bool money, bool higherIsBetter = true}) {
    final change = kpi.changeFraction;
    // «Хорошо» и «выросло» — не одно и то же: рост расходов красный,
    // рост доходов зелёный.
    final good = higherIsBetter ? kpi.isUp : !kpi.isUp;
    return _card(
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          Text(
            money
                ? CurrencyService.format(kpi.value)
                : kpi.value.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: color),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(
                kpi.delta == 0
                    ? Icons.remove
                    : (kpi.isUp ? Icons.arrow_upward : Icons.arrow_downward),
                size: 12,
                color: kpi.delta == 0
                    ? AppTheme.textMuted
                    : (good ? AppTheme.accentGreen : AppTheme.accentRed),
              ),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  change == null
                      ? (_ru ? 'нет базы' : 'no baseline')
                      : '${(change * 100).abs().toStringAsFixed(0)}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: kpi.delta == 0
                        ? AppTheme.textMuted
                        : (good ? AppTheme.accentGreen : AppTheme.accentRed),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Помесячная динамика доходов и расходов.
  Widget _trendCard(AnalyticsSnapshot d) {
    if (d.months.length < 2) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(_ru ? 'Динамика по месяцам' : 'Monthly trend'),
            SizedBox(height: 10),
            Text(
              _ru
                  ? 'Нужно хотя бы два месяца данных в выбранном периоде.'
                  : 'At least two months of data are needed for this period.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    final maxY = d.months
        .map((m) => m.income > m.expense ? m.income : m.expense)
        .reduce((a, b) => a > b ? a : b);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(_ru ? 'Динамика по месяцам' : 'Monthly trend'),
          SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: CurrencyService.display(maxY) * 1.2 + 1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                      color: AppTheme.glassBorder.withOpacity(0.5),
                      strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (v, meta) => Text(
                        _compact(v),
                        style: TextStyle(
                            fontSize: 9, color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= d.months.length) {
                          return SizedBox.shrink();
                        }
                        final m = d.months[i].month;
                        return Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            '${m.month.toString().padLeft(2, '0')}.'
                            '${m.year % 100}',
                            style: TextStyle(
                                fontSize: 9, color: AppTheme.textMuted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: AppTheme.surface.withOpacity(0.96),
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${ri == 0 ? (_ru ? 'Доход' : 'Income') : (_ru ? 'Расход' : 'Expense')}\n'
                      '${CurrencyService.format(ri == 0 ? d.months[gi].income : d.months[gi].expense)}',
                      TextStyle(
                        fontSize: 11,
                        color: ri == 0
                            ? AppTheme.accentGreen
                            : AppTheme.accentRed,
                      ),
                    ),
                  ),
                ),
                barGroups: List.generate(d.months.length, (i) {
                  final m = d.months[i];
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: CurrencyService.display(m.income),
                        color: AppTheme.accentGreen,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: CurrencyService.display(m.expense),
                        color: AppTheme.accentRed,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              _legendDot(AppTheme.accentGreen, _ru ? 'Доходы' : 'Income'),
              SizedBox(width: 18),
              _legendDot(AppTheme.accentRed, _ru ? 'Расходы' : 'Expenses'),
            ],
          ),
        ],
      ),
    );
  }

  /// Здоровье бизнеса: темп трат, средний чек, запас прочности.
  Widget _healthCard(AnalyticsSnapshot d) {
    final runway = d.runwayDays;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(_ru ? 'Здоровье' : 'Health'),
          SizedBox(height: 14),
          _statRow(
            icon: Icons.local_fire_department_outlined,
            color: AppTheme.accentRed,
            label: _ru ? 'Траты в день' : 'Burn per day',
            value: CurrencyService.format(d.burnPerDay),
          ),
          _statRow(
            icon: Icons.receipt_long_outlined,
            color: AppTheme.accentGreen,
            label: _ru ? 'Средний чек дохода' : 'Average income ticket',
            value: CurrencyService.format(d.averageIncomeTicket),
          ),
          _statRow(
            icon: runway == null ? Icons.trending_up : Icons.hourglass_bottom,
            color: runway == null
                ? AppTheme.accentGreen
                : (runway < 60 ? AppTheme.accentRed : AppTheme.accentOrange),
            label: _ru ? 'Запас прочности' : 'Runway',
            value: runway == null
                ? (_ru ? 'доходы перекрывают' : 'income covers it')
                : (_ru ? '$runway дн.' : '$runway days'),
          ),
          if (runway != null && runway < 60) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentRed.withOpacity(0.35)),
              ),
              child: Text(
                _ru
                    ? 'При нынешнем темпе денег хватит меньше чем на два '
                        'месяца. Стоит посмотреть прогноз и сценарии «Что если?».'
                    : 'At the current pace the money lasts less than two '
                        'months. Worth checking the forecast and what-if scenarios.',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.accentRed),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoriesCard(AnalyticsSnapshot d) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
              _ru ? 'Куда уходит и откуда приходит' : 'Where money moves'),
          SizedBox(height: 14),
          if (d.topExpenseCategories.isEmpty && d.topIncomeCategories.isEmpty)
            Text(
              _ru ? 'Нет операций за период' : 'No operations in this period',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          if (d.topExpenseCategories.isNotEmpty) ...[
            Text(_ru ? 'Расходы' : 'Expenses',
                style:
                    TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            SizedBox(height: 8),
            ..._bars(d.topExpenseCategories, AppTheme.accentRed),
            SizedBox(height: 14),
          ],
          if (d.topIncomeCategories.isNotEmpty) ...[
            Text(_ru ? 'Доходы' : 'Income',
                style:
                    TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            SizedBox(height: 8),
            ..._bars(d.topIncomeCategories, AppTheme.accentGreen),
          ],
        ],
      ),
    );
  }

  List<Widget> _bars(List<MapEntry<String, double>> rows, Color color) {
    final max = rows.first.value;
    return rows.map((e) {
      final share = max == 0 ? 0.0 : e.value / max;
      return Padding(
        padding: EdgeInsets.only(bottom: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Text(CurrencyService.format(e.value),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
              ],
            ),
            SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 5,
                backgroundColor: AppTheme.background,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _tasksCard(AnalyticsSnapshot d) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(_ru ? 'Продуктивность' : 'Productivity'),
          SizedBox(height: 14),
          if (d.tasksTotal == 0)
            Text(
              _ru
                  ? 'Задач пока нет — создайте их во вкладке «Задачи».'
                  : 'No tasks yet — create some in the Tasks tab.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: d.taskCompletion,
                      minHeight: 7,
                      backgroundColor: AppTheme.background,
                      valueColor:
                          AlwaysStoppedAnimation(AppTheme.accentOrange),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '${(d.taskCompletion * 100).round()}%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentOrange),
                ),
              ],
            ),
            SizedBox(height: 14),
            _statRow(
              icon: Icons.check_circle_outline,
              color: AppTheme.accentGreen,
              label: _ru ? 'Закрыто за период' : 'Closed in period',
              value: '${d.tasksDone}',
            ),
            _statRow(
              icon: Icons.warning_amber_rounded,
              color:
                  d.tasksOverdue > 0 ? AppTheme.accentRed : AppTheme.textMuted,
              label: _ru ? 'Просрочено' : 'Overdue',
              value: '${d.tasksOverdue}',
            ),
            _statRow(
              icon: Icons.list_alt,
              color: AppTheme.textMuted,
              label: _ru ? 'Всего задач' : 'Tasks in total',
              value: '${d.tasksTotal}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ],
        ),
      );

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      );

  Widget _cardTitle(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );

  String _compact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}
