import 'package:hive_flutter/hive_flutter.dart';

/// Глобальная валюта приложения: rub | usd
class CurrencyService {
  static const String _boxName = 'wesios_settings';
  static const String _key = 'app_currency';

  static String get current {
    try {
      final box = Hive.box(_boxName);
      return box.get(_key, defaultValue: 'rub') as String;
    } catch (_) {
      return 'rub';
    }
  }

  static bool get isRub => current == 'rub';
  static bool get isUsd => current == 'usd';

  static String get symbol => isRub ? '₽' : '\$';

  static Future<void> set(String code) async {
    final box = Hive.box(_boxName);
    await box.put(_key, code == 'usd' ? 'usd' : 'rub');
  }

  static String format(double value, {int decimals = 0}) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000) {
      return '$sign$symbol${(abs / 1000).toStringAsFixed(1)}k';
    }
    return '$sign$symbol${abs.toStringAsFixed(decimals)}';
  }
}
