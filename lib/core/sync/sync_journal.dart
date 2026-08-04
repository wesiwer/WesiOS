import 'dart:async';

import 'package:hive/hive.dart';

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
/// **Зачем он вообще нужен.** Слияние ([SyncMerge]) сравнивает время правки,
/// но у половины моделей такого поля нет: у операции есть дата операции, а не
/// дата, когда её последний раз редактировали. Добавлять поле в каждую модель
/// значило бы менять формат уже записанных на диск данных ради служебной
/// мелочи.
///
/// И главное: удаление вообще нельзя записать в модель — записи больше нет.
/// Надгробие обязано лежать снаружи. Раз оно всё равно снаружи, туда же
/// логично класть и отметку времени: одно место вместо двух.
///
/// **Как отметки появляются.** Никак — сами. Журнал подписывается на
/// изменения бокса ([BoxBase.watch]) и отмечает всё, что в нём произошло.
/// Расставлять вызовы `touch()` по восьми сервисам значило бы гарантированно
/// один пропустить, и запись молча перестала бы синхронизироваться.
class SyncJournal {
  static const String boxName = 'wesios_sync_journal';

  static Box<dynamic>? _box;
  static final Map<String, StreamSubscription<BoxEvent>> _watchers = {};

  /// Отметки, которые ставит движок, применяя чужие правки.
  ///
  /// Без этого получилась бы качель: движок записывает в бокс чужую правку,
  /// подписка видит изменение и честно отмечает его как «правка прямо
  /// сейчас», после чего на следующем проходе эта же запись уезжает обратно
  /// на сервер как более свежая. И так до бесконечности.
  ///
  /// Ожидание снимается первым же событием по этому ключу, поэтому порядок
  /// доставки событий значения не имеет — а он в Hive не гарантирован.
  static final Map<String, SyncStamp> _expected = {};

  static String key(String collection, String id) => '$collection/$id';

  static Future<Box<dynamic>> open() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    final opened = Hive.isBoxOpen(boxName)
        ? Hive.box<dynamic>(boxName)
        : await Hive.openBox<dynamic>(boxName);
    _box = opened;
    return opened;
  }

  static Box<dynamic>? get _opened {
    final box = _box;
    if (box != null && box.isOpen) return box;
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box = Hive.box<dynamic>(boxName);
  }

  /// Начинает следить за боксом. Повторный вызов ничего не ломает.
  static void attach(String collection, BoxBase<dynamic> box) {
    if (_watchers.containsKey(collection)) return;
    _watchers[collection] = box.watch().listen((event) {
      final id = '${event.key}';
      final k = key(collection, id);
      final expected = _expected.remove(k);
      _opened?.put(
        k,
        (expected ?? SyncStamp(DateTime.now(), deleted: event.deleted))
            .encode(),
      );
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
  /// человека, а применение чужой. Вызывается движком прямо перед записью.
  static void expect(String collection, String id, SyncStamp stamp) {
    _expected[key(collection, id)] = stamp;
  }

  /// Снять одно ожидание — запись, которую собирались применить, применить
  /// не удалось.
  static void forget(String collection, String id) =>
      _expected.remove(key(collection, id));

  /// Забыть все ожидания. Движок делает это в конце прохода, чтобы
  /// невыполненное ожидание не приклеилось к следующей настоящей правке.
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

  /// Все отметки одной коллекции: `id → отметка`.
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
  ///
  /// Первый запуск после обновления: в боксах лежат данные, а отметок нет.
  /// Без этого шага они выглядели бы как «не менялось никогда» и проиграли бы
  /// любому спору с сервером — то есть тихо стёрлись бы чужими.
  ///
  /// Время берётся [at] и должно быть **позже** всего, что лежит на сервере,
  /// иначе смысл теряется. Движок передаёт сюда момент первого запуска.
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
  ///
  /// Живые отметки не трогаем никогда: без отметки запись снова становится
  /// «не менялась никогда».
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
