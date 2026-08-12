import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/forecast_backtest.dart';
import '../services/forecast_engine.dart';

/// Блоки, одинаковые для основного прогноза и для песочницы.
///
/// Раньше песочница показывала только график и вердикты, а всё остальное —
/// P10/P50/P90, предупреждение о кассовом разрыве, на чём построен расчёт —
/// жило только в основном экране. Считает-то обе стороны один и тот же
/// [ForecastEngine], разной была только подача. Общий виджет убирает
/// расхождение и не даёт ему появиться заново.
class ForecastStatsRow extends StatelessWidget {
  final ForecastResult forecast;

  /// Прирост медианы за горизонт, в процентах. null — не показывать.
  final double? growthPercent;

  const ForecastStatsRow({
    super.key,
    required this.forecast,
    this.growthPercent,
  });

  @override
  Widget build(BuildContext context) {
    if (forecast.p50.isEmpty) return const SizedBox.shrink();
    final ru = WesiLocale.isRussian;
    final last = forecast.p50.length - 1;

    return Row(
      children: [
        _Stat(
          label: 'P50',
          value: CurrencyService.format(forecast.p50[last]),
          color: AppTheme.accent,
          hint: ru
              ? 'P50 — медианный сценарий (50% вероятность)'
              : 'P50 — median scenario (50% probability)',
          growth: growthPercent,
        ),
        const SizedBox(width: 8),
        _Stat(
          label: 'P10',
          value: CurrencyService.format(forecast.p10[last]),
          color: AppTheme.accentRed,
          hint: ru
              ? 'P10 — пессимистичный сценарий (10% хуже)'
              : 'P10 — worst-case (10th percentile)',
        ),
        const SizedBox(width: 8),
        _Stat(
          label: 'P90',
          value: CurrencyService.format(forecast.p90[last]),
          color: AppTheme.accentGreen,
          hint: ru
              ? 'P90 — оптимистичный сценарий (90% лучше)'
              : 'P90 — best-case (90th percentile)',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String hint;
  final double? growth;

  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    required this.hint,
    this.growth,
  });

  @override
  Widget build(BuildContext context) {
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
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 4),
                Tooltip(
                  message: hint,
                  child: Icon(Icons.info_outline,
                      size: 14, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            if (growth != null) ...[
              const SizedBox(height: 2),
              Text(
                '${growth! >= 0 ? '▲' : '▼'} '
                '${growth!.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: growth! >= 0
                      ? AppTheme.accentGreen
                      : AppTheme.accentRed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Предупреждение о кассовом разрыве.
class ForecastRiskBanner extends StatelessWidget {
  final ForecastResult forecast;

  const ForecastRiskBanner({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final alertDay = forecast.riskAlertDay;
    if (alertDay == null) return const SizedBox.shrink();
    final ru = WesiLocale.isRussian;
    final date = DateTime.now().add(Duration(days: alertDay));
    final dateLabel = '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? 'Денег может не хватить' : 'Money may run short',
                  style: TextStyle(
                      color: AppTheme.accentRed,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  ru
                      ? 'Примерно через $alertDay дн. ($dateLabel) деньги '
                          'могут закончиться. Так вышло больше чем в одном '
                          'варианте будущего из двадцати.'
                      : 'In about $alertDay days ($dateLabel) the money may '
                          'run out — that happened in more than one future '
                          'out of twenty.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// На чём построен расчёт — история, число траекторий, сезонность.
class ForecastDiagnostics extends StatelessWidget {
  final ForecastResult forecast;

  const ForecastDiagnostics({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    if (forecast.p50.isEmpty) return const SizedBox.shrink();
    final ru = WesiLocale.isRussian;
    final parts = [
      ru
          ? 'считали по ${forecast.historyDaysSpan} дн. ваших операций'
          : 'based on ${forecast.historyDaysSpan} days of your entries',
      ru
          ? 'проверено ${forecast.simulatedPaths} вариантов'
          : '${forecast.simulatedPaths} futures checked',
      forecast.seasonalityApplied
          ? (ru ? 'учли, что дни недели разные' : 'weekdays differ — accounted')
          : (ru
              ? 'дней недели пока не различаем — мало истории'
              : 'weekdays not separated yet — short history'),
    ];
    return Text(
      parts.join(' · '),
      style:
          TextStyle(fontSize: 11, color: AppTheme.textMuted.withOpacity(0.8)),
    );
  }
}

/// Карточка ретро-проверки: насколько прогноз был прав в прошлый раз.
class ForecastAccuracyCard extends StatelessWidget {
  final BacktestResult result;

  /// Пересчитать с другим горизонтом. null — переключателя не будет.
  final ValueChanged<int>? onHorizonChanged;

  /// Доступные горизонты проверки.
  static const List<int> horizons = [14, 30, 60, 90];

  const ForecastAccuracyCard({
    super.key,
    required this.result,
    this.onHorizonChanged,
  });

  Color get _gradeColor => switch (result.grade) {
        BacktestGrade.good => AppTheme.accentGreen,
        BacktestGrade.fair => AppTheme.accent,
        BacktestGrade.poor => AppTheme.accentRed,
        BacktestGrade.unknown => AppTheme.textMuted,
      };

  String _gradeLabel(bool ru) => switch (result.grade) {
        BacktestGrade.good => ru ? 'Прогноз оправдался' : 'Forecast held up',
        BacktestGrade.fair => ru ? 'Прогноз частично оправдался' : 'Partly held up',
        BacktestGrade.poor => ru ? 'Прогноз промахнулся' : 'Forecast missed',
        BacktestGrade.unknown =>
            ru ? 'Пока мало истории' : 'Not enough history',
      };

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final d = result.asOf;
    final asOfLabel = '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_toggle_off, size: 17, color: _gradeColor),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  ru ? 'А как он справлялся раньше' : 'How it did before',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _gradeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gradeColor.withOpacity(0.4)),
                ),
                child: Text(
                  _gradeLabel(ru),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _gradeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.insufficientData
                ? (ru
                    ? 'Чтобы проверить прогноз на прошлом, нужна история хотя '
                        'бы за ${ForecastBacktest.minHistoryBeforeAsOf} дней '
                        'до точки отсчёта. Пока её нет — накопится сама.'
                    : 'A backtest needs at least '
                        '${ForecastBacktest.minHistoryBeforeAsOf} days of '
                        'history before the cut-off date.')
                : (ru
                    ? 'Взяли данные на $asOfLabel, построили прогноз на '
                        '${result.horizonDays} дн. вперёд и сравнили с тем, '
                        'что произошло на самом деле.'
                    : 'Took the data as of $asOfLabel, forecast '
                        '${result.horizonDays} days ahead and compared it '
                        'with what actually happened.'),
            style: TextStyle(
                fontSize: 12, height: 1.4, color: AppTheme.textMuted),
          ),
          if (!result.insufficientData) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _metric(
                  ru ? 'Угадал' : 'Hit the range',
                  '${(result.coverage * 100).toStringAsFixed(0)}%',
                  _gradeColor,
                  ru
                      ? 'В скольких днях из ста настоящий баланс попал в тот '
                          'разброс, который прогноз обещал. Хорошо, когда '
                          'около 80.'
                      : 'How often the real balance landed inside the range '
                          'the forecast promised. About 80 is right.',
                ),
                const SizedBox(width: 8),
                _metric(
                  ru ? 'Промах' : 'Off by',
                  result.mape == null
                      ? CurrencyService.format(result.mae)
                      : '${result.mape!.toStringAsFixed(1)}%',
                  AppTheme.textPrimary,
                  ru
                      ? 'Насколько прогноз в среднем расходился с тем, что '
                          'вышло на самом деле.'
                      : 'How far the forecast was from what actually '
                          'happened, on average.',
                ),
                const SizedBox(width: 8),
                _metric(
                  ru ? 'Куда врёт' : 'Leans',
                  (result.bias >= 0 ? '+' : '−') +
                      CurrencyService.format(result.bias.abs()),
                  result.bias.abs() < result.mae * 0.3
                      ? AppTheme.textMuted
                      : AppTheme.accent,
                  ru
                      ? 'Плюс — прогноз был осторожнее, чем вышло на деле. '
                          'Минус — обещал больше денег, чем оказалось. '
                          'Около нуля — не врёт ни в ту, ни в другую сторону.'
                      : 'Plus — the forecast was more cautious than reality. '
                          'Minus — it promised more money than there was.',
                ),
              ],
            ),
          ],
          if (onHorizonChanged != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final h in horizons)
                  GestureDetector(
                    onTap: () => onHorizonChanged!(h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: h == result.horizonDays
                            ? AppTheme.accent.withOpacity(0.16)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: h == result.horizonDays
                              ? AppTheme.accent.withOpacity(0.5)
                              : AppTheme.glassBorder,
                        ),
                      ),
                      child: Text(
                        ru ? '$h дн.' : '${h}d',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: h == result.horizonDays
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: h == result.horizonDays
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color, String hint) {
    return Expanded(
      child: Tooltip(
        message: hint,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
