import 'dart:math';

import '../models/transaction_model.dart';
import 'forecast_engine.dart';

class HorizonBehaviorMonitor {
  HorizonBehaviorMonitor._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<ForecastActionPrompt> analyze({
    required List<TransactionModel> transactions,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final history = transactions.where((tx) => !_day(tx.date).isAfter(today)).toList();
    if (history.length < 12) return const [];

    var first = today;
    for (final tx in history) {
      final d = _day(tx.date);
      if (d.isBefore(first)) first = d;
    }
    final span = min(180, today.difference(first).inDays + 1);
    final start = today.subtract(Duration(days: span - 1));
    final income = List<double>.filled(span, 0);
    final expense = List<double>.filled(span, 0);
    for (final tx in history) {
      final offset = _day(tx.date).difference(start).inDays;
      if (offset < 0 || offset >= span) continue;
      if (tx.type == TransactionType.income) {
        income[offset] += tx.amount;
      } else {
        expense[offset] += tx.amount;
      }
    }

    final prompts = <ForecastActionPrompt>[];
    if (span >= 42) {
      final recentIncome = income.sublist(span - 14);
      final priorIncome = income.sublist(max(0, span - 70), span - 14);
      final recentExpense = expense.sublist(span - 14);
      final priorExpense = expense.sublist(max(0, span - 70), span - 14);

      final incomeShift = _standardizedMeanShift(priorIncome, recentIncome);
      final expenseShift = _standardizedMeanShift(priorExpense, recentExpense);
      final incomeOccurrencePrior = _occurrenceRate(priorIncome);
      final incomeOccurrenceRecent = _occurrenceRate(recentIncome);

      if (incomeShift <= -1.25 && _persistentCusumDrop(income, lookback: 14)) {
        prompts.add(ForecastActionPrompt(
          code: 'structural-income-downshift',
          severity: incomeShift <= -2.0
              ? ForecastPromptSeverity.critical
              : ForecastPromptSeverity.warning,
          textRu:
              'Похоже на структурный сдвиг входящих, а не случайную плохую неделю: недавний уровень устойчиво ниже исторического baseline.',
          textEn:
              'Incoming cash shows a likely structural downshift rather than one bad week: the recent level is persistently below baseline.',
        ));
      } else if (incomeShift >= 1.75 && _persistentCusumRise(income, lookback: 14)) {
        prompts.add(const ForecastActionPrompt(
          code: 'structural-income-upshift',
          severity: ForecastPromptSeverity.info,
          textRu:
              'Входящие устойчиво ускорились. Horizon учитывает рост как режим, но не экстраполирует его бесконечно.',
          textEn:
              'Incoming cash has persistently accelerated. Horizon treats it as a regime, but does not extrapolate it forever.',
        ));
      }

      if (expenseShift >= 1.50 && _persistentCusumRise(expense, lookback: 14)) {
        prompts.add(ForecastActionPrompt(
          code: 'structural-expense-upshift',
          severity: expenseShift >= 2.25
              ? ForecastPromptSeverity.critical
              : ForecastPromptSeverity.warning,
          textRu:
              'Расходы перешли на устойчиво более высокий уровень относительно предыдущего baseline.',
          textEn:
              'Spending has shifted to a persistently higher level versus the previous baseline.',
        ));
      }

      if (incomeOccurrencePrior >= 0.10 &&
          incomeOccurrenceRecent < incomeOccurrencePrior * 0.55) {
        prompts.add(const ForecastActionPrompt(
          code: 'incoming-frequency-break',
          severity: ForecastPromptSeverity.warning,
          textRu:
              'Ломается частота входящих: дни с поступлениями стали более чем на 45% реже обычного.',
          textEn:
              'Incoming frequency is breaking down: cash-in days are more than 45% less frequent than usual.',
        ));
      }
    }

    final historicalExpenses = history
        .where((t) => t.type == TransactionType.expense)
        .map((e) => e.amount)
        .where((e) => e > 0)
        .toList();
    if (historicalExpenses.length >= 12) {
      final sorted = [...historicalExpenses]..sort();
      final median = _median(sorted);
      final deviations = historicalExpenses.map((e) => (e - median).abs()).toList()..sort();
      final mad = _median(deviations);
      final recentCutoff = today.subtract(const Duration(days: 30));
      final recentAnomalies = history.where((tx) {
        if (tx.type != TransactionType.expense || !tx.date.isAfter(recentCutoff)) {
          return false;
        }
        if (mad <= 1e-9) return tx.amount > median * 2.5 && tx.amount > 0;
        final robustZ = 0.6745 * (tx.amount - median) / mad;
        return robustZ > 3.5;
      }).toList();
      if (recentAnomalies.length >= 2) {
        final total = recentAnomalies.fold<double>(0, (a, b) => a + b.amount);
        prompts.add(ForecastActionPrompt(
          code: 'clustered-expense-anomalies',
          severity: ForecastPromptSeverity.warning,
          textRu:
              'За 30 дней произошло ${recentAnomalies.length} аномально крупных расходов на ${total.toStringAsFixed(0)} ₽ суммарно. Это уже серия, а не одиночный выброс.',
          textEn:
              '${recentAnomalies.length} unusually large expenses occurred in 30 days (${total.toStringAsFixed(0)} total). This is a cluster, not one outlier.',
          amount: total,
        ));
      }
    }

    final unique = <String, ForecastActionPrompt>{};
    for (final prompt in prompts) {
      unique[prompt.code] = prompt;
    }
    return unique.values.toList();
  }

  static double _occurrenceRate(List<double> values) => values.isEmpty
      ? 0
      : values.where((v) => v > 0).length / values.length;

  static double _mean(List<double> values) => values.isEmpty
      ? 0
      : values.fold<double>(0, (a, b) => a + b) / values.length;

  static double _std(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _mean(values);
    final variance = values.fold<double>(0, (sum, value) {
          final d = value - mean;
          return sum + d * d;
        }) /
        (values.length - 1);
    return sqrt(max(0, variance));
  }

  static double _standardizedMeanShift(
    List<double> baseline,
    List<double> recent,
  ) {
    if (baseline.isEmpty || recent.isEmpty) return 0;
    final scale = max(1.0, _std(baseline));
    return (_mean(recent) - _mean(baseline)) / scale;
  }

  static bool _persistentCusumDrop(List<double> values, {required int lookback}) {
    if (values.length < lookback + 14) return false;
    final baseline = values.sublist(0, values.length - lookback);
    final recent = values.sublist(values.length - lookback);
    final mean = _mean(baseline);
    final scale = max(1.0, _std(baseline));
    var cusum = 0.0;
    var hits = 0;
    for (final value in recent) {
      cusum = min(0.0, cusum + (value - mean) / scale + 0.20);
      if (cusum <= -1.5) hits++;
    }
    return hits >= max(3, lookback ~/ 4);
  }

  static bool _persistentCusumRise(List<double> values, {required int lookback}) {
    if (values.length < lookback + 14) return false;
    final baseline = values.sublist(0, values.length - lookback);
    final recent = values.sublist(values.length - lookback);
    final mean = _mean(baseline);
    final scale = max(1.0, _std(baseline));
    var cusum = 0.0;
    var hits = 0;
    for (final value in recent) {
      cusum = max(0.0, cusum + (value - mean) / scale - 0.20);
      if (cusum >= 1.5) hits++;
    }
    return hits >= max(3, lookback ~/ 4);
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
