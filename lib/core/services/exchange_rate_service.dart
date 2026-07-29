import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'currency_service.dart';

/// Курсы валют.
///
/// Основной источник — официальный сайт ЦБ РФ (cbr.ru, XML_daily.asp).
/// Fallback-цепочка: exchangerate.host → зашитые курсы в [CurrencyService].
class ExchangeRateService {
  static const _cbrUrl = 'https://www.cbr.ru/scripts/XML_daily.asp';

  /// Запасной источник — без ключа и без регистрации.
  ///
  /// Прежний `api.exchangerate.host` сюда больше не годится: он перешёл на
  /// обязательный `access_key` и на запрос без ключа отвечает
  /// `{"success": false, ... "missing_access_key"}` со статусом 200. Из-за
  /// статуса 200 код считал ответ валидным, не находил `rates` и молча
  /// проваливался — то есть запасного источника фактически не существовало,
  /// и при недоступности ЦБ приложение откатывалось к зашитым курсам
  /// полугодовой давности.
  static const _fallbackUrl = 'https://open.er-api.com/v6/latest/RUB';

  /// На мобильном интернете ответ ЦБ (~9,5 КБ) на медленном канале не
  /// успевает прийти за 8 секунд — именно так курс и оставался «резервным».
  static const Duration _timeout = Duration(seconds: 20);

  static const String _cacheBox = 'wesios_settings';
  static const String _cacheKey = 'fx_rates_cache';
  static const String _cacheDateKey = 'fx_rates_cached_at';
  static const String _cacheSourceKey = 'fx_rates_source';

  /// Когда курсы последний раз успешно обновились (время запроса).
  static DateTime? lastUpdated;

  /// Дата, на которую ЦБ опубликовал курс (из атрибута Date в XML).
  static DateTime? rateDate;

  /// true — курсы не из ЦБ (fallback-API или зашитые значения).
  static bool usingFallback = true;

  /// Человекочитаемый источник текущих курсов.
  static String? source;

  /// Инкрементируется после успешного обновления — экраны подписываются
  /// на него, чтобы перерисовать курс, приехавший уже после старта.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<bool> refresh() async {
    // Сначала поднимаем последние удачные курсы с диска: даже если сеть
    // сейчас недоступна, показывать вчерашний реальный курс честнее, чем
    // зашитые в код значения, которые устаревают с каждым релизом.
    _restoreCache();

    final ok = await _refreshFromCbr() || await _refreshFromFallbackApi();
    if (ok) revision.value++;
    return ok;
  }

  /// Последние удачно полученные курсы, сохранённые между запусками.
  static void _restoreCache() {
    try {
      final box = Hive.box(_cacheBox);
      final raw = box.get(_cacheKey);
      if (raw is! Map) return;
      final map = <String, double>{};
      raw.forEach((k, v) {
        if (v is num) map['$k'] = v.toDouble();
      });
      if (map.length < 2) return;

      CurrencyService.setRates(map);
      final millis = box.get(_cacheDateKey);
      lastUpdated =
          millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
      // Кэш — это всё ещё не живой ответ ЦБ, поэтому помечаем как резерв;
      // успешный refresh ниже перезапишет и флаг, и источник.
      usingFallback = true;
      source = box.get(_cacheSourceKey) as String?;
      revision.value++;
    } catch (_) {
      // Бокс ещё не открыт или данные битые — просто работаем без кэша.
    }
  }

  static void _saveCache(Map<String, double> rates, String src) {
    try {
      final box = Hive.box(_cacheBox);
      box.put(_cacheKey, rates);
      box.put(_cacheDateKey, DateTime.now().millisecondsSinceEpoch);
      box.put(_cacheSourceKey, src);
    } catch (_) {
      // Сохранить не удалось — не повод ронять обновление курсов.
    }
  }

  // ========== ЦБ РФ ==========

  /// Порядок тегов в XML ЦБ: NumCode, CharCode, Nominal, Name, Value, VunitRate.
  static final RegExp _valuteRe = RegExp(
    r'<Valute[^>]*>.*?<CharCode>([A-Za-z]{3})</CharCode>.*?'
    r'<Nominal>(\d+)</Nominal>.*?<Value>([\d.,]+)</Value>.*?</Valute>',
    dotAll: true,
  );

  static final RegExp _dateRe = RegExp(r'Date="(\d{2})\.(\d{2})\.(\d{4})"');

  static Future<bool> _refreshFromCbr() async {
    try {
      final res = await http.get(Uri.parse(_cbrUrl)).timeout(_timeout);
      if (res.statusCode != 200) return false;

      // Тело в windows-1251. CharCode/Nominal/Value — ASCII, поэтому latin1
      // достаточно; кириллица в <Name> нам не нужна.
      final body = latin1.decode(res.bodyBytes, allowInvalid: true);

      final map = <String, double>{'rub': 1.0};
      for (final m in _valuteRe.allMatches(body)) {
        final code = m.group(1)!.toLowerCase();
        // Берём только валюты, которые поддерживает приложение.
        if (!CurrencyService.currencies.containsKey(code)) continue;

        final nominal = int.tryParse(m.group(2)!) ?? 0;
        final value = double.tryParse(m.group(3)!.replaceAll(',', '.'));
        if (value == null || value <= 0 || nominal <= 0) continue;

        // ЦБ отдаёт «сколько рублей за Nominal единиц» → приводим к 1 единице.
        map[code] = value / nominal;
      }

      // Только 'rub' — значит разметку распарсить не удалось.
      if (map.length < 2) return false;

      CurrencyService.setRates(map);

      final d = _dateRe.firstMatch(body);
      rateDate = d == null
          ? null
          : DateTime(
              int.parse(d.group(3)!),
              int.parse(d.group(2)!),
              int.parse(d.group(1)!),
            );
      lastUpdated = DateTime.now();
      usingFallback = false;
      source = 'cbr.ru';
      _saveCache(map, 'cbr.ru');
      debugPrint('CBR rates updated (${map.length - 1} currencies): $map');
      return true;
    } catch (e) {
      debugPrint('CBR refresh failed: $e');
      return false;
    }
  }

  // ========== Fallback ==========

  static Future<bool> _refreshFromFallbackApi() async {
    try {
      final res = await http.get(Uri.parse(_fallbackUrl)).timeout(_timeout);
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // Отдельная проверка результата в теле: этот класс API отвечает 200
      // даже на отказ, и без неё ошибка выглядела бы как «просто нет rates».
      if (data['result'] != null && data['result'] != 'success') {
        debugPrint('Fallback API refused: ${data['error'] ?? data['result']}');
        return false;
      }

      final rates = data['rates'] as Map<String, dynamic>?;
      if (rates == null) return false;

      // API отдаёт: 1 RUB = X USD → нам нужно 1 USD = 1/X RUB
      final map = <String, double>{'rub': 1.0};
      for (final entry in rates.entries) {
        final code = entry.key.toLowerCase();
        if (!CurrencyService.currencies.containsKey(code)) continue;
        final v = (entry.value as num?)?.toDouble();
        if (v != null && v > 0) map[code] = 1.0 / v;
      }
      if (map.length < 2) return false;

      CurrencyService.setRates(map);
      lastUpdated = DateTime.now();
      rateDate = null;
      usingFallback = true;
      source = 'open.er-api.com';
      _saveCache(map, 'open.er-api.com');
      debugPrint('Fallback rates updated: $map');
      return true;
    } catch (e) {
      debugPrint('ExchangeRateService fallback failed: $e');
      return false;
    }
  }

  // ========== UI helpers ==========

  /// Дата курса в формате дд.мм.гггг — для подписи «Курс ЦБ на …».
  static String? get rateDateLabel {
    final d = rateDate ?? lastUpdated;
    if (d == null) return null;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  /// Курс текущей валюты к рублю, например «1 $ = 90,12 ₽».
  /// Для рубля возвращает null — показывать нечего.
  static String? get currentRateLabel {
    final code = CurrencyService.current;
    if (code == 'rub') return null;
    final rate = CurrencyService.rateToRub(code);
    if (rate <= 0) return null;
    final symbol = CurrencyService.currencies[code]?[0] ?? code.toUpperCase();
    return '1 $symbol = ${rate.toStringAsFixed(2).replaceAll('.', ',')} ₽';
  }
}
