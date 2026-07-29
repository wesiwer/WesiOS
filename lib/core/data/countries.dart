import '../localization/wesi_locale.dart';

/// Список стран для профиля.
///
/// Порядок не алфавитный по всему списку: при русском интерфейсе Россия
/// идёт первой (и ближайшие соседи сразу за ней), потому что подавляющее
/// большинство пользователей выбирает именно их — искать свою страну в
/// середине алфавита неудобно. Остальные отсортированы по алфавиту.
class Countries {
  const Countries._();

  /// Приоритетные варианты для русского интерфейса.
  static const List<String> _priorityRu = [
    'Россия',
    'Беларусь',
    'Казахстан',
    'Украина',
    'Армения',
    'Азербайджан',
    'Грузия',
    'Узбекистан',
    'Киргизия',
    'Таджикистан',
    'Молдова',
  ];

  static const List<String> _priorityEn = ['United States', 'United Kingdom'];

  static const List<String> _restRu = [
    'Австралия', 'Австрия', 'Албания', 'Алжир', 'Аргентина', 'Афганистан',
    'Бангладеш', 'Бахрейн', 'Бельгия', 'Болгария', 'Боливия', 'Босния и Герцеговина',
    'Бразилия', 'Великобритания', 'Венгрия', 'Венесуэла', 'Вьетнам', 'Гана',
    'Гватемала', 'Германия', 'Гонконг', 'Греция', 'Дания', 'Доминикана',
    'Египет', 'Израиль', 'Индия', 'Индонезия', 'Иордания', 'Ирак', 'Иран',
    'Ирландия', 'Исландия', 'Испания', 'Италия', 'Йемен', 'Камбоджа', 'Канада',
    'Катар', 'Кения', 'Кипр', 'Китай', 'Колумбия', 'Коста-Рика', 'Куба',
    'Кувейт', 'Латвия', 'Ливан', 'Ливия', 'Литва', 'Люксембург', 'Маврикий',
    'Малайзия', 'Мальта', 'Марокко', 'Мексика', 'Монголия', 'Мьянма', 'Непал',
    'Нигерия', 'Нидерланды', 'Никарагуа', 'Новая Зеландия', 'Норвегия',
    'ОАЭ', 'Оман', 'Пакистан', 'Панама', 'Парагвай', 'Перу', 'Польша',
    'Португалия', 'Республика Корея', 'Румыния', 'США', 'Сальвадор',
    'Саудовская Аравия', 'Северная Македония', 'Сербия', 'Сингапур', 'Сирия',
    'Словакия', 'Словения', 'Судан', 'Таиланд', 'Тайвань', 'Танзания',
    'Тунис', 'Туркменистан', 'Турция', 'Уганда', 'Уругвай', 'Филиппины',
    'Финляндия', 'Франция', 'Хорватия', 'Черногория', 'Чехия', 'Чили',
    'Швейцария', 'Швеция', 'Шри-Ланка', 'Эквадор', 'Эстония', 'Эфиопия',
    'ЮАР', 'Ямайка', 'Япония',
  ];

  static const List<String> _restEn = [
    'Afghanistan', 'Albania', 'Algeria', 'Argentina', 'Armenia', 'Australia',
    'Austria', 'Azerbaijan', 'Bahrain', 'Bangladesh', 'Belarus', 'Belgium',
    'Bolivia', 'Bosnia and Herzegovina', 'Brazil', 'Bulgaria', 'Cambodia',
    'Canada', 'Chile', 'China', 'Colombia', 'Costa Rica', 'Croatia', 'Cuba',
    'Cyprus', 'Czechia', 'Denmark', 'Dominican Republic', 'Ecuador', 'Egypt',
    'El Salvador', 'Estonia', 'Ethiopia', 'Finland', 'France', 'Georgia',
    'Germany', 'Ghana', 'Greece', 'Guatemala', 'Hong Kong', 'Hungary',
    'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel',
    'Italy', 'Jamaica', 'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kuwait',
    'Kyrgyzstan', 'Latvia', 'Lebanon', 'Libya', 'Lithuania', 'Luxembourg',
    'Malaysia', 'Malta', 'Mauritius', 'Mexico', 'Moldova', 'Mongolia',
    'Montenegro', 'Morocco', 'Myanmar', 'Nepal', 'Netherlands', 'New Zealand',
    'Nicaragua', 'Nigeria', 'North Macedonia', 'Norway', 'Oman', 'Pakistan',
    'Panama', 'Paraguay', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar',
    'Romania', 'Russia', 'Saudi Arabia', 'Serbia', 'Singapore', 'Slovakia',
    'Slovenia', 'South Africa', 'South Korea', 'Spain', 'Sri Lanka', 'Sudan',
    'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania',
    'Thailand', 'Tunisia', 'Turkey', 'Turkmenistan', 'UAE', 'Uganda',
    'Ukraine', 'United Kingdom', 'United States', 'Uruguay', 'Uzbekistan',
    'Venezuela', 'Vietnam', 'Yemen',
  ];

  static String get notSpecified =>
      WesiLocale.isRussian ? 'Не указана' : 'Not specified';

  /// Полный список для текущего языка: «не указана», затем приоритетные,
  /// затем остальные без повторов.
  static List<String> get all {
    final ru = WesiLocale.isRussian;
    final priority = ru ? _priorityRu : _priorityEn;
    final rest = ru ? _restRu : _restEn;

    final seen = <String>{};
    final result = <String>[notSpecified];
    for (final c in [...priority, ...rest]) {
      if (seen.add(c)) result.add(c);
    }
    return result;
  }
}
