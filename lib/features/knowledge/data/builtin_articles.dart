import '../../../core/constants/app_version.dart';
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
    String h1(String t) => '{"insert":"$t\\n","attributes":{"header":1}}';
    String h2(String t) => '{"insert":"$t\\n","attributes":{"header":2}}';
    String h3(String t) => '{"insert":"$t\\n","attributes":{"header":3}}';
    String p(String t) => '{"insert":"$t\\n"}';
    String bold(String t) => '{"insert":"$t","attributes":{"bold":true}}';
    String italic(String t) => '{"insert":"$t","attributes":{"italic":true}}';
    String link(String text, String url) => '{"insert":"$text","attributes":{"link":"$url"}}';
    String bullet(String t) => '{"insert":"$t\\n","attributes":{"list":"bullet"}}';
    String numbered(String t) => '{"insert":"$t\\n","attributes":{"list":"ordered"}}';
    String br() => '{"insert":"\\n"}';
    String embedImage(String url) => '{"insert":{"image":"$url"}}';
    String embedVideo(String url) => '{"insert":{"video":"$url"}}';
    String embedTable(String json) => '{"insert":{"table":"$json"}}';
    String embedChart(String json) => '{"insert":{"chart":"$json"}}';

    // ─── Chart data helpers ─────────────────────────────────────────────────
    String chartBar(String title, List<String> labels, List<double> values) =>
        '{"type":"bar","title":"$title","source":"manual","data":${values.toString()},"labels":${labels.map((l) => '"$l"').toList().toString()}}';
    String chartLine(String title, List<String> labels, List<double> values) =>
        '{"type":"line","title":"$title","source":"manual","data":${values.toString()},"labels":${labels.map((l) => '"$l"').toList().toString()}}';
    String chartPie(String title, List<String> labels, List<double> values) =>
        '{"type":"pie","title":"$title","source":"manual","data":${values.toString()},"labels":${labels.map((l) => '"$l"').toList().toString()}}';
    String chartLinked(String type, String source, String title) =>
        '{"type":"$type","title":"$title","source":"$source","data":[],"labels":[]}';

    // ─── Table data helper ──────────────────────────────────────────────────
    String tableJson(List<List<String>> rows) {
      final encoded = rows.map((r) => r.map((c) => '"$c"').join(',')).join('],[');
      return '[[$encoded]]';
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  ROOT FOLDER: WesiOS
    // ═══════════════════════════════════════════════════════════════════════

    // ─── Root folder ────────────────────────────────────────────────────────
    final root = folder('wesios_root', ru ? 'WesiOS' : 'WesiOS');

    // ─── About article ──────────────────────────────────────────────────────
    final aboutBody = '[${h1(ru ? 'WesiOS — персональная операционная система' : 'WesiOS — Personal Operating System')},'
        '${p(ru ? 'WesiOS — это комплексная система управления личными и профессиональными процессами. Объединяет финансы, задачи, аналитику, базу знаний и инструменты в едином интерфейсе.' : 'WesiOS is a comprehensive system for managing personal and professional processes. Combines finance, tasks, analytics, knowledge base and tools in a unified interface.')},'
        '${h2(ru ? 'Версия' : 'Version')},'
        '${p('${AppVersion.fullLabel}')},'
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
    //  RETURN ALL ARTICLES
    // ═══════════════════════════════════════════════════════════════════════

    return [
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
