import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// WesiLocale — система локализации WesiOS.
///
/// Поддерживает русский и английский языки.
/// Язык сохраняется в Hive и применяется при перезапуске.
class WesiLocale {
  static const String _boxName = 'wesios_settings';
  static const String _key = 'app_language';

  static final Map<String, Map<String, String>> _strings = {
    'ru': {
      // Systems
      'wesi_treasury_title': 'Wesi Treasury',
      'wesi_treasury_desc': 'Полная система управления финансами. Отслеживайте доходы, расходы, выявляйте аномалии с помощью Z-score анализа, управляйте регулярными платежами и прогнозируйте будущий баланс с помощью симуляции Монте-Карло.',
      'wesi_treasury_purpose': 'Даёт вам полный контроль над финансами с помощью ИИ-аналитики и предиктивной аналитики.',

      'wesi_sales_title': 'Wesi Sales',
      'wesi_sales_desc': 'Записывайте и отслеживайте все входящие доходы, клиентские платежи и продажи. Автоматически категоризирует источники дохода и обновляет баланс в реальном времени.',
      'wesi_sales_purpose': 'Помогает понять, откуда приходят деньги, и выявить самые прибыльные каналы.',

      'wesi_expenses_title': 'Wesi Expenses',
      'wesi_expenses_desc': 'Отслеживайте каждый исходящий платёж — от канцтоваров до зарплат. Использует Z-score детекцию аномалий для автоматического выявления подозрительных трат.',
      'wesi_expenses_purpose': 'Держит расходы под контролем и предупреждает о возможном мошенничестве или ошибках до того, как они станут проблемой.',

      'wesi_voice_title': 'Wesi Voice',
      'wesi_voice_desc': 'Система голосового ввода. Говорите естественно, чтобы создавать задачи, записывать заметки или логировать транзакции без касания клавиатуры.',
      'wesi_voice_purpose': 'Экономит время и мгновенно фиксирует идеи, даже когда руки заняты другой работой.',

      'wesi_calculator_title': 'Wesi Calculator',
      'wesi_calculator_desc': 'Продвинутый калькулятор с поддержкой выражений, ввода с клавиатуры и истории. Обрабатывает сложные формулы со скобками и операторами.',
      'wesi_calculator_purpose': 'Быстрая математика без выхода из рабочего процесса. Поддерживает горячие клавиши для максимальной скорости.',

      'wesi_forecast_title': 'Wesi Treasury Forecast',
      'wesi_forecast_desc': 'Финансовое прогнозирование на основе Монте-Карло с доверительными интервалами P10/P50/P90. Анализирует историю транзакций для предсказания будущего баланса со статистической точностью.',
      'wesi_forecast_purpose': 'Увидьте, куда движутся ваши финансы. Планируйте вперёд с помощью data-driven доверительных интервалов, а не догадок.',

      // Forecast Screen
      'forecast': 'Прогноз',
      'breakdown': 'Структура',
      'trend': 'Тренд',
      'heatmap': 'Тепловая карта',
      'forecast_loading': 'Загрузка прогноза Wesi Treasury...',
      'monte_carlo_simulating': 'Запуск симуляции Монте-Карло...',
      'p50_in_days': 'P50 через {days} дн.',
      'p10_worst': 'P10 (Худший)',
      'p90_best': 'P90 (Лучший)',
      'lower_bound': 'Нижняя граница',
      'upper_bound': 'Верхняя граница',
      'display_options': 'Параметры отображения',
      'forecast_period': 'Период прогноза',
      'days': 'дн.',
      'today': 'Сегодня',
      'confidence_bands': 'Доверительные интервалы',
      'trend_line': 'Линия тренда',
      'p10_p90_range': 'Диапазон P10-P90',
      'weekly_activity_heatmap': 'Тепловая карта активности',
      'category_breakdown': 'Структура по категориям',
      'detected_anomalies': 'Обнаруженные аномалии',
      'currency_rub': '₽',
      'currency_usd': '\$',
      'currency_eur': '€',
      'select_currency': 'Выберите валюту',
      'operations': 'Операции',
      'search_operations': 'Поиск операций...',
      'no_transactions': 'Нет операций',
      'sort_by_date': 'По дате',
      'sort_by_amount': 'По сумме',
      'sort_by_category': 'По категории',

      'wesi_sandbox_title': 'Wesi Sandbox',
      'wesi_sandbox_desc': 'Изолированная среда для тестирования финансовых сценариев. Полностью повторяет функционал Wesi Treasury, но работает с отдельными данными. Позволяет безопасно экспериментировать с сценариями "что если".',
      'wesi_sandbox_purpose': 'Тестируйте гипотезы без риска испортить реальные данные. Проверяйте сценарии перед принятием решений.',

      // Context Menu
      'click_to_open': 'Нажмите, чтобы открыть эту систему',

      // Home Screen
      'balance_wesi_inc': 'Баланс Wesi Inc',
      'operational': 'Операционный',
      'marketing': 'Маркетинг',
      'reserve': 'Резерв',
      'calendar': 'Календарь',
      'all': 'Все',
      'no_events': 'Нет запланированных событий',
      'tasks': 'Задачи',
      'no_active_tasks': 'Нет активных задач',
      'create_first_task': 'Создайте первую задачу',
      'dashboard': 'Главная',
      'finances': 'Финансы',
      'analytics': 'Аналитика',
      'more': 'Ещё',

      // Treasury
      'current_balance': 'Текущий баланс',
      'total_income': 'Всего доходов',
      'total_expenses': 'Всего расходов',
      'net': 'Чистый',
      'anomalies_detected': 'Обнаружено аномалий',
      'recent_transactions': 'Последние транзакции',
      'forecast_p10_p50_p90': 'Прогноз P10/P50/P90',
      'monte_carlo_analysis': 'Анализ Монте-Карло с доверительными интервалами',
      'record_income': 'Записать доход или продажу',
      'record_expense': 'Записать расход',
      'loading_treasury': 'Загрузка Wesi Treasury...',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'title': 'Название',
      'amount': 'Сумма',
      'description_optional': 'Описание (необязательно)',
      'recurring_payment': 'Регулярный платёж',
      'category': 'Категория',
      'uncategorized': 'Без категории',
      'anomaly': 'АНОМАЛИЯ',
      'edit_operation': 'Редактировать операцию',
      'rate_cbr_on': 'Курс ЦБ на',
      'rate_fallback': 'Курс недоступен — резервное значение',
      'custom_range': 'Свой диапазон',
      'upload_avatar': 'Загрузить свою',
      'reset_avatar': 'Вернуть пресет',

      // Sandbox
      'sandbox_balance': 'Баланс песочницы',
      'sandbox_mode': 'РЕЖИМ ПЕСОЧНИЦЫ',
      'scenario': 'Сценарий',
      'data_isolated': 'Данные изолированы',
      'no_impact': 'Без влияния на реальные записи',
      'quick_scenarios': 'Быстрые сценарии',
      'test': 'ТЕСТ',
      'loading_sandbox': 'Загрузка изолированной среды...',
      'add_test_income': 'Добавить тестовый доход',
      'add_test_expense': 'Добавить тестовый расход',
      'sandbox_transactions': 'Транзакции песочницы',
      'clear_sandbox': 'Очистить песочницу',
      'only_in_sandbox': 'Эта транзакция существует только в песочнице',
      'add_to_sandbox': 'Добавить в песочницу',

      // Settings
      'settings': 'Настройки',
      'appearance': 'Внешний вид',
      'theme': 'Тема',
      'dark_monochrome': 'Тёмная монохромная',
      'language': 'Язык',
      'notifications': 'Уведомления',
      'push_notifications': 'Push-уведомления',
      'enabled': 'Включены',
      'email_notifications': 'Email-уведомления',
      'telegram_bot': 'Telegram-бот',
      'connect': 'Привязать',
      'privacy': 'Конфиденциальность',
      'privacy_mode': 'Privacy Mode',
      'hide_financial_data': 'Скрыть финансовые данные',
      'hotkeys': 'Горячие клавиши',
      'configure_hotkeys': 'Настроить хоткеи',
      'about_app': 'О приложении',
      'business_os': 'Business Operating System',
      'created_by': 'Создано Wesi Inc',
      'founder_story': 'История основателя',
      'about_wesios': 'О WesiOS',
      'data': 'Данные',
      'firebase_config': 'Firebase Config',
      'change_access_keys': 'Изменить ключи доступа',
      'export_backup': 'Экспорт бэкапа',
      'json_csv': 'JSON/CSV',
      'clear_cache': 'Очистить кэш',
      'delete_local_data': 'Удалить локальные данные',
      'select_language': 'Выберите язык',

      // Profile
      'profile': 'Профиль',
      'personal_info': 'Личная информация',
      'name': 'Имя',
      'email': 'Email',
      'birth_date': 'Дата рождения',
      'not_specified': 'Не указана',
      'gender': 'Пол',
      'not_specified_short': 'Не указан',
      'male': 'Мужской',
      'female': 'Женский',
      'country': 'Страна',
      'other': 'Другая',
      'keys_and_tokens': 'Ключи и токены',
      'firebase_project_config': 'Конфигурация Firebase проекта',
      'api_key': 'API Key',
      'app_id': 'App ID',
      'project_id': 'Project ID',
      'messaging_sender_id': 'Messaging Sender ID',
      'auth_domain': 'Auth Domain',
      'storage_bucket': 'Storage Bucket',
      'measurement_id': 'Measurement ID',
      'required_field': 'Обязательное поле',
      'saved': 'Сохранено',
      'config_cleared': 'Конфигурация очищена',
      'upload_custom': 'Загрузить свою',
      'upload_avatar_soon': 'Загрузка своей аватарки — скоро',

      // Tooltip
      'record_sale': 'Записать продажу или доход',
      'record_expense_tooltip': 'Зафиксировать расход',
      'voice_input': 'Голосовой ввод задачи или заметки',
      'wesi_calculator': 'Wesi Калькулятор — быстрые расчёты',
    },
    'en': {
      // Systems
      'wesi_treasury_title': 'Wesi Treasury',
      'wesi_treasury_desc': 'Complete financial management system. Track income, expenses, detect anomalies with Z-score analysis, manage recurring payments, and forecast future balance with Monte-Carlo simulation.',
      'wesi_treasury_purpose': 'Gives you full control over your finances with AI-powered insights and predictive analytics.',

      'wesi_sales_title': 'Wesi Sales',
      'wesi_sales_desc': 'Record and track all incoming revenue, client payments, and sales transactions. Automatically categorizes income sources and updates your balance in real-time.',
      'wesi_sales_purpose': 'Helps you understand where your money comes from and identify the most profitable channels.',

      'wesi_expenses_title': 'Wesi Expenses',
      'wesi_expenses_desc': 'Track every outgoing payment, from office supplies to salaries. Uses Z-score anomaly detection to flag unusual spending patterns automatically.',
      'wesi_expenses_purpose': 'Keeps your spending under control and alerts you to potential fraud or errors before they become problems.',

      'wesi_voice_title': 'Wesi Voice',
      'wesi_voice_desc': 'Hands-free input system. Speak naturally to create tasks, record notes, or log transactions without touching the keyboard.',
      'wesi_voice_purpose': 'Saves time and captures ideas instantly, even when your hands are busy with other work.',

      'wesi_calculator_title': 'Wesi Calculator',
      'wesi_calculator_desc': 'Advanced calculator with expression support, keyboard input, and history. Handles complex formulas with parentheses and operators.',
      'wesi_calculator_purpose': 'Quick math without leaving your workflow. Supports keyboard shortcuts for maximum speed.',

      'wesi_forecast_title': 'Wesi Treasury Forecast',
      'wesi_forecast_desc': 'Monte-Carlo powered financial forecasting with confidence intervals P10/P50/P90. Analyzes transaction history to predict future balance with statistical accuracy.',
      'wesi_forecast_purpose': 'See where your finances are heading. Plan ahead with data-driven confidence intervals, not guesswork.',

      // Forecast Screen
      'forecast': 'Forecast',
      'breakdown': 'Breakdown',
      'trend': 'Trend',
      'heatmap': 'Heatmap',
      'forecast_loading': 'Loading Wesi Treasury Forecast...',
      'monte_carlo_simulating': 'Running Monte-Carlo simulation...',
      'p50_in_days': 'P50 in {days} days',
      'p10_worst': 'P10 (Worst)',
      'p90_best': 'P90 (Best)',
      'lower_bound': 'Lower bound',
      'upper_bound': 'Upper bound',
      'display_options': 'Display Options',
      'forecast_period': 'Forecast Period',
      'days': 'days',
      'today': 'Today',
      'confidence_bands': 'Confidence Bands',
      'trend_line': 'Trend Line',
      'p10_p90_range': 'P10-P90 Range',
      'weekly_activity_heatmap': 'Weekly Activity Heatmap',
      'category_breakdown': 'Category Breakdown',
      'detected_anomalies': 'Detected Anomalies',
      'currency_rub': '₽',
      'currency_usd': '\$',
      'currency_eur': '€',
      'select_currency': 'Select Currency',
      'operations': 'Operations',
      'search_operations': 'Search operations...',
      'no_transactions': 'No transactions',
      'sort_by_date': 'By date',
      'sort_by_amount': 'By amount',
      'sort_by_category': 'By category',

      'wesi_sandbox_title': 'Wesi Sandbox',
      'wesi_sandbox_desc': 'Isolated environment for testing financial scenarios. Fully replicates Wesi Treasury functionality but works with separate data. Allows safe experimentation with "what if" scenarios.',
      'wesi_sandbox_purpose': 'Test hypotheses without risk of damaging real data. Validate scenarios before making decisions.',

      // Context Menu
      'click_to_open': 'Click to open this system',

      // Home Screen
      'balance_wesi_inc': 'Balance Wesi Inc',
      'operational': 'Operational',
      'marketing': 'Marketing',
      'reserve': 'Reserve',
      'calendar': 'Calendar',
      'all': 'All',
      'no_events': 'No scheduled events',
      'tasks': 'Tasks',
      'no_active_tasks': 'No active tasks',
      'create_first_task': 'Create your first task',
      'dashboard': 'Dashboard',
      'finances': 'Finances',
      'analytics': 'Analytics',
      'more': 'More',

      // Treasury
      'current_balance': 'Current Balance',
      'total_income': 'Total Income',
      'total_expenses': 'Total Expenses',
      'net': 'Net',
      'anomalies_detected': 'Anomalies Detected',
      'recent_transactions': 'Recent Transactions',
      'forecast_p10_p50_p90': 'Forecast P10/P50/P90',
      'monte_carlo_analysis': 'Monte-Carlo analysis with confidence intervals',
      'record_income': 'Record a new income or sale',
      'record_expense': 'Record a new expense',
      'loading_treasury': 'Loading Wesi Treasury...',
      'cancel': 'Cancel',
      'save': 'Save',
      'title': 'Title',
      'amount': 'Amount',
      'description_optional': 'Description (optional)',
      'recurring_payment': 'Recurring payment',
      'category': 'Category',
      'uncategorized': 'Uncategorized',
      'anomaly': 'ANOMALY',
      'edit_operation': 'Edit operation',
      'rate_cbr_on': 'CBR rate as of',
      'rate_fallback': 'Rate unavailable — using fallback',
      'custom_range': 'Custom range',
      'upload_avatar': 'Upload your own',
      'reset_avatar': 'Back to preset',

      // Sandbox
      'sandbox_balance': 'Sandbox Balance',
      'sandbox_mode': 'SANDBOX MODE',
      'scenario': 'Scenario',
      'data_isolated': 'Data is isolated',
      'no_impact': 'No impact on real records',
      'quick_scenarios': 'Quick Scenarios',
      'test': 'TEST',
      'loading_sandbox': 'Loading isolated environment...',
      'add_test_income': 'Add Test Income',
      'add_test_expense': 'Add Test Expense',
      'sandbox_transactions': 'Sandbox Transactions',
      'clear_sandbox': 'Clear sandbox',
      'only_in_sandbox': 'This transaction will only exist in the sandbox',
      'add_to_sandbox': 'Add to Sandbox',

      // Settings
      'settings': 'Settings',
      'appearance': 'Appearance',
      'theme': 'Theme',
      'dark_monochrome': 'Dark Monochrome',
      'language': 'Language',
      'notifications': 'Notifications',
      'push_notifications': 'Push Notifications',
      'enabled': 'Enabled',
      'email_notifications': 'Email Notifications',
      'telegram_bot': 'Telegram Bot',
      'connect': 'Connect',
      'privacy': 'Privacy',
      'privacy_mode': 'Privacy Mode',
      'hide_financial_data': 'Hide financial data',
      'hotkeys': 'Hotkeys',
      'configure_hotkeys': 'Configure hotkeys',
      'about_app': 'About App',
      'business_os': 'Business Operating System',
      'created_by': 'Created by Wesi Inc',
      'founder_story': 'Founder Story',
      'about_wesios': 'About WesiOS',
      'data': 'Data',
      'firebase_config': 'Firebase Config',
      'change_access_keys': 'Change access keys',
      'export_backup': 'Export Backup',
      'json_csv': 'JSON/CSV',
      'clear_cache': 'Clear Cache',
      'delete_local_data': 'Delete local data',
      'select_language': 'Select Language',

      // Profile
      'profile': 'Profile',
      'personal_info': 'Personal Information',
      'name': 'Name',
      'email': 'Email',
      'birth_date': 'Birth Date',
      'not_specified': 'Not specified',
      'not_specified_short': 'Not specified',
      'gender': 'Gender',
      'male': 'Male',
      'female': 'Female',
      'country': 'Country',
      'other': 'Other',
      'keys_and_tokens': 'Keys and Tokens',
      'firebase_project_config': 'Firebase Project Configuration',
      'api_key': 'API Key',
      'app_id': 'App ID',
      'project_id': 'Project ID',
      'messaging_sender_id': 'Messaging Sender ID',
      'auth_domain': 'Auth Domain',
      'storage_bucket': 'Storage Bucket',
      'measurement_id': 'Measurement ID',
      'required_field': 'Required field',
      'saved': 'Saved',
      'config_cleared': 'Configuration cleared',
      'upload_custom': 'Upload custom',
      'upload_avatar_soon': 'Custom avatar upload — coming soon',

      // Tooltip
      'record_sale': 'Record a sale or income',
      'record_expense_tooltip': 'Record an expense',
      'voice_input': 'Voice input for tasks and notes',
      'wesi_calculator': 'Wesi Calculator — quick calculations',
    },
  };

  static String get(String key, {String? language}) {
    final lang = language ?? _getSavedLanguage();
    return _strings[lang]?[key] ?? _strings['en']?[key] ?? key;
  }

  static String _getSavedLanguage() {
    try {
      final box = Hive.box(_boxName);
      return box.get(_key, defaultValue: 'ru');
    } catch (_) {
      return 'ru';
    }
  }

  /// Слушатель смены языка. `MaterialApp` подписан на него в `app.dart`,
  /// поэтому смена языка перестраивает всё дерево, а не только Settings.
  static final ValueNotifier<String> localeNotifier =
      ValueNotifier<String>(_getSavedLanguage());

  static Future<void> setLanguage(String lang) async {
    final box = Hive.box(_boxName);
    await box.put(_key, lang);
    localeNotifier.value = lang;
  }

  static String get currentLanguage => _getSavedLanguage();

  static bool get isRussian => currentLanguage == 'ru';
  static bool get isEnglish => currentLanguage == 'en';
}

/// Extension для удобного использования в виджетах
extension WesiLocaleString on String {
  String get w => WesiLocale.get(this);
}
