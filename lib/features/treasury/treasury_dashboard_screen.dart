import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../analytics/services/analytics_service.dart';
import 'models/transaction_model.dart';
import 'services/forecast_engine.dart';
import 'services/recurring_engine.dart';
import 'services/treasury_service.dart';

/// Живой обзор Wesi Treasury на тех же данных/движках, что основной модуль.
/// Demo-цифры, chart placeholders и пустые callbacks здесь запрещены.
class TreasuryDashboardScreen extends StatefulWidget {
  const TreasuryDashboardScreen({super.key});

  @override
  State<TreasuryDashboardScreen> createState() =>
      _TreasuryDashboardScreenState();
}

class _TreasuryDashboardScreenState extends State<TreasuryDashboardScreen> {
  final TreasuryService _treasury = TreasuryService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final TextEditingController _search = TextEditingController();

  late AnalyticsSnapshot _analytics;
  ForecastResult _forecast = ForecastResult.empty();
  List<TransactionModel> _transactions = const [];
  List<TransactionModel> _anomalies = const [];
  List<TransactionModel> _recurring = const [];
  double _balance = 0;
  bool _loading = true;
  String? _error;
  Timer? _reloadDebounce;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _analytics = AnalyticsSnapshot.empty(
      now.subtract(const Duration(days: 29)),
      now,
    );
    TreasuryService.revision.addListener(_onTreasuryRevision);
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    TreasuryService.revision.removeListener(_onTreasuryRevision);
    _reloadDebounce?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onTreasuryRevision() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 120), _load);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final transactions = await _treasury.getAllTransactions();
      final balance = await _treasury.getCurrentBalance();
      final anomalies = await _treasury.detectAnomalies();
      final recurring = await _treasury.getRecurringPayments();
      final forecast = await _treasury.generateForecast(days: 30);
      final analytics = await _analyticsService.build(periodDays: 30);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = transactions;
        _balance = balance;
        _anomalies = anomalies;
        _recurring = recurring;
        _forecast = forecast;
        _analytics = analytics;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  List<TransactionModel> get _visibleTransactions {
    final query = _search.text.trim().toLowerCase();
    final source = query.isEmpty
        ? _transactions
        : _transactions.where((tx) {
            return tx.title.toLowerCase().contains(query) ||
                (tx.category ?? '').toLowerCase().contains(query) ||
                (tx.description ?? '').toLowerCase().contains(query);
          }).toList();
    return source.take(10).toList();
  }

  int get _signalCount =>
      _anomalies.length + (_forecast.riskAlertDay == null ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: CurrencyService.privacyMode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 980;
                return Row(
                  children: [
                    if (desktop) _sidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          _topBar(compact: !desktop),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(
                                  desktop ? 24 : 14,
                                  18,
                                  desktop ? 24 : 14,
                                  40,
                                ),
                                child: _body(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _sidebar() {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppTheme.carbonDark.withOpacity(.5),
        border: Border(right: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: WesiTitle('Wesi Treasury', size: 16),
            ),
          ),
          const SizedBox(height: 24),
          _navItem('Dashboard', Icons.dashboard_rounded, active: true),
          _navItem('Transactions', Icons.receipt_long_rounded,
              onTap: () => _go('/treasury/operations')),
          _navItem('Forecast', Icons.trending_up_rounded,
              onTap: () => _go('/treasury/forecast')),
          _navItem('Recurring', Icons.repeat_rounded, onTap: _showRecurring),
          _navItem('Anomalies', Icons.warning_amber_rounded,
              onTap: _showSignals),
          _navItem('Analytics', Icons.analytics_outlined,
              onTap: () => _go('/analytics')),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LIVE TREASURY',
                      style: TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8)),
                  const SizedBox(height: 5),
                  Text('${_transactions.length} operations',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData icon,
      {bool active = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active
            ? AppTheme.accentOrange.withOpacity(.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: active
                ? BorderSide(color: AppTheme.accentOrange.withOpacity(.25))
                : BorderSide.none,
          ),
          leading: Icon(icon,
              size: 19,
              color: active ? AppTheme.accentOrange : AppTheme.textMuted),
          title: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color:
                      active ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _topBar({required bool compact}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.9),
        border: Border(bottom: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) ...[
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
          ],
          if (!compact)
            Text('Treasury Overview',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
          if (!compact) const Spacer(),
          Expanded(
            flex: compact ? 1 : 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 500 : 300),
              child: TextField(
                controller: _search,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: AppTheme.textMuted),
                  hintText: 'Search transactions…',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  filled: true,
                  fillColor: AppTheme.surface.withOpacity(.28),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: AppTheme.glassBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: AppTheme.glassBorder)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh Treasury',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          Badge(
            isLabelVisible: _signalCount > 0,
            label: Text('$_signalCount'),
            child: IconButton(
              tooltip: 'Treasury signals',
              onPressed: _showSignals,
              icon: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && _transactions.isEmpty) {
      return _stateCard(
        icon: Icons.error_outline_rounded,
        title: 'Treasury data unavailable',
        detail: _error!,
        action: 'Retry',
        onAction: _load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          _inlineWarning(_error!),
          const SizedBox(height: 12),
        ],
        _metrics(),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 760) {
            return Column(children: [
              _forecastCard(),
              const SizedBox(height: 14),
              _expenseBreakdown(),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: _forecastCard()),
            const SizedBox(width: 14),
            Expanded(child: _expenseBreakdown()),
          ]);
        }),
        const SizedBox(height: 18),
        _recentTransactions(),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 760) {
            return Column(children: [
              _recurringCard(),
              const SizedBox(height: 14),
              _signalsCard(),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _recurringCard()),
            const SizedBox(width: 14),
            Expanded(child: _signalsCard()),
          ]);
        }),
      ],
    );
  }

  Widget _metrics() {
    final cards = <Widget>[
      _metricCard('Total Balance', CurrencyService.formatExact(_balance),
          '${_transactions.length} operations',
          Icons.account_balance_wallet_outlined,
          _balance >= 0 ? AppTheme.accentGreen : AppTheme.accentRed),
      _metricCard('30d Income',
          CurrencyService.formatExact(_analytics.income.value),
          _kpiDelta(_analytics.income), Icons.south_west_rounded,
          AppTheme.accentGreen),
      _metricCard('30d Expenses',
          CurrencyService.formatExact(_analytics.expense.value),
          _kpiDelta(_analytics.expense), Icons.north_east_rounded,
          AppTheme.accentRed),
      _metricCard('30d Net', CurrencyService.formatExact(_analytics.net.value),
          _kpiDelta(_analytics.net), Icons.savings_outlined,
          _analytics.net.value >= 0
              ? AppTheme.accentOrange
              : AppTheme.accentRed),
    ];
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1100 ? 4 : c.maxWidth >= 620 ? 2 : 1;
      const gap = 12.0;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children:
            cards.map((card) => SizedBox(width: width, child: card)).toList(),
      );
    });
  }

  Widget _metricCard(String label, String value, String detail, IconData icon,
      Color color) {
    return _panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(child: Text(label,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
        ]),
        const SizedBox(height: 12),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color.withOpacity(.9), fontSize: 10)),
      ]),
    );
  }

  String _kpiDelta(Kpi kpi) {
    final fraction = kpi.changeFraction;
    if (fraction == null) return 'no previous-period baseline';
    return '${fraction >= 0 ? '+' : ''}${(fraction * 100).toStringAsFixed(1)}% vs previous 30d';
  }

  Widget _forecastCard() {
    return _panel(
      height: 310,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('30-day Forecast',
            trailing: _forecast.insufficientData
                ? 'insufficient history'
                : '${_forecast.simulatedPaths} paths'),
        const SizedBox(height: 12),
        Expanded(
          child: _forecast.insufficientData || _forecast.p50.isEmpty
              ? _emptyBlock(Icons.show_chart_rounded,
                  'Add at least 3 real transactions to build a forecast.')
              : Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: AppTheme.background.withOpacity(.22),
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.all(10),
                  child: CustomPaint(
                    painter: _ForecastPainter(
                      p10: _forecast.p10,
                      p50: _forecast.p50,
                      p90: _forecast.p90,
                      lowColor: AppTheme.accentRed.withOpacity(.55),
                      midColor: AppTheme.accentOrange,
                      highColor: AppTheme.accentGreen.withOpacity(.55),
                      gridColor: AppTheme.glassBorder,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
        if (!_forecast.insufficientData && _forecast.p50.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 12, runSpacing: 5, children: [
            _legend('P10', AppTheme.accentRed),
            _legend('P50', AppTheme.accentOrange),
            _legend('P90', AppTheme.accentGreen),
            Text('End P50 ${CurrencyService.format(_forecast.p50.last)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
          ]),
        ],
      ]),
    );
  }

  Widget _expenseBreakdown() {
    final categories = _analytics.topExpenseCategories;
    final maxValue = categories.isEmpty
        ? 1.0
        : categories.map((e) => e.value).reduce(math.max);
    return _panel(
      height: 310,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('30d Expense Breakdown'),
        const SizedBox(height: 14),
        if (categories.isEmpty)
          Expanded(child: _emptyBlock(Icons.pie_chart_outline_rounded,
              'No expenses in the last 30 days.'))
        else
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = categories[i];
                final fraction = (item.value / maxValue).clamp(0.0, 1.0);
                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(item.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10.5))),
                        const SizedBox(width: 8),
                        Text(CurrencyService.format(item.value),
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                            minHeight: 6,
                            value: fraction,
                            backgroundColor: AppTheme.background,
                            color: AppTheme.accentOrange),
                      ),
                    ]);
              },
            ),
          ),
      ]),
    );
  }

  Widget _recentTransactions() {
    final rows = _visibleTransactions;
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader(
          _search.text.trim().isEmpty ? 'Recent Transactions' : 'Search Results',
          action: TextButton(
              onPressed: () => _go('/treasury/operations'),
              child: const Text('View all')),
        ),
        const SizedBox(height: 10),
        if (_loading && _transactions.isEmpty)
          const LinearProgressIndicator(minHeight: 2)
        else if (rows.isEmpty)
          _emptyBlock(Icons.receipt_long_outlined,
              _search.text.trim().isEmpty
                  ? 'No real Treasury operations yet.'
                  : 'Nothing matched this search.')
        else
          ...rows.map(_transactionTile),
      ]),
    );
  }

  Widget _transactionTile(TransactionModel tx) {
    final income = tx.type == TransactionType.income;
    final date = tx.date.toLocal();
    final dateText = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(.24),
          borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: (income ? AppTheme.accentGreen : AppTheme.accentRed)
                  .withOpacity(.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(
              income ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 16,
              color: income ? AppTheme.accentGreen : AppTheme.accentRed),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('$dateText · ${tx.category ?? 'Uncategorized'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${income ? '+' : '-'}${CurrencyService.format(tx.amount)}',
            style: TextStyle(
                color: income ? AppTheme.accentGreen : AppTheme.accentRed,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _recurringCard() {
    final rows = _recurring.take(5).toList();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Recurring Payments',
            trailing: '${_recurring.length}',
            action: _recurring.length > 5
                ? TextButton(onPressed: _showRecurring, child: const Text('All'))
                : null),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          _emptyBlock(Icons.repeat_rounded,
              'No recurring Treasury operations configured.')
        else
          ...rows.map((tx) {
            final period = tx.recurringPeriod;
            final next = period == null
                ? null
                : RecurringEngine.advance(tx.date, period).toLocal();
            final nextText = next == null
                ? 'No period'
                : 'Next ${next.day.toString().padLeft(2, '0')}.${next.month.toString().padLeft(2, '0')}.${next.year}';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.repeat_rounded,
                  color: AppTheme.accentOrange, size: 18),
              title: Text(tx.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 11)),
              subtitle: Text(nextText,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
              trailing: Text(CurrencyService.format(tx.amount),
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            );
          }),
      ]),
    );
  }

  Widget _signalsCard() {
    final signals = <(IconData, String, String, Color)>[];
    if (_forecast.riskAlertDay != null) {
      signals.add((Icons.warning_amber_rounded, 'Cash-gap risk',
          'Risk exceeds 5% around forecast day ${_forecast.riskAlertDay}.',
          AppTheme.accentRed));
    }
    if (_anomalies.isNotEmpty) {
      signals.add((Icons.radar_rounded, 'Anomalies',
          '${_anomalies.length} operation(s) deviate from normal spending.',
          Colors.orange));
    }
    if (_recurring.isNotEmpty) {
      signals.add((Icons.repeat_rounded, 'Recurring schedule',
          '${_recurring.length} recurring operation(s) are tracked automatically.',
          AppTheme.accentOrange));
    }
    if (!_forecast.insufficientData) {
      signals.add((Icons.insights_rounded, 'Forecast confidence',
          '${_forecast.historyDaysSpan} history days · ${_forecast.simulatedPaths} simulated paths${_forecast.seasonalityApplied ? ' · weekday seasonality' : ''}.',
          AppTheme.accentGreen));
    }
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Treasury Signals'),
        const SizedBox(height: 10),
        if (signals.isEmpty)
          _emptyBlock(Icons.check_circle_outline_rounded,
              'No technical Treasury risks detected from current data.')
        else
          ...signals.take(5).map((signal) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(signal.$1, size: 17, color: signal.$4),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(signal.$2,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(signal.$3,
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 9.5,
                          height: 1.35)),
                ],
              )),
            ]),
          )),
      ]),
    );
  }

  Widget _sectionHeader(String title, {String? trailing, Widget? action}) {
    return Row(children: [
      Expanded(child: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800))),
      if (trailing != null) ...[
        const SizedBox(width: 8),
        Text(trailing,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
      ],
      if (action != null) ...[const SizedBox(width: 6), action],
    ]);
  }

  Widget _panel({required Widget child,
      EdgeInsets padding = const EdgeInsets.all(16), double? height}) {
    return Container(
      width: double.infinity,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.34),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder)),
      child: child,
    );
  }

  Widget _emptyBlock(IconData icon, String text) {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppTheme.textMuted, size: 26),
        const SizedBox(height: 7),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
      ]),
    ));
  }

  Widget _stateCard({required IconData icon, required String title,
      required String detail, required String action,
      required VoidCallback onAction}) {
    return _panel(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppTheme.accentRed, size: 32),
      const SizedBox(height: 10),
      Text(title, style: TextStyle(color: AppTheme.textPrimary)),
      const SizedBox(height: 5),
      Text(detail,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
      const SizedBox(height: 10),
      FilledButton(onPressed: onAction, child: Text(action)),
    ]));
  }

  Widget _inlineWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: AppTheme.accentRed.withOpacity(.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accentRed.withOpacity(.2))),
      child: Text('Treasury refresh warning: $text',
          style: TextStyle(color: AppTheme.accentRed, fontSize: 10)),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
    ]);
  }

  void _go(String route) => Navigator.of(context).pushNamed(route);

  void _showSignals() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.background,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Treasury Signals',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_forecast.riskAlertDay != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_rounded,
                    color: AppTheme.accentRed),
                title: const Text('Cash-gap risk'),
                subtitle: Text('Forecast risk exceeds 5% around day ${_forecast.riskAlertDay}.'),
              ),
            if (_anomalies.isEmpty && _forecast.riskAlertDay == null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle_outline,
                    color: AppTheme.accentGreen),
                title: const Text('No active Treasury warnings'),
                subtitle: const Text('Current data does not trigger anomaly or cash-gap alerts.'),
              ),
            for (final tx in _anomalies.take(12))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.radar_rounded),
                title: Text(tx.title),
                subtitle: Text(tx.category ?? 'Uncategorized'),
                trailing: Text(CurrencyService.format(tx.amount)),
              ),
          ],
        )),
      )),
    );
  }

  void _showRecurring() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.background,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recurring Payments',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_recurring.isEmpty)
              const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.repeat_rounded),
                  title: Text('No recurring operations')),
            for (final tx in _recurring)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.repeat_rounded),
                title: Text(tx.title),
                subtitle: Text(tx.recurringPeriod?.name ?? 'No period'),
                trailing: Text(CurrencyService.format(tx.amount)),
              ),
          ],
        )),
      )),
    );
  }
}

class _ForecastPainter extends CustomPainter {
  final List<double> p10;
  final List<double> p50;
  final List<double> p90;
  final Color lowColor;
  final Color midColor;
  final Color highColor;
  final Color gridColor;

  const _ForecastPainter({required this.p10, required this.p50,
      required this.p90, required this.lowColor, required this.midColor,
      required this.highColor, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final all = <double>[...p10, ...p50, ...p90];
    if (all.isEmpty || size.width <= 0 || size.height <= 0) return;
    var minValue = all.reduce(math.min);
    var maxValue = all.reduce(math.max);
    if ((maxValue - minValue).abs() < .0001) {
      minValue -= 1;
      maxValue += 1;
    }
    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    Offset point(List<double> series, int index) {
      final x = series.length <= 1 ? 0.0 : size.width * index / (series.length - 1);
      final normalized = ((series[index] - minValue) / (maxValue - minValue))
          .clamp(0.0, 1.0);
      return Offset(x, size.height - size.height * normalized);
    }
    void draw(List<double> series, Color color, double width) {
      if (series.isEmpty) return;
      final first = point(series, 0);
      final path = Path()..moveTo(first.dx, first.dy);
      for (var i = 1; i < series.length; i++) {
        final p = point(series, i);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
    }
    draw(p10, lowColor, 1.4);
    draw(p90, highColor, 1.4);
    draw(p50, midColor, 2.4);
  }

  @override
  bool shouldRepaint(covariant _ForecastPainter oldDelegate) {
    return oldDelegate.p10 != p10 || oldDelegate.p50 != p50 ||
        oldDelegate.p90 != p90 || oldDelegate.lowColor != lowColor ||
        oldDelegate.midColor != midColor || oldDelegate.highColor != highColor ||
        oldDelegate.gridColor != gridColor;
  }
}
