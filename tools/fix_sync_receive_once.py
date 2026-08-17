from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    source = p.read_text(encoding="utf-8")
    if old not in source:
        raise SystemExit(f"pattern not found in {path}: {old[:120]!r}")
    p.write_text(source.replace(old, new, 1), encoding="utf-8")


replace(
    "lib/features/auth/login_screen.dart",
    """    SessionService.startHeartbeat();
    if (employee.isOwner) {
      await SyncEngine.runOnLaunch();
      SyncAuto.start();
    } else {
      SyncAuto.stop();
    }
""",
    """    SessionService.startHeartbeat();
    // Every authenticated account participates in sync. The server applies
    // module/org/row permissions; disabling SyncAuto for non-owners leaves
    // their device without the remote revision receiver after a fresh login.
    await SyncEngine.runOnLaunch();
    SyncAuto.start();
""",
)

replace(
    "lib/core/sync/sync_auto.dart",
    """      // runOnLaunch уже сделал полный обмен — его результат можно принять
      // как исходную точку и не повторять тот же проход через секунду.
      if (_remoteRevision == null) {
        if (SyncEngine.lastReport.value?.ok == true) {
          _remoteRevision = revision;
          return;
        }

        final report = await _runAuto();
        if (report.ok) {
          _remoteRevision = revision;
        } else {
          _registerProbeFailure();
        }
        return;
      }
""",
    """      // A watermark is valid only after this receiver has completed its own
      // fresh full pull. `lastReport` may be left from an earlier listener or
      // session phase; accepting the current revision from that stale report
      // can permanently hide changes that arrived while SyncAuto was stopped.
      if (_remoteRevision == null) {
        final report = await _runAuto();
        if (report.ok) {
          await _captureRemoteRevision(fallback: revision);
        } else {
          _registerProbeFailure();
        }
        return;
      }
""",
)

replace(
    "lib/core/sync/sync_engine.dart",
    """    var applied = 0;
    for (final r in plan.toApplyLocally) {
      // Журнал предупреждается до записи, иначе он отметит чужую правку как
      // нашу, и она уедет обратно на сервер уже как более свежая.
      SyncJournal.expect(
          c.name, r.id, SyncStamp(r.updatedAt, deleted: r.deleted));
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

    if (applied > 0) c.notifyChanged();

    if (plan.toUpload.isEmpty) {
      return SyncCollectionReport(collection: c.name, applied: applied);
    }
""",
    """    var applied = 0;
    SyncFailure? applyFailure;

    Future<void> markApplyIncomplete(String id) async {
      SyncJournal.forget(c.name, id);
      await SyncJournal.record(
        c.name,
        id,
        SyncStamp(DateTime.fromMillisecondsSinceEpoch(0)),
      );
      applyFailure ??= const SyncFailure(
        'REMOTE_APPLY_INCOMPLETE',
        'Часть полученных с сервера данных не удалось применить',
      );
    }

    for (final r in plan.toApplyLocally) {
      // Журнал предупреждается до записи, иначе он отметит чужую правку как
      // нашу, и она уедет обратно на сервер уже как более свежая.
      SyncJournal.expect(
          c.name, r.id, SyncStamp(r.updatedAt, deleted: r.deleted));
      await SyncJournal.record(
          c.name, r.id, SyncStamp(r.updatedAt, deleted: r.deleted));

      try {
        if (r.deleted) {
          await c.removeById(r.id);
          applied++;
        } else if (await c.applyFields(r.fields)) {
          applied++;
        } else {
          // The row was fetched but not actually accepted by the local model.
          // Do not report a successful full sync: otherwise SyncAuto advances
          // its server watermark and this row can remain stranded forever.
          await markApplyIncomplete(r.id);
        }
      } catch (_) {
        // One malformed/dependency-blocked row must not abort application of
        // the remaining remote rows, but the pass is still incomplete and
        // must be retried before the revision watermark advances.
        await markApplyIncomplete(r.id);
      }
    }

    if (applied > 0) c.notifyChanged();

    if (plan.toUpload.isEmpty) {
      return SyncCollectionReport(
        collection: c.name,
        applied: applied,
        failure: applyFailure,
      );
    }
""",
)

replace(
    "lib/core/sync/sync_engine.dart",
    """      uploaded: pushed.sent,
      failure: pushed.failure,
""",
    """      uploaded: pushed.sent,
      failure: pushed.failure ?? applyFailure,
""",
)

replace(
    "lib/core/sync/sync_merge.dart",
    """class SyncMerge {
  /// Побеждает более поздняя правка — **по записи**, а не по всему документу.
""",
    """class SyncMerge {
  static bool _sameValue(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameValue(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameValue(a[i], b[i])) return false;
      }
      return true;
    }
    return false;
  }

  /// Побеждает более поздняя правка — **по записи**, а не по всему документу.
""",
)

replace(
    "lib/core/sync/sync_merge.dart",
    """        // Ровно одинаковое время — не «одно и то же». Часы двух устройств
        // расходятся, и совпадение до миллисекунды скорее случайность.
        // При споре выбираем удаление: воскресить стёртое хуже, чем
        // потерять правку, сделанную в ту же миллисекунду на другом
        // устройстве. Первое — потеря доверия к удалению, второе —
        // крайне редкий случай, который человек переделает.
        merged[id] = l.deleted ? l : r;
        if (l.deleted && !r.deleted) toUpload.add(l);
        if (r.deleted && !l.deleted) toApplyLocally.add(r);
""",
    """        // Ровно одинаковое время — не «одно и то же». При delete/live
        // споре удаление побеждает, чтобы стёртая запись не воскресла.
        // Если обе копии живы, но поля различаются, серверная копия является
        // детерминированным tie-breaker. Важно не только положить её в merged,
        // но и реально применить локально — раньше этот шаг отсутствовал и
        // устройство могло навсегда остаться с другой версией данных.
        if (l.deleted || r.deleted) {
          merged[id] = l.deleted ? l : r;
          if (l.deleted && !r.deleted) toUpload.add(l);
          if (r.deleted && !l.deleted) toApplyLocally.add(r);
        } else {
          merged[id] = r;
          if (!_sameValue(l.fields, r.fields)) {
            toApplyLocally.add(r);
          }
        }
""",
)

replace(
    "test/sync_multi_device_test.dart",
    """    // Отметка сброшена в начало времён — на следующем проходе, уже после
    // обновления приложения, запись попробуют разобрать снова.
    expect(SyncJournal.stampOf('tasks', 'FUTURE')?.updatedAt.year, 1970);
    expect(report.ok, isTrue);
""",
    """    // Отметка сброшена в начало времён — на следующем проходе, уже после
    // обновления приложения, запись попробуют разобрать снова. При этом весь
    // Sync не должен стать зелёным и продвинуть remote watermark.
    expect(SyncJournal.stampOf('tasks', 'FUTURE')?.updatedAt.year, 1970);
    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');
""",
)

Path("test/sync_receive_regression_test.dart").write_text(
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_merge.dart';

import 'fake_sync_transport.dart';

class _RejectingReceiveCollection extends SyncCollection<dynamic> {
  @override
  String get name => 'receive_probe';

  @override
  String get boxName => 'wesios_receive_probe';

  @override
  String idOf(dynamic value) =>
      value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) => fields;

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async => false;
}

void main() {
  final base = DateTime.utc(2026, 8, 17, 12);
  late Directory dir;
  late _RejectingReceiveCollection probe;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_receive_regression');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
    probe = _RejectingReceiveCollection();
    SyncCodec.collections.add(probe);
    await SyncEngine.prepare(now: base);
  });

  tearDownAll(() async {
    SyncCodec.collections.remove(probe);
    await SyncEngine.reset();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('fetched but unapplied remote row makes the pass incomplete', () async {
    final transport = FakeSyncTransport()
      ..seed(
        probe.name,
        'remote-1',
        {'id': 'remote-1', 'value': 'from-server'},
        base.add(const Duration(minutes: 1)),
      );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 2)),
      only: {probe.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');
    expect(report.applied, 0);
  });

  test('equal timestamp divergent live rows apply the server copy', () {
    final at = DateTime.utc(2026, 8, 17, 13);
    final plan = SyncMerge.merge(
      local: {
        'same': SyncRecord(
          id: 'same',
          fields: const {
            'id': 'same',
            'title': 'local',
            'nested': {'v': 1},
          },
          updatedAt: at,
        ),
      },
      remote: {
        'same': SyncRecord(
          id: 'same',
          fields: const {
            'id': 'same',
            'title': 'remote',
            'nested': {'v': 2},
          },
          updatedAt: at,
        ),
      },
    );

    expect(plan.toUpload, isEmpty);
    expect(plan.toApplyLocally, hasLength(1));
    expect(plan.toApplyLocally.single.fields['title'], 'remote');
  });

  test('fresh interactive login starts receive polling for every employee', () {
    final source = File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(source, contains('await SyncEngine.runOnLaunch();'));
    expect(source, contains('SyncAuto.start();'));
    expect(source, isNot(contains('if (employee.isOwner) {')));
  });

  test('initial remote watermark is never accepted from stale lastReport', () {
    final source = File('lib/core/sync/sync_auto.dart').readAsStringSync();
    expect(source, isNot(contains('SyncEngine.lastReport.value?.ok == true')));
    expect(
      source,
      contains(
        'if (_remoteRevision == null) {\n        final report = await _runAuto();',
      ),
    );
  });
}
''',
    encoding="utf-8",
)

replace("pubspec.yaml", "version: 0.22.23+98", "version: 0.22.24+99")
replace(
    "lib/core/constants/app_version.dart",
    "static const String number = '0.22.23';",
    "static const String number = '0.22.24';",
)
replace(
    "lib/core/constants/app_version.dart",
    "static const int build = 98;",
    "static const int build = 99;",
)
