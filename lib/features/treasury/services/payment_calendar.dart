/// Производственный календарь: выходные, праздники и перенос платежей.
///
/// Деньги ходят по рабочим дням, а не по календарным. Платёж, назначенный
/// на 1 января, уйдёт не первого — и не второго, и не восьмого. Аренда с
/// датой 31-го числа в субботу спишется в понедельник. Зарплата, наоборот,
/// по Трудовому кодексу выплачивается НАКАНУНЕ, если день выплаты выпал на
/// выходной, — то есть сдвигается назад, а не вперёд.
///
/// Без этого прогноз на ближнем горизонте промахивается системно: в
/// январе десять дней подряд не происходит ничего из ожидаемого, а потом
/// всё сваливается одним днём. Именно ближние две недели человек и
/// проверяет глазами, поэтому цена ошибки здесь выше, чем на дальнем краю.
///
/// Календарь считается по правилам, а не по таблице на конкретный год:
/// таблица протухает молча, а правила работают и в 2030-м. Переносы,
/// которые правительство назначает отдельным постановлением на каждый год,
/// сюда не входят — они непредсказуемы, и выдумывать их было бы враньём.
library;

import 'calendar_days.dart';

/// Как платёж относится к нерабочему дню.
enum PaymentShift {
  /// Уходит в ближайший следующий рабочий день. Так ведут себя списания:
  /// аренда, налоги, подписки, платежи по счетам.
  forward,

  /// Уходит в ближайший предыдущий рабочий день. Так по Трудовому кодексу
  /// выплачивается зарплата: «накануне этого дня».
  backward,

  /// Не двигается. Переводы между своими счетами, наличные, карта.
  none,
}

class PaymentCalendar {
  /// Нерабочие праздничные дни по статье 112 ТК РФ, как «месяц-день».
  ///
  /// Здесь только то, что закреплено законом и не меняется от года к году.
  static const Set<int> _fixedHolidays = {
    101, 102, 103, 104, 105, 106, 108, // новогодние каникулы
    107, // Рождество
    223, // День защитника Отечества
    308, // Международный женский день
    501, // Праздник Весны и Труда
    509, // День Победы
    612, // День России
    1104, // День народного единства
  };

  /// Праздник по статье 112 — без учёта переносов выходных.
  static bool isHoliday(DateTime date) =>
      _fixedHolidays.contains(date.month * 100 + date.day);

  /// Суббота или воскресенье.
  static bool isWeekend(DateTime date) =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  /// Банк в этот день деньги не двигает.
  static bool isNonWorking(DateTime date) => isWeekend(date) || isHoliday(date);

  /// Ближайший рабочий день в заданную сторону.
  ///
  /// Предел в 20 дней — с запасом: самая длинная нерабочая полоса в году,
  /// новогодние каникулы вместе с прилегающими выходными, короче.
  static DateTime nearestWorkingDay(DateTime date, {required bool forward}) {
    var result = dateOnly(date);
    var guard = 0;
    while (isNonWorking(result) && guard++ < 20) {
      result = addDays(result, forward ? 1 : -1);
    }
    return result;
  }

  /// Куда на самом деле придётся платёж, назначенный на [date].
  static DateTime settle(DateTime date, PaymentShift shift) {
    switch (shift) {
      case PaymentShift.none:
        return dateOnly(date);
      case PaymentShift.forward:
        return nearestWorkingDay(date, forward: true);
      case PaymentShift.backward:
        return nearestWorkingDay(date, forward: false);
    }
  }

  /// Как двигается платёж, судя по его названию и категории.
  ///
  /// Зарплата и всё, что человек получает от работодателя, по закону
  /// выплачивается накануне выходного. Остальные обязательные списания
  /// проходят в первый рабочий день после. Наличные и переводы между
  /// своими счетами не двигаются вовсе.
  static PaymentShift shiftFor({
    String? title,
    String? category,
    String? description,
  }) {
    final text = '${category ?? ''} ${title ?? ''} ${description ?? ''}'
        .toLowerCase();
    bool any(List<String> words) => words.any(text.contains);

    if (any(const [
      'зарплат',
      'аванс',
      'оклад',
      'salary',
      'payroll',
      'wage',
    ])) {
      return PaymentShift.backward;
    }
    if (any(const [
      'наличн',
      'cash',
      'перевод между',
      'между счет',
      'transfer between',
    ])) {
      return PaymentShift.none;
    }
    if (any(const [
      'аренд',
      'налог',
      'ндс',
      'взнос',
      'кредит',
      'ипотек',
      'лизинг',
      'подписк',
      'счёт',
      'счет',
      'rent',
      'tax',
      'loan',
      'mortgage',
      'lease',
      'subscription',
      'invoice',
      'bill',
      'utilit',
      'коммунал',
    ])) {
      return PaymentShift.forward;
    }
    // По умолчанию — обычное банковское списание.
    return PaymentShift.forward;
  }

  /// Сколько рабочих дней в отрезке [from; to] включительно.
  static int workingDaysBetween(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final total = dayDiff(start, dateOnly(to));
    if (total < 0) return 0;
    var count = 0;
    for (var i = 0; i <= total; i++) {
      if (!isNonWorking(addDays(start, i))) count++;
    }
    return count;
  }
}
