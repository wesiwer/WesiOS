/// Одна запись в синхронизации: значение плюс момент последней правки.
///
/// [updatedAt] — не «когда создали», а «когда последний раз меняли». Именно
/// он решает споры между устройствами, поэтому обязателен даже у удалённых.
class SyncRecord {
  final String id;

  /// Поля записи в том виде, в каком они уезжают в Firestore. Для удалённой
  /// записи пусты: хранить содержимое стёртого незачем.
  final Map<String, dynamic> fields;

  final DateTime updatedAt;

  /// Надгробие: запись удалили.
  ///
  /// Удаление не может быть просто исчезновением. Пропавшую запись второе
  /// устройство считает «у меня есть, у них нет» и выгружает обратно —
  /// удалённая операция воскресает. Надгробие говорит «её удалили тогда-то»,
  /// и это утверждение уже можно сравнить по времени с чужой правкой.
  final bool deleted;

  const SyncRecord({
    required this.id,
    required this.updatedAt,
    this.fields = const {},
    this.deleted = false,
  });

  SyncRecord asDeleted(DateTime at) =>
      SyncRecord(id: id, updatedAt: at, deleted: true);

  @override
  String toString() =>
      'SyncRecord($id, ${updatedAt.toIso8601String()}, deleted: $deleted)';
}

/// Что нужно сделать по итогам слияния.
class SyncPlan {
  /// Записи, которые надо отправить в облако.
  final List<SyncRecord> toUpload;

  /// Записи, которые надо применить локально.
  final List<SyncRecord> toApplyLocally;

  /// Итоговое состояние — то, что должно получиться с обеих сторон.
  final Map<String, SyncRecord> merged;

  const SyncPlan({
    required this.toUpload,
    required this.toApplyLocally,
    required this.merged,
  });

  bool get isEmpty => toUpload.isEmpty && toApplyLocally.isEmpty;

  /// Записи, которые останутся видимыми (без надгробий).
  List<SyncRecord> get alive =>
      merged.values.where((r) => !r.deleted).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
}

/// Слияние локального и облачного состояния.
///
/// Чистая функция: ни сети, ни хранилища. Это здесь главное — правила
/// разрешения споров должны быть видны целиком в одном месте и проверяться
/// тестами, а не выясняться по логам после потери данных.
class SyncMerge {
  /// Побеждает более поздняя правка — **по записи**, а не по всему документу.
  ///
  /// Слияние целыми документами означало бы, что правка одной операции на
  /// телефоне стирает правку другой операции на ноутбуке: обе лежат в одном
  /// документе, и «последний победил» уносит чужую работу заодно.
  static SyncPlan merge({
    required Map<String, SyncRecord> local,
    required Map<String, SyncRecord> remote,
  }) {
    final merged = <String, SyncRecord>{};
    final toUpload = <SyncRecord>[];
    final toApplyLocally = <SyncRecord>[];

    for (final id in {...local.keys, ...remote.keys}) {
      final l = local[id];
      final r = remote[id];

      if (l == null) {
        // Есть только в облаке — забираем, включая надгробие: иначе
        // удаление, сделанное на другом устройстве, до нас не доедет.
        merged[id] = r!;
        toApplyLocally.add(r);
        continue;
      }
      if (r == null) {
        merged[id] = l;
        toUpload.add(l);
        continue;
      }

      final cmp = l.updatedAt.compareTo(r.updatedAt);
      if (cmp > 0) {
        merged[id] = l;
        toUpload.add(l);
      } else if (cmp < 0) {
        merged[id] = r;
        toApplyLocally.add(r);
      } else {
        // Ровно одинаковое время — не «одно и то же». Часы двух устройств
        // расходятся, и совпадение до миллисекунды скорее случайность.
        // При споре выбираем удаление: воскресить стёртое хуже, чем
        // потерять правку, сделанную в ту же миллисекунду на другом
        // устройстве. Первое — потеря доверия к удалению, второе —
        // крайне редкий случай, который человек переделает.
        merged[id] = l.deleted ? l : r;
        if (l.deleted && !r.deleted) toUpload.add(l);
        if (r.deleted && !l.deleted) toApplyLocally.add(r);
      }
    }

    return SyncPlan(
      toUpload: toUpload,
      toApplyLocally: toApplyLocally,
      merged: merged,
    );
  }

  /// Надгробия старше [keepFor] можно выбрасывать.
  ///
  /// Хранить их вечно — значит копить мусор, который никогда не читают. Но
  /// выбрасывать рано опасно: устройство, пролежавшее выключенным дольше
  /// срока, не узнает об удалении и выгрузит запись обратно. Полгода —
  /// компромисс: дольше среднего перерыва между запусками, но не навсегда.
  static Map<String, SyncRecord> pruneTombstones(
    Map<String, SyncRecord> records,
    DateTime now, {
    Duration keepFor = const Duration(days: 180),
  }) {
    return {
      for (final e in records.entries)
        if (!e.value.deleted || now.difference(e.value.updatedAt) < keepFor)
          e.key: e.value,
    };
  }
}
