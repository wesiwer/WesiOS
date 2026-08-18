import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Часы, по которым решаются споры между устройствами.
///
/// Все локальные sync-stamps живут на той же точности, что и JavaScript Date
/// на сервере — миллисекунды. Дополнительно [now] является логическими
/// монотонными часами: два локальных изменения одной записи, случившиеся в
/// одну физическую миллисекунду, всё равно получают разные timestamps.
class SyncClock {
  static const String _boxName = 'wesios_settings';
  static const String _key = 'sync_clock_offset_ms';
  static const String _logicalKey = 'sync_clock_last_logical_ms';

  static const Duration _sane = Duration(days: 370);

  static Duration _offset = Duration.zero;
  static bool _loaded = false;

  /// Последний выданный локальный LWW timestamp в миллисекундах Unix epoch.
  ///
  /// Важный инвариант: watermark хранится не только в памяти, но и в Hive.
  /// Иначе после перезапуска приложения и перевода системных часов назад
  /// первая новая локальная правка могла получить timestamp старее уже
  /// синхронизированной версии и проиграть LWW, хотя пользователь изменил
  /// запись позже.
  static int? _lastLogicalMs;
  static bool _logicalLoaded = false;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<dynamic>(_boxName) : null;

  static Duration get offset {
    if (!_loaded) {
      final raw = _box?.get(_key);
      if (raw is int) _offset = Duration(milliseconds: raw);
      _loaded = true;
    }
    return _offset;
  }

  static int? _logicalWatermark() {
    if (!_logicalLoaded) {
      final raw = _box?.get(_logicalKey);
      if (raw is int && raw >= 0) _lastLogicalMs = raw;
      _logicalLoaded = true;
    }
    return _lastLogicalMs;
  }

  /// Текущий момент по общей для устройств server-adjusted шкале.
  ///
  /// JavaScript/PocketBase timestamps имеют миллисекундную точность. Раньше
  /// Dart отправлял микросекунды, сервер обрезал их до миллисекунд, и две
  /// быстрые правки одной записи могли схлопнуться в exact timestamp tie. На
  /// сервере такой tie специально оставляет уже существующую запись, поэтому
  /// вторая локальная правка могла потеряться.
  ///
  /// Время сначала приводится к миллисекундам, затем сравнивается с последним
  /// логическим watermark. Watermark переживает перезапуск процесса, поэтому
  /// последовательность локальных timestamps не откатывается назад вместе с
  /// системными часами.
  static DateTime now() {
    final physicalMs = DateTime.now().add(offset).millisecondsSinceEpoch;
    final previous = _logicalWatermark();
    final logicalMs = previous != null && physicalMs <= previous
        ? previous + 1
        : physicalMs;
    _lastLogicalMs = logicalMs;

    final box = _box;
    if (box != null) {
      // Hive обновляет in-memory value сразу; disk flush возвращается Future.
      // now() должен оставаться синхронным, потому что его вызывает Hive
      // watcher при каждой локальной правке. Не блокируем UI, но обязательно
      // запускаем persistence каждой выданной LWW-координаты.
      unawaited(box.put(_logicalKey, logicalMs));
    }

    return DateTime.fromMillisecondsSinceEpoch(logicalMs);
  }

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

    if ((delta - offset).abs() < const Duration(seconds: 2)) return;

    _offset = delta;
    _loaded = true;
    await _box?.put(_key, delta.inMilliseconds);
  }

  /// Забыть измеренное смещение и persisted logical watermark.
  ///
  /// Это полный диагностический reset часов. Обычный перезапуск приложения
  /// этот метод не вызывает — иначе межперезапускная монотонность потеряется.
  static Future<void> reset() async {
    _offset = Duration.zero;
    _loaded = true;
    _lastLogicalMs = null;
    _logicalLoaded = true;
    await _box?.delete(_key);
    await _box?.delete(_logicalKey);
  }

  /// Имитирует только новый процесс, не стирая persisted clock state.
  @visibleForTesting
  static void reloadProcessStateForTesting() {
    _offset = Duration.zero;
    _loaded = false;
    _lastLogicalMs = null;
    _logicalLoaded = false;
  }

  static DateTime? _parseHttpDate(String raw) {
    final m = RegExp(
      r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw.trim());
    if (m == null) return DateTime.tryParse(raw)?.toUtc();

    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
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