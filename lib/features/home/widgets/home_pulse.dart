import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../analytics/services/analytics_service.dart';
import '../../tasks/services/task_service.dart';
import '../../treasury/services/financial_advice.dart';
import '../../treasury/services/financial_health.dart';
import '../../treasury/services/treasury_service.dart';

/// «Пульс» — три числа, ради которых обычно и открывают приложение.
///
/// Считает тем же `AnalyticsService`, что и вкладка «Аналитика»: если бы
/// главная считала по-своему, два экрана однажды разошлись бы в цифрах, и
/// доверять было бы нечему.
class HomePulse extends StatefulWidget {
  const HomePulse({super.key});

  @override
  State<HomePulse> createState() => _HomePulseState();
}

class _HomePulseState extends State<HomePulse> {
  static const int _period = 30;

  AnalyticsSnapshot? _snapshot;
  FinancialHealth _health = FinancialHealth.empty;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
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
    final snapshot = await AnalyticsService().build(periodDays: _period);
    final treasury = TreasuryService();
    final txs = await treasury.getAllTransactions();
    final total = await treasury.getCurrentBalance();
    final health = FinancialHealth.compute(
      transactions: txs,
      // Деньги, которые есть сегодня: операции, датированные будущим, —
      // ещё не деньги.
      balance: TreasuryService.balanceOnDay(DateTime.now(), txs, total),
      now: DateTime.now(),
      periodDays: _period,
    );
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _health = health;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        final s = _snapshot;
        // Пока данных нет — не место для спиннера: пустая карточка на главной
        // мигала бы при каждом возврате на вкладку.
        if (s == null || s.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 560 ? 3 : 1;
            const gap = 12.0;
            final width = (c.maxWidth - gap * (columns - 1)) / columns;

            final cards = <Widget>[
              _kpiCard(
                title: _ru ? 'Доход за 30 дней' : 'Income, 30 days',
                kpi: s.income,
                positiveIsGood: true,
              ),
              _kpiCard(
                title: _ru ? 'Расход за 30 дней' : 'Spending, 30 days',
                kpi: s.expense,
                positiveIsGood: false,
              ),
              _cushionCard(),
            ];

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children:
                  cards.map((w) => SizedBox(width: width, child: w)).toList(),
            );
          },
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required Kpi kpi,
    required bool positiveIsGood,
  }) {
    final change = kpi.changeFraction;
    final grew = kpi.isUp;
    // Рост расходов — не хорошая новость, поэтому цвет зависит не от знака,
    // а от того, что этот рост означает.
    final good = positiveIsGood ? grew : !grew;
    final color = change == null
        ? AppTheme.textMuted
        : (good ? AppTheme.accentGreen : AppTheme.accentRed);

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textMuted)),
          SizedBox(height: 7),
          Text(
            CurrencyService.format(kpi.value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                change == null
                    ? Icons.remove
                    : (grew ? Icons.arrow_upward : Icons.arrow_downward),
                size: 12,
                color: color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  // Когда в прошлом периоде был ноль, процент не определён.
                  // «+∞ %» выглядит как показатель, но им не является.
                  change == null
                      ? (_ru ? 'сравнить не с чем' : 'nothing to compare')
                      : '${(change * 100).abs().toStringAsFixed(0)} % '
                          '${_ru ? 'к прошлым 30 дням' : 'vs prior 30 days'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// «На сколько хватит денег» — одним числом и без двусмысленности.
  ///
  /// Раньше здесь стояло число дней, посчитанное по нетто (насколько траты
  /// обгоняют доход), а подпись под ним показывала полные траты за день.
  /// Перемножить их и сойтись с балансом было нельзя, и карточка выглядела
  /// как ошибка. Теперь и число, и подпись говорят об одном: сколько
  /// протянешь на отложенном, если доход прекратится.
  Widget _cushionCard() {
    final h = _health;
    final advice = FinancialAdviceBuilder(ru: _ru).cushion(h);
    final days = h.cushionDays;
    final color = days == null
        ? AppTheme.textMuted
        : (days < 30
            ? AppTheme.accentRed
            : (days < h.targetDays ? AppTheme.accent : AppTheme.accentGreen));

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_ru ? 'Хватит денег на' : 'Money lasts',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 7),
          Text(
            days == null
                ? (_ru ? 'нет трат' : 'no spending')
                : (_ru ? '$days дн.' : '$days days'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 5),
          Text(
            days == null
                ? (_ru ? 'Расходов пока не было' : 'No expenses yet')
                : (_ru
                    ? 'без дохода, при тратах ${CurrencyService.format(h.spendPerDay)} в день'
                    : 'with no income, at ${CurrencyService.format(h.spendPerDay)} a day'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (advice.action.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              advice.action,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shell({required Widget child}) => Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );
}
