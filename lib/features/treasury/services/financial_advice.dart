import '../../../core/services/currency_service.dart';
import 'financial_health.dart';

/// Готовая формулировка для экрана: заголовок, объяснение и один шаг.
class FinancialAdvice {
  /// Главная строка — то, что человек прочитает первым.
  final String headline;

  /// Пояснение: откуда взялось число.
  final String detail;

  /// Что конкретно сделать. Пусто, если делать нечего.
  final String action;

  /// Тревожная ли новость — экран красит по этому признаку.
  final bool alarming;

  const FinancialAdvice({
    required this.headline,
    required this.detail,
    this.action = '',
    this.alarming = false,
  });
}

/// Словами о деньгах — без процентилей, «горизонтов» и «волатильности».
///
/// Главное правило: не предлагать невозможного. Совет «тратить на 30 000 в
/// день меньше» человеку, у которого весь доход меньше этой суммы, — не
/// совет, а упрёк: выполнить его нельзя никаким усилием. Если разрыв
/// закрывается только частью трат — так и говорим; если нет — честно
/// пишем, что одним урезанием не выйдет, и показываем, какого дохода не
/// хватает.
class FinancialAdviceBuilder {
  final bool ru;
  const FinancialAdviceBuilder({required this.ru});

  String _money(double v) => CurrencyService.format(v);

  String _days(int d) {
    if (!ru) return '$d days';
    final n = d % 100;
    if (n >= 11 && n <= 14) return '$d дней';
    switch (d % 10) {
      case 1:
        return '$d день';
      case 2:
      case 3:
      case 4:
        return '$d дня';
      default:
        return '$d дней';
    }
  }

  String _months(int days) {
    final m = days / 30;
    if (m >= 1) {
      final rounded = m.toStringAsFixed(m < 10 ? 1 : 0).replaceAll('.0', '');
      return ru ? 'примерно $rounded мес.' : 'about $rounded months';
    }
    return ru ? 'меньше месяца' : 'less than a month';
  }

  /// Сколько денег отложено и на сколько этого хватит.
  FinancialAdvice cushion(FinancialHealth h) {
    if (h.isEmpty || h.spendPerDay <= 0) {
      return FinancialAdvice(
        headline: ru ? 'Пока не из чего считать' : 'Nothing to measure yet',
        detail: ru
            ? 'Добавьте несколько трат — и здесь появится, на сколько хватает денег.'
            : 'Add a few expenses and this will show how long your money lasts.',
      );
    }

    final days = h.cushionDays ?? 0;
    return FinancialAdvice(
      headline: ru
          ? 'Отложенного хватит на ${_days(days)}'
          : 'Your savings last ${_days(days)}',
      detail: ru
          ? 'Это ${_months(days)} жизни без единого поступления. '
              'Считаем по вашим тратам — в среднем ${_money(h.spendPerDay)} в день.'
          : 'That is ${_months(days)} with no income at all, '
              'measured against your ${_money(h.spendPerDay)} a day.',
      action: h.targetReached
          ? (ru
              ? 'Запас на ${_days(h.targetDays)} собран — можно думать не о выживании, а о вложениях.'
              : 'You already hold ${_days(h.targetDays)} — time to think about investing, not surviving.')
          : (ru
              ? 'До запаса на ${_days(h.targetDays)} не хватает ${_money(h.gap)}.'
              : '${_money(h.gap)} short of a ${_days(h.targetDays)} buffer.'),
      alarming: days < 30,
    );
  }

  /// Что делать дальше — с оглядкой на то, что человек реально может.
  FinancialAdvice nextStep(FinancialHealth h) {
    if (h.isEmpty) {
      return FinancialAdvice(
        headline: ru ? 'Данных пока мало' : 'Not enough data yet',
        detail: ru
            ? 'Поработайте с приложением пару недель — появятся и советы.'
            : 'Give it a couple of weeks of entries and advice will appear.',
      );
    }

    // Деньги остаются — разговор про накопление, а не про урезание.
    if (h.netPerDay >= 0) {
      if (h.targetReached) {
        return FinancialAdvice(
          headline: ru ? 'Всё в порядке' : 'You are in the clear',
          detail: ru
              ? 'Доход перекрывает траты на ${_money(h.netPerDay)} в день, '
                  'а запас уже больше нормы.'
              : 'Income beats spending by ${_money(h.netPerDay)} a day, '
                  'and the buffer is above target.',
        );
      }
      final left = h.daysToTarget;
      return FinancialAdvice(
        headline: ru
            ? 'Остаётся ${_money(h.netPerDay)} в день'
            : '${_money(h.netPerDay)} left over each day',
        detail: left == null
            ? (ru
                ? 'Этого хватает, чтобы не проедать накопленное.'
                : 'Enough to stop eating into savings.')
            : (ru
                ? 'Если откладывать всё, что остаётся, запас на ${_days(h.targetDays)} '
                    'соберётся за ${_days(left)}.'
                : 'Saving all of it fills a ${_days(h.targetDays)} buffer in ${_days(left)}.'),
        action: ru
            ? 'Ничего урезать не нужно — достаточно не увеличивать траты.'
            : 'Nothing to cut — just keep spending where it is.',
      );
    }

    // Деньги тают. Считаем, сколько нужно урезать, и сразу — по силам ли это.
    final cut = h.cutPerDayNeeded;
    final share = (h.cutShareOfSpending * 100).round();
    final runway = h.runwayDays;

    final where = h.biggest == null
        ? ''
        : (ru
            ? ' Больше всего уходит на «${h.biggest!.category}» — '
                '${_money(h.biggest!.perDay)} в день, это ${(h.biggest!.share * 100).round()}% всех трат.'
            : ' The largest line is "${h.biggest!.category}" — '
                '${_money(h.biggest!.perDay)} a day, ${(h.biggest!.share * 100).round()}% of spending.');

    switch (h.feasibility) {
      case CutFeasibility.impossible:
        // Требуется урезать больше половины трат. Такое предложение
        // невыполнимо: обязательные платежи никуда не денутся.
        final needIncome = cut;
        return FinancialAdvice(
          headline: ru
              ? 'Одним урезанием трат тут не обойтись'
              : 'Cutting spending alone will not close this',
          detail: ru
              ? 'Чтобы выйти в ноль, пришлось бы тратить на $share% меньше — '
                  'это больше половины всех расходов, включая обязательные.'
                  '${runway == null ? '' : ' При нынешнем раскладе денег хватит на ${_days(runway)}.'}'
              : 'Breaking even would mean spending $share% less — more than half '
                  'of everything, including the bills you cannot skip.',
          action: ru
              ? 'Смотреть надо в сторону дохода: не хватает примерно '
                  '${_money(needIncome)} в день, то есть ${_money(needIncome * 30)} в месяц.$where'
              : 'The gap is on the income side: about ${_money(needIncome)} a day, '
                  '${_money(needIncome * 30)} a month.$where',
          alarming: true,
        );

      case CutFeasibility.hard:
        return FinancialAdvice(
          headline: ru
              ? 'Нужно тратить на ${_money(cut)} в день меньше'
              : 'Spend ${_money(cut)} a day less',
          detail: ru
              ? 'Это $share% ваших трат — заметно, но выполнимо. '
                  '${runway == null ? '' : 'Иначе денег хватит на ${_days(runway)}.'}'
              : 'That is $share% of your spending — noticeable but doable.',
          action: ru
              ? 'Начните с самой крупной статьи.$where'
              : 'Start with the largest line.$where',
          alarming: true,
        );

      case CutFeasibility.realistic:
        return FinancialAdvice(
          headline: ru
              ? 'Нужно тратить на ${_money(cut)} в день меньше'
              : 'Spend ${_money(cut)} a day less',
          detail: ru
              ? 'Это всего $share% трат — примерно ${_money(cut * 30)} за месяц. '
                  '${runway == null ? '' : 'Пока что денег хватит на ${_days(runway)}.'}'
              : 'Just $share% of spending, about ${_money(cut * 30)} a month.',
          action: ru ? 'Одной статьи обычно достаточно.$where' : 'One line is usually enough.$where',
        );

      case CutFeasibility.notNeeded:
        return FinancialAdvice(
          headline: ru ? 'Траты под контролем' : 'Spending is under control',
          detail: ru
              ? 'Доход покрывает расходы.'
              : 'Income covers the spending.',
        );
    }
  }
}
