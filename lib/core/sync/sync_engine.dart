import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_clock.dart';
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

  int get uploaded => collections.fold(0, (sum, c) => sum + c.uploaded);

  int get applied => collections.fold(0, (sum, c) => sum + c.applied);

  int get changed => uploaded + applied;

  /// Проход считается удачным, только если удались все коллекции.
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
class SyncEngine {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  static final ValueNotifier<SyncReport?> lastReport =
      ValueNotifier<SyncReport?>(null);

  static bool _journalReady = false;

  /// Единственный prepare текущего lifecycle.
  ///
  /// Холодный запуск раньше делал `runOnLaunch()->prepare()` при busy=false и
  /// почти одновременно запускал SyncAuto. Быстрый revision poll мог войти во
  /// второй `run()->prepare()`. Оба прохода открывали account-scoped boxes,
  /// seed'или timestamps и ставили watchers параллельно. Один shared Future
  /// делает подготовку атомарной относительно всех callers.
  static Future<void>? _prepareFuture;

  /// Generation текущего жизненного цикла sync engine.
  ///
  /// Нужна отдельно от SyncAuto: ручной/чатовый проход тоже может быть активен
  /// в момент logout/account switch. Старый run не должен после смены identity
  /// применить remote row в динамически вычисленный private box нового user.
  static int _runGeneration = 0;

  /// Немедленно делает все уже запущенные production-run протухшими.
  /// Реальный сетевой Future нельзя отменить задним числом, но после ближайшего
  /// await старый проход увидит generation mismatch и остановится до apply/push.
  static void invalidateActiveRun() {
    _runGeneration++;
    SyncJournal.discardExpectations();
  }

  static String _sessionFingerprint() {
    final session = SyncEndpoint.session;
    return '${session?['userId']}|${session?['sessionId']}|${session?['token']}';
  }

  /// Открыть журнал и подписать его на все синхронизируемые боксы.
  static Future<void> prepare({DateTime? now}) async {
    if (_journalReady) return;

    final existing = _prepareFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final generation = _runGeneration;
    final future = _prepareOnce(now: now, generation: generation);
    _prepareFuture = future;
    try {
      await future;
    } finally {
      if (identical(_prepareFuture, future)) _prepareFuture = null;
    }
  }

  static Future<void> _prepareOnce({
    DateTime? now,
    required int generation,
  }) async {
    bool cancelled() => generation != _runGeneration;

    await SyncJournal.open();
    if (cancelled()) return;

    for (final c in SyncCodec.collections) {
      if (cancelled()) return;
      try {
        final box = await c.ensureBox();
        if (cancelled()) return;
        SyncJournal.attach(
          c.name,
          box,
          acceptsKey: c.watchesBoxKey,
          syncIdForKey: c.syncIdForBoxKey,
        );
      } catch (_) {
        // Один недоступный бокс не должен срывать подписку на остальные.
      }
    }

    if (cancelled()) return;
    if (SyncEndpoint.seededAt == null) {
      final at = now ?? SyncClock.now();
      for (final c in SyncCodec.collections) {
        if (cancelled()) return;
        await SyncJournal.seed(c.name, c.local().keys, at);
      }
      if (cancelled()) return;
      await SyncEndpoint.markSeeded(at);
      if (cancelled()) return;
    }

    _journalReady = true;
  }

  /// Сбросить подписки и результат последнего прохода.
  ///
  /// Сначала инвалидируем уже идущий run/prepare и ждём их выхода. Только
  /// затем можно отвязать journal и открыть private boxes другой учётки.
  static Future<void> reset() async {
    invalidateActiveRun();

    final preparing = _prepareFuture;
    if (preparing != null) {
      try {
        await preparing;
      } catch (_) {
        // Reset всё равно обязан завершить очистку после неудачного prepare.
      }
    }

    while (busy.value) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await SyncJournal.detach();
    lastReport.value = null;
    _journalReady = false;
    _prepareFuture = null;
  }

  static Future<void> runOnLaunch() async {
    // При включённом Sync сразу входим в run(): он выставляет busy=true ДО
    // prepare(), поэтому запущенный рядом SyncAuto не сможет начать второй
    // полный проход. Если Sync выключен, journal всё равно готовим, чтобы
    // локальные изменения получали timestamps для будущего включения.
    if (!SyncEndpoint.enabled) {
      await prepare();
      return;
    }
    await run();
  }

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
        updatedAt:
            (stamp != null && !stamp.deleted) ? stamp.updatedAt : fallbackStamp,
      );
    });

    stamps.forEach((id, stamp) {
      if (!stamp.deleted || out.containsKey(id)) return;
      out[id] = SyncRecord(id: id, updatedAt: stamp.updatedAt, deleted: true);
    });

    return out;
  }

  static bool get firstEverExchange => SyncEndpoint.lastRun == null;

  static Map<String, SyncRecord> _onlyNewTo(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
  ) =>
      {
        for (final e in local.entries)
          if (!remote.containsKey(e.key)) e.key: e.value,
      };

  /// Один проход по всем коллекциям.
  ///
  /// Тестовый injected [transport] не привязывается к реальной server-session,
  /// чтобы существующие unit-тесты могли работать без SyncEndpoint. Production
  /// transport дополнительно фиксирует fingerprint auth-session на старте.
  static Future<SyncReport> run({
    SyncTransport? transport,
    DateTime? now,
    Set<String>? only,
  }) async {
    final at = now ?? SyncClock.now();

    if (busy.value) {
      return SyncReport(
        at: at,
        failure: const SyncFailure('BUSY', 'Синхронизация уже идёт'),
      );
    }

    final t = transport ?? PocketBaseTransport.fromSettings();
    if (!t.isSignedIn) {
      return _finish(SyncReport(at: at, failure: SyncFailure.notSignedIn));
    }

    final generation = _runGeneration;
    final productionSession = transport == null ? _sessionFingerprint() : null;
    bool cancelled() => generation != _runGeneration ||
        (productionSession != null &&
            productionSession != _sessionFingerprint());

    SyncFailure cancelledFailure() => const SyncFailure(
          'SESSION_CHANGED',
          'Сеанс изменился во время синхронизации',
        );

    busy.value = true;
    try {
      await prepare(now: at);
      if (cancelled()) {
        return _finish(SyncReport(at: at, failure: cancelledFailure()));
      }

      final reports = <SyncCollectionReport>[];
      for (final c in SyncCodec.collections) {
        if (only != null && !only.contains(c.name)) continue;
        if (cancelled()) {
          return _finish(SyncReport(
            at: at,
            collections: reports,
            failure: cancelledFailure(),
          ));
        }
        final one = await _runOne(c, t, at, cancelled: cancelled);
        reports.add(one);
        if (cancelled() || one.failure?.code == 'SESSION_CHANGED') {
          return _finish(SyncReport(
            at: at,
            collections: reports,
            failure: cancelledFailure(),
          ));
        }
      }

      if (cancelled()) {
        return _finish(SyncReport(
          at: at,
          collections: reports,
          failure: cancelledFailure(),
        ));
      }

      await SyncJournal.pruneTombstones(at);
      if (cancelled()) {
        return _finish(SyncReport(
          at: at,
          collections: reports,
          failure: cancelledFailure(),
        ));
      }
      // Fresh remote expectations must survive until the asynchronous Hive
      // watcher consumes them; only expired entries are pruned here.
      SyncJournal.pruneExpectations();

      final report = SyncReport(at: at, collections: reports);
      if (report.ok && only == null) await SyncEndpoint.markRun(at);

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
    DateTime at, {
    required bool Function() cancelled,
  }) async {
    SyncCollectionReport cancelledReport({int applied = 0}) =>
        SyncCollectionReport(
          collection: c.name,
          applied: applied,
          failure: const SyncFailure(
            'SESSION_CHANGED',
            'Сеанс изменился во время синхронизации',
          ),
        );

    if (cancelled()) return cancelledReport();
    final remote = await t.fetch(c.name);
    if (cancelled()) return cancelledReport();
    if (!remote.ok) {
      return SyncCollectionReport(collection: c.name, failure: remote.failure);
    }

    // После сетевого await identity проверена, поэтому синхронный localState
    // читается из того же account namespace, с которым начался этот run.
    final plan = SyncMerge.merge(
      local: firstEverExchange
          ? _onlyNewTo(localState(c, at), remote.value!)
          : localState(c, at),
      remote: remote.value!,
    );

    var applied = 0;
    SyncFailure? applyFailure;
    var pending = List<SyncRecord>.from(plan.toApplyLocally);

    Future<void> resetIncompleteStamp(String id) async {
      SyncJournal.forget(c.name, id);
      await SyncJournal.record(
        c.name,
        id,
        SyncStamp(DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }

    while (pending.isNotEmpty) {
      var progressed = false;
      final deferred = <SyncRecord>[];

      for (final r in pending) {
        if (cancelled()) return cancelledReport(applied: applied);

        SyncJournal.expect(
          c.name,
          r.id,
          SyncStamp(r.updatedAt, deleted: r.deleted),
        );
        await SyncJournal.record(
          c.name,
          r.id,
          SyncStamp(r.updatedAt, deleted: r.deleted),
        );
        if (cancelled()) {
          SyncJournal.forget(c.name, r.id);
          return cancelledReport(applied: applied);
        }

        var accepted = false;
        try {
          if (r.deleted) {
            await c.removeById(r.id);
            accepted = true;
          } else {
            accepted = await c.applyFields(r.fields);
          }
        } catch (_) {
          accepted = false;
        }

        if (cancelled()) {
          SyncJournal.forget(c.name, r.id);
          return cancelledReport(applied: applied);
        }

        if (accepted) {
          applied++;
          progressed = true;
        } else {
          SyncJournal.forget(c.name, r.id);
          deferred.add(r);
        }
      }

      if (deferred.isEmpty) {
        pending = const <SyncRecord>[];
        break;
      }
      pending = deferred;
      if (!progressed) break;
    }

    if (cancelled()) return cancelledReport(applied: applied);

    if (pending.isNotEmpty) {
      for (final r in pending) {
        if (cancelled()) return cancelledReport(applied: applied);
        await resetIncompleteStamp(r.id);
      }
      final first = pending.first.id;
      final suffix = pending.length > 1 ? ' (+${pending.length - 1})' : '';
      applyFailure = SyncFailure(
        'REMOTE_APPLY_INCOMPLETE',
        'Не удалось применить ${c.name}:$first$suffix',
      );
    }

    if (cancelled()) return cancelledReport(applied: applied);
    if (applied > 0) c.notifyChanged();

    if (applyFailure != null) {
      return SyncCollectionReport(
        collection: c.name,
        applied: applied,
        failure: applyFailure,
      );
    }

    if (plan.toUpload.isEmpty) {
      return SyncCollectionReport(
        collection: c.name,
        applied: applied,
      );
    }

    // Последняя проверка непосредственно перед write boundary: старый run не
    // должен отправлять plan, рассчитанный до account switch.
    if (cancelled()) return cancelledReport(applied: applied);
    final pushed = await t.push(c.name, plan.toUpload);
    if (cancelled()) return cancelledReport(applied: applied);

    if (pushed.deliveredIds.isNotEmpty) {
      await c.afterUpload(pushed.deliveredIds);
      if (cancelled()) return cancelledReport(applied: applied);
    }
    return SyncCollectionReport(
      collection: c.name,
      applied: applied,
      uploaded: pushed.sent,
      failure: pushed.failure,
    );
  }

  static SyncReport _finish(SyncReport report) {
    lastReport.value = report;
    return report;
  }
}
