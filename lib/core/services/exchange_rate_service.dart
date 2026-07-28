import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'currency_service.dart';

/// Курсы валют. Источник: exchangerate.host (бесплатный, без ключа)
/// Fallback: зашитые курсы в CurrencyService.
class ExchangeRateService {
  static const _url =
      'https://api.exchangerate.host/latest?base=RUB&symbols=USD,EUR,GBP,CNY,UAH,BYN,KZT';

  static DateTime? lastUpdated;

  /// Сколько RUB за 1 единицу валюты
  static Future<bool> refresh() async {
    try {
      final res = await http.get(Uri.parse(_url)).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = data['rates'] as Map<String, dynamic>?;
      if (rates == null) return false;

      // API отдаёт: 1 RUB = X USD → нам нужно 1 USD = 1/X RUB
      final map = <String, double>{'rub': 1.0};
      for (final entry in rates.entries) {
        final code = entry.key.toLowerCase();
        final v = (entry.value as num).toDouble();
        if (v > 0) map[code] = 1.0 / v;
      }
      CurrencyService.setRates(map);
      lastUpdated = DateTime.now();
      debugPrint('Exchange rates updated: $map');
      return true;
    } catch (e) {
      debugPrint('ExchangeRateService failed: $e');
      return false;
    }
  }
}
