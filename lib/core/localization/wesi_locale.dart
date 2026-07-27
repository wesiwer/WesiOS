import 'package:flutter/material.dart';
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

      'wesi_sandbox_title': 'Wesi Sandbox',
      'wesi_sandbox_desc': 'Изолированная среда для тестирования финансовых сценариев. Полностью повторяет функционал Wesi Treasury, но работает с отдельными данными. Позволяет безопасно экспериментировать с сценариями "что если".',
      'wesi_sandbox_purpose': 'Тестируйте гипотезы без риска испортить реальные данные. Проверяйте сценарии перед принятием решений.',

      // UI
      'current_balance': 'Текущий баланс',
      'last_30_days': 'за последние 30 дней',
      'transactions': 'Транзакции',
      'recurring': 'Регулярные платежи',
      'anomalies': 'Аномалии',
      'forecast': 'Прогноз',
      'add_income': 'Добавить доход',
      'add_expense': 'Добавить расход',
      'sales': 'Продажи',
      'expenses': 'Расходы',
      'voice': 'Голос',
      'calculator': 'Калькулятор',
      'net_position': 'чистая позиция',
      'sandbox_mode': 'РЕЖИМ ПЕСОЧНИЦЫ',
      'scenario': 'Сценарий',
      'data_isolated': 'Данные изолированы',
      'no_impact': 'Без влияния на реальные записи',
      'quick_scenarios': 'Быстрые сценарии',
      'sandbox_balance': 'Баланс песочницы',
      'test': 'ТЕСТ',
    },
    'en': {
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

      'wesi_sandbox_title': 'Wesi Sandbox',
      'wesi_sandbox_desc': 'Isolated environment for testing financial scenarios. Fully replicates Wesi Treasury functionality but works with separate data. Allows safe experimentation with "what if" scenarios.',
      'wesi_sandbox_purpose': 'Test hypotheses without risk of damaging real data. Validate scenarios before making decisions.',

      'current_balance': 'Current Balance',
      'last_30_days': 'last 30 days',
      'transactions': 'Transactions',
      'recurring': 'Recurring',
      'anomalies': 'Anomalies',
      'forecast': 'Forecast',
      'add_income': 'Add Income',
      'add_expense': 'Add Expense',
      'sales': 'Sales',
      'expenses': 'Expenses',
      'voice': 'Voice',
      'calculator': 'Calculator',
      'net_position': 'net position',
      'sandbox_mode': 'SANDBOX MODE',
      'scenario': 'Scenario',
      'data_isolated': 'Data is isolated',
      'no_impact': 'No impact on real records',
      'quick_scenarios': 'Quick Scenarios',
      'sandbox_balance': 'Sandbox Balance',
      'test': 'TEST',
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

  static Future<void> setLanguage(String lang) async {
    final box = Hive.box(_boxName);
    await box.put(_key, lang);
  }

  static String get currentLanguage => _getSavedLanguage();

  static bool get isRussian => currentLanguage == 'ru';
  static bool get isEnglish => currentLanguage == 'en';
}

/// Extension для удобного использования в виджетах
extension WesiLocaleString on String {
  String get w => WesiLocale.get(this);
}
