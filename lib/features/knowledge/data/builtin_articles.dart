import '../../../core/constants/app_version.dart';
import 'dart:convert';

import '../models/article_model.dart';

/// Полная документация WesiOS — встроенные статьи базы знаний.
///
/// Иерархия: папки (isFolder=true) содержат дочерние статьи (parentId).
/// При каждом запуске встроенные статьи перезаписываются (KnowledgeService.seed).
class BuiltinArticles {
  const BuiltinArticles._();

  static List<ArticleModel> all(bool ru) {
    final now = DateTime.now();

    // ─── Helper ─────────────────────────────────────────────────────────────
    ArticleModel folder(String id, String title, {String? parentId, bool pinned = false}) =>
        ArticleModel(
          id: id,
          title: title,
          body: '',
          section: ArticleSection.about,
          tags: ru ? const ['документация'] : const ['documentation'],
          createdAt: now,
          updatedAt: now,
          builtIn: true,
          pinned: pinned,
          parentId: parentId,
          isFolder: true,
        );

    ArticleModel article(String id, String title, String body,
            {String? parentId, bool pinned = false, List<String>? tags}) =>
        ArticleModel(
          id: id,
          title: title,
          body: body,
          section: ArticleSection.about,
          tags: tags ?? (ru ? const ['документация'] : const ['documentation']),
          createdAt: now,
          updatedAt: now,
          builtIn: true,
          pinned: pinned,
          parentId: parentId,
        );

    // ─── Rich content helpers ───────────────────────────────────────────────
    //
    // ПОЧЕМУ ЭТО ВЫГЛЯДИТ ИМЕННО ТАК. В формате Delta, которым Quill хранит
    // документ, атрибуты БЛОКА (заголовок, маркер списка) ставятся не на сам
    // текст, а на перевод строки, который этот блок закрывает. Здесь было
    // написано наоборот — `{"insert":"Заголовок\n","attributes":{"header":1}}`
    // одной операцией, — и редактор такую разметку читал неверно: заголовки и
    // списки в статьях выглядели не тем, чем должны были.
    //
    // Правильная форма: текст отдельной операцией, а перевод строки —
    // отдельной, и атрибут висит именно на ней.
    //
    // Текст ещё и экранируется через jsonEncode: собранный вручную JSON
    // ломался от любой кавычки внутри строки.
    String esc(String t) => jsonEncode(t);
    String lineBreak([String? attrs]) => attrs == null
        ? '{"insert":"\\n"}'
        : '{"insert":"\\n","attributes":$attrs}';

    String header(String t, int level) =>
        '{"insert":${esc(t)}},${lineBreak('{"header":$level}')}';

    String h1(String t) => header(t, 1);
    String h2(String t) => header(t, 2);
    String h3(String t) => header(t, 3);
    String p(String t) => '{"insert":${esc(t)}},${lineBreak()}';
    String bold(String t) =>
        '{"insert":${esc(t)},"attributes":{"bold":true}}';
    String italic(String t) =>
        '{"insert":${esc(t)},"attributes":{"italic":true}}';
    String link(String text, String url) =>
        '{"insert":${esc(text)},"attributes":{"link":${esc(url)}}}';
    String bullet(String t) =>
        '{"insert":${esc(t)}},${lineBreak('{"list":"bullet"}')}';
    String numbered(String t) =>
        '{"insert":${esc(t)}},${lineBreak('{"list":"ordered"}')}';
    String br() => lineBreak();
    // Вложенный JSON обязан быть ЭКРАНИРОВАН. Здесь стояло
    // `{"insert":{"chart":"$json"}}` — то есть готовый JSON диаграммы
    // вставлялся внутрь строкового значения как есть, со всеми своими
    // кавычками. Всё тело статьи после этого переставало разбираться, и
    // статья показывалась сырым текстом.
    String embedImage(String url) => '{"insert":{"image":${esc(url)}}}';
    String embedVideo(String url) => '{"insert":{"video":${esc(url)}}}';
    String embedTable(String json) => '{"insert":{"table":${esc(json)}}}';
    String embedChart(String json) => '{"insert":{"chart":${esc(json)}}}';

    // ─── Chart data helpers ─────────────────────────────────────────────────
    // Собираются jsonEncode, а не склейкой: заголовок с кавычкой или
    // подпись с апострофом ломали разметку целиком.
    String chart(String type, String title, List<String> labels,
            List<double> values,
            {String source = 'manual'}) =>
        jsonEncode({
          'type': type,
          'title': title,
          'source': source,
          'data': values,
          'labels': labels,
        });

    String chartBar(String title, List<String> labels, List<double> values) =>
        chart('bar', title, labels, values);
    String chartLine(String title, List<String> labels, List<double> values) =>
        chart('line', title, labels, values);
    String chartPie(String title, List<String> labels, List<double> values) =>
        chart('pie', title, labels, values);
    String chartLinked(String type, String source, String title) =>
        chart(type, title, const [], const [], source: source);

    // ─── Table data helper ──────────────────────────────────────────────────
    String tableJson(List<List<String>> rows) => jsonEncode(rows);


    // ═══════════════════════════════════════════════════════════════════════
    //  ROOT FOLDER: WesiOS
    // ═══════════════════════════════════════════════════════════════════════

    // ─── Root folder ────────────────────────────────────────────────────────
    final root = folder('wesios_root', ru ? 'WesiOS' : 'WesiOS');

    // ─── About article ──────────────────────────────────────────────────────
    final aboutBody = '[${h1(ru ? 'WesiOS — персональная операционная система' : 'WesiOS — Personal Operating System')},'
        '${p(ru ? 'WesiOS — это комплексная система управления личными и профессиональными процессами. Объединяет финансы, задачи, аналитику, базу знаний и инструменты в едином интерфейсе.' : 'WesiOS is a comprehensive system for managing personal and professional processes. Combines finance, tasks, analytics, knowledge base and tools in a unified interface.')},'
        '${h2(ru ? 'Версия' : 'Version')},'
        '${p(AppVersion.display)},'
        '${h2(ru ? 'Ключевые принципы' : 'Key Principles')},'
        '${bullet(ru ? 'Все данные хранятся локально (Hive) — приватность по умолчанию' : 'All data stored locally (Hive) — privacy by default')},'
        '${bullet(ru ? 'Firebase — опционально, для облачных функций' : 'Firebase — optional, for cloud functions')},'
        '${bullet(ru ? 'Мультивалютность: RUB, USD, EUR, GBP, CNY, UAH, BYN, KZT' : 'Multi-currency: RUB, USD, EUR, GBP, CNY, UAH, BYN, KZT')},'
        '${bullet(ru ? 'Кроссплатформенность: Windows, Android' : 'Cross-platform: Windows, Android')},'
        '${bullet(ru ? 'Светлая и тёмная тема с анимированным переходом' : 'Light and dark theme with animated transition')},'
        '${h2(ru ? 'Архитектура модулей' : 'Module Architecture')},'
        '${embedChart(chartBar(ru ? 'Модули WesiOS' : 'WesiOS Modules',
          [ru ? 'Treasury' : 'Treasury', ru ? 'Tasks' : 'Tasks', ru ? 'Forecast' : 'Forecast', ru ? 'Analytics' : 'Analytics', ru ? 'Calendar' : 'Calendar', ru ? 'Knowledge' : 'Knowledge'],
          [100, 85, 90, 75, 70, 95]))},'
        '${br()},'
        '${p(ru ? 'Диаграмма выше показывает относительную сложность и функциональность каждого модуля в системе.' : 'The chart above shows the relative complexity and functionality of each module in the system.')}'
        ']';

    final about = article('wesios_about',
        ru ? 'О WesiOS' : 'About WesiOS',
        aboutBody,
        parentId: 'wesios_root',
        pinned: true,
        tags: ru ? ['о программе', 'версия'] : ['about', 'version']);


    // ═══════════════════════════════════════════════════════════════════════
    //  FOLDER: Модули / Modules
    // ═══════════════════════════════════════════════════════════════════════

    final modulesFolder = folder('wesios_modules', ru ? 'Модули' : 'Modules', parentId: 'wesios_root');

    // ─── Wesi Treasury ──────────────────────────────────────────────────────
    final treasuryFolder = folder('wesios_treasury', ru ? 'Wesi Treasury' : 'Wesi Treasury', parentId: 'wesios_modules');

    final treasuryBody = '[${h1(ru ? 'Wesi Treasury — управление финансами' : 'Wesi Treasury — Finance Management')},'
        '${p(ru ? 'Treasury — центральный модуль учёта финансов. Все суммы хранятся в RUB-эквиваленте, отображаются через CurrencyService в выбранной валюте.' : 'Treasury is the central finance tracking module. All amounts stored in RUB equivalent, displayed via CurrencyService in selected currency.')},'
        '${h2(ru ? 'TransactionModel' : 'TransactionModel')},'
        '${p(ru ? 'Основная модель транзакции:' : 'Core transaction model:')},'
        '${embedTable(tableJson([
          [ru ? 'Поле' : 'Field', ru ? 'Тип' : 'Type', ru ? 'Описание' : 'Description'],
          ['id', 'String', ru ? 'Уникальный ID' : 'Unique ID'],
          ['amount', 'double', ru ? 'Сумма в RUB' : 'Amount in RUB'],
          ['currency', 'String', ru ? 'Валюта операции' : 'Transaction currency'],
          ['category', 'String', ru ? 'Категория' : 'Category'],
          ['type', 'String', ru ? 'income / expense / transfer' : 'income / expense / transfer'],
          ['date', 'DateTime', ru ? 'Дата операции' : 'Transaction date'],
          ['note', 'String', ru ? 'Примечание' : 'Note'],
          ['isRecurring', 'bool', ru ? 'Повторяющаяся' : 'Recurring'],
          ['recurringRule', 'String?', ru ? 'Правило повторения' : 'Recurrence rule'],
          ['accountId', 'String?', ru ? 'ID счёта' : 'Account ID'],
          ['tags', 'List<String>', ru ? 'Теги' : 'Tags'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Z-Score аномалии' : 'Z-Score Anomalies')},'
        '${p(ru ? 'Автоматическое обнаружение аномальных транзакций:' : 'Automatic anomaly detection:')},'
        '${bullet(ru ? 'μ (среднее) — средняя сумма по категории' : 'μ (mean) — average amount per category')},'
        '${bullet(ru ? 'σ (стандартное отклонение) — разброс сумм' : 'σ (std dev) — amount spread')},'
        '${bullet(ru ? 'Z = (x − μ) / σ — если |Z| > 2.0 → аномалия' : 'Z = (x − μ) / σ — if |Z| > 2.0 → anomaly')},'
        '${embedChart(chartLinked('line', 'treasury', ru ? 'Баланс за 7 месяцев' : 'Balance over 7 months'))},'
        '${br()},'
        '${h2(ru ? 'Recurring платежи' : 'Recurring Payments')},'
        '${p(ru ? 'Поддерживаемые правила повторения:' : 'Supported recurrence rules:')},'
        '${bullet('daily — ежедневно / daily')},'
        '${bullet('weekly — еженедельно / weekly')},'
        '${bullet('monthly — ежемесячно / monthly')},'
        '${bullet('yearly — ежегодно / yearly')},'
        '${h2(ru ? 'Как создать транзакцию' : 'How to Create a Transaction')},'
        '${numbered(ru ? 'Откройте модуль Treasury' : 'Open Treasury module')},'
        '${numbered(ru ? 'Нажмите + для новой операции' : 'Tap + for new operation')},'
        '${numbered(ru ? 'Укажите сумму, категорию, тип' : 'Enter amount, category, type')},'
        '${numbered(ru ? 'Добавьте теги и примечание' : 'Add tags and note')},'
        '${numbered(ru ? 'Сохраните — транзакция появится в списке' : 'Save — transaction appears in list')}'
        ']';

    final treasury = article('wesios_treasury_article',
        ru ? 'Управление финансами' : 'Finance Management',
        treasuryBody,
        parentId: 'wesios_treasury',
        tags: ru ? ['treasury', 'финансы', 'транзакции'] : ['treasury', 'finance', 'transactions']);


    // ─── Wesi Forecast ──────────────────────────────────────────────────────
    final forecastFolder = folder('wesios_forecast', ru ? 'Wesi Forecast' : 'Wesi Forecast', parentId: 'wesios_modules');

    final forecastBody = '[${h1(ru ? 'Wesi Forecast — прогнозирование' : 'Wesi Forecast — Forecasting')},'
        '${p(ru ? 'Прогнозирование финансового состояния на основе исторических данных. Использует Holt-Winters + Monte-Carlo через Firebase Cloud Functions.' : 'Financial forecasting based on historical data. Uses Holt-Winters + Monte-Carlo via Firebase Cloud Functions.')},'
        '${h2(ru ? 'Holt-Winters формулы' : 'Holt-Winters Formulas')},'
        '${p(ru ? 'Тройное экспоненциальное сглаживание:' : 'Triple exponential smoothing:')},'
        '${embedTable(tableJson([
          [ru ? 'Компонент' : 'Component', ru ? 'Формула' : 'Formula', ru ? 'Описание' : 'Description'],
          ['Level', 'L_t = α·(Y_t/S_{t-m}) + (1-α)·(L_{t-1}+T_{t-1})', ru ? 'Уровень ряда' : 'Series level'],
          ['Trend', 'T_t = β·(L_t-L_{t-1}) + (1-β)·T_{t-1}', ru ? 'Тренд' : 'Trend'],
          ['Season', 'S_t = γ·(Y_t/L_t) + (1-γ)·S_{t-m}', ru ? 'Сезонность' : 'Seasonality'],
          ['Forecast', 'F_{t+h} = (L_t + h·T_t)·S_{t-m+h}', ru ? 'Прогноз' : 'Forecast'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Monte-Carlo симуляция' : 'Monte-Carlo Simulation')},'
        '${bullet(ru ? '5000 итераций случайного блуждания' : '5000 random walk iterations')},'
        '${bullet(ru ? 'B_{t+1} = B_t + N(μ, σ) — следующий баланс' : 'B_{t+1} = B_t + N(μ, σ) — next balance')},'
        '${bullet(ru ? 'P10 = 10-й перцентиль (пессимистичный)' : 'P10 = 10th percentile (pessimistic)')},'
        '${bullet(ru ? 'P50 = медиана (реалистичный)' : 'P50 = median (realistic)')},'
        '${bullet(ru ? 'P90 = 90-й перцентиль (оптимистичный)' : 'P90 = 90th percentile (optimistic)')},'
        '${embedChart(chartLinked('area', 'forecast', ru ? 'Прогноз баланса' : 'Balance Forecast'))},'
        '${br()},'
        '${h2(ru ? 'Anomaly Filter' : 'Anomaly Filter')},'
        '${p(ru ? 'Фильтр аномалий отсекает выбросы перед прогнозированием. Порог: |Z| > 2.0.' : 'Anomaly filter removes outliers before forecasting. Threshold: |Z| > 2.0.')}'
        ']';

    final forecast = article('wesios_forecast_article',
        ru ? 'Прогнозирование' : 'Forecasting',
        forecastBody,
        parentId: 'wesios_forecast',
        tags: ru ? ['forecast', 'прогноз', 'holt-winters', 'monte-carlo'] : ['forecast', 'holt-winters', 'monte-carlo']);

    // ─── Wesi Sandbox ───────────────────────────────────────────────────────
    final sandboxFolder = folder('wesios_sandbox', ru ? 'Wesi Sandbox' : 'Wesi Sandbox', parentId: 'wesios_modules');

    final sandboxBody = '[${h1(ru ? 'Wesi Sandbox — песочница' : 'Wesi Sandbox — Sandbox')},'
        '${p(ru ? 'Изолированное зеркало Treasury для тестирования сценариев. Данные Sandbox не влияют на реальный баланс.' : 'Isolated mirror of Treasury for scenario testing. Sandbox data does not affect real balance.')},'
        '${h2(ru ? 'Сценарии' : 'Scenarios')},'
        '${embedTable(tableJson([
          [ru ? 'Сценарий' : 'Scenario', ru ? 'Описание' : 'Description'],
          [ru ? 'Стартап' : 'Startup', ru ? 'Начальный капитал, рост расходов' : 'Initial capital, growing expenses'],
          [ru ? 'Фриланс' : 'Freelancer', ru ? 'Нерегулярный доход, волатильность' : 'Irregular income, volatility'],
          [ru ? 'Кризис' : 'Crisis', ru ? 'Резкое падение доходов' : 'Sharp income drop'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Клонирование из реального' : 'Clone from Real')},'
        '${p(ru ? 'Кнопка «Клонировать» копирует все транзакции из Treasury в Sandbox для анализа «что если».' : '«Clone» button copies all transactions from Treasury to Sandbox for «what if» analysis.')}'
        ']';

    final sandbox = article('wesios_sandbox_article',
        ru ? 'Песочница' : 'Sandbox',
        sandboxBody,
        parentId: 'wesios_sandbox',
        tags: ru ? ['sandbox', 'песочница', 'сценарии'] : ['sandbox', 'scenarios']);

    // ─── Wesi Shield ────────────────────────────────────────────────────────
    final shieldFolder = folder('wesios_shield', ru ? 'Wesi Shield' : 'Wesi Shield', parentId: 'wesios_modules');

    final shieldBody = '[${h1(ru ? 'Wesi Shield — безопасность' : 'Wesi Shield — Security')},'
        '${p(ru ? 'Модуль защиты данных и приватности.' : 'Data protection and privacy module.')},'
        '${h2(ru ? 'Privacy Mode' : 'Privacy Mode')},'
        '${bullet(ru ? 'Суммы скрыты (***)' : 'Amounts hidden (***)')},'
        '${bullet(ru ? 'Данные не отображаются в UI' : 'Data not shown in UI')},'
        '${h2(ru ? 'Biometric Lock' : 'Biometric Lock')},'
        '${bullet(ru ? 'Face ID / Touch ID / Fingerprint' : 'Face ID / Touch ID / Fingerprint')},'
        '${bullet(ru ? 'Защита входа в приложение' : 'App entry protection')},'
        '${h2(ru ? 'PIN-код' : 'PIN Code')},'
        '${bullet(ru ? 'SHA-256 + salt' : 'SHA-256 + salt')},'
        '${bullet(ru ? '4-6 цифр' : '4-6 digits')},'
        '${h2(ru ? 'ShieldGate' : 'ShieldGate')},'
        '${p(ru ? 'Промежуточный экран блокировки. Требует PIN или биометрию для доступа к данным.' : 'Intermediate lock screen. Requires PIN or biometrics to access data.')}'
        ']';

    final shield = article('wesios_shield_article',
        ru ? 'Безопасность' : 'Security',
        shieldBody,
        parentId: 'wesios_shield',
        tags: ru ? ['shield', 'безопасность', 'privacy', 'pin'] : ['shield', 'security', 'privacy', 'pin']);


    // ─── Wesi Tasks ─────────────────────────────────────────────────────────
    final tasksFolder = folder('wesios_tasks', ru ? 'Wesi Tasks' : 'Wesi Tasks', parentId: 'wesios_modules');

    final tasksBody = '[${h1(ru ? 'Wesi Tasks — управление задачами' : 'Wesi Tasks — Task Management')},'
        '${p(ru ? 'Система управления задачами с приоритетами, фильтрами и drag-drop.' : 'Task management system with priorities, filters and drag-drop.')},'
        '${h2(ru ? 'Приоритеты' : 'Priorities')},'
        '${embedTable(tableJson([
          [ru ? 'Приоритет' : 'Priority', ru ? 'Цвет' : 'Color', ru ? 'Значение' : 'Meaning'],
          [ru ? 'Критический' : 'Critical', ru ? 'Красный' : 'Red', ru ? 'Срочно, блокирует другие задачи' : 'Urgent, blocks other tasks'],
          [ru ? 'Высокий' : 'High', ru ? 'Оранжевый' : 'Orange', ru ? 'Важно, влияет на результат' : 'Important, affects outcome'],
          [ru ? 'Средний' : 'Medium', ru ? 'Жёлтый' : 'Yellow', ru ? 'Стандартный приоритет' : 'Standard priority'],
          [ru ? 'Низкий' : 'Low', ru ? 'Зелёный' : 'Green', ru ? 'Может подождать' : 'Can wait'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Статусы' : 'Statuses')},'
        '${bullet(ru ? 'todo — к выполнению' : 'todo — to do')},'
        '${bullet(ru ? 'in_progress — в работе' : 'in_progress — in progress')},'
        '${bullet(ru ? 'done — выполнено' : 'done — done')},'
        '${bullet(ru ? 'archived — в архиве' : 'archived — archived')},'
        '${embedChart(chartPie(ru ? 'Распределение задач' : 'Task Distribution',
          [ru ? 'Выполнено' : 'Done', ru ? 'В работе' : 'In Progress', ru ? 'К выполнению' : 'To Do', ru ? 'Архив' : 'Archived'],
          [45.0, 25.0, 20.0, 10.0]))},'
        '${br()},'
        '${h2(ru ? 'Интеграция с Calendar' : 'Calendar Integration')},'
        '${p(ru ? 'Задачи с дедлайном автоматически отображаются в календаре.' : 'Tasks with deadlines automatically appear in calendar.')}'
        ']';

    final tasks = article('wesios_tasks_article',
        ru ? 'Задачи' : 'Tasks',
        tasksBody,
        parentId: 'wesios_tasks',
        tags: ru ? ['tasks', 'задачи', 'приоритеты'] : ['tasks', 'priorities']);

    // ─── Wesi Calculator ────────────────────────────────────────────────────
    final calcFolder = folder('wesios_calculator', ru ? 'Wesi Calculator' : 'Wesi Calculator', parentId: 'wesios_modules');

    final calcBody = '[${h1(ru ? 'Wesi Calculator — калькулятор' : 'Wesi Calculator — Calculator')},'
        '${p(ru ? 'Научный калькулятор с историей вычислений и конвертацией валют.' : 'Scientific calculator with calculation history and currency conversion.')},'
        '${h2(ru ? 'Режимы' : 'Modes')},'
        '${bullet(ru ? 'Classic — стандартный калькулятор' : 'Classic — standard calculator')},'
        '${bullet(ru ? 'Scientific — тригонометрия, логарифмы, степени' : 'Scientific — trigonometry, logarithms, powers')},'
        '${h2(ru ? 'Функции' : 'Functions')},'
        '${embedTable(tableJson([
          [ru ? 'Функция' : 'Function', ru ? 'Описание' : 'Description'],
          ['sin, cos, tan', ru ? 'Тригонометрия' : 'Trigonometry'],
          ['log, ln', ru ? 'Логарифмы' : 'Logarithms'],
          ['x², x³, xʸ', ru ? 'Степени' : 'Powers'],
          ['√, ³√', ru ? 'Корни' : 'Roots'],
          ['π, e', ru ? 'Константы' : 'Constants'],
          ['!, %', ru ? 'Факториал, процент' : 'Factorial, percent'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'История' : 'History')},'
        '${p(ru ? 'Последние 50 вычислений сохраняются. Тап на историю — вставка в поле ввода.' : 'Last 50 calculations saved. Tap history — insert into input field.')}'
        ']';

    final calc = article('wesios_calc_article',
        ru ? 'Калькулятор' : 'Calculator',
        calcBody,
        parentId: 'wesios_calculator',
        tags: ru ? ['calculator', 'калькулятор', 'научный'] : ['calculator', 'scientific']);

    // ─── Wesi Calendar ──────────────────────────────────────────────────────
    final calendarFolder = folder('wesios_calendar', ru ? 'Wesi Calendar' : 'Wesi Calendar', parentId: 'wesios_modules');

    final calendarBody = '[${h1(ru ? 'Wesi Calendar — календарь' : 'Wesi Calendar — Calendar')},'
        '${p(ru ? 'Календарь с событиями из задач и транзакций.' : 'Calendar with events from tasks and transactions.')},'
        '${h2(ru ? 'Виды' : 'Views')},'
        '${bullet(ru ? 'Месяц — обзор всего месяца' : 'Month — full month overview')},'
        '${bullet(ru ? 'Неделя — детальный план' : 'Week — detailed plan')},'
        '${bullet(ru ? 'День — почасовой график' : 'Day — hourly schedule')},'
        '${h2(ru ? 'Цветные индикаторы' : 'Color Indicators')},'
        '${embedTable(tableJson([
          [ru ? 'Цвет' : 'Color', ru ? 'Источник' : 'Source'],
          [ru ? 'Синий' : 'Blue', ru ? 'Задачи с дедлайном' : 'Tasks with deadline'],
          [ru ? 'Зелёный' : 'Green', ru ? 'Доходы' : 'Income'],
          [ru ? 'Красный' : 'Red', ru ? 'Расходы' : 'Expenses'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Интеграция' : 'Integration')},'
        '${p(ru ? 'События из Tasks и Treasury автоматически появляются в календаре.' : 'Events from Tasks and Treasury automatically appear in calendar.')}'
        ']';

    final calendar = article('wesios_calendar_article',
        ru ? 'Календарь' : 'Calendar',
        calendarBody,
        parentId: 'wesios_calendar',
        tags: ru ? ['calendar', 'календарь', 'события'] : ['calendar', 'events']);

    // ─── Wesi Analytics ─────────────────────────────────────────────────────
    final analyticsFolder = folder('wesios_analytics', ru ? 'Wesi Analytics' : 'Wesi Analytics', parentId: 'wesios_modules');

    final analyticsBody = '[${h1(ru ? 'Wesi Analytics — аналитика' : 'Wesi Analytics — Analytics')},'
        '${p(ru ? 'Визуализация финансовых данных: графики, метрики, heatmap.' : 'Financial data visualization: charts, metrics, heatmap.')},'
        '${h2(ru ? 'Графики' : 'Charts')},'
        '${bullet(ru ? 'Bar — столбчатый (доходы/расходы по категориям)' : 'Bar — by category')},'
        '${bullet(ru ? 'Line — линейный (динамика баланса)' : 'Line — balance dynamics')},'
        '${bullet(ru ? 'Pie — круговой (структура расходов)' : 'Pie — expense structure')},'
        '${bullet(ru ? 'Heatmap — тепловая карта (активность по дням)' : 'Heatmap — daily activity')},'
        '${embedChart(chartLinked('bar', 'analytics', ru ? 'Аналитика по категориям' : 'Category Analytics'))},'
        '${br()},'
        '${h2(ru ? 'Метрики' : 'Metrics')},'
        '${embedTable(tableJson([
          [ru ? 'Метрика' : 'Metric', ru ? 'Описание' : 'Description'],
          [ru ? 'Общий баланс' : 'Total Balance', ru ? 'Сумма всех счетов' : 'Sum of all accounts'],
          [ru ? 'Доход за период' : 'Period Income', ru ? 'Сумма income-транзакций' : 'Sum of income transactions'],
          [ru ? 'Расход за период' : 'Period Expense', ru ? 'Сумма expense-транзакций' : 'Sum of expense transactions'],
          [ru ? 'Средний чек' : 'Average Check', ru ? 'Средняя сумма транзакции' : 'Average transaction amount'],
          [ru ? 'Топ категория' : 'Top Category', ru ? 'Категория с наибольшим расходом' : 'Category with highest expense'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Периоды' : 'Periods')},'
        '${bullet(ru ? 'Неделя' : 'Week')},'
        '${bullet(ru ? 'Месяц' : 'Month')},'
        '${bullet(ru ? 'Квартал' : 'Quarter')},'
        '${bullet(ru ? 'Год' : 'Year')}'
        ']';

    final analytics = article('wesios_analytics_article',
        ru ? 'Аналитика' : 'Analytics',
        analyticsBody,
        parentId: 'wesios_analytics',
        tags: ru ? ['analytics', 'аналитика', 'графики'] : ['analytics', 'charts']);


    // ─── Wesi Home ──────────────────────────────────────────────────────────
    final homeFolder = folder('wesios_home', ru ? 'Wesi Home' : 'Wesi Home', parentId: 'wesios_modules');

    final homeBody = '[${h1(ru ? 'Wesi Home — главный экран' : 'Wesi Home — Home Screen')},'
        '${p(ru ? 'Центральная панель с быстрым доступом ко всем модулям.' : 'Central dashboard with quick access to all modules.')},'
        '${h2(ru ? 'Компоненты' : 'Components')},'
        '${bullet(ru ? 'WesiClock — часы (digital / analog)' : 'WesiClock — digital / analog clock')},'
        '${bullet(ru ? 'Quick Actions — быстрые действия' : 'Quick Actions — quick actions')},'
        '${bullet(ru ? 'Balance Card — текущий баланс' : 'Balance Card — current balance')},'
        '${bullet(ru ? 'Calendar Preview — ближайшие события' : 'Calendar Preview — upcoming events')},'
        '${bullet(ru ? 'Tasks Preview — активные задачи' : 'Tasks Preview — active tasks')},'
        '${bullet(ru ? 'Global Search — поиск по всем модулям' : 'Global Search — search across all modules')},'
        '${bullet(ru ? 'Alerts — уведомления и напоминания' : 'Alerts — notifications and reminders')},'
        '${h2(ru ? 'Bottom Navigation' : 'Bottom Navigation')},'
        '${p(ru ? '5 табов через IndexedStack (без анимации переключения для скорости):' : '5 tabs via IndexedStack (no transition animation for speed):')},'
        '${embedTable(tableJson([
          [ru ? 'Таб' : 'Tab', ru ? 'Содержимое' : 'Content'],
          [ru ? 'Главная' : 'Home', ru ? 'Dashboard, часы, быстрые действия' : 'Dashboard, clock, quick actions'],
          [ru ? 'Treasury' : 'Treasury', ru ? 'Финансы, операции, прогноз' : 'Finance, operations, forecast'],
          [ru ? 'Задачи' : 'Tasks', ru ? 'Список задач, фильтры' : 'Task list, filters'],
          [ru ? 'Аналитика' : 'Analytics', ru ? 'Графики, метрики' : 'Charts, metrics'],
          [ru ? 'Ещё' : 'More', ru ? 'Календарь, Калькулятор, База знаний, Настройки' : 'Calendar, Calculator, Knowledge, Settings'],
        ]))},'
        '${br()},'
        '${embedChart(chartBar(ru ? 'Активность по модулям' : 'Module Activity',
          [ru ? 'Главная' : 'Home', ru ? 'Treasury' : 'Treasury', ru ? 'Задачи' : 'Tasks', ru ? 'Аналитика' : 'Analytics'],
          [95.0, 88.0, 72.0, 65.0]))}'
        ']';

    final home = article('wesios_home_article',
        ru ? 'Главный экран' : 'Home Screen',
        homeBody,
        parentId: 'wesios_home',
        tags: ru ? ['home', 'главный экран', 'dashboard'] : ['home', 'dashboard']);

    // ─── Wesi Profile ───────────────────────────────────────────────────────
    final profileFolder = folder('wesios_profile', ru ? 'Wesi Profile' : 'Wesi Profile', parentId: 'wesios_modules');

    final profileBody = '[${h1(ru ? 'Wesi Profile — профиль' : 'Wesi Profile — Profile')},'
        '${p(ru ? 'Управление профилем пользователя.' : 'User profile management.')},'
        '${h2(ru ? 'Аватарки' : 'Avatars')},'
        '${p(ru ? '8 пресетов аватарок + возможность загрузки своей:' : '8 avatar presets + custom upload:')},'
        '${embedTable(tableJson([
          [ru ? 'Пресет' : 'Preset', ru ? 'Описание' : 'Description'],
          ['1', ru ? 'Классический' : 'Classic'],
          ['2', ru ? 'Минималистичный' : 'Minimalist'],
          ['3', ru ? 'Геометрический' : 'Geometric'],
          ['4', ru ? 'Природный' : 'Nature'],
          ['5', ru ? 'Технологичный' : 'Tech'],
          ['6', ru ? 'Абстрактный' : 'Abstract'],
          ['7', ru ? 'Монохромный' : 'Monochrome'],
          ['8', ru ? 'Цветной' : 'Colorful'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'Founder Story' : 'Founder Story')},'
        '${p(ru ? 'История создания WesiOS с Easter-egg (лого смерти с косой в разделе истории).' : 'WesiOS creation story with Easter-egg (death logo with scythe in history section).')}'
        ']';

    final profile = article('wesios_profile_article',
        ru ? 'Профиль' : 'Profile',
        profileBody,
        parentId: 'wesios_profile',
        tags: ru ? ['profile', 'профиль', 'аватар'] : ['profile', 'avatar']);

    // ─── Wesi Settings ──────────────────────────────────────────────────────
    final settingsFolder = folder('wesios_settings', ru ? 'Wesi Settings' : 'Wesi Settings', parentId: 'wesios_modules');

    final settingsBody = '[${h1(ru ? 'Wesi Settings — настройки' : 'Wesi Settings — Settings')},'
        '${p(ru ? 'Глобальные настройки приложения.' : 'Global application settings.')},'
        '${h2(ru ? 'Язык' : 'Language')},'
        '${bullet('RU — русский')},'
        '${bullet('EN — English')},'
        '${h2(ru ? 'Тема' : 'Theme')},'
        '${bullet(ru ? 'Тёмная (Carbon)' : 'Dark (Carbon)')},'
        '${bullet(ru ? 'Светлая (White/Grey/Blue)' : 'Light (White/Grey/Blue)')},'
        '${h2(ru ? 'Firebase' : 'Firebase')},'
        '${bullet(ru ? 'Подключение к проекту Firebase' : 'Connect to Firebase project')},'
        '${bullet(ru ? 'Cloud Functions — прогнозирование' : 'Cloud Functions — forecasting')},'
        '${h2(ru ? 'GitHub' : 'GitHub')},'
        '${bullet(ru ? 'Токен для доступа к репозиторию' : 'Token for repository access')},'
        '${bullet(ru ? 'OTA обновления через Releases' : 'OTA updates via Releases')},'
        '${h2(ru ? 'Безопасность' : 'Security')},'
        '${bullet(ru ? 'PIN-код' : 'PIN code')},'
        '${bullet(ru ? 'Биометрия' : 'Biometrics')},'
        '${bullet(ru ? 'Privacy Mode' : 'Privacy Mode')}'
        ']';

    final settings = article('wesios_settings_article',
        ru ? 'Настройки' : 'Settings',
        settingsBody,
        parentId: 'wesios_settings',
        tags: ru ? ['settings', 'настройки', 'тема', 'язык'] : ['settings', 'theme', 'language']);

    // ─── Knowledge Base (self-reference) ────────────────────────────────────
    final kbFolder = folder('wesios_kb', ru ? 'Knowledge Base' : 'Knowledge Base', parentId: 'wesios_modules');

    final kbBody = '[${h1(ru ? 'Knowledge Base — база знаний' : 'Knowledge Base — Knowledge Base')},'
        '${p(ru ? 'Система документации с rich-редактором, иерархией и связанными данными.' : 'Documentation system with rich editor, hierarchy and linked data.')},'
        '${h2(ru ? 'Возможности редактора' : 'Editor Features')},'
        '${bullet(ru ? 'Форматирование: bold, italic, underline, strike' : 'Formatting: bold, italic, underline, strike')},'
        '${bullet(ru ? 'Заголовки H1/H2/H3' : 'Headings H1/H2/H3')},'
        '${bullet(ru ? 'Списки: bullet, numbered' : 'Lists: bullet, numbered')},'
        '${bullet(ru ? 'Ссылки: https:// и wesios://article/ID' : 'Links: https:// and wesios://article/ID')},'
        '${bullet(ru ? 'Изображения: URL и с устройства' : 'Images: URL and from device')},'
        '${bullet(ru ? 'Видео: URL и с устройства' : 'Video: URL and from device')},'
        '${bullet(ru ? 'Аудио: URL и с устройства' : 'Audio: URL and from device')},'
        '${bullet(ru ? 'Таблицы: диалог строки×столбцы' : 'Tables: dialog rows×columns')},'
        '${bullet(ru ? 'Графики: bar, line, pie, area' : 'Charts: bar, line, pie, area')},'
        '${bullet(ru ? 'Emoji: 300+ смайликов' : 'Emoji: 300+ emojis')},'
        '${h2(ru ? 'Иерархия' : 'Hierarchy')},'
        '${p(ru ? 'Статьи организованы в дерево: папки (isFolder) содержат дочерние статьи (parentId).' : 'Articles organized in tree: folders (isFolder) contain child articles (parentId).')},'
        '${embedChart(chartBar(ru ? 'Структура базы знаний' : 'Knowledge Base Structure',
          [ru ? 'Модули' : 'Modules', ru ? 'Сервисы' : 'Services', ru ? 'Архитектура' : 'Architecture'],
          [12.0, 8.0, 5.0]))}'
        ']';

    final kb = article('wesios_kb_article',
        ru ? 'База знаний' : 'Knowledge Base',
        kbBody,
        parentId: 'wesios_kb',
        tags: ru ? ['knowledge', 'база знаний', 'редактор'] : ['knowledge', 'editor']);


    // ═══════════════════════════════════════════════════════════════════════
    //  FOLDER: Системные сервисы / System Services
    // ═══════════════════════════════════════════════════════════════════════

    final servicesFolder = folder('wesios_services', ru ? 'Системные сервисы' : 'System Services', parentId: 'wesios_root');

    // ─── WesiLocale ─────────────────────────────────────────────────────────
    final localeArticle = article('wesios_locale',
        ru ? 'WesiLocale — локализация' : 'WesiLocale — Localization',
        '[${h1(ru ? 'WesiLocale' : 'WesiLocale')},'
        '${p(ru ? 'Система локализации RU/EN с Hive persistence.' : 'RU/EN localization system with Hive persistence.')},'
        '${h2(ru ? 'Ключевые методы' : 'Key Methods')},'
        '${embedTable(tableJson([
          [ru ? 'Метод' : 'Method', ru ? 'Описание' : 'Description'],
          ['get(key)', ru ? 'Получить строку по ключу' : 'Get string by key'],
          ['setLanguage(lang)', ru ? 'Сменить язык' : 'Change language'],
          ['isRussian', ru ? 'true = RU' : 'true = RU'],
          ['load()', ru ? 'Загрузить из Hive' : 'Load from Hive'],
        ]))},'
        '${br()},'
        '${p(ru ? '80+ строк на каждом языке.' : '80+ strings per language.')}'
        ']',
        parentId: 'wesios_services',
        tags: ru ? ['locale', 'локализация', 'ru', 'en'] : ['locale', 'localization']);

    // ─── CurrencyService ────────────────────────────────────────────────────
    final currencyArticle = article('wesios_currency',
        ru ? 'CurrencyService — валюты' : 'CurrencyService — Currencies',
        '[${h1(ru ? 'CurrencyService' : 'CurrencyService')},'
        '${p(ru ? 'Мультивалютность и конвертация.' : 'Multi-currency and conversion.')},'
        '${h2(ru ? 'Поддерживаемые валюты' : 'Supported Currencies')},'
        '${embedTable(tableJson([
          [ru ? 'Валюта' : 'Currency', ru ? 'Код' : 'Code', ru ? 'Символ' : 'Symbol'],
          [ru ? 'Рубль' : 'Ruble', 'RUB', '₽'],
          [ru ? 'Доллар' : 'Dollar', 'USD', r'$'],
          [ru ? 'Евро' : 'Euro', 'EUR', '€'],
          [ru ? 'Фунт' : 'Pound', 'GBP', '£'],
          [ru ? 'Юань' : 'Yuan', 'CNY', '¥'],
          [ru ? 'Гривна' : 'Hryvnia', 'UAH', '₴'],
          [ru ? 'Бел. рубль' : 'Bel. Ruble', 'BYN', 'Br'],
          [ru ? 'Тенге' : 'Tenge', 'KZT', '₸'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'API курсов' : 'Exchange API')},'
        '${p(ru ? 'exchangerate.host + fallback на зашитые курсы.' : 'exchangerate.host + fallback to hardcoded rates.')}'
        ']',
        parentId: 'wesios_services',
        tags: ru ? ['currency', 'валюты', 'конвертация'] : ['currency', 'conversion']);

    // ─── AppUpdateService ───────────────────────────────────────────────────
    final updateArticle = article('wesios_update',
        ru ? 'AppUpdateService — обновления' : 'AppUpdateService — Updates',
        '[${h1(ru ? 'AppUpdateService' : 'AppUpdateService')},'
        '${p(ru ? 'OTA обновления через GitHub Releases.' : 'OTA updates via GitHub Releases.')},'
        '${h2(ru ? 'Процесс' : 'Process')},'
        '${numbered(ru ? 'Проверка app-manifest.json' : 'Check app-manifest.json')},'
        '${numbered(ru ? 'Сравнение версий (semver)' : 'Version comparison (semver)')},'
        '${numbered(ru ? 'Скачивание новой сборки' : 'Download new build')},'
        '${numbered(ru ? 'Установка' : 'Install')},'
        '${h2(ru ? 'Файлы релиза' : 'Release Files')},'
        '${embedTable(tableJson([
          [ru ? 'Файл' : 'File', ru ? 'Платформа' : 'Platform'],
          ['wesios-windows-x64.zip', 'Windows'],
          ['wesios-android.apk', 'Android'],
          ['app-manifest.json', 'OTA'],
        ]))}'
        ']',
        parentId: 'wesios_services',
        tags: ru ? ['update', 'обновления', 'ota'] : ['update', 'ota']);

    // ═══════════════════════════════════════════════════════════════════════
    //  FOLDER: Архитектура / Architecture
    // ═══════════════════════════════════════════════════════════════════════

    final archFolder = folder('wesios_arch', ru ? 'Архитектура' : 'Architecture', parentId: 'wesios_root');

    final archBody = '[${h1(ru ? 'Архитектура WesiOS' : 'WesiOS Architecture')},'
        '${h2(ru ? 'Принципы' : 'Principles')},'
        '${bullet(ru ? 'Локальное хранение — Hive' : 'Local storage — Hive')},'
        '${bullet(ru ? 'Опциональное облако — Firebase' : 'Optional cloud — Firebase')},'
        '${bullet(ru ? 'Мультивалютность — CurrencyService' : 'Multi-currency — CurrencyService')},'
        '${bullet(ru ? 'Темизация — ThemeNotifier + AnimatedTheme' : 'Theming — ThemeNotifier + AnimatedTheme')},'
        '${bullet(ru ? 'Локализация — WesiLocale + Hive' : 'Localization — WesiLocale + Hive')},'
        '${h2(ru ? 'Hive typeId' : 'Hive typeId')},'
        '${embedTable(tableJson([
          [ru ? 'typeId' : 'typeId', ru ? 'Модель' : 'Model'],
          ['1', 'TransactionModel'],
          ['2', 'CurrencyRatesModel'],
          ['3', 'AppUpdateModel'],
          ['10', 'TaskModel'],
          ['11', 'CalendarEventModel'],
          ['12', 'CRMActionModel'],
          ['13', 'AudioVaultItemModel'],
          ['14', 'AIMessageModel'],
          ['15', 'AIChatSessionModel'],
          ['16', 'ArticleSection'],
          ['17', 'ArticleModel'],
        ]))},'
        '${br()},'
        '${h2(ru ? 'CI/CD' : 'CI/CD')},'
        '${bullet(ru ? 'build.yml — Windows + Android CI' : 'build.yml — Windows + Android CI')},'
        '${bullet(ru ? 'release-app.yml — релизные сборки' : 'release-app.yml — release builds')},'
        '${bullet(ru ? 'Android подпись через Secrets' : 'Android signing via Secrets')}'
        ']';

    final arch = article('wesios_arch_article',
        ru ? 'Обзор архитектуры' : 'Architecture Overview',
        archBody,
        parentId: 'wesios_arch',
        tags: ru ? ['architecture', 'архитектура', 'hive'] : ['architecture', 'hive']);

    // ═══════════════════════════════════════════════════════════════════════
    //  ДЕНЬГИ (finance deep dive)
    // ═══════════════════════════════════════════════════════════════════════

    final moneyFolder = folder('wesios_money', ru ? 'Деньги' : 'Money', parentId: 'wesios_kb');

    final debtsBody = '[${h1(ru ? 'Долги: как гасить и не утонуть' : 'Debt: How to Pay Off Without Drowning')},'
        '${p(ru ? 'Долги — не приговор, но требуют системы. Главное правило: не платить всем понемногу, а закрывать по приоритету.' : 'Debt is not a sentence, but it needs a system. The main rule: do not pay everyone a little, but close by priority.')},'
        '${br()},'
        '${h2(ru ? 'Снежный ком vs Лавина' : 'Snowball vs Avalanche')},'
        '${p(ru ? 'Два проверенных метода. Выбирай тот, который лучше работает для твоей психики:' : 'Two proven methods. Choose the one that works better for your psyche:')},'
        '${h3(ru ? 'Снежный ком (Snowball)' : 'Snowball')},'
        '${bullet(ru ? 'Сортируй долги от меньшего к большему' : 'Sort debts from smallest to largest')},'
        '${bullet(ru ? 'Закрывай самый маленький первым — быстрая победа даёт мотивацию' : 'Close the smallest first — a quick win gives motivation')},'
        '${bullet(ru ? 'Перекинь освободившийся платёж на следующий по списку' : 'Redirect the freed payment to the next one on the list')},'
        '${bullet(ru ? 'Плюс: эмоциональная разрядка. Минус: переплата по процентам выше' : 'Plus: emotional relief. Minus: higher interest overpayment')},'
        '${h3(ru ? 'Лавина (Avalanche)' : 'Avalanche')},'
        '${bullet(ru ? 'Сортируй долги от высокой ставки к низкой' : 'Sort debts from highest rate to lowest')},'
        '${bullet(ru ? 'Закрывай самый дорогой первым — экономишь больше денег' : 'Close the most expensive first — you save more money')},'
        '${bullet(ru ? 'Плюс: меньше переплата. Минус: первые результаты медленнее' : 'Plus: less overpayment. Minus: first results are slower')},'
        '${br()},'
        '${h2(ru ? 'Когда рефинансировать' : 'When to Refinance')},'
        '${p(ru ? 'Рефинансирование имеет смысл, если:' : 'Refinancing makes sense if:')},'
        '${bullet(ru ? 'Новая ставка минимум на 2–3% ниже текущей' : 'New rate is at least 2–3% lower than current')},'
        '${bullet(ru ? 'Срок остался достаточно длинным (от 2 лет) — иначе экономия съест комиссия' : 'Remaining term is long enough (2+ years) — otherwise fees eat savings')},'
        '${bullet(ru ? 'Нет скрытых штрафов за досрочное погашение' : 'No hidden penalties for early repayment')},'
        '${bullet(ru ? 'Пересчитай полную стоимость: новый кредит + комиссии + страховки' : 'Recalculate total cost: new loan + fees + insurance')},'
        '${br()},'
        '${h2(ru ? 'Чего избегать' : 'What to Avoid')},'
        '${bullet(ru ? 'Не бери новый кредит, чтобы закрыть старый — это круговая зависимость' : 'Do not take a new loan to close the old one — it is circular dependency')},'
        '${bullet(ru ? 'Не игнорируй микрозаймы — их ставки 300%+ годовых' : 'Do not ignore microloans — their rates are 300%+ annually')},'
        '${bullet(ru ? 'Не прячь голову в песок: чем раньше признаешь проблему, тем больше вариантов' : 'Do not bury your head in the sand: the earlier you admit the problem, the more options')},'
        '${bullet(ru ? 'Не отдавай последние деньги на долги — оставь подушку безопасности' : 'Do not give your last money to debts — keep a safety cushion')}'
        ']';

    final debts = article('wesios_debts', ru ? 'Долги: как гасить' : 'Debt: How to Pay Off', debtsBody,
        parentId: 'wesios_money',
        tags: ru ? ['долги', 'финансы', 'снежный ком', 'лавина'] : ['debt', 'finance', 'snowball', 'avalanche']);

    final insuranceBody = '[${h1(ru ? 'Страхование: что реально нужно' : 'Insurance: What You Actually Need')},'
        '${p(ru ? 'Страхование — это не инвестиция. Это защита от катастрофы. Плати только за то, что реально снизит риск краха.' : 'Insurance is not an investment. It is protection against catastrophe. Pay only for what actually reduces the risk of ruin.')},'
        '${br()},'
        '${h2(ru ? 'Что реально нужно' : 'What You Actually Need')},'
        '${h3(ru ? 'Медицинское (ОМС + ДМС)' : 'Health Insurance')},'
        '${bullet(ru ? 'ОМС — база, бесплатно. Покрывает экстренную помощь и госпитализацию' : 'Public health insurance — base, free. Covers emergency care and hospitalization')},'
        '${bullet(ru ? 'ДМС — если хочешь выбор врачей, быструю диагностику, стоматологию' : 'Private health insurance — if you want choice of doctors, fast diagnostics, dentistry')},'
        '${bullet(ru ? 'Проверь: покрывает ли заграницу, если ездишь' : 'Check: does it cover abroad if you travel')},'
        '${h3(ru ? 'Страхование жизни (если есть иждивенцы)' : 'Life Insurance (if you have dependents)')},'
        '${bullet(ru ? 'Нужно, если от твоего дохода зависят дети, родители, партнёр' : 'Needed if children, parents, or partner depend on your income')},'
        '${bullet(ru ? 'Сумма = 5–10 годовых расходов семьи' : 'Amount = 5–10 annual family expenses')},'
        '${bullet(ru ? 'Выбирай срочное (term), а не накопительное — дешевле и прозрачнее' : 'Choose term, not whole life — cheaper and more transparent')},'
        '${h3(ru ? 'Имущество (квартира, авто)' : 'Property (apartment, car)')},'
        '${bullet(ru ? 'Квартира: полис от затопления, пожара, кражи. Особенно если ипотека' : 'Apartment: policy against flooding, fire, theft. Especially if mortgage')},'
        '${bullet(ru ? 'Авто: ОСАГО обязательно. КАСКО — если машина дороже 3 годовых доходов' : 'Car: mandatory liability insurance. Comprehensive — if car is worth > 3 annual incomes')},'
        '${br()},'
        '${h2(ru ? 'Что часто лишнее' : 'What Is Often Unnecessary')},'
        '${bullet(ru ? 'Накопительное страхование жизни — дорого, доходность ниже депозита' : 'Whole life insurance — expensive, returns lower than deposits')},'
        '${bullet(ru ? 'Страхование от потери работы — обычно много исключений, сложно получить выплату' : 'Job loss insurance — usually many exclusions, hard to claim')},'
        '${bullet(ru ? 'Страхование телефона/гаджетов — часто дороже ремонта, много отказов' : 'Phone/gadget insurance — often more expensive than repair, many rejections')},'
        '${bullet(ru ? 'Страхование путешествий «на всякий» — читай мелкий шрифт, часто не покрывает' : 'Travel insurance "just in case" — read the fine print, often does not cover')},'
        '${br()},'
        '${h2(ru ? 'Правило 80/20' : 'The 80/20 Rule')},'
        '${p(ru ? '80% защиты даёт 20% страховок: медицина + жизнь (если есть иждивенцы) + имущество. Остальное — маркетинг.' : '80% of protection comes from 20% of insurances: health + life (if dependents) + property. The rest is marketing.')}'
        ']';

    final insurance = article('wesios_insurance', ru ? 'Страхование' : 'Insurance', insuranceBody,
        parentId: 'wesios_money',
        tags: ru ? ['страхование', 'финансы', 'защита'] : ['insurance', 'finance', 'protection']);

    final pensionBody = '[${h1(ru ? 'Пенсия и длинный горизонт' : 'Pension and Long-Term Planning')},'
        '${p(ru ? 'Даже если тебе 25 — пенсия твоя личная ответственность. Государственная пенсия — дополнение, а не основа.' : 'Even if you are 25 — pension is your personal responsibility. State pension is a supplement, not a foundation.')},'
        '${br()},'
        '${h2(ru ? 'Простые шаги без сложных терминов' : 'Simple Steps Without Complex Terms')},'
        '${numbered(ru ? 'Начни с 5% от дохода — незаметно, но через 10 лет накопится серьёзная сумма' : 'Start with 5% of income — unnoticeable, but over 10 years it accumulates significantly')},'
        '${numbered(ru ? 'Увеличивай на 1% каждый год — пока не дойдёшь до 15–20%' : 'Increase by 1% each year — until you reach 15–20%')},'
        '${numbered(ru ? 'Используй налоговый вычет: в РФ ИИС тип Б даёт вычет 13% от взносов' : 'Use tax deduction: in Russia IIS type B gives 13% deduction on contributions')},'
        '${numbered(ru ? 'Не клади всё в один инструмент: раздели между депозитом, облигациями, фондами' : 'Do not put everything in one instrument: split between deposits, bonds, funds')},'
        '${numbered(ru ? 'Пересматривай план раз в год — жизнь меняется, план тоже должен' : 'Review the plan annually — life changes, the plan should too')},'
        '${br()},'
        '${h2(ru ? 'Правило 72' : 'The Rule of 72')},'
        '${p(ru ? 'Чтобы узнать, за сколько лет капитал удвоится — раздели 72 на процент доходности:' : 'To know how many years it takes to double capital — divide 72 by the return rate:')},'
        '${bullet(ru ? 'Депозит 6% → 72 / 6 = 12 лет на удвоение' : 'Deposit 6% → 72 / 6 = 12 years to double')},'
        '${bullet(ru ? 'Облигации 8% → 72 / 8 = 9 лет' : 'Bonds 8% → 72 / 8 = 9 years')},'
        '${bullet(ru ? 'Индексный фонд 10% → 72 / 10 = 7.2 года' : 'Index fund 10% → 72 / 10 = 7.2 years')},'
        '${br()},'
        '${h2(ru ? 'Главная ошибка' : 'The Biggest Mistake')},'
        '${p(ru ? 'Ждать «когда будет больше денег». Начни сейчас с любой суммы. Время — главный актив, не деньги.' : 'Waiting for "when there is more money". Start now with any amount. Time is the main asset, not money.')}'
        ']';

    final pension = article('wesios_pension', ru ? 'Пенсия и длинный горизонт' : 'Pension and Long-Term', pensionBody,
        parentId: 'wesios_money',
        tags: ru ? ['пенсия', 'инвестиции', 'долгосрочка'] : ['pension', 'investments', 'long-term']);

    final moneyPsychBody = '[${h1(ru ? 'Психология денег' : 'Money Psychology')},'
        '${p(ru ? 'Деньги — это не только цифры. Это эмоции, убеждения, страхи. Понять свою психологию — важнее любого бюджета.' : 'Money is not just numbers. It is emotions, beliefs, fears. Understanding your psychology is more important than any budget.')},'
        '${br()},'
        '${h2(ru ? 'Страх бедности' : 'Fear of Poverty')},'
        '${p(ru ? 'Если ты постоянно боишься остаться без денег — даже при хорошем доходе:' : 'If you constantly fear being broke — even with good income:')},'
        '${bullet(ru ? 'Признай: страх редко связан с реальной угрозой, чаще — с детским опытом' : 'Admit: fear is rarely tied to real threat, more often to childhood experience')},'
        '${bullet(ru ? 'Создай подушку безопасности: 3–6 месяцев расходов — это лечит тревогу лучше любого шопинга' : 'Build a safety cushion: 3–6 months of expenses — it cures anxiety better than any shopping')},'
        '${bullet(ru ? 'Веди учёт в Wesi Treasury — конкретные цифры снимают тревожную неопределённость' : 'Track in Wesi Treasury — concrete numbers remove anxious uncertainty')},'
        '${br()},'
        '${h2(ru ? '«Я этого заслужил»' : '"I Deserve This"')},'
        '${p(ru ? 'Классическая ловушка: тяжёлая неделя → «надо себя побаловать» → импульсивная покупка → сожаление.' : 'Classic trap: hard week → "need to treat myself" → impulse purchase → regret.')},'
        '${bullet(ru ? 'Отложи покупку на 48 часов — 80% желаний пройдут' : 'Postpone the purchase for 48 hours — 80% of desires will pass')},'
        '${bullet(ru ? 'Задай вопрос: «Я покупаю вещь или эмоцию?»' : 'Ask: "Am I buying a thing or an emotion?"')},'
        '${bullet(ru ? 'Создай «фонд удовольствий» в Treasury — фиксированная сумма на спонтанность, но в рамках' : 'Create a "fun fund" in Treasury — fixed amount for spontaneity, but within limits')},'
        '${br()},'
        '${h2(ru ? 'Покупки из тревоги' : 'Anxiety Purchases')},'
        '${p(ru ? 'Когда нервничаешь — мозг ищет быструю награду. Шопинг даёт дофамин, но кратковременный.' : 'When nervous — the brain seeks a quick reward. Shopping gives dopamine, but short-lived.')},'
        '${bullet(ru ? 'Замени покупку на прогулку, душ, разговор с другом — те же 20 минут, но без минуса на счету' : 'Replace shopping with a walk, shower, talk with a friend — same 20 minutes, but no account minus')},'
        '${bullet(ru ? 'Если всё же купил — не бей себя. Запиши в Treasury, проанализируй через месяц' : 'If you still bought — do not beat yourself up. Log it in Treasury, analyze in a month')},'
        '${br()},'
        '${h2(ru ? 'Практика: неделя осознанности' : 'Practice: Week of Awareness')},'
        '${numbered(ru ? 'Записывай каждую покупку в Treasury сразу' : 'Log every purchase in Treasury immediately')},'
        '${numbered(ru ? 'Вечером отмечай: что чувствовал перед покупкой?' : 'In the evening note: what did you feel before the purchase?')},'
        '${numbered(ru ? 'В конце недели посмотри паттерны — увидишь триггеры' : 'At the end of the week look at patterns — you will see triggers')}'
        ']';

    final moneyPsych = article('wesios_money_psych', ru ? 'Психология денег' : 'Money Psychology', moneyPsychBody,
        parentId: 'wesios_money',
        tags: ru ? ['психология', 'деньги', 'тревога', 'привычки'] : ['psychology', 'money', 'anxiety', 'habits']);
    // ═══════════════════════════════════════════════════════════════════════
    //  РАБОТА И НАВЫКИ
    // ═══════════════════════════════════════════════════════════════════════

    final workFolder = folder('wesios_work', ru ? 'Работа и навыки' : 'Work & Skills', parentId: 'wesios_kb');

    final learningBody = '[${h1(ru ? 'Обучение без выгорания' : 'Learning Without Burnout')},'
        '${p(ru ? 'Новые навыки — инвестиция. Но если учиться неправильно, выгорание придёт быстрее результата.' : 'New skills are an investment. But if you learn incorrectly, burnout comes faster than results.')},'
        '${br()},'
        '${h2(ru ? 'Как выбирать курсы' : 'How to Choose Courses')},'
        '${bullet(ru ? 'Сначала практика — потом теория. Не читай 500 страниц, если ещё не написал строчку кода' : 'Practice first — theory later. Do not read 500 pages if you have not written a line of code')},'
        '${bullet(ru ? 'Проверяй автора: делал ли он то, чему учит? Или только продаёт?' : 'Check the author: have they done what they teach? Or only selling?')},'
        '${bullet(ru ? 'Смотри отзывы с конкретикой: «стало проще» — плохо; «автоматизировал отчётность за 2 часа» — хорошо' : 'Look for specific reviews: "became easier" is bad; "automated reporting in 2 hours" is good')},'
        '${bullet(ru ? 'Не покупай курс «на потом» — начни с бесплатного материала, убедись, что тема тебе нужна' : 'Do not buy a course "for later" — start with free material, make sure the topic is needed')},'
        '${br()},'
        '${h2(ru ? 'Практика vs теория' : 'Practice vs Theory')},'
        '${p(ru ? 'Правило 70/20/10: 70% практики, 20% обучения у других, 10% теории. Большинство делают наоборот.' : 'Rule 70/20/10: 70% practice, 20% learning from others, 10% theory. Most do the opposite.')},'
        '${bullet(ru ? 'Проектный подход: учись на реальном проекте, даже если маленьком' : 'Project approach: learn on a real project, even if small')},'
        '${bullet(ru ? 'Принцип Pomodoro: 25 минут практики, 5 минут перерыв. Не 3 часа залипания' : 'Pomodoro principle: 25 minutes practice, 5 minutes break. Not 3 hours of zoning out')},'
        '${bullet(ru ? 'Сразу применяй: прочитал про паттерн — используй в текущем коде, не «запомнишь на потом»' : 'Apply immediately: read about a pattern — use it in current code, do not "remember for later"')},'
        '${br()},'
        '${h2(ru ? 'Портфолио' : 'Portfolio')},'
        '${p(ru ? 'Портфолио — это не красивые скриншоты. Это доказательство, что ты можешь.' : 'Portfolio is not pretty screenshots. It is proof that you can.')},'
        '${bullet(ru ? '3–5 проектов лучше, чем 20 слабых. Выбирай лучшее' : '3–5 projects are better than 20 weak ones. Choose the best')},'
        '${bullet(ru ? 'Описывай задачу → решение → результат (цифры!). «Сделал» — плохо; «сократил время на 40%» — хорошо' : 'Describe problem → solution → result (numbers!). "Did" is bad; "reduced time by 40%" is good')},'
        '${bullet(ru ? 'GitHub — обязательно. Даже если приватный репозиторий, покажи структуру и README' : 'GitHub is mandatory. Even if private repo, show structure and README')},'
        '${bullet(ru ? 'Обновляй раз в квартал — устаревшее портфолио хуже, чем никакого' : 'Update quarterly — outdated portfolio is worse than none')}'
        ']';

    final learning = article('wesios_learning', ru ? 'Обучение без выгорания' : 'Learning Without Burnout', learningBody,
        parentId: 'wesios_work',
        tags: ru ? ['обучение', 'навыки', 'портфолио', 'курсы'] : ['learning', 'skills', 'portfolio', 'courses']);

    final careerChangeBody = '[${h1(ru ? 'Смена профессии: первые шаги' : 'Career Change: First Steps')},'
        '${p(ru ? 'Смена профессии — это марафон, не спринт. Главное: не бросать текущий доход, пока новый не подтверждён.' : 'Career change is a marathon, not a sprint. The key: do not quit current income until the new one is confirmed.')},'
        '${br()},'
        '${h2(ru ? 'Параллельный переход' : 'Parallel Transition')},'
        '${numbered(ru ? 'Определи, какие навыки новой профессии пересекаются с текущей — это твой мост' : 'Identify which skills of the new profession overlap with current — that is your bridge')},'
        '${numbered(ru ? 'Начни с 5–10 часов в неделю — вечером, выходные. Не жги мосты' : 'Start with 5–10 hours a week — evenings, weekends. Do not burn bridges')},'
        '${numbered(ru ? 'Возьми первый проект за символическую сумму или бесплатно — для портфолио и обратной связи' : 'Take the first project for symbolic pay or free — for portfolio and feedback')},'
        '${numbered(ru ? 'Найди ментора — человек, который уже прошёл этот путь' : 'Find a mentor — someone who has already walked this path')},'
        '${numbered(ru ? 'Когда новый доход покрывает 50–70% текущего — можно думать о полном переходе' : 'When new income covers 50–70% of current — you can consider full transition')},'
        '${br()},'
        '${h2(ru ? 'Финансовые подушки' : 'Financial Cushions')},'
        '${bullet(ru ? 'Минимум: 6 месяцев расходов — если переход затянется' : 'Minimum: 6 months of expenses — if transition takes longer')},'
        '${bullet(ru ? 'Идеал: 12 месяцев — спокойно учишься, не паникуешь' : 'Ideal: 12 months — you learn calmly, without panic')},'
        '${bullet(ru ? 'Отдельный счёт: «деньги на переход» — не трогай на бытовые траты' : 'Separate account: "transition money" — do not touch for daily expenses')},'
        '${bullet(ru ? 'Учти: первые 3–6 месяцев новой профессии доход может быть ниже' : 'Consider: first 3–6 months of new profession income may be lower')},'
        '${br()},'
        '${h2(ru ? 'Красные флаги' : 'Red Flags')},'
        '${bullet(ru ? '«Бросай всё сейчас» — кто так говорит, не платит твои счета' : '"Quit everything now" — whoever says that does not pay your bills')},'
        '${bullet(ru ? '«За 3 месяца станешь senior» — ложь, не верь' : '"Become senior in 3 months" — lie, do not believe')},'
        '${bullet(ru ? '«Все так делают» — твой путь уникален, не копируй слепо' : '"Everyone does it" — your path is unique, do not copy blindly')}'
        ']';

    final careerChange = article('wesios_career', ru ? 'Смена профессии' : 'Career Change', careerChangeBody,
        parentId: 'wesios_work',
        tags: ru ? ['карьера', 'переход', 'навыки', 'финансы'] : ['career', 'transition', 'skills', 'finance']);

    final negotiationsBody = '[${h1(ru ? 'Переговоры: зарплата, ставки, условия' : 'Negotiations: Salary, Rates, Terms')},'
        '${p(ru ? 'Переговоры — не конфликт, а поиск точки, где обе стороны выигрывают. Готовься заранее.' : 'Negotiations are not conflict, but finding a point where both sides win. Prepare in advance.')},'
        '${br()},'
        '${h2(ru ? 'Скрипты' : 'Scripts')},'
        '${h3(ru ? 'Зарплата' : 'Salary')},'
        '${p(ru ? 'Когда спрашивают ожидания:' : 'When asked about expectations:')},'
        '${bullet(ru ? '«Я ищу рыночную компенсацию для этого уровня. Можете поделиться вилкой бюджета?» — перекладываешь мяч' : '"I am looking for market compensation for this level. Can you share the budget range?" — you pass the ball')},'
        '${bullet(ru ? '«Мой текущий пакет X. Для перехода рассматриваю Y+» — конкретика, но гибкость' : '"My current package is X. For a move I consider Y+" — specifics, but flexibility')},'
        '${bullet(ru ? 'Не называй число первым, если можешь избежать. Информация — валюта' : 'Do not name a number first if you can avoid it. Information is currency')},'
        '${h3(ru ? 'Ставки фрилансера' : 'Freelance Rates')},'
        '${bullet(ru ? 'Посчитай желаемый годовой доход → раздели на 1000 рабочих часов → это твоя ставка' : 'Calculate desired annual income → divide by 1000 working hours → that is your rate')},'
        '${bullet(ru ? 'Добавь 20% на непредвиденное: правки, задержки, переработки' : 'Add 20% for unforeseen: revisions, delays, overtime')},'
        '${bullet(ru ? 'Никогда не опускай ставку «чтобы взять проект» — клиент, который не ценит твою цену, не ценит и работу' : 'Never lower your rate "to get the project" — a client who does not value your price does not value your work')},'
        '${br()},'
        '${h2(ru ? 'Принципы' : 'Principles')},'
        '${bullet(ru ? 'Молчание — инструмент. После предложения помолчи 3 секунды — часто услышишь улучшение' : 'Silence is a tool. After an offer, pause for 3 seconds — often you will hear an improvement')},'
        '${bullet(ru ? 'Пакет, а не зарплата: отпуск, ДМС, гибкий график, удалёнка — всё имеет цену' : 'Package, not salary: vacation, health insurance, flexible hours, remote — everything has value')},'
        '${bullet(ru ? 'Письменное подтверждение: устные обещания — это обещания. Договор — это договор' : 'Written confirmation: verbal promises are promises. Contract is a contract')},'
        '${bullet(ru ? 'Готовься к «нет»: лучший результат переговоров — когда ты готов уйти' : 'Prepare for "no": the best negotiation result is when you are ready to walk away')}'
        ']';

    final negotiations = article('wesios_negotiations', ru ? 'Переговоры' : 'Negotiations', negotiationsBody,
        parentId: 'wesios_work',
        tags: ru ? ['переговоры', 'зарплата', 'ставки', 'фриланс'] : ['negotiations', 'salary', 'rates', 'freelance']);

    final remoteBody = '[${h1(ru ? 'Удалёнка и домашний офис' : 'Remote Work & Home Office')},'
        '${p(ru ? 'Работать из дома — навык. Без границ дом превращается в офис 24/7, а офис — в спальню.' : 'Working from home is a skill. Without boundaries, home becomes an office 24/7, and the office becomes a bedroom.')},'
        '${br()},'
        '${h2(ru ? 'Границы' : 'Boundaries')},'
        '${bullet(ru ? 'Физическая: отдельная комната или хотя бы угол со столом. Не работай с дивана' : 'Physical: separate room or at least a corner with a desk. Do not work from the couch')},'
        '${bullet(ru ? 'Временная: чёткие часы работы. Скажи семье: «с 9 до 18 я на работе, даже если дома»' : 'Temporal: clear working hours. Tell family: "from 9 to 6 I am at work, even if at home"')},'
        '${bullet(ru ? 'Цифровая: отдельный аккаунт/браузер для работы. Закрывай рабочие вкладки вечером' : 'Digital: separate account/browser for work. Close work tabs in the evening')},'
        '${bullet(ru ? 'Социальная: не отвечай на рабочие сообщения после 19:00, если не критично' : 'Social: do not reply to work messages after 7 PM unless critical')},'
        '${br()},'
        '${h2(ru ? 'Эргономика' : 'Ergonomics')},'
        '${bullet(ru ? 'Монитор на уровне глаз, расстояние 50–70 см. Шея скажет спасибо' : 'Monitor at eye level, 50–70 cm away. Your neck will thank you')},'
        '${bullet(ru ? 'Клавиатура и мышь на одном уровне с локтями — запястья ровные' : 'Keyboard and mouse at elbow level — wrists straight')},'
        '${bullet(ru ? 'Встаёшь каждый час: 5 минут ходьбы, растяжка, глаза в окно' : 'Stand up every hour: 5 minutes walk, stretch, eyes out the window')},'
        '${bullet(ru ? 'Хороший стул или подушка на сиденье — 8 часов в день, это инвестиция' : 'Good chair or cushion on seat — 8 hours a day, it is an investment')},'
        '${br()},'
        '${h2(ru ? '«Я на работе» без офиса' : '"I Am at Work" Without an Office')},'
        '${p(ru ? 'Психологический трюк: одевайся для работы (не пижама), включай рабочий плейлист, завари кофе в «рабочую» кружку.' : 'Psychological trick: dress for work (not pajamas), turn on work playlist, make coffee in the "work" mug.')},'
        '${bullet(ru ? 'Ритуал начала: 5 минут планирования дня перед экраном' : 'Start ritual: 5 minutes of day planning before the screen')},'
        '${bullet(ru ? 'Ритуал конца: закрой ноутбук, скажи вслух «работа закончена»' : 'End ritual: close laptop, say aloud "work is done"')},'
        '${bullet(ru ? 'Если лень — работай 10 минут. Часто инерция подхватывает' : 'If lazy — work for 10 minutes. Often inertia kicks in')}'
        ']';

    final remote = article('wesios_remote', ru ? 'Удалёнка и домашний офис' : 'Remote Work', remoteBody,
        parentId: 'wesios_work',
        tags: ru ? ['удалёнка', 'офис', 'эргономика', 'границы'] : ['remote', 'office', 'ergonomics', 'boundaries']);
    // ═══════════════════════════════════════════════════════════════════════
    //  ГОЛОВА И ОТНОШЕНИЯ
    // ═══════════════════════════════════════════════════════════════════════

    final mindFolder = folder('wesios_mind', ru ? 'Голова и отношения' : 'Mind & Relationships', parentId: 'wesios_kb');

    final stressBody = '[${h1(ru ? 'Стресс и тревога: бытовые техники' : 'Stress & Anxiety: Everyday Techniques')},'
        '${p(ru ? 'Стресс — не враг. Он сигнализирует о угрозе. Проблема, когда он не выключается.' : 'Stress is not the enemy. It signals a threat. The problem is when it does not turn off.')},'
        '${br()},'
        '${h2(ru ? 'Дыхание' : 'Breathing')},'
        '${p(ru ? 'Самый быстрый способ снизить тревогу — замедлить дыхание. Нейробиология: медленное дыхание активирует парасимпатическую нервную систему.' : 'The fastest way to reduce anxiety is to slow breathing. Neurobiology: slow breathing activates the parasympathetic nervous system.')},'
        '${bullet(ru ? '4-7-8: вдох 4 сек, задержка 7, выдох 8. 3–4 цикла — эффект за 1 минуту' : '4-7-8: inhale 4 sec, hold 7, exhale 8. 3–4 cycles — effect in 1 minute')},'
        '${bullet(ru ? 'Квадратное дыхание: 4-4-4-4 (вдох-задержка-выдох-задержка). Хорошо перед важным разговором' : 'Box breathing: 4-4-4-4 (inhale-hold-exhale-hold). Good before an important conversation')},'
        '${bullet(ru ? 'Длинный выдох: выдыхай в 2 раза дольше, чем вдыхаешь. Мгновенный эффект' : 'Long exhale: exhale twice as long as inhale. Instant effect')},'
        '${br()},'
        '${h2(ru ? 'Заземление' : 'Grounding')},'
        '${p(ru ? 'Когда мысли несутся — верни внимание в тело и пространство.' : 'When thoughts race — bring attention back to body and space.')},'
        '${bullet(ru ? '5-4-3-2-1: 5 вещей, которые видишь; 4 — слышишь; 3 — чувствуешь; 2 — пахнут; 1 — вкус' : '5-4-3-2-1: 5 things you see; 4 — hear; 3 — feel; 2 — smell; 1 — taste')},'
        '${bullet(ru ? 'Холодная вода на запястья или лицо — активирует рефлекс ныряния, замедляет сердцебиение' : 'Cold water on wrists or face — activates dive reflex, slows heartbeat')},'
        '${bullet(ru ? 'Прогулка босиком по траве/земле — если есть возможность' : 'Barefoot walk on grass/ground — if possible')},'
        '${br()},'
        '${h2(ru ? 'Когда уже к специалисту' : 'When to See a Professional')},'
        '${p(ru ? 'Самопомощь — хорошо, но не всегда достаточно. Обращайся, если:' : 'Self-help is good, but not always enough. Seek help if:')},'
        '${bullet(ru ? 'Тревога мешает работать или спать более 2 недель' : 'Anxiety interferes with work or sleep for more than 2 weeks')},'
        '${bullet(ru ? 'Появились физические симптомы: боли в груди, головокружение, постоянная усталость' : 'Physical symptoms appear: chest pain, dizziness, constant fatigue')},'
        '${bullet(ru ? 'Мысли о самоповреждении — даже флэш-моменты' : 'Thoughts of self-harm — even flash moments')},'
        '${bullet(ru ? 'Панические атаки повторяются — это лечится, не терпи' : 'Panic attacks repeat — this is treatable, do not endure')},'
        '${br()},'
        '${h2(ru ? 'Практика: тревожный дневник' : 'Practice: Anxiety Journal')},'
        '${numbered(ru ? 'Запиши, что произошло' : 'Write what happened')},'
        '${numbered(ru ? 'Оцени тревогу от 1 до 10' : 'Rate anxiety from 1 to 10')},'
        '${numbered(ru ? 'Что ты думаешь, что произойдёт? (катастрофа)' : 'What do you think will happen? (catastrophe)')},'
        '${numbered(ru ? 'Что реально произошло в прошлый раз, когда так думал?' : 'What actually happened last time you thought this?')},'
        '${numbered(ru ? 'Через неделю перечитай — увидишь паттерн' : 'Re-read in a week — you will see the pattern')}'
        ']';

    final stress = article('wesios_stress', ru ? 'Стресс и тревога' : 'Stress & Anxiety', stressBody,
        parentId: 'wesios_mind',
        tags: ru ? ['стресс', 'тревога', 'дыхание', 'заземление'] : ['stress', 'anxiety', 'breathing', 'grounding']);

    final communicationBody = '[${h1(ru ? 'Общение: сложные разговоры' : 'Communication: Difficult Conversations')},'
        '${p(ru ? 'Сложные разговоры — не про победу, а про понимание. Цель: не «доказать», а «договориться».' : 'Difficult conversations are not about winning, but about understanding. Goal: not "prove", but "agree".')},'
        '${br()},'
        '${h2(ru ? 'Критика' : 'Giving Criticism')},'
        '${bullet(ru ? 'Ситуация-поведение-влияние: «В отчёте (ситуация) пропущены цифры (поведение), клиент запутался (влияние)»' : 'Situation-behavior-impact: "In the report (situation) numbers are missing (behavior), client got confused (impact)"')},'
        '${bullet(ru ? 'Не «ты плохой», а «действие создало проблему»' : 'Not "you are bad", but "the action created a problem"')},'
        '${bullet(ru ? 'Предложи решение: «В следующий раз проверь цифры перед отправкой»' : 'Offer a solution: "Next time check numbers before sending"')},'
        '${br()},'
        '${h2(ru ? 'Просьбы' : 'Making Requests')},'
        '${bullet(ru ? 'Конкретика: не «помоги», а «проверь отчёт к 17:00»' : 'Specifics: not "help me", but "check the report by 5 PM"')},'
        '${bullet(ru ? 'Объясни зачем: «Если не проверим — клиент получит ошибку»' : 'Explain why: "If we do not check — client gets an error"')},'
        '${bullet(ru ? 'Дай выбор: «Ты можешь сделать сегодня или завтра утром?»' : 'Give choice: "Can you do it today or tomorrow morning?"')},'
        '${br()},'
        '${h2(ru ? 'Конфликты без разрушения' : 'Conflict Without Destruction')},'
        '${bullet(ru ? 'Слушай до конца, не перебивай. Часто человек сам находит решение, если его выслушают' : 'Listen to the end, do not interrupt. Often the person finds a solution themselves if heard')},'
        '${bullet(ru ? 'Повтори своими словами: «Ты говоришь, что…» — покажи, что услышал' : 'Repeat in your own words: "You are saying that…" — show you heard')},'
        '${bullet(ru ? 'Найди общий интерес: «Нам обоим важно, чтобы проект вышел в срок»' : 'Find common interest: "We both care that the project is delivered on time"')},'
        '${bullet(ru ? 'Отдели позицию от человека: «Я не согласен с решением, но уважаю тебя»' : 'Separate position from person: "I disagree with the decision, but I respect you"')},'
        '${bullet(ru ? 'Если накал растёт — сделай паузу: «Давай перерыв 10 минут»' : 'If tension rises — take a break: "Let us take a 10-minute break"')}'
        ']';

    final communication = article('wesios_communication', ru ? 'Общение' : 'Communication', communicationBody,
        parentId: 'wesios_mind',
        tags: ru ? ['общение', 'критика', 'конфликт', 'просьбы'] : ['communication', 'criticism', 'conflict', 'requests']);

    final lonelinessBody = '[${h1(ru ? 'Одиночество и круг' : 'Loneliness & Circle')},'
        '${p(ru ? 'Работать в одиночку — нормально. Но поддержка нужна всем. Вопрос: как её строить, если нет офиса и команды?' : 'Working alone is normal. But everyone needs support. Question: how to build it without an office and team?')},'
        '${br()},'
        '${h2(ru ? 'Типы поддержки' : 'Types of Support')},'
        '${h3(ru ? 'Эмоциональная' : 'Emotional')},'
        '${bullet(ru ? 'Человек, которому можно сказать «всё провалилось» и не услышать советов' : 'Someone you can say "everything failed" to and not hear advice')},'
        '${bullet(ru ? 'Не обязательно друг — может быть партнёр, родственник, терапевт' : 'Not necessarily a friend — can be partner, relative, therapist')},'
        '${h3(ru ? 'Практическая' : 'Practical')},'
        '${bullet(ru ? 'Коллега, с которым можно обсудить код, архитектуру, ставку' : 'Colleague to discuss code, architecture, rates with')},'
        '${bullet(ru ? 'Сообщества: Telegram-чаты, Discord-серверы по специализации' : 'Communities: Telegram chats, Discord servers by specialization')},'
        '${h3(ru ? 'Информационная' : 'Informational')},'
        '${bullet(ru ? 'Ментор, который уже прошёл твой путь' : 'Mentor who has already walked your path')},'
        '${bullet(ru ? 'Блогер/автор, чей опыт близок к твоему' : 'Blogger/author whose experience is close to yours')},'
        '${br()},'
        '${h2(ru ? 'Как строить круг' : 'How to Build Your Circle')},'
        '${numbered(ru ? 'Начни с одного человека — не пытайся собрать армию сразу' : 'Start with one person — do not try to gather an army immediately')},'
        '${numbered(ru ? 'Будь первым: напиши коллеге с вопросом, предложи кофе онлайн' : 'Be first: write a colleague with a question, offer virtual coffee')},'
        '${numbered(ru ? 'Участвуй в сообществах: отвечай на вопросы, делись опытом — репутация строится' : 'Participate in communities: answer questions, share experience — reputation builds')},'
        '${numbered(ru ? 'Поддерживай регулярность: раз в месяц созвон, раз в неделю сообщение' : 'Maintain regularity: monthly call, weekly message')},'
        '${numbered(ru ? 'Качество > количество: 2–3 близких связи лучше 50 поверхностных' : 'Quality > quantity: 2–3 close connections better than 50 superficial')},'
        '${br()},'
        '${h2(ru ? 'Если работаешь один' : 'If You Work Alone')},'
        '${bullet(ru ? 'Коворкинг раз в неделю — даже если не разговариваешь, энергия других людей помогает' : 'Coworking once a week — even if you do not talk, energy of other people helps')},'
        '${bullet(ru ? 'Публичные проекты: open source, блог — создают связи через общее дело' : 'Public projects: open source, blog — create connections through shared work')},'
        '${bullet(ru ? 'Не стыдись одиночества — стыд вредит больше, чем само одиночество' : 'Do not be ashamed of loneliness — shame hurts more than loneliness itself')}'
        ']';

    final loneliness = article('wesios_loneliness', ru ? 'Одиночество и круг' : 'Loneliness & Circle', lonelinessBody,
        parentId: 'wesios_mind',
        tags: ru ? ['одиночество', 'поддержка', 'сеть', 'коллеги'] : ['loneliness', 'support', 'network', 'colleagues']);

    final comparisonBody = '[${h1(ru ? 'Сравнение с другими' : 'Comparison With Others')},'
        '${p(ru ? 'Соцсети показывают лучшие 1% жизни человека. Сравниваешься с этим — проигрываешь всегда.' : 'Social media shows the best 1% of a person\'s life. Comparing yourself to this — you always lose.')},'
        '${br()},'
        '${h2(ru ? 'Механизм' : 'The Mechanism')},'
        '${p(ru ? 'Мозг эволюционно настроен сравнивать себя с племенем — чтобы понять своё место. В древности это работало. В интернете — ломается.' : 'The brain is evolutionarily tuned to compare itself with the tribe — to understand its place. In ancient times it worked. On the internet — it breaks.')},'
        '${bullet(ru ? '«Успешный успех» — это маркетинг. За каждым постом — 20 провалов, которые не показали' : '"Successful success" is marketing. Behind every post — 20 failures that were not shown')},'
        '${bullet(ru ? 'Алгоритмы показывают то, что вызывает эмоции. Зависть — сильная эмоция. Ты в ловушке.' : 'Algorithms show what triggers emotions. Envy is a strong emotion. You are in a trap.')},'
        '${br()},'
        '${h2(ru ? 'Как не сливать энергию' : 'How to Not Drain Energy')},'
        '${bullet(ru ? 'Сравнивай себя с собой вчерашним, а не с кем-то в интернете' : 'Compare yourself to yesterday\'s you, not to someone on the internet')},'
        '${bullet(ru ? 'Лимит на соцсети: 30 минут в день, таймер. Или убери ленту, оставь только сообщения' : 'Social media limit: 30 minutes a day, timer. Or remove feed, keep only messages')},'
        '${bullet(ru ? 'Задай вопрос: «Что я сейчас делаю вместо того, чтобы делать?»' : 'Ask: "What am I doing right now instead of what I should be doing?"')},'
        '${bullet(ru ? 'Подпишись на людей, которые учат, а не хвастаются — разница в энергии огромна' : 'Follow people who teach, not brag — the energy difference is huge')},'
        '${bullet(ru ? 'Веди дневник достижений: каждый день 3 вещи, которые сделал. Это реальность, не фильтр' : 'Keep an achievement journal: every day 3 things you did. This is reality, not a filter')},'
        '${br()},'
        '${h2(ru ? 'Практика: цифровой детокс' : 'Practice: Digital Detox')},'
        '${numbered(ru ? 'Убери все уведомления соцсетей с телефона' : 'Remove all social media notifications from phone')},'
        '${numbered(ru ? 'Удали приложения, оставь только веб-версию (меньше удобства = меньше залипания)' : 'Delete apps, keep only web version (less convenience = less zoning out)')},'
        '${numbered(ru ? '«Тихие часы»: 1–2 часа в день без телефона — читай, гуляй, разговаривай' : '"Quiet hours": 1–2 hours a day without phone — read, walk, talk')},'
        '${numbered(ru ? 'Раз в неделю полный день без соцсетей — заметь, что изменилось' : 'Once a week full day without social media — notice what changed')}'
        ']';

    final comparison = article('wesios_comparison', ru ? 'Сравнение с другими' : 'Comparison With Others', comparisonBody,
        parentId: 'wesios_mind',
        tags: ru ? ['сравнение', 'соцсети', 'энергия', 'детокс'] : ['comparison', 'social media', 'energy', 'detox']);
    // ═══════════════════════════════════════════════════════════════════════
    //  ПРИВЫЧКИ И ВНИМАНИЕ
    // ═══════════════════════════════════════════════════════════════════════

    final habitsFolder = folder('wesios_habits', ru ? 'Привычки и внимание' : 'Habits & Attention', parentId: 'wesios_kb');

    final habitFormBody = '[${h1(ru ? 'Формирование привычек' : 'Habit Formation')},'
        '${p(ru ? 'Привычка — это автоматизированное поведение. Мозг экономит энергию, повторяя то, что уже знает. Используй это.' : 'A habit is automated behavior. The brain saves energy by repeating what it already knows. Use this.')},'
        '${br()},'
        '${h2(ru ? 'Маленькие шаги' : 'Small Steps')},'
        '${bullet(ru ? 'Не «буду бегать по часу», а «надену кроссовки». Маленькое действие запускает инерцию' : 'Not "I will run for an hour", but "I will put on sneakers". Small action triggers inertia')},'
        '${bullet(ru ? 'Правило 2 минут: если привычка занимает меньше 2 минут — делай сразу. Зарядка, запись расхода, стакан воды' : '2-minute rule: if habit takes less than 2 minutes — do it immediately. Stretching, logging expense, glass of water')},'
        '${bullet(ru ? 'Уменьши порог входа: книга на подушке, зубная нить на виду, Wesi Treasury на главном экране' : 'Lower the barrier: book on pillow, dental floss in sight, Wesi Treasury on home screen')},'
        '${br()},'
        '${h2(ru ? 'Триггеры' : 'Triggers')},'
        '${p(ru ? 'Триггер — сигнал, который запускает привычку. Свяжи новую привычку с существующей:' : 'Trigger — a signal that launches a habit. Link new habit to existing one:')},'
        '${bullet(ru ? 'После кофе — 5 минут планирования в Wesi Treasury' : 'After coffee — 5 minutes of planning in Wesi Treasury')},'
        '${bullet(ru ? 'После обеда — 10 минут прогулка' : 'After lunch — 10 minute walk')},'
        '${bullet(ru ? 'Перед сном — 5 минут дневник (3 достижения дня)' : 'Before sleep — 5 minute journal (3 daily achievements)')},'
        '${bullet(ru ? 'Каждый понедельник — обзор финансов за неделю в Treasury' : 'Every Monday — weekly finance review in Treasury')},'
        '${br()},'
        '${h2(ru ? 'Срывы без самобичевания' : 'Relapses Without Self-Flagellation')},'
        '${p(ru ? 'Срыв — не провал, а данные. Каждый срыв учит, что не работает.' : 'A relapse is not failure, but data. Every relapse teaches what does not work.')},'
        '${bullet(ru ? 'Не «я слабый», а «что помешало?» — время, место, настроение, люди' : 'Not "I am weak", but "what prevented it?" — time, place, mood, people')},'
        '${bullet(ru ? 'Правило «никогда не пропускай дважды»: один срыв — случайность, два — паттерн' : '"Never miss twice" rule: one relapse is chance, two is a pattern')},'
        '${bullet(ru ? 'Верни порог: если сложно — упрости привычку в 2 раза, не бросай' : 'Lower the bar: if hard — simplify the habit by half, do not quit')},'
        '${bullet(ru ? 'Отпразднуй неделю без срыва — мозг любит награды' : 'Celebrate a week without relapse — the brain loves rewards')}'
        ']';

    final habitForm = article('wesios_habit_form', ru ? 'Формирование привычек' : 'Habit Formation', habitFormBody,
        parentId: 'wesios_habits',
        tags: ru ? ['привычки', 'триггеры', 'срывы', 'планирование'] : ['habits', 'triggers', 'relapses', 'planning']);

    final digitalMinBody = '[${h1(ru ? 'Цифровой минимализм' : 'Digital Minimalism')},'
        '${p(ru ? 'Внимание — самый ценный ресурс. Технологии созданы, чтобы его захватывать. Бери контроль обратно.' : 'Attention is the most valuable resource. Technology is designed to capture it. Take control back.')},'
        '${br()},'
        '${h2(ru ? 'Уведомления' : 'Notifications')},'
        '${bullet(ru ? 'Отключи все, кроме: звонки, SMS, календарь, банк' : 'Disable all except: calls, SMS, calendar, bank')},'
        '${bullet(ru ? 'Убери значки с иконок — красные точки — это манипуляция' : 'Remove badges from icons — red dots are manipulation')},'
        '${bullet(ru ? 'Группируй уведомления: 3 раза в день, а не каждые 5 минут' : 'Batch notifications: 3 times a day, not every 5 minutes')},'
        '${bullet(ru ? 'WesiOS: настройте уведомления в Settings → Notifications. Только важное' : 'WesiOS: configure notifications in Settings → Notifications. Only important')},'
        '${br()},'
        '${h2(ru ? 'Ленты' : 'Feeds')},'
        '${bullet(ru ? 'Убери бесконечную ленту: удали приложения соцсетей, используй веб-версию с таймером' : 'Remove infinite scroll: delete social media apps, use web version with timer')},'
        '${bullet(ru ? 'Подпишись на 10 источников максимум. Качество > количество' : 'Subscribe to max 10 sources. Quality > quantity')},'
        '${bullet(ru ? 'RSS вместо ленты: Feedly, Inoreader — ты контролируешь, что читаешь' : 'RSS instead of feed: Feedly, Inoreader — you control what you read')},'
        '${br()},'
        '${h2(ru ? 'Тихие часы' : 'Quiet Hours')},'
        '${bullet(ru ? 'Утро: первый час без телефона. Мозг свежий — не трать на ленту' : 'Morning: first hour without phone. Brain is fresh — do not waste on feed')},'
        '${bullet(ru ? 'Вечер: за 1 час до сна — экраны off. Читай бумажную книгу, разговаривай' : 'Evening: 1 hour before sleep — screens off. Read paper book, talk')},'
        '${bullet(ru ? 'Работа: 90 минут фокуса, 15 минут перерыв. Телефон в другой комнате' : 'Work: 90 minutes focus, 15 minutes break. Phone in another room')},'
        '${br()},'
        '${h2(ru ? 'Внимание как ресурс' : 'Attention as a Resource')},'
        '${p(ru ? 'Представь, что внимание — это деньги. Каждое уведомление, каждый скролл — трата. Бюджет внимания важнее бюджета денег.' : 'Imagine attention is money. Every notification, every scroll — an expense. Attention budget is more important than money budget.')},'
        '${bullet(ru ? 'Веди «дневник внимания»: что отвлекало сегодня и сколько раз' : 'Keep an "attention journal": what distracted you today and how many times')},'
        '${bullet(ru ? 'Установи «таксу» на отвлечение: каждый раз, когда залип — 10 отжиманий или 5 минут уборки' : 'Set a "tax" on distraction: every time you zone out — 10 push-ups or 5 minutes cleaning')},'
        '${bullet(ru ? 'Используй Wesi Treasury для учёта не только денег, но и времени — фиксируй, куда уходит день' : 'Use Wesi Treasury to track not only money but time — log where the day goes')}'
        ']';

    final digitalMin = article('wesios_digital_min', ru ? 'Цифровой минимализм' : 'Digital Minimalism', digitalMinBody,
        parentId: 'wesios_habits',
        tags: ru ? ['минимализм', 'внимание', 'уведомления', 'продуктивность'] : ['minimalism', 'attention', 'notifications', 'productivity']);

    final decisionsBody = '[${h1(ru ? 'Решения: как не застревать в выборе' : 'Decisions: How to Not Get Stuck')},'
        '${p(ru ? 'Паралич анализа — когда выборов слишком много, и ты ничего не делаешь. Есть выход.' : 'Analysis paralysis — when there are too many choices and you do nothing. There is a way out.')},'
        '${br()},'
        '${h2(ru ? 'Критерии «достаточно хорошо»' : '"Good Enough" Criteria')},'
        '${p(ru ? 'Перфекционизм в решениях — враг. Цель не «лучшее», а «достаточно хорошее».' : 'Perfectionism in decisions is the enemy. Goal is not "best", but "good enough".')},'
        '${bullet(ru ? 'Задай 3 критерия максимум. Больше — анализ бесконечен' : 'Set max 3 criteria. More — analysis is endless')},'
        '${bullet(ru ? 'Оцени каждый вариант по шкале 1–5. Сумма > 12 = «достаточно хорошо»' : 'Rate each option 1–5. Sum > 12 = "good enough"')},'
        '${bullet(ru ? 'Дай себе дедлайн: 24 часа на быстрые решения, 1 неделя на важные' : 'Give yourself a deadline: 24 hours for quick decisions, 1 week for important')},'
        '${bullet(ru ? 'После решения — не оглядывайся. Доверь себе' : 'After decision — do not look back. Trust yourself')},'
        '${br()},'
        '${h2(ru ? 'Техники' : 'Techniques')},'
        '${h3(ru ? '10-10-10' : '10-10-10')},'
        '${p(ru ? 'Спроси себя: как я буду чувствовать это решение через 10 минут, 10 месяцев, 10 лет?' : 'Ask yourself: how will I feel about this decision in 10 minutes, 10 months, 10 years?')},'
        '${bullet(ru ? 'Через 10 минут: часто эмоции улягутся, решение станет очевидным' : 'In 10 minutes: emotions often settle, decision becomes obvious')},'
        '${bullet(ru ? 'Через 10 месяцев: увидишь реальное влияние' : 'In 10 months: you will see real impact')},'
        '${bullet(ru ? 'Через 10 лет: поймёшь, что на самом деле важно' : 'In 10 years: you will understand what really matters')},'
        '${h3(ru ? 'Правило 37%' : '37% Rule')},'
        '${p(ru ? 'Исследуй 37% вариантов, затем выбирай лучший из оставшихся. Математически оптимально.' : 'Explore 37% of options, then choose the best of the rest. Mathematically optimal.')},'
        '${bullet(ru ? 'Квартира: посмотри 10 из 27 → бери лучшую из оставшихся 17' : 'Apartment: see 10 of 27 → take best of remaining 17')},'
        '${bullet(ru ? 'Работа: пообщайся с 3–4 компаниями, затем принимай оффер' : 'Job: talk to 3–4 companies, then accept offer')},'
        '${br()},'
        '${h2(ru ? 'Когда выбор не важен' : 'When Choice Does Not Matter')},'
        '${p(ru ? 'Многие решения — обратимые. Не трать энергию на то, что можно изменить позже.' : 'Many decisions are reversible. Do not waste energy on what can be changed later.')},'
        '${bullet(ru ? 'Редактор кода? VS Code, IntelliJ, Vim — все работают. Выбери один и забудь' : 'Code editor? VS Code, IntelliJ, Vim — all work. Pick one and forget')},'
        '${bullet(ru ? 'Фреймворк? Flutter, React, Vue — все делают приложения. Начни с любого' : 'Framework? Flutter, React, Vue — all make apps. Start with any')},'
        '${bullet(ru ? 'Цвет стены? Покрась, если не нравится — перекрась' : 'Wall color? Paint it, if you do not like it — repaint')}'
        ']';

    final decisions = article('wesios_decisions', ru ? 'Решения' : 'Decisions', decisionsBody,
        parentId: 'wesios_habits',
        tags: ru ? ['решения', 'выбор', 'перфекционизм', 'продуктивность'] : ['decisions', 'choice', 'perfectionism', 'productivity']);
    // ═══════════════════════════════════════════════════════════════════════
    //  ЖИЗНЬ ВОКРУГ
    // ═══════════════════════════════════════════════════════════════════════

    final lifeFolder = folder('wesios_life', ru ? 'Жизнь вокруг' : 'Life Around', parentId: 'wesios_kb');

    final homeLifeBody = '[${h1(ru ? 'Дом и быт: порядок без перфекционизма' : 'Home & Household: Order Without Perfectionism')},'
        '${p(ru ? 'Порядок в доме — это не эстетика, а экономия энергии. Когда всё на своих местах, мозг не тратит силы на поиск.' : 'Order at home is not aesthetics, but energy saving. When everything is in its place, the brain does not waste energy searching.')},'
        '${br()},'
        '${h2(ru ? 'Порядок без перфекционизма' : 'Order Without Perfectionism')},'
        '${bullet(ru ? 'Правило «одной минуты»: если занимает меньше минуты — сделай сразу. Вешай пальто, мой чашку' : 'One-minute rule: if it takes less than a minute — do it immediately. Hang coat, wash cup')},'
        '${bullet(ru ? '«Домашняя зона отчуждения»: один ящик/полка для «пока не знаю куда». Раз в месяц разбирай' : 'Home limbo zone: one drawer/shelf for "not sure where yet". Sort once a month')},'
        '${bullet(ru ? 'Не выбрасывай всё подряд. Спроси: «использовал за год?» — нет → убирай' : 'Do not throw everything away. Ask: "used in a year?" — no → remove')},'
        '${bullet(ru ? 'Порядок — не цель, а инструмент. Достаточно 80% порядка, 100% — перфекционизм' : 'Order is not a goal, but a tool. 80% order is enough, 100% is perfectionism')},'
        '${br()},'
        '${h2(ru ? 'Рутина, которая экономит силы' : 'Routine That Saves Energy')},'
        '${p(ru ? 'Рутина — это автопилот для быта. Чем больше автоматизировано, тем больше энергии на важное.' : 'Routine is autopilot for household. The more automated, the more energy for what matters.')},'
        '${bullet(ru ? 'Воскресенье — день планирования: меню на неделю, список покупок, уборка 30 минут' : 'Sunday — planning day: weekly menu, shopping list, 30 min cleaning')},'
        '${bullet(ru ? 'Вечерняя рутина: посуда, завтрак на завтра, одежда на завтра. Утро начинается спокойно' : 'Evening routine: dishes, breakfast for tomorrow, clothes for tomorrow. Morning starts calmly')},'
        '${bullet(ru ? 'Финансовая рутина: понедельник — обзор недели в Wesi Treasury, 1-е число — обзор месяца' : 'Finance routine: Monday — weekly review in Wesi Treasury, 1st — monthly review')},'
        '${bullet(ru ? 'Одинаковые завтраки/обеды — не скучно, а экономит решения. Мозг любит шаблоны' : 'Same breakfasts/lunches — not boring, but saves decisions. Brain loves patterns')},'
        '${br()},'
        '${h2(ru ? 'Пространство для работы' : 'Workspace')},'
        '${bullet(ru ? 'Рабочий стол: только то, что нужно сейчас. Всё остальное — в ящик' : 'Desk: only what you need now. Everything else — in drawer')},'
        '${bullet(ru ? 'Провода: один кабель-органайзер, не спагетти' : 'Cables: one cable organizer, not spaghetti')},'
        '${bullet(ru ? 'Растения: одно, но живое. Зелень снижает стресс' : 'Plants: one, but alive. Greenery reduces stress')},'
        '${bullet(ru ? 'Свет: дневной свет лучше любой лампы. Стол у окна, если можно' : 'Light: daylight better than any lamp. Desk by window if possible')}'
        ']';

    final homeLife = article('wesios_home', ru ? 'Дом и быт' : 'Home & Household', homeLifeBody,
        parentId: 'wesios_life',
        tags: ru ? ['дом', 'быт', 'рутина', 'порядок'] : ['home', 'household', 'routine', 'order']);

    final restBody = '[${h1(ru ? 'Отдых как навык' : 'Rest as a Skill')},'
        '${p(ru ? 'Отдых — не лень. Это восстановление ресурса. Без отдыха продуктивность падает, ошибки растут, выгорание приближается.' : 'Rest is not laziness. It is resource recovery. Without rest, productivity drops, errors grow, burnout approaches.')},'
        '${br()},'
        '${h2(ru ? 'Ежедневное восстановление' : 'Daily Recovery')},'
        '${bullet(ru ? 'Микроперерывы: каждые 90 минут — 10 минут от экрана. Глаза, спина, мозг скажут спасибо' : 'Microbreaks: every 90 minutes — 10 minutes off screen. Eyes, back, brain will thank you')},'
        '${bullet(ru ? 'Прогулка: 15 минут после обеда — лучше кофе для бодрости' : 'Walk: 15 minutes after lunch — better than coffee for alertness')},'
        '${bullet(ru ? 'Дневной сон: 10–20 минут до 15:00. Дольше — инерция, позже — бессонница' : 'Nap: 10–20 minutes before 3 PM. Longer — grogginess, later — insomnia')},'
        '${bullet(ru ? 'Вечер: 1 час без экранов перед сном. Читай, растяжка, разговор' : 'Evening: 1 hour screen-free before sleep. Read, stretch, talk')},'
        '${br()},'
        '${h2(ru ? 'Отпуск' : 'Vacation')},'
        '${bullet(ru ? 'Минимум: 1 неделя каждые 3 месяца. Мозг перезагружается не за 2 дня' : 'Minimum: 1 week every 3 months. Brain does not reboot in 2 days')},'
        '${bullet(ru ? 'Полный отрыв: не проверяй почту, не отвечай на сообщения. Делегируй заранее' : 'Full disconnect: do not check email, do not reply to messages. Delegate in advance')},'
        '${bullet(ru ? 'Активный отдых > пассивный. Прогулки, спорт, природа — лучше, чем сериалы' : 'Active rest > passive. Walks, sports, nature — better than TV shows')},'
        '${bullet(ru ? 'Планируй отпуск заранее: предвкушение — часть отдыха' : 'Plan vacation in advance: anticipation is part of rest')},'
        '${br()},'
        '${h2(ru ? 'Отдых от работы внутри дня' : 'Rest From Work Within the Day')},'
        '${p(ru ? 'Не работай больше 6 часов подряд. После 6 часов эффективность падает экспоненциально.' : 'Do not work more than 6 hours straight. After 6 hours efficiency drops exponentially.')},'
        '${bullet(ru ? 'Техника Pomodoro: 25 минут работы, 5 минут отдыха. 4 цикла — длинный перерыв 15–30 минут' : 'Pomodoro technique: 25 minutes work, 5 minutes rest. 4 cycles — long break 15–30 minutes')},'
        '${bullet(ru ? 'Переключение контекста: после кодинга — прогулка, не ещё кодинг' : 'Context switching: after coding — walk, not more coding')},'
        '${bullet(ru ? 'Физическая активность: 20 минут упражнений — лучше перерыв, чем соцсети' : 'Physical activity: 20 minutes exercise — better break than social media')}'
        ']';

    final rest = article('wesios_rest', ru ? 'Отдых как навык' : 'Rest as a Skill', restBody,
        parentId: 'wesios_life',
        tags: ru ? ['отдых', 'восстановление', 'помодоро', 'выгорание'] : ['rest', 'recovery', 'pomodoro', 'burnout']);

    final expVsThingsBody = '[${h1(ru ? 'Опыт vs вещи' : 'Experiences vs Things')},'
        '${p(ru ? 'Исследования показывают: опыт даёт больше счастья, чем вещи. Почему?' : 'Research shows: experiences bring more happiness than things. Why?')},'
        '${br()},'
        '${h2(ru ? 'Почему опыт лучше' : 'Why Experience Is Better')},'
        '${bullet(ru ? 'Опыт не стареет. Вещь устаревает, ломается, надоедает. Воспоминание — нет' : 'Experience does not age. Things become outdated, break, get boring. Memories do not')},'
        '${bullet(ru ? 'Опыт связан с идентичностью. «Я тот, кто путешествовал» — сильнее, чем «у меня есть iPhone»' : 'Experience is tied to identity. "I am the one who traveled" is stronger than "I have an iPhone"')},'
        '${bullet(ru ? 'Опыт социален. Вещь — индивидуальна. Поездку можно обсуждать, вещь — нет' : 'Experience is social. Things are individual. A trip can be discussed, a thing cannot')},'
        '${bullet(ru ? 'Опыт не сравнивается. Вещи сравниваются с чужими. Воспоминания — уникальны' : 'Experience is not compared. Things are compared with others. Memories are unique')},'
        '${br()},'
        '${h2(ru ? 'Когда вещь выгоднее' : 'When a Thing Is Better')},'
        '${p(ru ? 'Не всё черно-бело. Иногда вещь — правильный выбор:' : 'Not everything is black and white. Sometimes a thing is the right choice:')},'
        '${bullet(ru ? 'Инструменты работы: хороший ноутбук, стул, монитор — инвестиция в доход' : 'Work tools: good laptop, chair, monitor — investment in income')},'
        '${bullet(ru ? 'Вещи, которые экономят время: робот-пылесос, посудомойка — время = деньги' : 'Things that save time: robot vacuum, dishwasher — time = money')},'
        '${bullet(ru ? 'Вещи, которые создают опыт: гитара, велосипед, фотоаппарат' : 'Things that create experience: guitar, bicycle, camera')},'
        '${br()},'
        '${h2(ru ? 'Правило 50/30/20 для досуга' : '50/30/20 Rule for Leisure')},'
        '${p(ru ? 'Раздели досуговый бюджет:' : 'Divide your leisure budget:')},'
        '${bullet(ru ? '50% — опыт: поездки, курсы, концерты, спорт' : '50% — experience: trips, courses, concerts, sports')},'
        '${bullet(ru ? '30% — вещи-инструменты: оборудование, книги, софт' : '30% — tool things: equipment, books, software')},'
        '${bullet(ru ? '20% — вещи-удовольствия: без вины, но в рамках' : '20% — pleasure things: without guilt, but within limits')},'
        '${br()},'
        '${h2(ru ? 'Практика: опытный квартал' : 'Practice: Experiential Quarter')},'
        '${numbered(ru ? 'Выбери один опыт в квартал: курс, поездка, марафон' : 'Choose one experience per quarter: course, trip, marathon')},'
        '${numbered(ru ? 'Запланируй заранее, забронируй — обязательство повышает вероятность' : 'Plan in advance, book — commitment increases probability')},'
        '${numbered(ru ? 'Зафиксируй в Wesi Treasury как инвестицию в себя' : 'Log in Wesi Treasury as an investment in yourself')},'
        '${numbered(ru ? 'После — запиши 3 момента, которые запомнились. Усиливает эффект' : 'After — write down 3 moments you remember. Amplifies the effect')}'
        ']';

    final expVsThings = article('wesios_exp_vs_things', ru ? 'Опыт vs вещи' : 'Experiences vs Things', expVsThingsBody,
        parentId: 'wesios_life',
        tags: ru ? ['опыт', 'вещи', 'счастье', 'инвестиции'] : ['experience', 'things', 'happiness', 'investment']);

    final legalBody = '[${h1(ru ? 'Простые юридические вещи' : 'Simple Legal Matters')},'
        '${p(ru ? 'Юридическая грамотность — не про адвоката, а про базовую защиту. Несколько простых правил спасают нервы и деньги.' : 'Legal literacy is not about a lawyer, but basic protection. A few simple rules save nerves and money.')},'
        '${br()},'
        '${h2(ru ? 'Договор аренды' : 'Rental Agreement')},'
        '${bullet(ru ? 'Всегда письменно. Устная договорённость — это обещание, не договор' : 'Always in writing. Verbal agreement is a promise, not a contract')},'
        '${bullet(ru ? 'Проверь: кто собственник? Паспорт + выписка из ЕГРН. Не верь посредникам' : 'Check: who is the owner? Passport + EGRN extract. Do not trust intermediaries')},'
        '${bullet(ru ? 'Фиксируй состояние квартиры: фото/видео при заселении. Подпись арендодателя на акте' : 'Document apartment condition: photos/video on move-in. Landlord signature on act')},'
        '${bullet(ru ? 'Срок и условия расторжения: пропиши заранее, сколько предупреждать' : 'Term and termination conditions: specify in advance how much notice')},'
        '${bullet(ru ? 'Депозит: что покрывает, когда возвращается, в каком виде' : 'Deposit: what it covers, when returned, in what form')},'
        '${br()},'
        '${h2(ru ? 'Расписка' : 'IOU / Receipt')},'
        '${bullet(ru ? 'Обязательно письменно: сумма прописью, дата, срок возврата, подписи обеих сторон' : 'Mandatory in writing: amount in words, date, repayment term, both signatures')},'
        '${bullet(ru ? 'Свидетели: 2 человека, паспортные данные. Без свидетелей — сложно доказать' : 'Witnesses: 2 people, passport details. Without witnesses — hard to prove')},'
        '${bullet(ru ? 'Не давай в долг больше, чем готов потерять. Это правило, не совет' : 'Do not lend more than you are ready to lose. This is a rule, not advice')},'
        '${br()},'
        '${h2(ru ? 'Что хранить «на всякий»' : 'What to Keep "Just in Case"')},'
        '${bullet(ru ? 'Копии паспорта: скан + фото на облаке. Потеря паспорта без копии — кошмар' : 'Passport copies: scan + photo in cloud. Losing passport without copy — nightmare')},'
        '${bullet(ru ? 'Договоры: аренда, работа, кредит — храни в одном месте, цифровом и бумажном' : 'Contracts: rental, employment, loan — keep in one place, digital and paper')},'
        '${bullet(ru ? 'Чеки и квитанции: 3 года для налогов, 5 лет для крупных покупок' : 'Receipts and invoices: 3 years for taxes, 5 years for large purchases')},'
        '${bullet(ru ? 'Медицинские документы: выписки, анализы — пригодятся при смене врача' : 'Medical documents: extracts, tests — useful when changing doctor')},'
        '${bullet(ru ? 'Финансовые: выписки, договоры страхования, завещание' : 'Financial: statements, insurance contracts, will')},'
        '${br()},'
        '${h2(ru ? 'WesiOS: учёт договоров' : 'WesiOS: Contract Tracking')},'
        '${p(ru ? 'Используй Wesi Treasury для учёта: дата договора, сумма, срок, напоминания. Не полагайся на память.' : 'Use Wesi Treasury to track: contract date, amount, term, reminders. Do not rely on memory.')}'
        ']';

    final legal = article('wesios_legal', ru ? 'Простые юридические вещи' : 'Simple Legal Matters', legalBody,
        parentId: 'wesios_life',
        tags: ru ? ['юриспруденция', 'договор', 'расписка', 'документы'] : ['law', 'contract', 'receipt', 'documents']);
    // ═══════════════════════════════════════════════════════════════════════
    //  ДЛЯ САМОЗАНЯТЫХ
    // ═══════════════════════════════════════════════════════════════════════

    final freelanceFolder = folder('wesios_freelance', ru ? 'Для самозанятых' : 'For Freelancers', parentId: 'wesios_kb');

    final firstClientsBody = '[${h1(ru ? 'Первые клиенты' : 'First Clients')},'
        '${p(ru ? 'Начать без портфолио и репутации — сложно, но возможно. Главное: показать результат, а не обещания.' : 'Starting without portfolio and reputation is hard, but possible. The key: show results, not promises.')},'
        '${br()},'
        '${h2(ru ? 'Где искать' : 'Where to Look')},'
        '${bullet(ru ? 'Свой круг: друзья, знакомые, бывшие коллеги. 70% первых клиентов — от знакомых' : 'Your circle: friends, acquaintances, former colleagues. 70% of first clients come from connections')},'
        '${bullet(ru ? 'Фриланс-биржи: Upwork, Toptal, Freelancer — для портфолио и рейтинга. Демпингуй на первых 2–3 проектах' : 'Freelance platforms: Upwork, Toptal, Freelancer — for portfolio and rating. Undercut on first 2–3 projects')},'
        '${bullet(ru ? 'Сообщества: Telegram-чаты, Discord, Reddit — отвечай на вопросы, предлагай помощь' : 'Communities: Telegram chats, Discord, Reddit — answer questions, offer help')},'
        '${bullet(ru ? 'Контент: блог, YouTube, GitHub — клиенты приходят к тем, кто учит' : 'Content: blog, YouTube, GitHub — clients come to those who teach')},'
        '${br()},'
        '${h2(ru ? 'Холодные сообщения без стыда' : 'Cold Outreach Without Shame')},'
        '${p(ru ? 'Холодное письмо — не спам, если оно персонализировано и полезно.' : 'Cold email is not spam if it is personalized and useful.')},'
        '${bullet(ru ? 'Исследуй клиента: что он делает, какие проблемы видишь. Не шаблон' : 'Research the client: what they do, what problems you see. Not a template')},'
        '${bullet(ru ? 'Предложи конкретику: «вижу, что у вас… я могу… за X»' : 'Offer specifics: "I see you have… I can… for X"')},'
        '${bullet(ru ? 'Коротко: 3–4 предложения. Длинные письма не читают' : 'Short: 3–4 sentences. Long emails are not read')},'
        '${bullet(ru ? 'Признай риск: «я понимаю, что это холодное письмо, но…» — снижает защиту' : 'Acknowledge risk: "I understand this is a cold email, but…" — lowers defense')},'
        '${bullet(ru ? 'Не жди ответа на каждое. Конверсия 1–3% — норма. 100 писем = 1–3 клиента' : 'Do not expect reply to every one. 1–3% conversion is normal. 100 emails = 1–3 clients')},'
        '${br()},'
        '${h2(ru ? 'Минимальный оффер' : 'Minimum Viable Offer')},'
        '${p(ru ? 'Не продавай «всё под ключ». Продавай конкретный результат за конкретные деньги и срок.' : 'Do not sell "turnkey everything". Sell a specific result for specific money and time.')},'
        '${bullet(ru ? 'Чёткий скоуп: что входит, что не входит. Пропиши в договоре' : 'Clear scope: what is included, what is not. Specify in contract')},'
        '${bullet(ru ? 'Предоплата 30–50%: без предоплаты — хобби, не бизнес' : '30–50% upfront: without upfront — it is a hobby, not business')},'
        '${bullet(ru ? 'Первый проект — упрощённый: сделай хорошо, получи отзыв, масштабируй' : 'First project — simplified: do well, get review, scale')},'
        '${bullet(ru ? 'Документируй всё: переписка, договор, ТЗ. Wesi Treasury — фиксируй доходы и расходы по проекту' : 'Document everything: correspondence, contract, specs. Wesi Treasury — log project income and expenses')}'
        ']';

    final firstClients = article('wesios_first_clients', ru ? 'Первые клиенты' : 'First Clients', firstClientsBody,
        parentId: 'wesios_freelance',
        tags: ru ? ['клиенты', 'фриланс', 'холодные письма', 'оффер'] : ['clients', 'freelance', 'cold outreach', 'offer']);

    final redFlagsBody = '[${h1(ru ? 'Когда отказывать клиенту' : 'When to Refuse a Client')},'
        '${p(ru ? 'Не каждый клиент — твой клиент. Умение отказывать — навык, который экономит время, нервы и репутацию.' : 'Not every client is your client. Ability to say no — a skill that saves time, nerves, and reputation.')},'
        '${br()},'
        '${h2(ru ? 'Красные флаги до начала' : 'Red Flags Before Start')},'
        '${bullet(ru ? '«Сделаешь быстро?» — без ТЗ, без срока, без бюджета. Это не проект, а исследование' : '"Can you do it quickly?" — without specs, timeline, budget. This is not a project, but research')},'
        '${bullet(ru ? '«Денег нет, но будет потом» — обещания не платят счета' : '"No money now, but later" — promises do not pay bills')},'
        '${bullet(ru ? '«Друг сказал, что это просто» — не ценит экспертизу, будет торговаться' : '"My friend said it is simple" — does not value expertise, will haggle')},'
        '${bullet(ru ? '«Уже работал с 5 фрилансерами, все плохие» — клиент — проблема, не исполнители' : '"Already worked with 5 freelancers, all bad" — the client is the problem, not the executors')},'
        '${bullet(ru ? 'Не хочет договор — значит, не собирается платить' : 'Does not want a contract — means they do not intend to pay')},'
        '${br()},'
        '${h2(ru ? 'Красные флаги в процессе' : 'Red Flags During the Project')},'
        '${bullet(ru ? 'Постоянные «маленькие правки» вне скоупа — это не правки, а бесплатная работа' : 'Constant "small fixes" outside scope — these are not fixes, but free work')},'
        '${bullet(ru ? 'Задержка оплаты без объяснения — первый звонок. Второй — тревога' : 'Payment delay without explanation — first bell. Second — alarm')},'
        '${bullet(ru ? '«Давай сначала сделаем, потом обсудим деньги» — классика мошенничества' : '"Let us do it first, then discuss money" — classic scam')},'
        '${bullet(ru ? 'Микроменеджмент: контроль каждый час, правки через 10 минут после сдачи' : 'Micromanagement: checking every hour, fixes 10 minutes after delivery')},'
        '${br()},'
        '${h2(ru ? 'Как отказать' : 'How to Refuse')},'
        '${bullet(ru ? 'Вежливо, но твёрдо: «Спасибо за предложение, но это не мой профиль/не по моей ставке»' : 'Politely but firmly: "Thank you for the offer, but this is not my profile/not my rate"')},'
        '${bullet(ru ? 'Не оправдывайся. «Занят» — достаточно. Подробности — слабость' : 'Do not justify. "Busy" is enough. Details are weakness')},'
        '${bullet(ru ? 'Предложи альтернативу: «Не могу, но знаю коллегу, который…» — репутация растёт' : 'Offer alternative: "I cannot, but I know a colleague who…" — reputation grows')},'
        '${bullet(ru ? 'Запиши в Wesi Treasury: почему отказал. Через месяц увидишь паттерн — кто твой клиент' : 'Log in Wesi Treasury: why you refused. In a month you will see the pattern — who is your client')}'
        ']';

    final redFlags = article('wesios_red_flags', ru ? 'Когда отказывать' : 'When to Refuse', redFlagsBody,
        parentId: 'wesios_freelance',
        tags: ru ? ['клиенты', 'красные флаги', 'отказ', 'фриланс'] : ['clients', 'red flags', 'refusal', 'freelance']);

    final accountingBody = '[${h1(ru ? 'Бухгалтерия на пальцах' : 'Accounting in Plain Terms')},'
        '${p(ru ? 'Бухгалтерия — не страх, а инструмент. Если вести сразу — потом не будет головной боли.' : 'Accounting is not fear, but a tool. If you keep it up — there will be no headache later.')},'
        '${br()},'
        '${h2(ru ? 'Что писать в Wesi Treasury' : 'What to Log in Wesi Treasury')},'
        '${bullet(ru ? 'Каждый доход: дата, клиент, сумма, валюта, проект. Сразу, не «потом вспомню»' : 'Every income: date, client, amount, currency, project. Immediately, not "I will remember later"')},'
        '${bullet(ru ? 'Каждый расход: дата, категория, сумма, чек/квитанция. Фото чека — обязательно' : 'Every expense: date, category, amount, receipt. Photo of receipt — mandatory')},'
        '${bullet(ru ? 'Налоги: откладывай 6% (УСН) или 13% (НДФЛ) с каждого дохода на отдельный счёт' : 'Taxes: set aside 6% (simplified tax) or 13% (income tax) from every income to a separate account')},'
        '${bullet(ru ? 'Валюта: если работаешь с иностранцами — фиксируй курс на дату. Treasury хранит в RUB-эквиваленте' : 'Currency: if working with foreigners — log rate on date. Treasury stores in RUB equivalent')},'
        '${br()},'
        '${h2(ru ? 'Что хранить' : 'What to Keep')},'
        '${bullet(ru ? 'Чеки и квитанции: 5 лет. Цифровые копии — в облаке' : 'Receipts and invoices: 5 years. Digital copies — in cloud')},'
        '${bullet(ru ? 'Договоры: бессрочно, пока не истёк срок исковой давности' : 'Contracts: indefinitely, until statute of limitations expires')},'
        '${bullet(ru ? 'Выписки банка: 3 года для налоговой' : 'Bank statements: 3 years for tax office')},'
        '${bullet(ru ? 'Акты выполненных работ: подписанные клиентом. Без подписи — доказательств нет' : 'Work completion acts: signed by client. Without signature — no proof')},'
        '${br()},'
        '${h2(ru ? 'Простая схема учёта' : 'Simple Accounting Scheme')},'
        '${numbered(ru ? 'Получил деньги → сразу в Treasury (доход)' : 'Received money → immediately in Treasury (income)')},'
        '${numbered(ru ? 'Отложил налоги (6–13%) на отдельный счёт' : 'Set aside taxes (6–13%) to separate account')},'
        '${numbered(ru ? 'Заплатил за расход → сразу в Treasury (расход)' : 'Paid for expense → immediately in Treasury (expense)')},'
        '${numbered(ru ? 'Раз в месяц: проверь баланс, заплати налоги, сделай выписку' : 'Once a month: check balance, pay taxes, make statement')},'
        '${numbered(ru ? 'Раз в квартал: сверь с банком, подготовь декларацию' : 'Once a quarter: reconcile with bank, prepare declaration')},'
        '${numbered(ru ? 'Раз в год: налоговая декларация, проверь вычеты' : 'Once a year: tax declaration, check deductions')}'
        ']';

    final accounting = article('wesios_accounting', ru ? 'Бухгалтерия на пальцах' : 'Simple Accounting', accountingBody,
        parentId: 'wesios_freelance',
        tags: ru ? ['бухгалтерия', 'налоги', 'учёт', 'Treasury'] : ['accounting', 'taxes', 'tracking', 'Treasury']);

    final stabilityBody = '[${h1(ru ? 'Выход на стабильность' : 'Reaching Stability')},'
        '${p(ru ? 'Фриланс — волна. Стабильность — это когда волны не топят, а качат.' : 'Freelance is a wave. Stability is when waves do not drown, but rock.')},'
        '${br()},'
        '${h2(ru ? 'Ретейнеры' : 'Retainers')},'
        '${bullet(ru ? 'Фиксированная ежемесячная оплата за фиксированный объём работы. Предсказуемый доход' : 'Fixed monthly payment for fixed scope of work. Predictable income')},'
        '${bullet(ru ? 'Начни с 1 клиента. 20–30% времени под ретейнер — остальное на проекты' : 'Start with 1 client. 20–30% time under retainer — rest on projects')},'
        '${bullet(ru ? 'Условия: чёткий скоуп, часы, канал связи, срок оплаты (аванс!)' : 'Terms: clear scope, hours, communication channel, payment term (advance!)')},'
        '${bullet(ru ? 'Не больше 2–3 ретейнеров — иначе превращаешься в наёмного' : 'No more than 2–3 retainers — otherwise you become an employee')},'
        '${br()},'
        '${h2(ru ? 'Пакеты' : 'Packages')},'
        '${bullet(ru ? 'Не продавай часы — продавай результат. «Сайт за X» лучше, чем «100 часов по Y»' : 'Do not sell hours — sell results. "Site for X" is better than "100 hours at Y"')},'
        '${bullet(ru ? '3 пакета: базовый, стандартный, премиум. 80% выбирают средний' : '3 packages: basic, standard, premium. 80% choose middle')},'
        '${bullet(ru ? 'Пакет = скоуп + срок + правки + поддержка. Всё прописано заранее' : 'Package = scope + timeline + revisions + support. Everything specified in advance')},'
        '${br()},'
        '${h2(ru ? 'Повторные продажи' : 'Repeat Sales')},'
        '${p(ru ? 'Новый клиент в 5–7 раз дороже, чем старый. Инвестируй в отношения.' : 'New client is 5–7 times more expensive than old one. Invest in relationships.')},'
        '${bullet(ru ? 'После проекта: напиши через неделю — всё работает? Нужна ли поддержка?' : 'After project: write in a week — everything working? Need support?')},'
        '${bullet(ru ? 'Предложи обслуживание: обновления, бэкапы, мониторинг — пассивный доход' : 'Offer maintenance: updates, backups, monitoring — passive income')},'
        '${bullet(ru ? 'Запиши в Wesi Treasury: дата контакта, результат, следующий шаг' : 'Log in Wesi Treasury: contact date, result, next step')},'
        '${bullet(ru ? 'День рождения клиента — напиши. Мелочь, но запоминается' : 'Client\'s birthday — write. Small thing, but memorable')},'
        '${br()},'
        '${h2(ru ? 'Метрики стабильности' : 'Stability Metrics')},'
        '${bullet(ru ? 'Предсказуемый доход: 50%+ от ретейнеров и повторных продаж' : 'Predictable income: 50%+ from retainers and repeat sales')},'
        '${bullet(ru ? 'Подушка: 6 месяцев расходов на отдельном счёте' : 'Cushion: 6 months of expenses on separate account')},'
        '${bullet(ru ? 'Разнообразие: не более 30% дохода от одного клиента' : 'Diversity: no more than 30% income from one client')},'
        '${bullet(ru ? 'Время: 20% времени на поиск клиентов — норма. Если 50% — кризис' : 'Time: 20% time on client acquisition is normal. If 50% — crisis')}'
        ']';

    final stability = article('wesios_stability', ru ? 'Выход на стабильность' : 'Reaching Stability', stabilityBody,
        parentId: 'wesios_freelance',
        tags: ru ? ['стабильность', 'ретейнеры', 'пакеты', 'продажи'] : ['stability', 'retainers', 'packages', 'sales']);
    // ═══════════════════════════════════════════════════════════════════════
    //  МЕТА (про саму базу)
    // ═══════════════════════════════════════════════════════════════════════

    final metaFolder = folder('wesios_meta', ru ? 'Мета' : 'Meta', parentId: 'wesios_kb');

    final howToUseBody = '[${h1(ru ? 'Как пользоваться этой базой' : 'How to Use This Knowledge Base')},'
        '${p(ru ? 'База знаний WesiOS — не энциклопедия, а практичный справочник. Читай выборочно, применяй сразу.' : 'WesiOS Knowledge Base is not an encyclopedia, but a practical handbook. Read selectively, apply immediately.')},'
        '${br()},'
        '${h2(ru ? 'Если «всё горит»' : 'If Everything Is on Fire')},'
        '${p(ru ? 'Когда кризис — не читай всё подряд. Сфокусируйся на одном:' : 'When in crisis — do not read everything. Focus on one:')},'
        '${numbered(ru ? 'Деньги горят → «Долги: как гасить» + открой Wesi Treasury, посмотри реальную картину' : 'Money is burning → "Debt: How to Pay Off" + open Wesi Treasury, see the real picture')},'
        '${numbered(ru ? 'Выгорание → «Отдых как навык» + «Стресс и тревога» + сделай перерыв сегодня' : 'Burnout → "Rest as a Skill" + "Stress & Anxiety" + take a break today')},'
        '${numbered(ru ? 'Конфликт → «Общение: сложные разговоры» + напиши письмо, не отправляй сразу' : 'Conflict → "Communication: Difficult Conversations" + write a letter, do not send immediately')},'
        '${numbered(ru ? 'Нет клиентов → «Первые клиенты» + напиши 10 холодных писем сегодня' : 'No clients → "First Clients" + write 10 cold emails today')},'
        '${numbered(ru ? 'Не знаю, куда расти → «Обучение без выгорания» + «Смена профессии»' : 'Do not know where to grow → "Learning Without Burnout" + "Career Change"')},'
        '${br()},'
        '${h2(ru ? 'Если «хочу расти»' : 'If You Want to Grow')},'
        '${p(ru ? 'Когда есть ресурс — читай системно. План на квартал:' : 'When you have resources — read systematically. Quarterly plan:')},'
        '${numbered(ru ? 'Месяц 1: Деньги → «Долги», «Страхование», «Пенсия». Зафиксируй в Treasury' : 'Month 1: Money → "Debt", "Insurance", "Pension". Log in Treasury')},'
        '${numbered(ru ? 'Месяц 2: Работа → «Обучение», «Переговоры», «Удалёнка». Примени на практике' : 'Month 2: Work → "Learning", "Negotiations", "Remote". Apply in practice')},'
        '${numbered(ru ? 'Месяц 3: Голова → «Стресс», «Общение», «Привычки». Веди дневник' : 'Month 3: Mind → "Stress", "Communication", "Habits". Keep a journal')},'
        '${br()},'
        '${h2(ru ? 'Как работать со статьями' : 'How to Work With Articles')},'
        '${bullet(ru ? 'Не читай про запас — читай, когда тема актуальна' : 'Do not read in advance — read when the topic is relevant')},'
        '${bullet(ru ? 'Выделяй главное: используй редактор WesiOS, добавляй заметки' : 'Highlight key points: use WesiOS editor, add notes')},'
        '${bullet(ru ? 'Делись: перешли коллеге, обсудите. Обучение через обсуждение — мощнее' : 'Share: forward to colleague, discuss. Learning through discussion is stronger')},'
        '${bullet(ru ? 'Возвращайся: перечитывай через месяц. Новый контекст — новое понимание' : 'Come back: re-read in a month. New context — new understanding')},'
        '${bullet(ru ? 'Дополняй: если нашёл ошибку или хочешь добавить — напиши в Issues репозитория' : 'Add: if you found an error or want to add — write in repository Issues')}'
        ']';

    final howToUse = article('wesios_how_to_use', ru ? 'Как пользоваться базой' : 'How to Use This Base', howToUseBody,
        parentId: 'wesios_meta',
        tags: ru ? ['мета', 'навигация', 'база знаний', 'WesiOS'] : ['meta', 'navigation', 'knowledge base', 'WesiOS']);

    final quarterlyBody = '[${h1(ru ? 'Чеклист квартала' : 'Quarterly Checklist')},'
        '${p(ru ? '10 вопросов раз в 3 месяца. 30 минут честных ответов — лучше, чем год самообмана.' : '10 questions every 3 months. 30 minutes of honest answers — better than a year of self-deception.')},'
        '${br()},'
        '${h2(ru ? 'Деньги' : 'Money')},'
        '${numbered(ru ? 'Моя подушка безопасности: сколько месяцев расходов? (цель: 3–6)' : 'My safety cushion: how many months of expenses? (goal: 3–6)')},'
        '${numbered(ru ? 'Мой долг: растёт или падает? Какой план погашения?' : 'My debt: growing or falling? What is the repayment plan?')},'
        '${numbered(ru ? 'Мои доходы: откуда 80%? Если от 1 источника — риск' : 'My income: where does 80% come from? If from 1 source — risk')},'
        '${br()},'
        '${h2(ru ? 'Энергия' : 'Energy')},'
        '${numbered(ru ? 'Как я чувствую себя по утрам? (1–10) Тенденция?' : 'How do I feel in the morning? (1–10) Trend?')},'
        '${numbered(ru ? 'Сколько часов в неделю я работаю? (цель: 40–50, не 60+)' : 'How many hours do I work per week? (goal: 40–50, not 60+)')},'
        '${numbered(ru ? 'Когда последний раз был полноценный отпуск? (цель: каждые 3 месяца)' : 'When was the last real vacation? (goal: every 3 months)')},'
        '${br()},'
        '${h2(ru ? 'Смысл' : 'Meaning')},'
        '${numbered(ru ? 'Чем я занимаюсь — моё? Или «надо» / «привычка»?' : 'What I do — is it mine? Or "should" / "habit"?')},'
        '${numbered(ru ? 'Что я выучил за квартал? 1 новый навык или 1 глубокое знание' : 'What did I learn this quarter? 1 new skill or 1 deep knowledge')},'
        '${br()},'
        '${h2(ru ? 'Отношения' : 'Relationships')},'
        '${numbered(ru ? 'С кем я провожу больше всего времени? Эти люди меня растят или тянут вниз?' : 'Who do I spend the most time with? Do these people grow me or pull me down?')},'
        '${numbered(ru ? 'Когда последний раз говорил «нет»? Если давно — проверь границы' : 'When did I last say "no"? If long ago — check boundaries')},'
        '${br()},'
        '${h2(ru ? 'Что делать с ответами' : 'What to Do With Answers')},'
        '${bullet(ru ? 'Зафиксируй в Wesi Treasury: создай транзакцию «Квартальный обзор» с заметками' : 'Log in Wesi Treasury: create a transaction "Quarterly Review" with notes')},'
        '${bullet(ru ? 'Выбери 1 действие на квартал. Не 10 — одно. Сфокусируйся' : 'Choose 1 action for the quarter. Not 10 — one. Focus')},'
        '${bullet(ru ? 'Поставь напоминание через 3 месяца. Цикл повторяется' : 'Set a reminder for 3 months. Cycle repeats')}'
        ']';

    final quarterly = article('wesios_quarterly', ru ? 'Чеклист квартала' : 'Quarterly Checklist', quarterlyBody,
        parentId: 'wesios_meta',
        tags: ru ? ['чеклист', 'квартал', 'рефлексия', 'рост'] : ['checklist', 'quarterly', 'reflection', 'growth']);

    // ═══════════════════════════════════════════════════════════════════════
    //  RETURN ALL ARTICLES
    // ═══════════════════════════════════════════════════════════════════════

    return [
      // Money
      moneyFolder, debts, insurance, pension, moneyPsych,
      // Work
      workFolder, learning, careerChange, negotiations, remote,
      // Mind
      mindFolder, stress, communication, loneliness, comparison,
      // Habits
      habitsFolder, habitForm, digitalMin, decisions,
      // Life
      lifeFolder, homeLife, rest, expVsThings, legal,
      // Freelance
      freelanceFolder, firstClients, redFlags, accounting, stability,
      // Meta
      metaFolder, howToUse, quarterly,
      // Root
      root,
      about,
      // Modules folder
      modulesFolder,
      // Treasury
      treasuryFolder, treasury,
      // Forecast
      forecastFolder, forecast,
      // Sandbox
      sandboxFolder, sandbox,
      // Shield
      shieldFolder, shield,
      // Tasks
      tasksFolder, tasks,
      // Calculator
      calcFolder, calc,
      // Calendar
      calendarFolder, calendar,
      // Analytics
      analyticsFolder, analytics,
      // Home
      homeFolder, home,
      // Profile
      profileFolder, profile,
      // Settings
      settingsFolder, settings,
      // Knowledge Base
      kbFolder, kb,
      // Services folder
      servicesFolder,
      localeArticle,
      currencyArticle,
      updateArticle,
      // Architecture folder
      archFolder,
      arch,
    ];
  }
}
