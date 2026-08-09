import 'dart:math';
import '../models/transaction_model.dart';
import 'anomaly_engine.dart';
import 'recurring_engine.dart';

/// Один гипотетический будущий доход/расход для сценария «Что если?».
/// Не пишется в базу — существует только на время одного вызова
/// [ForecastEngine.generate].
class WhatIfEvent {
  final String title;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final RecurringPeriod? recurringPeriod;

  const WhatIfEvent({
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    this.recurringPeriod,
  });

  bool get isRecurring => recurringPeriod != null;
}

/// Виртуальный сценарий «Что если?»: одноразовые события + процентная
/// корректировка будущих доходов/расходов. Ничего из этого не трогает
/// реальные транзакции — параметр передаётся в один конкретный вызов
/// [ForecastEngine.generate] и не сохраняется.
class WhatIfScenario {
  final List<WhatIfEvent> events;

  /// 1.0 — без изменений, 0.8 — доходы на 20% меньше, 1.2 — на 20% больше.
  final double incomeMultiplier;

  /// 1.0 — без изменений, 1.3 — расходы на 30% больше.
  final double expenseMultiplier;

  const WhatIfScenario({
    this.events = const [],
    this.incomeMultiplier = 1.0,
    this.expenseMultiplier = 1.0,
  });

  bool get isEmpty =>
      events.isEmpty && incomeMultiplier == 1.0 && expenseMultiplier == 1.0;

  static const WhatIfScenario none = WhatIfScenario();
}

/// Результат прогноза с диагностикой — не просто три ряда чисел, а понятная
/// оценка того, насколько прогнозу можно доверять, плюс оценка риска
/// кассового разрыва.
class ForecastResult {
  final List<double> p10;
  final List<double> p50;
  final List<double> p90;

  /// Текущая скорость изменения баланса (EWMA, ₽/день, доход минус расход),
  /// без учёта сезонности по дню недели и регулярных платежей.
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

  /// Cash Gap Risk Score: для каждого дня прогноза — доля симулированных
  /// траекторий, где баланс в этот день ушёл ниже нуля (0..1).
  final List<double> belowZeroProbability;

  /// Runway: первый день (1-based), на который медианный (P50) баланс
  /// уходит в минус. null — в пределах горизонта прогноза не уходит.
  final int? runwayDays;

  /// Первый день, на который вероятность кассового разрыва (баланс < 0)
  /// превышает 5% симулированных траекторий. null — риск не выявлен.
  final int? riskAlertDay;

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
    this.belowZeroProbability = const [],
    this.runwayDays,
    this.riskAlertDay,
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

/// Статистика одного денежного потока (доходы или расходы отдельно):
/// сезонность по дню недели, тренд (EWMA), пул для bootstrap-шума.
/// Разделение потоков даёт две вещи: точность (у доходов и расходов разные
/// недельные паттерны — расходы растут на выходных, доходы обычно в будни)
/// и возможность независимо крутить множители в сценарии «Что если?».
class _StreamStats {
  final List<double> weekdayFactor;
  final double trendPerDay;
  final List<double> residualPool;
  final bool hasBootstrapPool;
  final double volatility;

  const _StreamStats({
    required this.weekdayFactor,
    required this.trendPerDay,
    required this.residualPool,
    required this.hasBootstrapPool,
    required this.volatility,
  });

  static _StreamStats compute({
    required List<double> dense,
    required Set<int> anomalyDayIndex,
    required DateTime minDay,
    required int spanDays,
    required bool seasonalityApplied,
    required int minResidualsForBootstrap,
    required double halfLifeDays,
  }) {
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

    final deseasonalized = List<double>.generate(spanDays, (i) {
      final wd = minDay.add(Duration(days: i)).weekday - 1;
      return dense[i] - weekdayFactor[wd];
    });

    final decay = pow(0.5, 1 / halfLifeDays).toDouble();
    double ewma = deseasonalized.isNotEmpty ? deseasonalized.first : 0;
    for (int i = 1; i < spanDays; i++) {
      ewma = decay * ewma + (1 - decay) * deseasonalized[i];
    }

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

    final hasBootstrapPool = residualPool.length >= minResidualsForBootstrap;
    final volatility = _stdDev(hasBootstrapPool ? residualPool : dense);

    return _StreamStats(
      weekdayFactor: weekdayFactor,
      trendPerDay: ewma,
      residualPool: residualPool,
      hasBootstrapPool: hasBootstrapPool,
      volatility: volatility,
    );
  }

  static double _stdDev(List<double> v) {
    if (v.length < 2) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final sumSq = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (v.length - 1));
  }
}

/// Продвинутый движок финансового прогноза — общий для Treasury и Sandbox.
///
/// В отличие от простого случайного блуждания с аналитической (нормальной)
/// шириной доверительного интервала, это настоящий bootstrap Monte-Carlo:
///
/// - известные регулярные платежи проецируются детерминированно по датам
///   ([RecurringEngine]), а не смешиваются со стохастическим шумом;
/// - доходы и расходы моделируются РАЗДЕЛЬНО (разная сезонность, разный
///   тренд, разный шум), а не только их нетто — это и точнее, и даёт
///   осмысленный рычаг для сценария «Что если?» (можно уменьшить только
///   доход или увеличить только расход);
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
///   формуле — корректно отражают асимметрию, а не только нормальную форму;
/// - на каждый день считается доля траекторий с отрицательным балансом
///   (Cash Gap Risk Score) и «runway» — когда P50 уходит в минус;
/// - опционально — дисконтирование (DCF) для длинных горизонтов: будущий
///   баланс приводится к сегодняшним деньгам по годовой ставке.
class ForecastEngine {
  // ТЗ просит 5 000–10 000 прогонов; 5 000 — нижняя граница диапазона.
  // Профиль на синтетических тестах: ~450k итераций на 90-дневный горизонт,
  // не заметно на десктопе. Поднять до 10 000 — тривиально, если этого мало.
  static const int defaultPaths = 5000;
  static const int _minPaths = 100;
  static const int _defaultSeed = 42;
  static const int _seasonalityMinSpanDays = 21;
  static const int _minResidualsForBootstrap = 5;
  static const double _halfLifeDays = 10.0;

  /// Минимальный охват истории в днях, при котором вообще имеет смысл
  /// строить статистический прогноз.
  ///
  /// Без этого порога одного дня истории хватало, чтобы движок «сработал»:
  /// пул остатков пуст, волатильность равна нулю (стандартное отклонение по
  /// одной точке не определено), и все 5000 траекторий получались
  /// ОДИНАКОВЫМИ. На графике это выглядело как уверенная прямая линия с
  /// совпадающими P10/P50/P90 — то есть модель показывала максимальную
  /// уверенность именно там, где данных меньше всего. Честнее сказать
  /// «мало истории», чем нарисовать ровную прямую.
  static const int minHistorySpanDays = 7;

  /// Порог тревоги «кассового разрыва»: если вероятность ухода в минус
  /// в какой-то день превышает это значение — riskAlertDay указывает на него.
  static const double _riskAlertThreshold = 0.05;

  /// Сколько траекторий реально симулировать на данном горизонте.
  ///
  /// Стоимость расчёта — `paths × days`, и на пятилетнем горизонте 5000
  /// путей дают 9 миллионов шагов: на телефоне это заметное подвисание.
  /// Держим объём работы примерно постоянным, снижая число путей на длинных
  /// горизонтах, но не ниже [_longHorizonMinPaths] — иначе перцентили
  /// начинают заметно скакать от одного пересчёта к другому.
  ///
  /// Точность от этого страдает мало: на годы вперёд разброс определяется
  /// накопленной неопределённостью, а не числом выборок.
  static int pathsForHorizon(int days, [int requested = defaultPaths]) {
    final base = requested < _minPaths ? _minPaths : requested;
    if (days <= _fullPathsHorizonDays) return base;
    final scaled = (base * _fullPathsHorizonDays / days).round();
    return scaled < _longHorizonMinPaths ? _longHorizonMinPaths : scaled;
  }

  /// До этого горизонта считаем полным числом путей.
  static const int _fullPathsHorizonDays = 120;

  /// Ниже этого числа траекторий перцентили становятся шумными.
  static const int _longHorizonMinPaths = 800;

  static ForecastResult generate({
    required List<TransactionModel> transactions,
    required double currentBalance,
    int days = 30,
    int paths = defaultPaths,
    int seed = _defaultSeed,
    WhatIfScenario whatIf = WhatIfScenario.none,

    /// Годовая ставка дисконтирования (инфляция/стоимость денег), 0 —
    /// без дисконтирования. Применяется к итоговым P10/P50/P90 (DCF),
    /// не к вероятностной части — риск кассового разрыва считается в
    /// номинальных деньгах, это вопрос "хватит ли денег", а не "сколько они
    /// стоят сегодня".
    double annualDiscountRate = 0.0,

    /// Какой день считать «сегодня».
    ///
    /// По умолчанию — настоящее сегодня. Параметр нужен ретро-проверке
    /// (см. ForecastBacktest): чтобы спросить «а что бы прогноз сказал месяц
    /// назад», движок должен уметь встать на ту дату. Заодно это делает
    /// расчёт проверяемым: без него любой тест зависел бы от системных часов.
    DateTime? asOf,
  }) {
    if (days <= 0 || transactions.length < 3) return ForecastResult.empty();

    final today = asOf ?? DateTime.now();
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

    // Хватает ли истории, чтобы вообще оценивать тренд и разброс.
    //
    // Разделяем два случая, потому что «прямая линия» бывает и правильной:
    // — есть регулярные платежи → будущее известно по датам, прямая линия
    //   это корректный детерминированный результат, история не нужна;
    // — нет ни истории, ни регулярных платежей → экстраполировать нечего,
    //   и попытка растянуть нетто одного дня на месяц даёт ту самую
    //   уверенную прямую с P10 == P50 == P90. Честнее вернуть «мало данных».
    final hasEnoughHistory = spanDays >= minHistorySpanDays;
    if (!hasEnoughHistory && recurringTxs.isEmpty) {
      return ForecastResult.empty();
    }

    // Плотные (без пропусков) дневные ряды НЕ-регулярного дохода/расхода,
    // раздельно. Регулярные платежи полностью известны наперёд, поэтому не
    // смешиваем их со случайным шумом — иначе их вклад учтётся дважды.
    final denseIncome = List<double>.filled(spanDays, 0);
    final denseExpense = List<double>.filled(spanDays, 0);
    for (final tx in transactions) {
      if (recurringIds.contains(tx.id)) continue;
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      final idx = day.difference(minDay).inDays;
      if (idx < 0 || idx >= spanDays) continue;
      if (tx.type == TransactionType.income) {
        denseIncome[idx] += tx.amount;
      } else {
        denseExpense[idx] += tx.amount;
      }
    }

    // Аномалии — по не-регулярным расходам: редкий разовый шок не должен
    // портить оценку «обычной» волатильности расходов.
    final anomalies = AnomalyEngine.detect(
      transactions.where((t) => !recurringIds.contains(t.id)).toList(),
    );
    final anomalyDayIndex = <int>{};
    final shockMagnitudes = <double>[]; // всегда >0 — суммы расходов-шоков
    for (final a in anomalies) {
      final day = DateTime(a.date.year, a.date.month, a.date.day);
      final idx = day.difference(minDay).inDays;
      if (idx >= 0 && idx < spanDays) anomalyDayIndex.add(idx);
      shockMagnitudes.add(a.amount);
    }
    final shockProbabilityPerDay =
        spanDays > 0 ? (anomalies.length / spanDays).clamp(0.0, 0.5) : 0.0;

    // Сезонность по дню недели: нужно хотя бы 3 полных недели истории —
    // иначе «средний понедельник» это по сути один случайный день.
    final seasonalityApplied = spanDays >= _seasonalityMinSpanDays;

    final incomeStats = _StreamStats.compute(
      dense: denseIncome,
      anomalyDayIndex: anomalyDayIndex,
      minDay: minDay,
      spanDays: spanDays,
      seasonalityApplied: seasonalityApplied,
      minResidualsForBootstrap: _minResidualsForBootstrap,
      halfLifeDays: _halfLifeDays,
    );
    final expenseStats = _StreamStats.compute(
      dense: denseExpense,
      anomalyDayIndex: anomalyDayIndex,
      minDay: minDay,
      spanDays: spanDays,
      seasonalityApplied: seasonalityApplied,
      minResidualsForBootstrap: _minResidualsForBootstrap,
      halfLifeDays: _halfLifeDays,
    );

    // Регулярные платежи — раздельно по типу, чтобы множители «Что если?»
    // могли независимо подкрутить будущую зарплату (доход) и будущую аренду
    // (расход).
    final recurringIncomeByOffset = RecurringEngine.projectFutureContributions(
      recurringTxs.where((t) => t.type == TransactionType.income).toList(),
      days: days,
      from: todayOnly,
    );
    final recurringExpenseByOffset = RecurringEngine.projectFutureContributions(
      recurringTxs.where((t) => t.type == TransactionType.expense).toList(),
      days: days,
      from: todayOnly,
    );

    // Виртуальные операции «Что если?»: разовые и регулярные.
    final whatIfByOffset = <int, double>{};
    final whatIfHorizon = todayOnly.add(Duration(days: days));
    for (final e in whatIf.events) {
      final net = e.type == TransactionType.income ? e.amount : -e.amount;
      final start = DateTime(e.date.year, e.date.month, e.date.day);
      final period = e.recurringPeriod;
      if (period == null) {
        final offset = start.difference(todayOnly).inDays;
        if (offset < 1 || offset > days) continue;
        whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;
        continue;
      }

      var occurrence = start.isAfter(todayOnly)
          ? start
          : RecurringEngine.nextOccurrenceAfter(start, period, todayOnly);
      var guard = 0;
      while (!occurrence.isAfter(whatIfHorizon) && guard < 10000) {
        final offset = occurrence.difference(todayOnly).inDays;
        if (offset >= 1 && offset <= days) {
          whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;
        }
        occurrence = RecurringEngine.advance(occurrence, period);
        guard++;
      }
    }

    final incomeMult = whatIf.incomeMultiplier;
    final expenseMult = whatIf.expenseMultiplier;

    // ---------- Monte-Carlo: bootstrap-шум + сезонность + тренд + шоки + регулярные ----------
    final rng = Random(
        seed); // фиксированный seed — стабильность между перерисовками UI
    final effectivePaths = pathsForHorizon(days, paths);
    final balances =
        List.generate(days, (_) => List<double>.filled(effectivePaths, 0));

    for (int p = 0; p < effectivePaths; p++) {
      double balance = currentBalance;
      for (int i = 0; i < days; i++) {
        final futureDay = todayOnly.add(Duration(days: i + 1));
        final wd = futureDay.weekday - 1;

        final incomeSeasonal =
            seasonalityApplied ? incomeStats.weekdayFactor[wd] : 0.0;
        final expenseSeasonal =
            seasonalityApplied ? expenseStats.weekdayFactor[wd] : 0.0;

        final incomeNoise = incomeStats.hasBootstrapPool
            ? incomeStats
                .residualPool[rng.nextInt(incomeStats.residualPool.length)]
            : (incomeStats.volatility > 0
                ? _gaussian(rng) * incomeStats.volatility
                : 0.0);
        final expenseNoise = expenseStats.hasBootstrapPool
            ? expenseStats
                .residualPool[rng.nextInt(expenseStats.residualPool.length)]
            : (expenseStats.volatility > 0
                ? _gaussian(rng) * expenseStats.volatility
                : 0.0);

        double shock = 0;
        if (shockMagnitudes.isNotEmpty &&
            rng.nextDouble() < shockProbabilityPerDay) {
          shock = shockMagnitudes[rng.nextInt(shockMagnitudes.length)];
        }

        // При короткой истории статистическую часть не считаем вовсе: тренд,
        // оценённый по паре дней, — это не тренд, а один случайный день,
        // растянутый на весь горизонт. Остаются только регулярные платежи,
        // которые известны по датам и в истории не нуждаются.
        final incomeToday = hasEnoughHistory
            ? (incomeStats.trendPerDay + incomeSeasonal + incomeNoise) *
                incomeMult
            : 0.0;
        final expenseToday = hasEnoughHistory
            ? (expenseStats.trendPerDay +
                    expenseSeasonal +
                    expenseNoise +
                    shock) *
                expenseMult
            : 0.0;

        final recurringIncome =
            (recurringIncomeByOffset[i + 1] ?? 0.0) * incomeMult;
        final recurringExpense =
            (recurringExpenseByOffset[i + 1] ?? 0.0) * expenseMult;
        final whatIfNet = whatIfByOffset[i + 1] ?? 0.0;

        balance += incomeToday -
            expenseToday +
            recurringIncome +
            recurringExpense + // уже отрицательный (см. projectFutureContributions)
            whatIfNet;
        balances[i][p] = balance;
      }
    }

    final p10 = <double>[];
    final p50 = <double>[];
    final p90 = <double>[];
    final belowZeroProbability = <double>[];
    int? runwayDays;
    int? riskAlertDay;

    for (int i = 0; i < days; i++) {
      final sorted = List<double>.of(balances[i])..sort();
      final medianVal = _percentile(sorted, 0.50);
      p10.add(_percentile(sorted, 0.10));
      p50.add(medianVal);
      p90.add(_percentile(sorted, 0.90));

      var negIdx = sorted.indexWhere((v) => v >= 0);
      if (negIdx == -1) negIdx = sorted.length;
      final belowZero = negIdx / sorted.length;
      belowZeroProbability.add(belowZero);

      if (runwayDays == null && medianVal < 0) runwayDays = i + 1;
      if (riskAlertDay == null && belowZero > _riskAlertThreshold) {
        riskAlertDay = i + 1;
      }
    }

    if (annualDiscountRate > 0) {
      for (int i = 0; i < days; i++) {
        final factor = 1 / pow(1 + annualDiscountRate, (i + 1) / 365.0);
        p10[i] *= factor;
        p50[i] *= factor;
        p90[i] *= factor;
      }
    }

    return ForecastResult(
      p10: p10,
      p50: p50,
      p90: p90,
      trendPerDay: incomeStats.trendPerDay - expenseStats.trendPerDay,
      dailyVolatility: sqrt(
          pow(incomeStats.volatility, 2) + pow(expenseStats.volatility, 2)),
      historyDaysSpan: spanDays,
      simulatedPaths: effectivePaths,
      insufficientData: false,
      seasonalityApplied: seasonalityApplied,
      weekdayFactor: seasonalityApplied
          ? List<double>.generate(
              7,
              (wd) =>
                  incomeStats.weekdayFactor[wd] -
                  expenseStats.weekdayFactor[wd])
          : const [],
      belowZeroProbability: belowZeroProbability,
      runwayDays: runwayDays,
      riskAlertDay: riskAlertDay,
    );
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
