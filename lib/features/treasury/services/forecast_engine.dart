import 'dart:math';
import '../models/transaction_model.dart';
import 'anomaly_engine.dart';
import 'recurring_engine.dart';

/// Результат прогноза с диагностикой — не просто три ряда чисел, а понятная
/// оценка того, насколько прогнозу можно доверять.
class ForecastResult {
  final List<double> p10;
  final List<double> p50;
  final List<double> p90;

  /// Текущая скорость изменения баланса (EWMA, ₽/день), без учёта сезонности
  /// по дню недели и регулярных платежей — «куда движемся прямо сейчас».
  final double trendPerDay;

  /// Стандартное отклонение дневного нетто (шум вокруг тренда).
  final double dailyVolatility;

  /// Сколько календарных дней истории использовано для оценки.
  final int historyDaysSpan;

  /// Сколько траекторий было симулировано (Monte-Carlo paths).
  final int simulatedPaths;

  /// true — данных меньше 3 транзакций, прогноз не строился.
  final bool insufficientData;

  /// true — истории хватило (≥3 недель), чтобы учитывать день недели.
  final bool seasonalityApplied;

  /// Отклонение среднего нетто от общего среднего по каждому дню недели,
  /// индекс 0=Пн..6=Вс. Пусто, если [seasonalityApplied] == false.
  final List<double> weekdayFactor;

  const ForecastResult({
    required this.p10,
    required this.p50,
    required this.p90,
    required this.trendPerDay,
    required this.dailyVolatility,
    required this.historyDaysSpan,
    required this.simulatedPaths,
    required this.insufficientData,
    required this.seasonalityApplied,
    this.weekdayFactor = const [],
  });

  factory ForecastResult.empty() => const ForecastResult(
        p10: [],
        p50: [],
        p90: [],
        trendPerDay: 0,
        dailyVolatility: 0,
        historyDaysSpan: 0,
        simulatedPaths: 0,
        insufficientData: true,
        seasonalityApplied: false,
      );

  Map<String, List<double>> toMap() => {'p10': p10, 'p50': p50, 'p90': p90};
}

/// Продвинутый движок финансового прогноза — общий для Treasury и Sandbox.
///
/// В отличие от простого случайного блуждания с аналитической (нормальной)
/// шириной доверительного интервала, это настоящий bootstrap Monte-Carlo:
///
/// - известные регулярные платежи проецируются детерминированно по датам
///   ([RecurringEngine]), а не смешиваются со стохастическим шумом;
/// - сезонность по дню недели считается отдельно от тренда и шума;
/// - тренд — экспоненциально взвешенное среднее (EWMA, полураспад 10 дней):
///   недавние дни весят больше, устойчивее к разовым всплескам, чем плоское
///   окно «последние N дней»;
/// - шум берётся эмпирическим bootstrap'ом из истории (а не из нормального
///   распределения) — сохраняет реальную форму и асимметрию расходов;
/// - обнаруженные аномалии ([AnomalyEngine]) исключаются из «фонового шума»
///   (иначе редкий скачок навсегда раздувает волатильность), но участвуют как
///   риск редкого «шока» — с исторической частотой и амплитудой;
/// - P10/P50/P90 считаются эмпирически по итогам симуляции путей, а не по
///   формуле — корректно отражают асимметрию, а не только нормальную форму.
class ForecastEngine {
  static const int defaultPaths = 1000;
  static const int _minPaths = 100;
  static const int _defaultSeed = 42;
  static const int _seasonalityMinSpanDays = 21;
  static const int _minResidualsForBootstrap = 5;
  static const double _halfLifeDays = 10.0;

  static ForecastResult generate({
    required List<TransactionModel> transactions,
    required double currentBalance,
    int days = 30,
    int paths = defaultPaths,
    int seed = _defaultSeed,
  }) {
    if (days <= 0 || transactions.length < 3) return ForecastResult.empty();

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    DateTime minDay = todayOnly;
    for (final tx in transactions) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = todayOnly.difference(minDay).inDays + 1;

    final recurringTxs = transactions
        .where((t) => t.isRecurring && t.recurringPeriod != null)
        .toList();
    final recurringIds = recurringTxs.map((t) => t.id).toSet();

    // Плотный (без пропусков) дневной ряд НЕ-регулярного нетто. Регулярные
    // платежи полностью известны наперёд, поэтому не смешиваем их со
    // случайным шумом — иначе их вклад учтётся дважды: и как тренд/шум
    // (через историю), и как детерминированная проекция ниже.
    final dense = List<double>.filled(spanDays, 0);
    for (final tx in transactions) {
      if (recurringIds.contains(tx.id)) continue;
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      final idx = day.difference(minDay).inDays;
      if (idx < 0 || idx >= spanDays) continue;
      dense[idx] += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    // Аномалии — по не-регулярным транзакциям: редкий разовый шок не должен
    // портить оценку «обычной» волатильности.
    final anomalies = AnomalyEngine.detect(
      transactions.where((t) => !recurringIds.contains(t.id)).toList(),
    );
    final anomalyDayIndex = <int>{};
    final shockMagnitudes = <double>[];
    for (final a in anomalies) {
      final day = DateTime(a.date.year, a.date.month, a.date.day);
      final idx = day.difference(minDay).inDays;
      if (idx >= 0 && idx < spanDays) anomalyDayIndex.add(idx);
      shockMagnitudes
          .add(a.type == TransactionType.income ? a.amount : -a.amount);
    }
    final shockProbabilityPerDay =
        spanDays > 0 ? (anomalies.length / spanDays).clamp(0.0, 0.5) : 0.0;

    // Сезонность по дню недели: нужно хотя бы 3 полных недели истории —
    // иначе «средний понедельник» это по сути один случайный день.
    final seasonalityApplied = spanDays >= _seasonalityMinSpanDays;
    final weekdayFactor = List<double>.filled(7, 0);
    if (seasonalityApplied) {
      final weekdaySum = List<double>.filled(7, 0);
      final weekdayCount = List<int>.filled(7, 0);
      double overallSum = 0;
      int overallCount = 0;
      for (int i = 0; i < spanDays; i++) {
        if (anomalyDayIndex.contains(i)) continue;
        final wd = minDay.add(Duration(days: i)).weekday - 1; // 0=Пн..6=Вс
        weekdaySum[wd] += dense[i];
        weekdayCount[wd]++;
        overallSum += dense[i];
        overallCount++;
      }
      final overallMean = overallCount > 0 ? overallSum / overallCount : 0.0;
      for (int wd = 0; wd < 7; wd++) {
        if (weekdayCount[wd] > 0) {
          weekdayFactor[wd] = weekdaySum[wd] / weekdayCount[wd] - overallMean;
        }
      }
    }

    // Ряд без сезонности — то, что осталось после вычета «эффекта дня недели».
    final deseasonalized = List<double>.generate(spanDays, (i) {
      final wd = minDay.add(Duration(days: i)).weekday - 1;
      return dense[i] - weekdayFactor[wd];
    });

    // Тренд — EWMA по деsezонализированному ряду: недавние дни весят больше,
    // устойчивее к разовым всплескам, чем жёсткое окно или плоское смешивание
    // «общее среднее / среднее за 14 дней».
    final decay = pow(0.5, 1 / _halfLifeDays).toDouble();
    double ewma = deseasonalized.first;
    for (int i = 1; i < spanDays; i++) {
      ewma = decay * ewma + (1 - decay) * deseasonalized[i];
    }
    final trendPerDay = ewma;

    // Пул для bootstrap: «чистый шум» вокруг ДОЛГОСРОЧНОГО среднего (не
    // текущего тренда) — амплитуда и форма разброса считаются стабильными во
    // времени, даже если сам уровень (тренд) сместился.
    double resSum = 0;
    for (int i = 0; i < spanDays; i++) {
      if (anomalyDayIndex.contains(i)) continue;
      resSum += deseasonalized[i];
    }
    final nonAnomalyCount = spanDays - anomalyDayIndex.length;
    final longRunMean = nonAnomalyCount > 0 ? resSum / nonAnomalyCount : 0.0;
    final residualPool = <double>[];
    for (int i = 0; i < spanDays; i++) {
      if (anomalyDayIndex.contains(i)) continue;
      residualPool.add(deseasonalized[i] - longRunMean);
    }

    final hasBootstrapPool = residualPool.length >= _minResidualsForBootstrap;
    final dailyVolatility = _stdDev(hasBootstrapPool ? residualPool : dense);

    final recurringByOffset = RecurringEngine.projectFutureContributions(
      recurringTxs,
      days: days,
      from: todayOnly,
    );

    // ---------- Monte-Carlo: bootstrap-шум + сезонность + тренд + шоки + регулярные ----------
    final rng = Random(seed); // фиксированный seed — стабильность между перерисовками UI
    final effectivePaths = paths < _minPaths ? _minPaths : paths;
    final balances =
        List.generate(days, (_) => List<double>.filled(effectivePaths, 0));

    for (int p = 0; p < effectivePaths; p++) {
      double balance = currentBalance;
      for (int i = 0; i < days; i++) {
        final futureDay = todayOnly.add(Duration(days: i + 1));
        final wd = futureDay.weekday - 1;
        final seasonal = seasonalityApplied ? weekdayFactor[wd] : 0.0;

        final double noise;
        if (hasBootstrapPool) {
          noise = residualPool[rng.nextInt(residualPool.length)];
        } else if (dailyVolatility > 0) {
          // Слишком мало данных для честного bootstrap — приближаем шум
          // нормальным распределением того же масштаба волатильности.
          noise = _gaussian(rng) * dailyVolatility;
        } else {
          noise = 0;
        }

        double shock = 0;
        if (shockMagnitudes.isNotEmpty &&
            rng.nextDouble() < shockProbabilityPerDay) {
          shock = shockMagnitudes[rng.nextInt(shockMagnitudes.length)];
        }

        final recurringNet = recurringByOffset[i + 1] ?? 0.0;
        balance += trendPerDay + seasonal + noise + shock + recurringNet;
        balances[i][p] = balance;
      }
    }

    final p10 = <double>[];
    final p50 = <double>[];
    final p90 = <double>[];
    for (int i = 0; i < days; i++) {
      final sorted = List<double>.of(balances[i])..sort();
      p10.add(_percentile(sorted, 0.10));
      p50.add(_percentile(sorted, 0.50));
      p90.add(_percentile(sorted, 0.90));
    }

    return ForecastResult(
      p10: p10,
      p50: p50,
      p90: p90,
      trendPerDay: trendPerDay,
      dailyVolatility: dailyVolatility,
      historyDaysSpan: spanDays,
      simulatedPaths: effectivePaths,
      insufficientData: false,
      seasonalityApplied: seasonalityApplied,
      weekdayFactor: seasonalityApplied ? weekdayFactor : const [],
    );
  }

  static double _stdDev(List<double> v) {
    if (v.length < 2) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final sumSq =
        v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (v.length - 1));
  }

  /// Линейная интерполяция по отсортированному списку (аналог numpy.percentile).
  static double _percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final pos = q * (sorted.length - 1);
    final lower = pos.floor();
    final upper = pos.ceil();
    if (lower == upper) return sorted[lower];
    final frac = pos - lower;
    return sorted[lower] + (sorted[upper] - sorted[lower]) * frac;
  }

  /// Box-Muller: стандартное нормальное число из равномерного RNG.
  static double _gaussian(Random rng) {
    final u1 = 1.0 - rng.nextDouble(); // (0,1], избегаем log(0)
    final u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
  }
}
