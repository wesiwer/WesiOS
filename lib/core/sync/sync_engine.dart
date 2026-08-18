import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_clock.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_journal.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

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

class SyncReport {
  final DateTime at;
  final List<SyncCollectionReport> collections;
  final SyncFailure? failure;

  const SyncReport({
    required this.at,
    this.collections = const [],
    this.failure,
  });

  int get uploaded => collections.fold(0, (sum, c) => sum + c.uploaded);
  int get applied => collections.fold(0, (sum, c) => sum + c.applied);
  int get changed => uploaded + applied;
  bool get ok => failure == null && collections.every((c) => c.ok);

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
    if (changed == 0) return russian ? 'Всё уже совпадает' : 'Already in sync';
    return russian
        ? 'Отправлено $uploaded, получено $applied'
        : 'Sent $uploaded, received $applied';
  }
}

class SyncEngine {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  static final ValueNotifier<SyncReport?> lastReport =
      ValueNotifier<SyncReport?>(null);

  static bool _journalReady = false;
  static Future<void>? _prepareFuture;
  static int _runGeneration = 0;

  static DateTime get _epoch =>
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static void invalidateActiveRun() {
    _runGeneration++;
    SyncJournal.discardExpectations();
  }

  static String _sessionFingerprint() {
    final session = SyncEndpoint.session;
    return '${session?['userId']}|${session?['sessionId']}|${session?['token']}';
  }

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

    final observedAt = now ?? SyncClock.now();
    final seedAt = SyncEndpoint.lastRun == null ? observedAt : _epoch;
    for (final c in SyncCodec.collections) {
      if (cancelled()) return;
      await SyncJournal.seed(c.name, c.local().keys, seedAt);
    }
    if (cancelled()) return;

    if (SyncEndpoint.seededAt == null) {
      await SyncEndpoint.markSeeded(observedAt);
      if (cancelled()) return;
    }

    _journalReady = true;
  }

  static Future<void> reset() async {
    invalidateActiveRun();

    final preparing = _prepareFuture;
    if (preparing != null) {
      try {
        await preparing;
      } catch (_) {}
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
    final safeFallback = firstEverExchange ? fallbackStamp : _epoch;

    values.forEach((id, value) {
      final stamp = stamps[id];
      out[id] = SyncRecord(
        id: id,
        fields: c.encode(value),
        updatedAt:
            (stamp != null && !stamp.deleted) ? stamp.updatedAt : safeFallback,
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

    Future<bool> applyAuthoritative(SyncRecord r) async {
      if (cancelled()) return false;
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
        return false;
      }

      try {
        if (r.deleted) {
          await c.removeById(r.id);
          return !cancelled();
        }
        final accepted = await c.applyFields(r.fields);
        if (!accepted) SyncJournal.forget(c.name, r.id);
        return accepted && !cancelled();
      } catch (_) {
        SyncJournal.forget(c.name, r.id);
        return false;
      }
    }

    Future<void> resetIncompleteStamp(String id) async {
      SyncJournal.forget(c.name, id);
      await SyncJournal.record(c.name, id, SyncStamp(_epoch));
    }

    if (cancelled()) return cancelledReport();
    final remote = await t.fetch(c.name);
    if (cancelled()) return cancelledReport();
    if (!remote.ok) {
      return SyncCollectionReport(collection: c.name, failure: remote.failure);
    }

    final plan = SyncMerge.merge(
      local: firstEverExchange
          ? _onlyNewTo(localState(c, at), remote.value!)
          : localState(c, at),
      remote: remote.value!,
    );

    var applied = 0;
    SyncFailure? applyFailure;
    var pending = List<SyncRecord>.from(plan.toApplyLocally);

    while (pending.isNotEmpty) {
      var progressed = false;
      final deferred = <SyncRecord>[];

      for (final r in pending) {
        if (cancelled()) return cancelledReport(applied: applied);
        final accepted = await applyAuthoritative(r);
        if (cancelled()) return cancelledReport(applied: applied);

        if (accepted) {
          applied++;
          progressed = true;
        } else {
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
      return SyncCollectionReport(collection: c.name, applied: applied);
    }

    if (cancelled()) return cancelledReport(applied: applied);
    final pushed = await t.push(c.name, plan.toUpload);
    if (cancelled()) return cancelledReport(applied: applied);

    SyncFailure? policyFailure;
    var policyApplied = 0;

    for (final id in pushed.forbiddenIds) {
      if (cancelled()) return cancelledReport(applied: applied + policyApplied);
      final visibleRemote = remote.value![id];

      if (visibleRemote != null) {
        if (await applyAuthoritative(visibleRemote)) {
          policyApplied++;
        } else {
          await resetIncompleteStamp(id);
          policyFailure ??= SyncFailure(
            'REMOTE_APPLY_INCOMPLETE',
            'Не удалось восстановить read-only ${c.name}:$id',
          );
        }
        continue;
      }

      SyncJournal.expect(
        c.name,
        id,
        SyncStamp(_epoch, deleted: true),
      );
      await SyncJournal.record(
        c.name,
        id,
        SyncStamp(_epoch, deleted: true),
      );
      try {
        await c.removeById(id);
        if (cancelled()) {
          SyncJournal.forget(c.name, id);
          return cancelledReport(applied: applied + policyApplied);
        }
        policyApplied++;
      } catch (_) {
        SyncJournal.forget(c.name, id);
        await resetIncompleteStamp(id);
        policyFailure ??= SyncFailure(
          'LOCAL_POLICY_PURGE_FAILED',
          'Не удалось удалить локальный кэш ${c.name}:$id после отзыва доступа',
        );
      }
    }

    if (policyApplied > 0) c.notifyChanged();
    applied += policyApplied;

    if (pushed.deliveredIds.isNotEmpty) {
      final uploadedById = <String, SyncRecord>{
        for (final record in plan.toUpload) record.id: record,
      };

      for (final id in pushed.deliveredIds) {
        if (cancelled()) return cancelledReport(applied: applied);
        final source = uploadedById[id];
        if (source == null) continue;

        // Do not let an HTTP response for an older snapshot erase a user edit
        // made while the request was in flight. Reconcile the accepted server
        // timestamp only if the journal still describes exactly the record we
        // sent. If it changed meanwhile, the newer local stamp must survive so
        // the next sync can upload the newer payload.
        final current = SyncJournal.stampOf(c.name, id);
        final unchangedSincePlan = current != null &&
            current.updatedAt == source.updatedAt &&
            current.deleted == source.deleted;
        if (!unchangedSincePlan) continue;

        final serverStamp = pushed.acceptedStamps[id] ?? _epoch;
        await SyncJournal.record(
          c.name,
          id,
          SyncStamp(serverStamp, deleted: source.deleted),
        );
      }

      if (cancelled()) return cancelledReport(applied: applied);
      await c.afterUpload(pushed.deliveredIds);
      if (cancelled()) return cancelledReport(applied: applied);
    }

    return SyncCollectionReport(
      collection: c.name,
      applied: applied,
      uploaded: pushed.sent,
      failure: policyFailure ?? pushed.failure,
    );
  }

  static SyncReport _finish(SyncReport report) {
    lastReport.value = report;
    return report;
  }
}
