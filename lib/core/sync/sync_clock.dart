import 'package:hive/hive.dart';

/// Часы, по которым решаются споры между устройствами.
///
/// Слияние выбирает более позднюю правку, а «позднее» до сих пор считалось по
/// часам самого устройства. Часы у устройств расходятся: на телефоне их ведёт
/// оператор, на компьютере — сеть или никто, и разница в несколько минут не
/// редкость, а норма. Проверено тестом: правка, сделанная на телефоне на пять
/// минут ПОЗЖЕ, проигрывала правке с ноутбука просто потому, что телефон
/// отставал. Человек видит это как «мои изменения не сохранились».
///
/// Лечится приведением всех устройств к одной шкале — серверной. Сервер и так
/// сообщает своё время в заголовке `Date` каждого ответа; остаётся вычесть из
/// него своё и запомнить разницу. Менять сервер для этого не нужно.
///
/// Смещение переживает перезапуск: правки, сделанные до первого обмена,
/// должны получить ту же шкалу, что и все остальные.
class SyncClock {
  static const String _boxName = 'wesios_settings';
  static const String _key = 'sync_clock_offset_ms';

  /// Больше этого смещение не бывает ни при каких сбитых часах — такое
  /// значение означает испорченный заголовок, а не разницу во времени.
  /// Принять его значило бы отправить все свои правки в другой век.
  static const Duration _sane = Duration(days: 370);

  static Duration _offset = Duration.zero;
  static bool _loaded = false;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<dynamic>(_boxName) : null;

  /// Насколько часы сервера впереди наших.
  static Duration get offset {
    if (!_loaded) {
      final raw = _box?.get(_key);
      if (raw is int) _offset = Duration(milliseconds: raw);
      _loaded = true;
    }
    return _offset;
  }

  /// Текущий момент по общей для всех устройств шкале.
  static DateTime now() => DateTime.now().add(offset);

  /// Учесть время сервера из заголовка `Date`.
  ///
  /// [sentAt] и [receivedAt] — моменты по нашим часам до и после запроса.
  /// Сетевая задержка делится пополам, как в обычной сверке часов: сервер
  /// сформировал ответ где-то посередине между отправкой и получением.
  /// Точности заголовка (одна секунда) с запасом хватает — расхождения,
  /// из-за которых теряются правки, измеряются минутами.
  static Future<void> observeServerDate(
    String? header, {
    required DateTime sentAt,
    required DateTime receivedAt,
  }) async {
    if (header == null || header.isEmpty) return;
    final server = _parseHttpDate(header);
    if (server == null) return;

    final middle = sentAt.add(
      Duration(
        microseconds: receivedAt.difference(sentAt).inMicroseconds ~/ 2,
      ),
    );
    final delta = server.difference(middle);
    if (delta.abs() > _sane) return;

    // Секунда туда-сюда — это точность самого заголовка, а не расхождение
    // часов. Перезаписывать из-за неё значение не нужно.
    if ((delta - offset).abs() < const Duration(seconds: 2)) return;

    _offset = delta;
    _loaded = true;
    await _box?.put(_key, delta.inMilliseconds);
  }

  /// Забыть измеренное смещение. Нужно тестам и смене сервера.
  static Future<void> reset() async {
    _offset = Duration.zero;
    _loaded = true;
    await _box?.delete(_key);
  }

  /// Разбор даты из HTTP-заголовка.
  ///
  /// Свой разбор, а не `HttpDate.parse`: тот бросает исключение на любом
  /// отклонении от формата, а сюда приходит заголовок от чужого сервера —
  /// прокси, зеркала, чего угодно. Ронять из-за него синхронизацию нельзя,
  /// и «не разобрали» — совершенно нормальный ответ.
  static DateTime? _parseHttpDate(String raw) {
    // Формат RFC 1123: "Tue, 12 Aug 2026 19:41:52 GMT".
    final m = RegExp(
      r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw.trim());
    if (m == null) return DateTime.tryParse(raw)?.toUtc();

    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final month = months[m.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
