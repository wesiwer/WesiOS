import '../models/transaction_model.dart';
import 'calendar_days.dart';

/// Насколько выполнимо предложение сократить траты.
enum CutFeasibility {
  /// Сокращать нечего — деньги и так не уходят в минус.
  notNeeded,

  /// Подъёмно: урезать нужно небольшую часть трат.
  realistic,

  /// Тяжело, но возможно: это заметная доля всех трат.
  hard,

  /// Одним сокращением не решается: пришлось бы урезать больше половины
  /// всех трат, включая обязательные.
  impossible,
}

/// Самая крупная статья расходов — с неё имеет смысл начинать.
class BiggestExpense {
  final String category;

  /// Сколько уходит на неё в день (в среднем за период).
  final double perDay;

  /// Какую долю всех трат она занимает, 0..1.
  final double share;

  const BiggestExpense({
    required this.category,
    required this.perDay,
    required this.share,
  });
}

/// Честный ответ на два разных вопроса, которые легко перепутать.
///
/// «На сколько хватит денег» имеет два смысла, и раньше экран смешивал их:
/// число дней считалось по нетто (сколько денег уходит сверх того, что
/// приходит), а подпись под ним показывала полные траты. Получалось «денег
/// на 100 дней при тратах 30 000 в день» — перемножить эти два числа и
/// сойтись с балансом было невозможно.
///
/// Здесь они разведены:
/// — [cushionDays] — сколько протянешь, если доход прекратится совсем. Это
///   и есть смысл финансовой подушки, и считается она от привычных трат.
/// — [runwayDays] — сколько протянешь при нынешнем раскладе, когда доход
///   есть, но его не хватает. Пусто, если доход перекрывает траты.
class FinancialHealth {
  /// Деньги, доступные сегодня.
  final double cushion;

  /// Сколько в среднем уходит в день — привычка тратить.
  final double spendPerDay;

  /// Сколько в среднем приходит в день.
  final double earnPerDay;

  /// Сколько дней можно прожить на накопленное, если доход прекратится.
  /// null — трат нет, считать не от чего.
  final int? cushionDays;

  /// Сколько дней до нуля при нынешнем раскладе (доход есть, но меньше
  /// трат). null — доход покрывает траты, деньги не кончаются.
  final int? runwayDays;

  /// Сколько дней жизни считаем нормальным запасом.
  final int targetDays;

  /// Сколько денег нужно, чтобы набрать [targetDays] дней.
  final double targetAmount;

  /// Сколько ещё не хватает до нормы. 0 — норма уже набрана.
  final double gap;

  /// Сколько дней собирать недостающее, если откладывать всё, что остаётся.
  /// null — сейчас ничего не остаётся.
  final int? daysToTarget;

  /// Сколько нужно сокращать в день, чтобы перестать проедать накопленное.
  /// 0 — сокращать нечего.
  final double cutPerDayNeeded;

  /// Какую долю трат пришлось бы урезать, 0..1.
  final double cutShareOfSpending;

  final CutFeasibility feasibility;

  /// Самая крупная статья расходов, если она вообще выделяется.
  final BiggestExpense? biggest;

  final bool isEmpty;

  const FinancialHealth({
    required this.cushion,
    required this.spendPerDay,
    required this.earnPerDay,
    required this.cushionDays,
    required this.runwayDays,
    required this.targetDays,
    required this.targetAmount,
    required this.gap,
    required this.daysToTarget,
    required this.cutPerDayNeeded,
    required this.cutShareOfSpending,
    required this.feasibility,
    required this.biggest,
    this.isEmpty = false,
  });

  static const FinancialHealth empty = FinancialHealth(
    cushion: 0,
    spendPerDay: 0,
    earnPerDay: 0,
    cushionDays: null,
    runwayDays: null,
    targetDays: 90,
    targetAmount: 0,
    gap: 0,
    daysToTarget: null,
    cutPerDayNeeded: 0,
    cutShareOfSpending: 0,
    feasibility: CutFeasibility.notNeeded,
    biggest: null,
    isEmpty: true,
  );

  /// Сколько остаётся в день. Отрицательное — накопления тают.
  double get netPerDay => earnPerDay - spendPerDay;

  /// Норма набрана?
  bool get targetReached => gap <= 0;

  /// Три месяца — общепринятый ориентир для подушки. Первый рубеж, о котором
  /// говорит база знаний, — один месяц; он отслеживается через [cushionDays].
  static const int defaultTargetDays = 90;

  /// Считает по операциям за последние [periodDays] дней.
  ///
  /// [balance] — деньги на сегодня. Операции, датированные будущим, в него
  /// входить не должны: это ещё не деньги, а план.
  static FinancialHealth compute({
    required List<TransactionModel> transactions,
    required double balance,
    required DateTime now,
    int periodDays = 30,
    int targetDays = defaultTargetDays,
  }) {
    if (periodDays <= 0) return empty;
    final today = dateOnly(now);
    final from = addDays(today, -(periodDays - 1));

    var income = 0.0;
    var expense = 0.0;
    final byCategory = <String, double>{};
    for (final tx in transactions) {
      final day = dateOnly(tx.date);
      if (day.isBefore(from) || day.isAfter(today)) continue;
      if (tx.type == TransactionType.income) {
        income += tx.amount;
      } else {
        expense += tx.amount;
        final key = (tx.category == null || tx.category!.trim().isEmpty)
            ? '—'
            : tx.category!;
        byCategory[key] = (byCategory[key] ?? 0) + tx.amount;
      }
    }
    if (income == 0 && expense == 0) return empty;

    final spendPerDay = expense / periodDays;
    final earnPerDay = income / periodDays;
    final net = earnPerDay - spendPerDay;

    // Подушка меряется привычкой тратить, а не остатком после доходов:
    // вопрос в том, сколько протянешь, если доход прекратится.
    final cushionDays =
        spendPerDay > 0 ? (balance / spendPerDay).floor() : null;

    final runwayDays =
        (net < 0 && balance > 0) ? (balance / -net).floor() : null;

    final targetAmount = spendPerDay * targetDays;
    final gap = targetAmount - balance;
    final daysToTarget =
        (gap > 0 && net > 0) ? (gap / net).ceil() : (gap <= 0 ? 0 : null);

    // Сколько нужно урезать, чтобы перестать проедать накопленное, — это
    // ровно та сумма, на которую траты обгоняют доход. Больше просить
    // бессмысленно: это уже не «выйти в ноль», а «начать копить».
    final cutNeeded = net < 0 ? -net : 0.0;
    final cutShare = spendPerDay > 0 ? cutNeeded / spendPerDay : 0.0;

    final feasibility = cutNeeded <= 0
        ? CutFeasibility.notNeeded
        : cutShare <= 0.25
            ? CutFeasibility.realistic
            : cutShare <= 0.5
                ? CutFeasibility.hard
                : CutFeasibility.impossible;

    BiggestExpense? biggest;
    if (byCategory.isNotEmpty && expense > 0) {
      final top = byCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
      biggest = BiggestExpense(
        category: top.key,
        perDay: top.value / periodDays,
        share: top.value / expense,
      );
    }

    return FinancialHealth(
      cushion: balance,
      spendPerDay: spendPerDay,
      earnPerDay: earnPerDay,
      cushionDays: cushionDays,
      runwayDays: runwayDays,
      targetDays: targetDays,
      targetAmount: targetAmount,
      gap: gap > 0 ? gap : 0,
      daysToTarget: daysToTarget,
      cutPerDayNeeded: cutNeeded,
      cutShareOfSpending: cutShare,
      feasibility: feasibility,
      biggest: biggest,
    );
  }
}
