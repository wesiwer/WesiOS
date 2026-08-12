import 'dart:math';
import '../models/transaction_model.dart';
import 'anomaly_engine.dart';
import 'calendar_days.dart';
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

  /// Сколько в среднем остаётся за день: доход минус расход, без учёта
  /// дня недели, регулярных платежей и разовых выбросов.
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
/// сезонность по дню недели, средний дневной поток, пул для bootstrap-шума.
/// Разделение потоков даёт две вещи: точность (у доходов и расходов разные
/// недельные паттерны — расходы растут на выходных, доходы обычно в будни)
/// и возможность независимо крутить множители в сценарии «Что если?».
class _StreamStats {
  /// Длина отрезка, по которому усредняется дневной поток.
  ///
  /// Тридцать дней — это месячный цикл денег: зарплата, аренда, подписки.
  /// Более короткий отрезок снова начал бы зависеть от того, какое сегодня
  /// число.
  static const int _trendChunkDays = 30;

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
  }) {
    final weekdayFactor = List<double>.filled(7, 0);
    if (seasonalityApplied) {
      final weekdaySum = List<double>.filled(7, 0);
      final weekdayCount = List<int>.filled(7, 0);
      double overallSum = 0;
      int overallCount = 0;
      for (int i = 0; i < spanDays; i++) {
        if (anomalyDayIndex.contains(i)) continue;
        final wd = addDays(minDay, i).weekday - 1; // 0=Пн..6=Вс
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
      final wd = addDays(minDay, i).weekday - 1;
      return dense[i] - weekdayFactor[wd];
    });

    // Сколько в среднем приходит (или уходит) за день.
    //
    // Считается по месячным отрезкам, а не по отдельным дням, и вот почему.
    // Деньги живут месячным циклом: расходы идут понемногу каждый день, а
    // доход приходит редко и крупно — зарплата, аванс, оплата счёта. Оценка
    // «по последним дням с затуханием» на таком ряде показывает не средний
    // доход, а расстояние до последнего поступления: сразу после зарплаты
    // она завышена, через две недели занижена вдвое, и человек, у которого
    // доходы ровно сходятся с расходами, видит прогноз, уверенно ползущий
    // вниз. На проверке: доход и расход по 90 000 за три месяца, а движок
    // насчитывал −120 в день и сносил баланс на 5 455 за месяц.
    //
    // Отрезок в 30 дней вмещает целое число зарплат независимо от того,
    // какое сегодня число, поэтому фаза цикла больше ни на что не влияет.
    // Свежесть при этом не теряется: отрезки взвешены, вес каждого
    // следующего вдвое меньше.
    //
    // Дни-выбросы исключены: редкий крупный ремонт — не привычка, и он
    // моделируется отдельно, как случайный шок. Если оставить его здесь, он
    // учтётся дважды.
    final trendPerDay = _averagePerDay(
      deseasonalized,
      anomalyDayIndex,
      spanDays,
    );

    // Разброс вокруг среднего. Центрируем вокруг того же числа, которое
    // потом станет основой прогноза: иначе шум сам по себе тянул бы
    // баланс в сторону.
    final residualPool = <double>[];
    for (int i = 0; i < spanDays; i++) {
      if (anomalyDayIndex.contains(i)) continue;
      residualPool.add(deseasonalized[i] - trendPerDay);
    }

    final hasBootstrapPool = residualPool.length >= minResidualsForBootstrap;
    final volatility = _stdDev(hasBootstrapPool ? residualPool : dense);

    return _StreamStats(
      weekdayFactor: weekdayFactor,
      trendPerDay: trendPerDay,
      residualPool: residualPool,
      hasBootstrapPool: hasBootstrapPool,
      volatility: volatility,
    );
  }

  /// Средний дневной поток: месячные отрезки от свежего к старому, вес
  /// каждого следующего вдвое меньше.
  ///
  /// Неполный остаток истории отбрасывается, если есть хотя бы один целый
  /// отрезок: как раз он и вносил бы перекос от фазы месяца. Когда истории
  /// меньше отрезка, берём что есть — это лучше, чем ничего.
  static double _averagePerDay(
    List<double> values,
    Set<int> anomalyDayIndex,
    int spanDays,
  ) {
    if (spanDays <= 0) return 0;

    double weightedSum = 0;
    double weightTotal = 0;
    var weight = 1.0;

    // Идём от последнего дня назад отрезками по [_trendChunkDays].
    var end = spanDays; // не включая
    while (end > 0) {
      final start = end - _trendChunkDays;
      if (start < 0 && end < spanDays) break; // неполный хвост — пропускаем
      final from = start < 0 ? 0 : start;

      double sum = 0;
      var days = 0;
      for (var i = from; i < end; i++) {
        if (anomalyDayIndex.contains(i)) continue;
        sum += values[i];
        days++;
      }
      if (days > 0) {
        weightedSum += weight * (sum / days);
        weightTotal += weight;
      }
      weight /= 2;
      end = from;
      if (from == 0) break;
    }

    return weightTotal > 0 ? weightedSum / weightTotal : 0;
  }

  static double _stdDev(List<double> v) {
    if (v.length < 2) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final sumSq = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
    return sqrt(sumSq / (v.length - 1));
  }

  /// Случайная точка входа в историю для одной траектории.
  int randomCursor(Random rng) =>
      residualPool.isEmpty ? 0 : rng.nextInt(residualPool.length);

  /// Отклонение от среднего на шаге [step].
  ///
  /// Дни берутся не вразнобой, а подряд, с одной случайной точки входа и
  /// по кругу. Разница принципиальная там, где доход приходит редко и
  /// крупно.
  ///
  /// Если тянуть каждый день независимо, зарплата превращается в лотерею:
  /// за месяц вперёд она выпадает то ноль раз, то дважды. Ноль раз — это
  /// больше трети всех вариантов, и медиана уезжает вниз, хотя на деле
  /// зарплата приходит раз в месяц как часы. Человек, у которого доходы
  /// сходятся с расходами, видел график, уверенно ползущий в минус.
  ///
  /// Идя по истории подряд, траектория переносит в будущее её собственный
  /// ритм: месяц истории содержит ровно столько зарплат, сколько их было.
  double noiseAt(int step, Random rng) {
    if (hasBootstrapPool) {
      return residualPool[step % residualPool.length];
    }
    return volatility > 0 ? _gaussian(rng) * volatility : 0.0;
  }

  /// Box-Muller: стандартное нормальное число из равномерного RNG.
  static double _gaussian(Random rng) {
    final u1 = 1.0 - rng.nextDouble(); // (0,1], избегаем log(0)
    final u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
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
/// - средний дневной поток считается по месячным отрезкам с убывающим
///   весом: расходы идут каждый день, а доход приходит редко и крупно, и
///   оценка «по последним дням» показывала бы не средний доход, а то,
///   сколько дней прошло с зарплаты;
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
    final todayOnly = dateOnly(today);

    DateTime minDay = todayOnly;
    for (final tx in transactions) {
      final day = dateOnly(tx.date);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = dayDiff(minDay, todayOnly) + 1;

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
      final idx = dayDiff(minDay, tx.date);
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
      final idx = dayDiff(minDay, a.date);
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
      // Выбросы ищутся только среди расходов (см. AnomalyEngine). Раньше их
      // дни выбрасывались и из статистики доходов — то есть день, когда
      // чинили сервер, переставал считаться днём с зарплатой.
      anomalyDayIndex: const <int>{},
      minDay: minDay,
      spanDays: spanDays,
      seasonalityApplied: seasonalityApplied,
      minResidualsForBootstrap: _minResidualsForBootstrap,
    );
    final expenseStats = _StreamStats.compute(
      dense: denseExpense,
      anomalyDayIndex: anomalyDayIndex,
      minDay: minDay,
      spanDays: spanDays,
      seasonalityApplied: seasonalityApplied,
      minResidualsForBootstrap: _minResidualsForBootstrap,
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
    for (final e in whatIf.events) {
      final net = e.type == TransactionType.income ? e.amount : -e.amount;
      final start = dateOnly(e.date);
      final period = e.recurringPeriod;
      if (period == null) {
        final offset = dayDiff(todayOnly, start);
        if (offset < 1 || offset > days) continue;
        whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;
        continue;
      }
      RecurringEngine.forEachOccurrence(
        start,
        period,
        from: todayOnly,
        days: days,
        onOccurrence: (offset) {
          whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;
        },
      );
    }

    // Операции, которые человек уже внёс, но датировал будущим, — это факт,
    // а не шум: аванс, назначенный на следующую неделю, приходит в свой
    // день. Раньше они попадали только в стартовый баланс, то есть деньги
    // «появлялись» сегодня, а на своей дате уже ничего не происходило.
    final plannedByOffset = <int, double>{};
    for (final tx in transactions) {
      if (recurringIds.contains(tx.id)) continue;
      final offset = dayDiff(todayOnly, dateOnly(tx.date));
      if (offset < 1 || offset > days) continue;
      plannedByOffset[offset] = (plannedByOffset[offset] ?? 0) +
          (tx.type == TransactionType.income ? tx.amount : -tx.amount);
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
      // Точка входа в историю у каждой траектории своя, а дальше она идёт
      // по дням подряд (см. _StreamStats.noiseAt).
      final incomeCursor = incomeStats.randomCursor(rng);
      final expenseCursor = expenseStats.randomCursor(rng);
      for (int i = 0; i < days; i++) {
        final futureDay = addDays(todayOnly, i + 1);
        final wd = futureDay.weekday - 1;

        final incomeSeasonal =
            seasonalityApplied ? incomeStats.weekdayFactor[wd] : 0.0;
        final expenseSeasonal =
            seasonalityApplied ? expenseStats.weekdayFactor[wd] : 0.0;

        final incomeNoise = incomeStats.noiseAt(incomeCursor + i, rng);
        final expenseNoise = expenseStats.noiseAt(expenseCursor + i, rng);

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
        final plannedNet = plannedByOffset[i + 1] ?? 0.0;

        balance += incomeToday -
            expenseToday +
            recurringIncome +
            recurringExpense + // уже отрицательный (см. projectFutureContributions)
            plannedNet +
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
}
