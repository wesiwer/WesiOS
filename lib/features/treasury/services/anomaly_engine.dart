import 'dart:math';
import '../models/transaction_model.dart';

/// Общая детекция аномалий — используется TreasuryService и SandboxService,
/// а также ForecastEngine (чтобы разовые всплески не искажали волатильность
/// обычных дней).
///
/// Раньше использовался обычный z-score (среднее и стандартное отклонение),
/// который сам чувствителен к тем же выбросам, что должен ловить: один
/// гигантский разовый расход раздувает stdDev настолько, что перестаёт быть
/// аномалией по собственной же метрике («эффект маскировки»).
///
/// Modified z-score на медиане и MAD (median absolute deviation) — известная
/// устойчивая альтернатива (Iglewicz & Hoaglin, 1993), порог 3.5 — стандартная
/// рекомендация для этого метода.
class AnomalyEngine {
  static const double _threshold = 3.5;

  static List<TransactionModel> detect(List<TransactionModel> all) {
    final expenses =
        all.where((t) => t.type == TransactionType.expense).toList();
    if (expenses.length < 4) return [];

    final amounts = expenses.map((e) => e.amount).toList();
    final median = _median(amounts);
    final mad = _median(amounts.map((a) => (a - median).abs()).toList());

    final anomalies = <TransactionModel>[];

    if (mad > 0) {
      for (final tx in expenses) {
        final modifiedZ = 0.6745 * (tx.amount - median) / mad;
        if (modifiedZ.abs() > _threshold) {
          anomalies.add(tx.copyWith(isAnomaly: true, zScore: modifiedZ));
        }
      }
    } else {
      // Вырожденный случай: больше половины расходов совпадают, MAD = 0.
      // Откатываемся на z-score по среднему/stdDev (выборочная дисперсия).
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      final variance = amounts
              .map((a) => (a - mean) * (a - mean))
              .reduce((a, b) => a + b) /
          (amounts.length - 1);
      final stdDev = sqrt(variance);
      if (stdDev > 0) {
        for (final tx in expenses) {
          final z = (tx.amount - mean) / stdDev;
          if (z.abs() > 2.0) {
            anomalies.add(tx.copyWith(isAnomaly: true, zScore: z));
          }
        }
      }
    }

    return anomalies;
  }

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final n = sorted.length;
    if (n == 0) return 0;
    final mid = n ~/ 2;
    return n.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
