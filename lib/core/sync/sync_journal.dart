import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'sync_account_scope.dart';
import 'sync_clock.dart';

/// Отметка о записи: когда её последний раз трогали и не удалена ли она.
class SyncStamp {
  final DateTime updatedAt;
  final bool deleted;

  const SyncStamp(this.updatedAt, {this.deleted = false});

  /// Хранится строкой, а не объектом: на журнал не нужен адаптер Hive, и
  /// содержимое можно прочитать глазами при разборе полётов.
  String encode() =>
      '${updatedAt.toUtc().toIso8601String()}|${deleted ? 1 : 0}';

  static SyncStamp? decode(Object? raw) {
    if (raw is! String) return null;
    final bar = raw.lastIndexOf('|');
    if (bar < 0) return null;
    final at = DateTime.tryParse(raw.substring(0, bar));
    if (at == null) return null;
    return SyncStamp(at, deleted: raw.substring(bar + 1) == '1');
  }

  @override
  String toString() => 'SyncStamp(${encode()})';
}

/// Журнал изменений: что и когда поменялось, и что было удалено.
///
/// Журнал является частью sync identity не меньше, чем сами данные. В нём
/// лежат timestamps и tombstones, а значит глобальный journal на общем
/// устройстве способен перенести конфликтную метку сотрудника A в merge
/// сотрудника B даже тогда, когда их data-boxes уже раздельные. Поэтому
/// journal тоже хранится в account-scoped Hive namespace.
class SyncJournal {
  static const String baseBoxName = 'wesios_sync_journal';
  static String get boxName => SyncAccountScope.boxName(baseBoxName);

  static Box<dynamic>? _box;
  static String? _openedBoxName;
  static final Map<String, StreamSubscription<BoxEvent>> _watchers = {};

  /// Отметки, которые ставит движок, применяя чужие правки.
  ///
  /// Без этого получилась бы качель: движок записывает в бокс чужую правку,
  /// подписка видит изменение и честно отмечает его как «правка прямо
  /// сейчас», после чего на следующем проходе эта же запись уезжает обратно
  /// на сервер как более свежая. И так до бесконечности.
  static final Map<String, SyncStamp> _expected = {};

  /// Счётчик **своих** правок — тех, что сделал человек, а не привёз обмен.
  static final ValueNotifier<int> localChanges = ValueNotifier<int>(0);

  static String key(String collection, String id) => '$collection/$id';

  static Future<Box<dynamic>> open() async {
    final currentName = boxName;
    final cached = _box;
    if (cached != null && cached.isOpen && _openedBoxName == currentName) {
      return cached;
    }

    // Account rebind всегда сначала вызывает SyncEngine.reset()/detach(), но
    // сам journal-box мог оставаться открытым. Не переиспользуем его для новой
    // server identity: tombstone `profile/me` или одинаковый id Sandbox от
    // предыдущего пользователя не должен участвовать в новом merge.
    if (cached != null && cached.isOpen && _openedBoxName != currentName) {
      await cached.close();
    }

    final opened = Hive.isBoxOpen(currentName)
        ? Hive.box<dynamic>(currentName)
        : await Hive.openBox<dynamic>(currentName);
    _box = opened;
    _openedBoxName = currentName;
    return opened;
  }

  static Box<dynamic>? get _opened {
    final currentName = boxName;
    final box = _box;
    if (box != null && box.isOpen && _openedBoxName == currentName) return box;

    // Getter не открывает/закрывает Hive асинхронно. Если identity уже
    // изменилась, старый journal считается недоступным до следующего open().
    // Это fail-closed: лучше временно не увидеть stamp, чем прочитать чужой.
    if (!Hive.isBoxOpen(currentName)) return null;
    _openedBoxName = currentName;
    return _box = Hive.box<dynamic>(currentName);
  }

  /// Начинает следить за боксом. Повторный вызов ничего не ломает.
  static void attach(
    String collection,
    BoxBase<dynamic> box, {
    bool Function(Object? key)? acceptsKey,
    String Function(Object? key)? syncIdForKey,
  }) {
    if (_watchers.containsKey(collection)) return;
    _watchers[collection] = box.watch().listen((event) {
      if (acceptsKey != null && !acceptsKey(event.key)) return;
      final id = syncIdForKey?.call(event.key) ?? '${event.key}';
      if (id.isEmpty) return;
      final k = key(collection, id);
      final expected = _expected.remove(k);
      _opened?.put(
        k,
        (expected ?? SyncStamp(SyncClock.now(), deleted: event.deleted))
            .encode(),
      );
      if (expected == null) localChanges.value++;
    });
  }

  static Future<void> detach() async {
    for (final sub in _watchers.values) {
      await sub.cancel();
    }
    _watchers.clear();
    _expected.clear();
  }

  /// Предупредить журнал, что следующее изменение этого ключа — не правка
  /// человека, а применение чужой.
  static void expect(String collection, String id, SyncStamp stamp) {
    _expected[key(collection, id)] = stamp;
  }

  static void forget(String collection, String id) =>
      _expected.remove(key(collection, id));

  static void clearExpectations() => _expected.clear();

  static SyncStamp? stampOf(String collection, String id) =>
      SyncStamp.decode(_opened?.get(key(collection, id)));

  static Future<void> record(
    String collection,
    String id,
    SyncStamp stamp,
  ) async {
    await _opened?.put(key(collection, id), stamp.encode());
  }

  static Map<String, SyncStamp> forCollection(String collection) {
    final box = _opened;
    if (box == null) return const {};
    final prefix = '$collection/';
    final out = <String, SyncStamp>{};
    for (final k in box.keys) {
      final s = '$k';
      if (!s.startsWith(prefix)) continue;
      final stamp = SyncStamp.decode(box.get(k));
      if (stamp != null) out[s.substring(prefix.length)] = stamp;
    }
    return out;
  }

  /// Проставить отметки записям, которые появились до журнала.
  static Future<void> seed(
    String collection,
    Iterable<String> ids,
    DateTime at,
  ) async {
    final box = _opened;
    if (box == null) return;
    final stamp = SyncStamp(at).encode();
    final missing = <String, String>{};
    for (final id in ids) {
      final k = key(collection, id);
      if (box.get(k) == null) missing[k] = stamp;
    }
    if (missing.isNotEmpty) await box.putAll(missing);
  }

  /// Выбросить надгробия старше срока.
  static Future<void> pruneTombstones(
    DateTime now, {
    Duration keepFor = const Duration(days: 180),
  }) async {
    final box = _opened;
    if (box == null) return;
    final dead = <dynamic>[];
    for (final k in box.keys) {
      final stamp = SyncStamp.decode(box.get(k));
      if (stamp == null) {
        dead.add(k);
        continue;
      }
      if (stamp.deleted && now.difference(stamp.updatedAt) >= keepFor) {
        dead.add(k);
      }
    }
    if (dead.isNotEmpty) await box.deleteAll(dead);
  }
}
