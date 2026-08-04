import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_journal.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

/// Что произошло с одной коллекцией.
class SyncCollectionReport {
  final String collection;
  final int uploaded;
  final int applied;
  final SyncFailure? failure;

  const SyncCollectionReport({
    required this.collection,
    this.uploaded = 0,
    this.applied = 0,
    this.failure,
  });

  bool get ok => failure == null;
}

/// Итог прохода.
class SyncReport {
  final DateTime at;
  final List<SyncCollectionReport> collections;

  /// Отказ, из-за которого не начали вообще: нет адреса, нет входа, нет сети.
  final SyncFailure? failure;

  const SyncReport({
    required this.at,
    this.collections = const [],
    this.failure,
  });

  int get uploaded =>
      collections.fold(0, (sum, c) => sum + c.uploaded);

  int get applied => collections.fold(0, (sum, c) => sum + c.applied);

  int get changed => uploaded + applied;

  /// Проход считается удачным, только если удались все коллекции.
  ///
  /// «Три из пяти прошло» — это не успех: человек увидит зелёную галочку и
  /// решит, что данные на сервере, а двух коллекций там нет.
  bool get ok => failure == null && collections.every((c) => c.ok);

  /// Первая настоящая причина отказа — её и показываем.
  SyncFailure? get firstFailure {
    if (failure != null) return failure;
    for (final c in collections) {
      if (c.failure != null) return c.failure;
    }
    return null;
  }

  String describe({bool russian = true}) {
    final f = firstFailure;
    if (f != null) return f.describe(russian: russian);
    if (changed == 0) {
      return russian ? 'Всё уже совпадает' : 'Already in sync';
    }
    return russian
        ? 'Отправлено $uploaded, получено $applied'
        : 'Sent $uploaded, received $applied';
  }
}

/// Синхронизация устройств.
///
/// Порядок работы одинаков для всех коллекций:
/// 1. собрать местное состояние — записи из бокса плюс надгробия из журнала;
/// 2. забрать состояние сервера;
/// 3. слить ([SyncMerge]) — правила спора живут там и только там;
/// 4. применить чужие правки у себя;
/// 5. отправить свои.
///
/// **Почему сначала применяем, потом отправляем.** Если отправить первым и
/// оборваться на середине, сервер окажется в состоянии, которого нет ни у
/// одного устройства. Обратный порядок в худшем случае оставляет наши правки
/// дома — их отправит следующий проход.
class SyncEngine {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  static final ValueNotifier<SyncReport?> lastReport =
      ValueNotifier<SyncReport?>(null);

  static bool _journalReady = false;

  /// Открыть журнал и подписать его на все синхронизируемые боксы.
  ///
  /// Вызывается на старте приложения — до того, как человек что-то поменяет.
  /// Подписка, поставленная позже, пропустила бы правки, сделанные до неё, и
  /// они выглядели бы как «не менялось никогда».
  static Future<void> prepare({DateTime? now}) async {
    if (_journalReady) return;
    await SyncJournal.open();

    for (final c in SyncCodec.collections) {
      try {
        SyncJournal.attach(c.name, await c.ensureBox());
      } catch (_) {
        // Один недоступный бокс не должен срывать подписку на остальные:
        // без синхронизации одного модуля жить можно, без запуска — нет.
      }
    }

    // Первый запуск: у уже лежащих записей отметок нет. Ставим им время
    // первого запуска — оно заведомо позже всего, что успело оказаться на
    // сервере до появления этого устройства.
    if (SyncEndpoint.seededAt == null) {
      final at = now ?? DateTime.now();
      for (final c in SyncCodec.collections) {
        await SyncJournal.seed(c.name, c.local().keys, at);
      }
      await SyncEndpoint.markSeeded(at);
    }

    _journalReady = true;
  }

  /// Сбросить подписки и результат последнего прохода.
  static Future<void> reset() async {
    await SyncJournal.detach();
    lastReport.value = null;
    _journalReady = false;
  }

  /// Проход при запуске программы, если человек включил «автоматически».
  ///
  /// Молча: неудача при старте не должна встречать человека сообщением об
  /// ошибке — он ещё ничего не сделал. Результат виден на экране
  /// синхронизации и в подписи к пункту настроек.
  static Future<void> runOnLaunch() async {
    await prepare();
    if (!SyncEndpoint.enabled) return;
    await run();
  }

  /// Местное состояние коллекции в виде, понятном слиянию.
  ///
  /// Надгробия берутся из журнала: записи в боксе уже нет, а сказать серверу
  /// «её удалили тогда-то» надо — иначе она вернётся с другого устройства.
  static Map<String, SyncRecord> localState(
    SyncCollection<dynamic> c,
    DateTime fallbackStamp,
  ) {
    final values = c.local();
    final stamps = SyncJournal.forCollection(c.name);
    final out = <String, SyncRecord>{};

    values.forEach((id, value) {
      final stamp = stamps[id];
      out[id] = SyncRecord(
        id: id,
        fields: c.encode(value),
        // Записи без отметки быть не должно — журнал засевается на старте.
        // Но если она всё-таки есть, лучше объявить её свежей, чем дать
        // молча стереть себя чужой копией.
        updatedAt: (stamp != null && !stamp.deleted)
            ? stamp.updatedAt
            : fallbackStamp,
      );
    });

    stamps.forEach((id, stamp) {
      if (!stamp.deleted || out.containsKey(id)) return;
      out[id] = SyncRecord(id: id, updatedAt: stamp.updatedAt, deleted: true);
    });

    return out;
  }

  /// Один проход по всем коллекциям.
  ///
  /// [transport] передаётся тестами; в приложении берётся из настроек.
  static Future<SyncReport> run({
    SyncTransport? transport,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();

    if (busy.value) {
      // Два прохода одновременно означали бы, что второй читает боксы,
      // пока первый их переписывает.
      return SyncReport(
        at: at,
        failure: const SyncFailure('BUSY', 'Синхронизация уже идёт'),
      );
    }

    final t = transport ?? PocketBaseTransport.fromSettings();
    if (t == null) {
      return _finish(SyncReport(at: at, failure: SyncFailure.notConfigured));
    }
    if (!t.isSignedIn) {
      return _finish(SyncReport(at: at, failure: SyncFailure.notSignedIn));
    }

    busy.value = true;
    try {
      await prepare(now: at);
      final reports = <SyncCollectionReport>[];

      for (final c in SyncCodec.collections) {
        reports.add(await _runOne(c, t, at));
      }

      await SyncJournal.pruneTombstones(at);
      SyncJournal.clearExpectations();

      final report = SyncReport(at: at, collections: reports);
      if (report.ok) await SyncEndpoint.markRun(at);

      // Пропуск протух — выбрасываем его. Иначе экран продолжал бы
      // показывать «сервер подключён», а каждый следующий проход молча
      // отказывал бы: худший вид поломки — тот, который выглядит рабочим.
      if (report.firstFailure?.code == 'NOT_SIGNED_IN') {
        t.signOut();
        await SyncEndpoint.clearSession();
      }
      return _finish(report);
    } finally {
      busy.value = false;
    }
  }

  static Future<SyncCollectionReport> _runOne(
    SyncCollection<dynamic> c,
    SyncTransport t,
    DateTime at,
  ) async {
    final remote = await t.fetch(c.name);
    if (!remote.ok) {
      return SyncCollectionReport(
          collection: c.name, failure: remote.failure);
    }

    final plan = SyncMerge.merge(
      local: localState(c, at),
      remote: remote.value!,
    );

    var applied = 0;
    for (final r in plan.toApplyLocally) {
      // Журнал предупреждается до записи, иначе он отметит чужую правку как
      // нашу, и она уедет обратно на сервер уже как более свежая.
      SyncJournal.expect(c.name, r.id, SyncStamp(r.updatedAt, deleted: r.deleted));
      await SyncJournal.record(
          c.name, r.id, SyncStamp(r.updatedAt, deleted: r.deleted));

      if (r.deleted) {
        await c.removeById(r.id);
        applied++;
      } else if (await c.applyFields(r.fields)) {
        applied++;
      } else {
        // Запись не разобралась — например, приехала от более новой версии
        // приложения. Откатываем отметку в самое начало времён: тогда
        // следующий проход снова увидит серверную копию как более свежую и
        // попробует ещё раз, уже после обновления. Оставить отметку как есть
        // значило бы решить, что запись у нас уже есть.
        SyncJournal.forget(c.name, r.id);
        await SyncJournal.record(
            c.name, r.id, SyncStamp(DateTime.fromMillisecondsSinceEpoch(0)));
      }
    }

    if (plan.toUpload.isEmpty) {
      return SyncCollectionReport(collection: c.name, applied: applied);
    }
    final pushed = await t.push(c.name, plan.toUpload);
    return SyncCollectionReport(
      collection: c.name,
      applied: applied,
      uploaded: pushed.value ?? 0,
      failure: pushed.failure,
    );
  }

  static SyncReport _finish(SyncReport report) {
    lastReport.value = report;
    return report;
  }
}
