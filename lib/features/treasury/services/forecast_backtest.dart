import '../models/transaction_model.dart';
import 'forecast_engine.dart';

/// Один день ретро-проверки: что прогноз обещал и что вышло на самом деле.
class BacktestPoint {
  final DateTime date;

  /// Фактический баланс на конец этого дня.
  final double actual;

  final double p10;
  final double p50;
  final double p90;

  const BacktestPoint({
    required this.date,
    required this.actual,
    required this.p10,
    required this.p50,
    required this.p90,
  });

  /// Ошибка медианного сценария со знаком: >0 — прогноз занизил.
  double get error => actual - p50;

  /// Попал ли факт в коридор P10…P90.
  bool get inBand => actual >= p10 && actual <= p90;
}

/// Насколько прогноз оказался прав.
class BacktestResult {
  final List<BacktestPoint> points;

  /// День, на который «встал» прогноз (последний известный ему).
  final DateTime asOf;

  /// На сколько дней вперёд проверяли.
  final int horizonDays;

  /// Средняя абсолютная ошибка P50, в рублях.
  final double mae;

  /// Та же ошибка в процентах от факта.
  ///
  /// null, когда фактический баланс всё время слишком близок к нулю: делить
  /// на почти-ноль бессмысленно, проценты получаются любые.
  final double? mape;

  /// Доля дней, когда факт попал в коридор P10…P90 (0..1).
  ///
  /// Ориентир — 0.8: коридор строится как 10-й и 90-й процентили, то есть
  /// по построению должен накрывать примерно 80% случаев. Заметно меньше —
  /// прогноз слишком самоуверен, заметно больше — коридор бесполезно широк.
  final double coverage;

  /// Средняя ошибка СО ЗНАКОМ. Показывает систематический перекос:
  /// стабильный минус — прогноз привычно завышает баланс.
  final double bias;

  /// Проверить не удалось: мало истории или горизонт не помещается.
  final bool insufficientData;

  const BacktestResult({
    required this.points,
    required this.asOf,
    required this.horizonDays,
    required this.mae,
    required this.mape,
    required this.coverage,
    required this.bias,
    this.insufficientData = false,
  });

  factory BacktestResult.empty(DateTime asOf, int horizonDays) =>
      BacktestResult(
        points: const [],
        asOf: asOf,
        horizonDays: horizonDays,
        mae: 0,
        mape: null,
        coverage: 0,
        bias: 0,
        insufficientData: true,
      );

  /// Словесная оценка попадания в коридор — чтобы число не приходилось
  /// интерпретировать самому.
  ///
  /// Оценка НЕсимметричная, и это намеренно. Опасен только недобор: если
  /// коридор обещал накрыть 80% дней, а накрыл 40%, прогноз самоуверен и
  /// доверять ему нельзя. Перебор же сам по себе не порок — на ровных
  /// данных коридор законно накрывает все 100%, и называть это «средне»
  /// было бы неправдой. (Слишком широкий коридор виден по другому
  /// показателю — ошибке в процентах.)
  BacktestGrade get grade {
    if (insufficientData) return BacktestGrade.unknown;
    if (coverage >= 0.7) return BacktestGrade.good;
    if (coverage >= 0.5) return BacktestGrade.fair;
    return BacktestGrade.poor;
  }
}

enum BacktestGrade { unknown, poor, fair, good }

/// Ретро-проверка прогноза: отматываем на [horizonDays] назад, строим
/// прогноз по данным, известным НА ТУ ДАТУ, и сравниваем с тем, что
/// произошло на самом деле.
///
/// Смысл в том, что точность прогноза нельзя объявить — её можно только
/// показать на своих же данных. Число «коридор накрыл 78% дней» говорит о
/// доверии к прогнозу больше, чем любое описание модели.
class ForecastBacktest {
  /// Минимум истории ДО точки отсчёта, иначе проверять нечего: движку самому
  /// нужно около трёх недель, чтобы вообще что-то оценить.
  static const int minHistoryBeforeAsOf = 21;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Фактический баланс на конец дня [day].
  ///
  /// Считается от ТЕКУЩЕГО баланса назад: он уже включает всё, что
  /// произошло, поэтому достаточно вычесть операции, случившиеся позже
  /// [day]. Так не нужен начальный остаток счетов и не накапливается
  /// расхождение с цифрой, которую человек видит на экране.
  static double balanceOn(
    DateTime day,
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    final cutoff = _dateOnly(day);
    var future = 0.0;
    for (final tx in transactions) {
      if (_dateOnly(tx.date).isAfter(cutoff)) {
        future += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }
    return currentBalance - future;
  }

  static BacktestResult run({
    required List<TransactionModel> transactions,
    required double currentBalance,
    int horizonDays = 30,
    DateTime? now,
    double annualDiscountRate = 0.0,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final asOf = today.subtract(Duration(days: horizonDays));

    if (horizonDays <= 0 || transactions.length < 3) {
      return BacktestResult.empty(asOf, horizonDays);
    }

    // История ДО точки отсчёта — только по ней прогноз и имел право строиться.
    final past = transactions
        .where((t) => !_dateOnly(t.date).isAfter(asOf))
        .toList();
    if (past.length < 3) return BacktestResult.empty(asOf, horizonDays);

    var earliest = asOf;
    for (final t in past) {
      final d = _dateOnly(t.date);
      if (d.isBefore(earliest)) earliest = d;
    }
    if (asOf.difference(earliest).inDays < minHistoryBeforeAsOf) {
      return BacktestResult.empty(asOf, horizonDays);
    }

    final balanceAtAsOf = balanceOn(asOf, transactions, currentBalance);

    final forecast = ForecastEngine.generate(
      transactions: past,
      currentBalance: balanceAtAsOf,
      days: horizonDays,
      annualDiscountRate: annualDiscountRate,
      asOf: asOf,
    );
    if (forecast.insufficientData || forecast.p50.isEmpty) {
      return BacktestResult.empty(asOf, horizonDays);
    }

    final points = <BacktestPoint>[];
    final n = [forecast.p50.length, horizonDays].reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < n; i++) {
      final date = asOf.add(Duration(days: i + 1));
      points.add(BacktestPoint(
        date: date,
        actual: balanceOn(date, transactions, currentBalance),
        p10: forecast.p10[i],
        p50: forecast.p50[i],
        p90: forecast.p90[i],
      ));
    }
    if (points.isEmpty) return BacktestResult.empty(asOf, horizonDays);

    var absSum = 0.0;
    var signedSum = 0.0;
    var inBand = 0;
    var pctSum = 0.0;
    var pctCount = 0;
    // Порог, ниже которого проценты теряют смысл: 1% от типичного масштаба
    // баланса, но не меньше рубля.
    var scale = 0.0;
    for (final p in points) {
      scale += p.actual.abs();
    }
    scale /= points.length;
    final pctFloor = (scale * 0.01).clamp(1.0, double.infinity);

    for (final p in points) {
      absSum += p.error.abs();
      signedSum += p.error;
      if (p.inBand) inBand++;
      if (p.actual.abs() >= pctFloor) {
        pctSum += p.error.abs() / p.actual.abs();
        pctCount++;
      }
    }

    return BacktestResult(
      points: points,
      asOf: asOf,
      horizonDays: horizonDays,
      mae: absSum / points.length,
      mape: pctCount == 0 ? null : (pctSum / pctCount) * 100,
      coverage: inBand / points.length,
      bias: signedSum / points.length,
    );
  }
}
