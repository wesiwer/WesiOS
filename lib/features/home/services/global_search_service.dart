import '../../knowledge/models/article_model.dart';
import '../../tasks/models/task_model.dart';
import '../../treasury/models/account_model.dart';
import '../../treasury/models/transaction_model.dart';

/// Откуда пришёл результат поиска.
enum SearchKind { transaction, task, article, account, module }

/// Одна найденная сущность.
class SearchHit {
  final SearchKind kind;
  final String title;
  final String? subtitle;

  /// Куда вести по нажатию.
  final String route;

  /// Чем выше, тем ближе к началу списка.
  final int score;

  const SearchHit({
    required this.kind,
    required this.title,
    required this.route,
    required this.score,
    this.subtitle,
  });
}

/// Экран приложения как цель поиска — чтобы «песочница» находила песочницу,
/// а не только операции со словом «песочница» в названии.
class SearchableModule {
  final String route;
  final String ru;
  final String en;

  const SearchableModule(this.route, this.ru, this.en);
}

/// Поиск по всему, что есть локально: операции, задачи, статьи, счета, экраны.
///
/// Считается на уже загруженных списках, а не ходит в Hive сам: так поиск
/// проверяется тестами без хранилища, а вызывающий код сам решает, что
/// подгружать.
class GlobalSearchService {
  static const List<SearchableModule> modules = [
    SearchableModule('/treasury', 'Финансы, кошелёк, счета', 'Finance, wallet, accounts'),
    SearchableModule('/treasury/operations', 'Операции, история транзакций', 'Operations, transaction history'),
    SearchableModule('/treasury/forecast', 'Прогноз, кассовый разрыв', 'Forecast, cash gap'),
    SearchableModule('/treasury/sandbox', 'Песочница, сценарии, что если', 'Sandbox, scenarios, what if'),
    SearchableModule('/tasks', 'Задачи, доска, канбан', 'Tasks, board, kanban'),
    SearchableModule('/calendar', 'Календарь, события, сроки', 'Calendar, events, deadlines'),
    SearchableModule('/analytics', 'Аналитика, отчёты, KPI', 'Analytics, reports, KPI'),
    SearchableModule('/knowledge', 'База знаний, справка, о программе', 'Knowledge base, help, about'),
    SearchableModule('/shield', 'Wesi Shield, защита, пароль, блокировка', 'Wesi Shield, protection, password, lock'),
    SearchableModule('/settings', 'Настройки, язык, валюта, обновление', 'Settings, language, currency, update'),
    SearchableModule('/profile', 'Профиль, аватар, ключи Firebase', 'Profile, avatar, Firebase keys'),
    SearchableModule('/roadmap', 'Дорожная карта, планы', 'Roadmap, plans'),
    SearchableModule('/crm', 'CRM, клиенты, сделки', 'CRM, clients, deals'),
    SearchableModule('/audio', 'Audio Vault, биты, демо', 'Audio Vault, beats, demos'),
    SearchableModule('/founder', 'История основателя', 'Founder story'),
  ];

  /// Нормализация запроса и текста к одному виду.
  ///
  /// «Ё» приводится к «е» намеренно: человек, ищущий «учет», не должен
  /// промахиваться мимо «учёта» из-за буквы, которую половина клавиатур
  /// вообще не набирает.
  static String normalize(String s) =>
      s.toLowerCase().replaceAll('ё', 'е').trim();

  /// Оценка совпадения: точное начало важнее вхождения в середину.
  ///
  /// Без ранжирования результат «содержит подстроку» ставил бы случайное
  /// длинное описание выше точного названия — искать в таком списке нечем.
  static int _score(String haystack, String needle) {
    final h = normalize(haystack);
    if (h.isEmpty) return 0;
    if (h == needle) return 100;
    if (h.startsWith(needle)) return 70;
    // Совпадение с началом слова ценнее совпадения внутри слова:
    // «сч» в «счёт» — то, что искали, «сч» в «отсчёт» — скорее нет.
    if (h.contains(' $needle')) return 50;
    if (h.contains(needle)) return 25;
    return 0;
  }

  static SearchHit? _best({
    required SearchKind kind,
    required String route,
    required String title,
    String? subtitle,
    required List<String> haystacks,
    required String needle,
    int bonus = 0,
  }) {
    var best = 0;
    for (final h in haystacks) {
      final s = _score(h, needle);
      if (s > best) best = s;
    }
    if (best == 0) return null;
    return SearchHit(
      kind: kind,
      title: title,
      subtitle: subtitle,
      route: route,
      score: best + bonus,
    );
  }

  /// Ищет по всем источникам сразу.
  ///
  /// `limit` ограничивает итог, а не каждый источник по отдельности: иначе
  /// десять подходящих операций вытеснили бы единственную точную задачу.
  static List<SearchHit> search({
    required String query,
    List<TransactionModel> transactions = const [],
    List<TaskModel> tasks = const [],
    List<ArticleModel> articles = const [],
    List<AccountModel> accounts = const [],
    bool russian = true,
    int limit = 24,
  }) {
    final needle = normalize(query);
    if (needle.length < 2) return const [];

    final hits = <SearchHit>[];

    for (final m in modules) {
      final hit = _best(
        kind: SearchKind.module,
        route: m.route,
        title: (russian ? m.ru : m.en).split(',').first,
        subtitle: russian ? 'Раздел' : 'Section',
        haystacks: [m.ru, m.en],
        needle: needle,
        // Разделы чуть выше при равном совпадении: попасть в нужный экран
        // почти всегда полезнее, чем в одну запись внутри него.
        bonus: 5,
      );
      if (hit != null) hits.add(hit);
    }

    for (final a in accounts) {
      final hit = _best(
        kind: SearchKind.account,
        route: '/treasury',
        title: a.name,
        subtitle: russian ? 'Счёт' : 'Account',
        haystacks: [a.name],
        needle: needle,
      );
      if (hit != null) hits.add(hit);
    }

    for (final t in transactions) {
      final hit = _best(
        kind: SearchKind.transaction,
        route: '/treasury/operations',
        title: t.title,
        subtitle: t.category,
        haystacks: [t.title, t.category ?? '', t.description ?? ''],
        needle: needle,
      );
      if (hit != null) hits.add(hit);
    }

    for (final t in tasks) {
      final hit = _best(
        kind: SearchKind.task,
        route: '/tasks',
        title: t.title,
        subtitle: t.tags.isEmpty ? null : t.tags.join(' · '),
        haystacks: [t.title, t.description ?? '', ...t.tags],
        needle: needle,
      );
      if (hit != null) hits.add(hit);
    }

    for (final a in articles) {
      final hit = _best(
        kind: SearchKind.article,
        route: '/knowledge',
        title: a.title,
        subtitle: russian ? 'База знаний' : 'Knowledge base',
        haystacks: [a.title, a.body, ...a.tags],
        needle: needle,
      );
      if (hit != null) hits.add(hit);
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      // При равном счёте — по алфавиту, а не как легло: иначе один и тот же
      // запрос давал бы разный порядок при каждом наборе.
      return byScore != 0 ? byScore : a.title.compareTo(b.title);
    });

    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }
}
