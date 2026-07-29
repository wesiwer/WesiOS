import 'package:hive_flutter/hive_flutter.dart';

/// Поддерживаемые валюты и курсы к RUB (базовая).
/// Курсы обновляются через ExchangeRateService (ЦБ / fallback).
class CurrencyService {
  static const String _boxName = 'wesios_settings';
  static const String _key = 'app_currency';

  /// code -> (symbol, nameRu, nameEn)
  static const Map<String, List<String>> currencies = {
    'rub': ['₽', 'Российский рубль', 'Russian Ruble'],
    'usd': ['\$', 'Доллар США', 'US Dollar'],
    'eur': ['€', 'Евро', 'Euro'],
    'gbp': ['£', 'Фунт стерлингов', 'British Pound'],
    'cny': ['¥', 'Китайский юань', 'Chinese Yuan'],
    'uah': ['₴', 'Украинская гривна', 'Ukrainian Hryvnia'],
    'byn': ['Br', 'Белорусский рубль', 'Belarusian Ruble'],
    'kzt': ['₸', 'Казахстанский тенге', 'Kazakhstani Tenge'],
  };

  /// Страны, где валюта является национальной, и флаг для быстрого узнавания.
  /// Нужно, чтобы по коду валюты было понятно, о какой стране речь.
  static const Map<String, List<String>> _countries = {
    'rub': ['🇷🇺', 'Россия', 'Russia'],
    'usd': ['🇺🇸', 'США', 'United States'],
    'eur': ['🇪🇺', 'Еврозона', 'Eurozone'],
    'gbp': ['🇬🇧', 'Великобритания', 'United Kingdom'],
    'cny': ['🇨🇳', 'Китай', 'China'],
    'uah': ['🇺🇦', 'Украина', 'Ukraine'],
    'byn': ['🇧🇾', 'Беларусь', 'Belarus'],
    'kzt': ['🇰🇿', 'Казахстан', 'Kazakhstan'],
  };

  static String flag(String code) => _countries[code]?[0] ?? '';

  static String countryName(String code, {bool russian = true}) {
    final c = _countries[code];
    if (c == null) return '';
    return russian ? c[1] : c[2];
  }

  static String currencyName(String code, {bool russian = true}) {
    final c = currencies[code];
    if (c == null) return code.toUpperCase();
    return russian ? c[1] : c[2];
  }

  static String symbolOf(String code) => currencies[code]?[0] ?? '';

  /// Курсы: сколько единиц валюты за 1 RUB (хранятся как «за 1 USD» и пересчитываются).
  /// Значения по умолчанию; живые — через setRates().
  static Map<String, double> _ratesToRub = {
    'rub': 1.0,
    'usd': 90.0,
    'eur': 98.0,
    'gbp': 115.0,
    'cny': 12.5,
    'uah': 2.2,
    'byn': 28.0,
    'kzt': 0.18,
  };

  static String get current {
    try {
      final box = Hive.box(_boxName);
      final code = box.get(_key, defaultValue: 'rub') as String;
      return currencies.containsKey(code) ? code : 'rub';
    } catch (_) {
      return 'rub';
    }
  }

  static String get symbol => currencies[current]?[0] ?? '₽';

  static String name({bool russian = true}) {
    final list = currencies[current];
    if (list == null) return current;
    return russian ? list[1] : list[2];
  }

  static Future<void> set(String code) async {
    final box = Hive.box(_boxName);
    await box.put(_key, currencies.containsKey(code) ? code : 'rub');
  }

  /// Обновить курсы: map code -> сколько RUB за 1 единицу валюты
  static void setRates(Map<String, double> rates) {
    _ratesToRub = {..._ratesToRub, ...rates, 'rub': 1.0};
  }

  static double rateToRub(String code) => _ratesToRub[code] ?? 1.0;

  /// value хранится в «внутренних» единицах (RUB-эквивалент).
  /// Показываем в выбранной валюте.
  static double fromRub(double rubAmount) {
    final rate = rateToRub(current);
    if (rate == 0) return rubAmount;
    return rubAmount / rate;
  }

  static double toRub(double amountInCurrent) {
    return amountInCurrent * rateToRub(current);
  }

  static String format(double rubValue, {int decimals = 0}) {
    final v = fromRub(rubValue);
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1000000) {
      return '$sign$symbol${(abs / 1000000).toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      return '$sign$symbol${(abs / 1000).toStringAsFixed(1)}k';
    }
    return '$sign$symbol${abs.toStringAsFixed(decimals)}';
  }

  static List<String> get codes => currencies.keys.toList();
}
