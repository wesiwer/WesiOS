import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'pocketbase_transport.dart';
import 'sync_clock.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_journal.dart';
import 'sync_merge.dart';
import 'sync_recovery_guard.dart';
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

  static bool _fatalTransportFailure(String? code) =>
      code == 'NOT_SIGNED_IN' ||
      code == 'NETWORK' ||
      code == 'BAD_ADDRESS' ||
      code == 'NOT_WESIOS';

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
      } catch (_) {}
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
    if (SyncRecoveryGuard.active) {
      await prepare();
      return;
    }
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
        updatedAt: (stamp != null && !stamp.deleted)
            ? stamp.updatedAt
            : safeFallback,
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
  ) => {
    for (final e in local.entries)
      if (!remote.containsKey(e.key)) e.key: e.value,
  };

  static dynamic _localValueBySyncId(SyncCollection<dynamic> c, String id) {
    // The collection projection is authoritative. Structurally invalid
    // raw Hive rows may be quarantined by a codec and must not look like
    // concurrent user edits that block authoritative server repair.
    try {
      return c.local()[id];
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _purgeLocalCacheBySyncId(
    SyncCollection<dynamic> c,
    String id,
  ) async {
    final box = c.box();
    if (box != null) {
      final keys = box.keys.toList(growable: false);
      for (final key in keys) {
        var matches = false;
        try {
          matches = c.watchesBoxKey(key) && c.syncIdForBoxKey(key) == id;
        } catch (_) {}

        if (!matches) {
          try {
            final value = box.get(key);
            matches =
                value != null && c.shouldSync(value) && c.idOf(value) == id;
          } catch (_) {}
        }

        if (!matches) continue;
        await box.delete(key);
        return _localValueBySyncId(c, id) == null;
      }
    }

    try {
      await c.removeById(id);
    } catch (_) {
      return false;
    }
    return _localValueBySyncId(c, id) == null;
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((e) => '$e').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return [for (final item in value) _canonical(item)];
    return value;
  }

  static bool _sameFields(Map<String, dynamic> a, Map<String, dynamic> b) {
    try {
      return jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));
    } catch (_) {
      return false;
    }
  }

  static bool _localSnapshotStillCurrent(
    SyncCollection<dynamic> c,
    String id,
    SyncRecord? snapshot,
  ) {
    final currentStamp = SyncJournal.stampOf(c.name, id);
    final currentValue = _localValueBySyncId(c, id);

    if (snapshot == null) {
      // A quarantined row can become visible after its parent/root is
      // repaired earlier in this same pass. Visibility is not a local edit;
      // a real Hive edit is journaled and therefore has a fresh stamp.
      return currentStamp == null;
    }

    if (currentStamp == null ||
        currentStamp.updatedAt != snapshot.updatedAt ||
        currentStamp.deleted != snapshot.deleted) {
      return false;
    }

    if (snapshot.deleted) return currentValue == null;
    if (currentValue == null) return false;

    try {
      return _sameFields(c.encode(currentValue), snapshot.fields);
    } catch (_) {
      return false;
    }
  }

  static Future<SyncReport> run({
    SyncTransport? transport,
    DateTime? now,
    Set<String>? only,
  }) async {
    final at = now ?? SyncClock.now();

    if (SyncRecoveryGuard.active) {
      return _finish(
        SyncReport(
          at: at,
          failure: const SyncFailure(
            'RECOVERY_LOCKED',
            'Обычная синхронизация заблокирована до проверки локальной копии на сервере',
          ),
        ),
      );
    }

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
    bool cancelled() =>
        generation != _runGeneration ||
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
          return _finish(
            SyncReport(
              at: at,
              collections: reports,
              failure: cancelledFailure(),
            ),
          );
        }
        final one = await _runOne(c, t, at, cancelled: cancelled);
        reports.add(one);
        if (cancelled() || one.failure?.code == 'SESSION_CHANGED') {
          return _finish(
            SyncReport(
              at: at,
              collections: reports,
              failure: cancelledFailure(),
            ),
          );
        }
        if (_fatalTransportFailure(one.failure?.code)) {
          final report = SyncReport(at: at, collections: reports);
          if (one.failure?.code == 'NOT_SIGNED_IN') {
            t.signOut();
            await SyncEndpoint.clearSession();
          }
          return _finish(report);
        }
      }

      if (cancelled()) {
        return _finish(
          SyncReport(at: at, collections: reports, failure: cancelledFailure()),
        );
      }

      await SyncJournal.pruneTombstones(at);
      if (cancelled()) {
        return _finish(
          SyncReport(at: at, collections: reports, failure: cancelledFailure()),
        );
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

      var accepted = false;
      try {
        if (r.deleted) {
          await c.removeById(r.id);
          // A codec may intentionally keep a durable local entity (for
          // example organization/account history). A remote tombstone is only
          // applied when the row actually disappears from THIS collection's
          // sync projection. Archived/local-only representations are fine:
          // `_localValueBySyncId` already ignores shouldSync=false rows.
          accepted = _localValueBySyncId(c, r.id) == null;
        } else {
          accepted = await c.applyFields(r.fields);
        }
      } catch (_) {
        accepted = false;
      }

      if (cancelled()) {
        SyncJournal.forget(c.name, r.id);
        return false;
      }
      if (!accepted) {
        SyncJournal.forget(c.name, r.id);
        return false;
      }

      await SyncJournal.record(
        c.name,
        r.id,
        SyncStamp(r.updatedAt, deleted: r.deleted),
      );
      return !cancelled();
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

    final allLocalBefore = localState(c, at);
    final mergeLocal = firstEverExchange
        ? _onlyNewTo(allLocalBefore, remote.value!)
        : allLocalBefore;
    final plan = SyncMerge.merge(local: mergeLocal, remote: remote.value!);

    var applied = 0;
    SyncFailure? applyFailure;
    var concurrentLocalChange = false;
    String? concurrentId;
    var pending = List<SyncRecord>.from(plan.toApplyLocally);

    while (pending.isNotEmpty) {
      var progressed = false;
      final deferred = <SyncRecord>[];

      for (final r in pending) {
        if (cancelled()) return cancelledReport(applied: applied);
        await Future<void>.delayed(Duration.zero);
        if (cancelled()) return cancelledReport(applied: applied);

        if (!_localSnapshotStillCurrent(c, r.id, allLocalBefore[r.id])) {
          concurrentLocalChange = true;
          concurrentId ??= r.id;
          continue;
        }

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
    } else if (concurrentLocalChange) {
      applyFailure = SyncFailure(
        'LOCAL_CHANGED_DURING_SYNC',
        'Локальная запись ${c.name}:${concurrentId ?? '?'} изменилась во время синхронизации; конфликт будет пересчитан',
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

    for (final r in plan.toUpload) {
      await Future<void>.delayed(Duration.zero);
      if (cancelled()) return cancelledReport(applied: applied);
      if (!_localSnapshotStillCurrent(c, r.id, allLocalBefore[r.id])) {
        return SyncCollectionReport(
          collection: c.name,
          applied: applied,
          failure: SyncFailure(
            'LOCAL_CHANGED_DURING_SYNC',
            'Локальная запись ${c.name}:${r.id} изменилась до отправки; план будет пересчитан',
          ),
        );
      }
    }

    if (cancelled()) return cancelledReport(applied: applied);
    final pushed = await t.push(c.name, plan.toUpload);
    if (cancelled()) return cancelledReport(applied: applied);

    final uploadedById = <String, SyncRecord>{
      for (final record in plan.toUpload) record.id: record,
    };

    SyncFailure? reconciliationFailure;
    var reconciliationApplied = 0;
    Map<String, SyncRecord> refreshedRemote = remote.value!;
    final needsRefresh =
        pushed.forbiddenIds.isNotEmpty || pushed.authoritativeIds.isNotEmpty;
    var refreshSucceeded = true;

    if (needsRefresh) {
      // Both permission denial and `applied:false` are post-push outcomes, so
      // the pre-push fetch is stale by definition. One shared refresh gives us
      // the current permission-filtered server payload for both cases.
      final refreshed = await t.fetch(c.name);
      if (cancelled()) return cancelledReport(applied: applied);
      if (refreshed.ok) {
        refreshedRemote = refreshed.value!;
      } else {
        refreshSucceeded = false;
        // For forbidden rows keep the old fail-closed purge behaviour below.
        // For authoritativeIds do NOT destroy local data merely because this
        // second GET had a transient network failure; surface the real failure
        // and retry later.
        if (pushed.authoritativeIds.isNotEmpty) {
          reconciliationFailure ??=
              refreshed.failure ??
              const SyncFailure(
                'AUTHORITATIVE_REFRESH_FAILED',
                'Не удалось перечитать серверную версию после отклонённой записи',
              );
        } else {
          reconciliationFailure ??= SyncFailure(
            'POLICY_REFRESH_FAILED',
            'Сервер запретил изменение ${c.name}, но не удалось обновить права чтения: ${refreshed.failure?.message ?? 'неизвестная ошибка'}',
          );
        }
      }
    }

    // applied:false means the server intentionally kept its current row. It is
    // neither a delivered upload nor a permission failure. Re-fetch and apply
    // that exact row now, otherwise server revision may not change and local
    // payload could remain divergent indefinitely.
    if (refreshSucceeded) {
      for (final id in pushed.authoritativeIds) {
        if (cancelled()) {
          return cancelledReport(applied: applied + reconciliationApplied);
        }

        final source = uploadedById[id];
        if (source == null) continue;
        if (!_localSnapshotStillCurrent(c, id, allLocalBefore[id])) {
          return SyncCollectionReport(
            collection: c.name,
            applied: applied + reconciliationApplied,
            uploaded: pushed.sent,
            failure: SyncFailure(
              'LOCAL_CHANGED_DURING_SYNC',
              'Локальная запись ${c.name}:$id изменилась, пока сервер отклонял предыдущую версию; новый конфликт будет пересчитан',
            ),
          );
        }

        final visibleRemote = refreshedRemote[id];
        if (visibleRemote != null) {
          if (await applyAuthoritative(visibleRemote)) {
            reconciliationApplied++;
          } else {
            await resetIncompleteStamp(id);
            reconciliationFailure ??= SyncFailure(
              'REMOTE_APPLY_INCOMPLETE',
              'Не удалось применить authoritative ${c.name}:$id после server rejection',
            );
          }
          continue;
        }

        // The POST returned applied:false for an existing authoritative row,
        // but a permission-filtered GET no longer exposes it. Fail closed: do
        // not retain a cache that current identity cannot prove it may read.
        SyncJournal.expect(c.name, id, SyncStamp(_epoch, deleted: true));
        try {
          final purged = await _purgeLocalCacheBySyncId(c, id);
          if (cancelled()) {
            SyncJournal.forget(c.name, id);
            return cancelledReport(applied: applied + reconciliationApplied);
          }
          if (!purged) throw StateError('cache still contains $id');
          await SyncJournal.record(
            c.name,
            id,
            SyncStamp(_epoch, deleted: true),
          );
          reconciliationApplied++;
          reconciliationFailure ??= SyncFailure(
            'AUTHORITATIVE_ROW_HIDDEN',
            'Сервер отклонил ${c.name}:$id и после обновления прав запись больше не доступна',
          );
        } catch (_) {
          SyncJournal.forget(c.name, id);
          await resetIncompleteStamp(id);
          reconciliationFailure ??= SyncFailure(
            'LOCAL_POLICY_PURGE_FAILED',
            'Не удалось удалить локальный кэш ${c.name}:$id после скрытия authoritative записи',
          );
        }
      }
    }

    // Permission-denied writes are reconciled independently. If the refresh
    // failed, `refreshedRemote` must be treated as empty so forbidden cache is
    // evicted rather than trusting the stale pre-push snapshot.
    final policyRemote = refreshSucceeded
        ? refreshedRemote
        : const <String, SyncRecord>{};

    for (final id in pushed.forbiddenIds) {
      if (cancelled()) {
        return cancelledReport(applied: applied + reconciliationApplied);
      }
      final visibleRemote = policyRemote[id];

      if (visibleRemote != null) {
        if (await applyAuthoritative(visibleRemote)) {
          reconciliationApplied++;
        } else {
          await resetIncompleteStamp(id);
          reconciliationFailure ??= SyncFailure(
            'REMOTE_APPLY_INCOMPLETE',
            'Не удалось восстановить read-only ${c.name}:$id',
          );
        }
        continue;
      }

      SyncJournal.expect(c.name, id, SyncStamp(_epoch, deleted: true));
      try {
        final purged = await _purgeLocalCacheBySyncId(c, id);
        if (cancelled()) {
          SyncJournal.forget(c.name, id);
          return cancelledReport(applied: applied + reconciliationApplied);
        }
        if (!purged) throw StateError('cache still contains $id');
        await SyncJournal.record(c.name, id, SyncStamp(_epoch, deleted: true));
        reconciliationApplied++;
      } catch (_) {
        SyncJournal.forget(c.name, id);
        await resetIncompleteStamp(id);
        reconciliationFailure ??= SyncFailure(
          'LOCAL_POLICY_PURGE_FAILED',
          'Не удалось удалить локальный кэш ${c.name}:$id после отзыва доступа',
        );
      }
    }

    if (reconciliationApplied > 0) c.notifyChanged();
    applied += reconciliationApplied;

    if (pushed.deliveredIds.isNotEmpty) {
      for (final id in pushed.deliveredIds) {
        if (cancelled()) return cancelledReport(applied: applied);
        final source = uploadedById[id];
        if (source == null) continue;

        final current = SyncJournal.stampOf(c.name, id);
        final unchangedSincePlan =
            current != null &&
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
      failure: reconciliationFailure ?? pushed.failure,
    );
  }

  static SyncReport _finish(SyncReport report) {
    lastReport.value = report;
    return report;
  }
}
