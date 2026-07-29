import '../../../core/constants/app_version.dart';
import '../models/article_model.dart';

/// Статьи, которые поставляются вместе с приложением.
///
/// Живут в коде, а не в базе: их нужно обновлять вместе с самим приложением,
/// когда меняется функциональность, — справка, которая осталась от версии
/// годичной давности, хуже её отсутствия. При каждом запуске встроенные
/// статьи перезаписываются поверх сохранённых (см. `KnowledgeService.seed`),
/// пользовательские — не трогаются.
class BuiltinArticles {
  const BuiltinArticles._();

  static List<ArticleModel> all(bool ru) {
    final now = DateTime.now();
    ArticleModel a(String id, String title, String body, {bool pinned = false}) =>
        ArticleModel(
          id: id,
          title: title,
          body: body,
          section: ArticleSection.about,
          tags: ru
              ? const ['о программе', 'справка']
              : const ['about', 'help'],
          createdAt: now,
          updatedAt: now,
          builtIn: true,
          pinned: pinned,
        );

    if (!ru) {
      return [
        a('about_wesios', 'What WesiOS is', _aboutEn, pinned: true),
        a('about_treasury', 'Finance: Treasury, forecast, sandbox', _financeEn),
        a('about_tasks', 'Tasks, calendar and analytics', _workEn),
        a('about_updates', 'Updates and forecast models', _updatesEn),
      ];
    }

    return [
      a('about_wesios', 'Что такое WesiOS', _aboutRu, pinned: true),
      a('about_treasury', 'Финансы: кошелёк, прогноз, песочница', _financeRu),
      a('about_tasks', 'Задачи, календарь и аналитика', _workRu),
      a('about_updates', 'Обновления и модели прогноза', _updatesRu),
    ];
  }

  static const String _aboutRu = '''
# WesiOS — операционная система бизнеса

WesiOS собирает в одном месте то, что обычно разнесено по пяти сервисам:
деньги, задачи, знания и аналитику. Версия ${AppVersion.display}.

## Главный принцип: данные ваши

Всё хранится **локально на устройстве** (Hive). Приложение работает без
интернета: сеть нужна только курсам валют, скачиванию моделей прогноза и
обновлениям. Подключение Firebase — по желанию, ключи вводятся вручную и
лежат за паролем.

## Из чего состоит

- **Главная** — баланс, быстрые операции, часы, календарь на сегодня,
  ближайшие задачи и фраза дня (их больше тысячи, чтобы не приедались).
- **Задачи** — канбан с приоритетами, сроками, исполнителями и чек-листами.
- **Финансы (Wesi Treasury)** — счета, операции, категории, курсы валют.
- **Аналитика** — KPI в сравнении с прошлым периодом, динамика, здоровье.
- **Ещё** — все модули продукта с честной пометкой стадии готовности.

## Как начать

1. Откройте «Финансы» и добавьте первые операции — «Доход» и «Траты».
2. Заведите нужные счета, если направлений несколько.
3. Создайте пару задач со сроками — они появятся в календаре на главной.
4. Через неделю данных зайдите в «Прогноз»: раньше он честно откажется
   строить траекторию, потому что по одному дню предсказывать нечего.
''';

  static const String _financeRu = '''
# Финансы

## Кошелёк (Wesi Treasury)

Операции двух типов: доход и трата. У каждой — сумма, категория, дата,
описание и, при необходимости, повторение (регулярный платёж).

**Счета.** Общий баланс компании можно разбить на несколько счетов: резерв,
отдельный проект, наличные, карта. Переключатель наверху меняет разрез всего
экрана. Основной счёт удалить нельзя — на него ссылаются все операции,
созданные до появления счетов; счёт с историей архивируется, а не удаляется.

**Категории** у доходов и расходов разные и правятся вручную: набор
«ПО / Маркетинг / Офис» подходит не каждому делу.

**Валюты.** Внутри всё хранится в рублёвом эквиваленте, а показывается в
выбранной валюте по курсу ЦБ. Если курс недоступен, используется последнее
удачно полученное значение, а не выдуманное.

## Прогноз

Три слоя:

1. **Жёсткая логика** — регулярные платежи известны точно и просто
   прибавляются к траектории.
2. **Статистика** — тренд (EWMA), недельная сезонность, фильтр аномалий.
3. **Monte-Carlo** — тысячи траекторий, из которых берутся P10 / P50 / P90.

Горизонт — от недели до пяти лет. На длинных горизонтах число траекторий
снижается: стоимость расчёта равна «пути × дни», и пять лет по пять тысяч
путей — это девять миллионов шагов.

**Cash Gap Risk Score** — день, на который вероятность уйти в минус
превышает 5%. **«Что если?»** — разовое событие и/или сдвиг доходов и
расходов в процентах, без записи в базу.

## Песочница

Полная копия кошелька на **изолированных** данных: что угодно можно ломать,
на реальные деньги это не влияет. Есть готовые сценарии (Startup, Freelancer,
Crisis), клонирование реальных данных и собственный прогноз, где сценарии
«Что если?» **сохраняются под именами** и сравниваются на одном графике.
''';

  static const String _workRu = '''
# Работа и аналитика

## Задачи

Канбан из четырёх колонок: Бэклог, В работе, На проверке, Готово.
На десктопе карточки переносятся мышью, на телефоне — через меню на карточке
(четыре колонки в ряд там не помещаются).

У задачи есть приоритет, срок, исполнитель и чек-лист с прогрессом.
Завершённые задачи не считаются просроченными, даже если срок прошёл —
иначе доска краснела бы от уже сделанного.

## Календарь

Срок задачи и есть событие дня: отдельной сущности «событие» пока нет.
Карточка календаря на главной показывает то, что назначено на сегодня.

## Аналитика

Все числа даны **в сравнении с предыдущим периодом такой же длины** — голая
сумма за месяц не говорит, хорошо это или плохо.

- KPI: доходы, расходы, чистый результат, число операций.
- Динамика по месяцам, топ категорий с обеих сторон.
- Здоровье: траты в день, средний чек, запас прочности (runway).
- Продуктивность: закрытые и просроченные задачи.

Две честности зашиты специально: изменение не показывается как «+∞ %», если
в прошлом периоде был ноль, и запас прочности не выдумывается, когда доходы
перекрывают траты.
''';

  static const String _updatesRu = '''
# Обновления и модели прогноза

## Обновление приложения

WesiOS проверяет наличие новой версии сам и предлагает обновиться кнопкой —
в «Настройках» и полоской на главной. Ничего не скачивается без вашего
согласия.

- **Android** — скачивается APK и открывается системный установщик. Android
  потребует разрешить установку из WesiOS: это одноразовая галочка, экран
  настроек откроется сам.
- **Windows** — скачивается архив, приложение закрывается, файлы
  подменяются и приложение запускается заново.

Кнопка «Пропустить» скрывает предложение до следующей версии.

## Модели прогноза

Базовый движок **Wesi Horizon** встроен в приложение и работает всегда.
Дополнительно можно скачать **Prophet** и **SARIMAX** — они не входят в
установщик, потому что весят сотни мегабайт, и качаются по кнопке только
если нужны. В окне прогноза их можно включать по отдельности, сравнивать
между собой или усреднять.

Модели собираются заранее в CI и проверяются перед публикацией: если свежая
сборка не выдаёт корректный прогноз, она не публикуется, и у вас остаётся
предыдущая рабочая.
''';

  static const String _aboutEn = '''
# WesiOS — a business operating system

WesiOS brings together what is normally scattered across five services:
money, tasks, knowledge and analytics.

## The core principle: the data is yours

Everything is stored **locally on the device**. The app works offline; the
network is only needed for exchange rates, forecast models and updates.

## What is inside

- **Home** — balance, quick operations, clock, today's calendar and tasks.
- **Tasks** — a kanban board with priorities, due dates and checklists.
- **Finance** — accounts, operations, categories, currencies.
- **Analytics** — KPIs compared with the previous period, trends, health.
- **More** — every module with an honest readiness badge.
''';

  static const String _financeEn = '''
# Finance

Operations come in two kinds: income and expense. The company balance can be
split across several accounts — a reserve, a project, cash, a card.

The forecast has three layers: hard logic for recurring payments, statistics
(trend, weekly seasonality, anomaly filter) and a Monte-Carlo simulation that
produces P10 / P50 / P90. Horizons run from a week to five years.

The sandbox is a full copy of the wallet on **isolated** data, with saved
what-if scenarios compared on a single chart.
''';

  static const String _workEn = '''
# Work and analytics

The kanban board has four columns. A task carries a priority, a due date, an
assignee and a checklist. A finished task never counts as overdue.

Analytics compares every number with the previous period of the same length,
because a bare monthly total does not tell you whether it is good or bad.
''';

  static const String _updatesEn = '''
# Updates and forecast models

WesiOS checks for a new version itself and offers to update with a button.
Nothing is downloaded without your consent.

The built-in **Wesi Horizon** engine always works. Prophet and SARIMAX are
optional downloads — they weigh hundreds of megabytes and are not part of the
installer.
''';
}
