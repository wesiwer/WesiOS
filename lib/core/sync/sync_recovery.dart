import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../features/team/services/team_service.dart';
import 'pocketbase_transport.dart';
import 'sync_auto.dart';
import 'sync_clock.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_merge.dart';
import 'sync_recovery_guard.dart';
import 'sync_transport.dart';

class SyncRecoveryCollectionReport {
  final String collection;
  final int local;
  final int uploaded;
  final int verified;
  final SyncFailure? failure;

  const SyncRecoveryCollectionReport({
    required this.collection,
    required this.local,
    this.uploaded = 0,
    this.verified = 0,
    this.failure,
  });

  bool get ok => failure == null && verified == local;
}

class SyncRecoveryReport {
  final String runId;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<SyncRecoveryCollectionReport> collections;
  final SyncFailure? failure;

  const SyncRecoveryReport({
    required this.runId,
    required this.startedAt,
    required this.finishedAt,
    this.collections = const [],
    this.failure,
  });

  int get local => collections.fold(0, (sum, row) => sum + row.local);
  int get uploaded => collections.fold(0, (sum, row) => sum + row.uploaded);
  int get verified => collections.fold(0, (sum, row) => sum + row.verified);
  bool get ok =>
      failure == null && collections.every((collection) => collection.ok);

  SyncFailure? get firstFailure {
    if (failure != null) return failure;
    for (final row in collections) {
      if (row.failure != null) return row.failure;
    }
    return null;
  }

  String describe({bool russian = true}) {
    final problem = firstFailure;
    if (problem != null) {
      return russian
          ? 'Защитный перенос остановлен: ${problem.message}. Локальные данные не изменены; обычная синхронизация остаётся заблокированной.'
          : 'Protected upload stopped: ${problem.message}. Local data was not changed and normal sync remains locked.';
    }
    return russian
        ? 'Проверено $verified из $local локальных записей. Серверная копия совпадает с телефоном. Обычная синхронизация пока оставлена выключенной.'
        : 'Verified $verified of $local local records. The server copy matches this device. Normal sync remains disabled for safety.';
  }
}

class _RecoverySnapshot {
  final Map<String, Map<String, Map<String, dynamic>>> collections;

  const _RecoverySnapshot(this.collections);

  int get count => collections.values.fold(0, (sum, rows) => sum + rows.length);

  Map<String, int> get counts => <String, int>{
    for (final entry in collections.entries) entry.key: entry.value.length,
  };
}

/// One-way, fail-closed migration for installations that accumulated business
/// data while normal synchronization was unhealthy.
///
/// Invariants:
///  * business Hive boxes are read-only for the whole recovery pass;
///  * normal sync is persistently disabled before any network operation;
///  * a durable local JSON snapshot is completed before the first upload;
///  * server rows are upserted but never deleted by recovery;
///  * every local row is fetched back and compared field-by-field;
///  * if local data changes during the pass, verification fails and can be
///    repeated from a new snapshot without rolling the local edit back.
class SyncRecovery {
  SyncRecovery._();

  static const String backupBoxName = 'wesios_sync_recovery_backups_v1';

  /// Dependency order matters. Parents/access records are uploaded before
  /// business rows that reference them.
  static const List<String> protectedCollections = <String>[
    'organizations',
    'employees',
    'organization_grants',
    'accounts',
    'finance_categories',
    'tasks',
    'roadmap_projects',
    'crm_clients',
    'transactions',
    'inter_org_transfers',
    'sandbox_transactions',
    'what_if_presets',
    'task_ai_memory',
    'roadmap_items',
    'crm_deals',
    'transaction_audit',
    'critical_audit',
    'crm_interactions',
    'horizon_predictions',
    'horizon_learning',
    'horizon_competition',
    'horizon_contracts',
  ];

  /// Foundations alone (root organization/owner employee) do not prove that
  /// this installation contains user-created business data.
  static const Set<String> _meaningfulCollections = <String>{
    'accounts',
    'finance_categories',
    'transactions',
    'inter_org_transfers',
    'sandbox_transactions',
    'what_if_presets',
    'transaction_audit',
    'critical_audit',
    'horizon_predictions',
    'horizon_learning',
    'horizon_competition',
    'horizon_contracts',
    'tasks',
    'task_ai_memory',
    'roadmap_projects',
    'roadmap_items',
    'crm_clients',
    'crm_deals',
    'crm_interactions',
  };

  static bool get safetyLocked => SyncRecoveryGuard.active;
  static bool get verified => SyncRecoveryGuard.lastStatus == 'verified';

  /// Called once during the protected mobile upgrade before SyncEngine starts.
  /// Existing installations with meaningful local business data are locked
  /// before the first normal pull can run on the new version.
  static Future<void> armMigrationIfNeeded() async {
    if (SyncRecoveryGuard.active || SyncRecoveryGuard.migrationChecked) return;

    final current = TeamService.current;
    if (current == null) return;
    if (!current.isOwner) {
      await SyncRecoveryGuard.markMigrationChecked();
      return;
    }

    var hasMeaningfulData = false;
    for (final name in _meaningfulCollections) {
      final collection = SyncCodec.byName(name);
      if (collection == null) continue;
      try {
        await collection.ensureBox();
        if (collection.local().isNotEmpty) {
          hasMeaningfulData = true;
          break;
        }
      } catch (_) {
        // Fail closed: inability to inspect a protected business box is a
        // reason to prevent normal pull, not a reason to assume it is empty.
        hasMeaningfulData = true;
        break;
      }
    }

    if (hasMeaningfulData) {
      final previousEnabled = SyncEndpoint.enabled;
      await SyncRecoveryGuard.lock(
        previousEnabled: previousEnabled,
        reason: 'protected-mobile-upgrade-v1',
      );
      await SyncEndpoint.setEnabled(false);
      SyncAuto.stop(force: true);
    }
    await SyncRecoveryGuard.markMigrationChecked();
  }

  static Future<SyncRecoveryReport> run({
    SyncTransport? transport,
    List<SyncCollection<dynamic>>? collections,
    @visibleForTesting bool requireOwner = true,
    @visibleForTesting bool manageSafety = true,
  }) async {
    final startedAt = DateTime.now();
    final runId = startedAt.toUtc().toIso8601String().replaceAll(':', '-');
    final reports = <SyncRecoveryCollectionReport>[];

    SyncRecoveryReport failed(SyncFailure failure) => SyncRecoveryReport(
      runId: runId,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      collections: List.unmodifiable(reports),
      failure: failure,
    );

    if (requireOwner && TeamService.current?.isOwner != true) {
      return failed(
        const SyncFailure(
          'RECOVERY_OWNER_REQUIRED',
          'Безопасный перенос локального источника доступен только владельцу WesiOS',
        ),
      );
    }

    final target = collections ?? _resolveProtectedCollections();
    if (target == null) {
      return failed(
        const SyncFailure(
          'RECOVERY_CODEC_MISSING',
          'Не все защищаемые разделы зарегистрированы в движке синхронизации',
        ),
      );
    }

    final t = transport ?? PocketBaseTransport.fromSettings();
    if (!t.isSignedIn) {
      return failed(SyncFailure.notSignedIn);
    }

    if (manageSafety) {
      final previousEnabled = SyncRecoveryGuard.active
          ? SyncRecoveryGuard.previousEnabled
          : SyncEndpoint.enabled;
      await SyncRecoveryGuard.lock(
        previousEnabled: previousEnabled,
        reason: 'local-authoritative-upload-v1',
      );
      await SyncEndpoint.setEnabled(false);
      SyncAuto.stop(force: true);
      SyncEngine.invalidateActiveRun();
      for (var i = 0; i < 100 && SyncEngine.busy.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (SyncEngine.busy.value) {
        final report = failed(
          const SyncFailure(
            'RECOVERY_SYNC_BUSY',
            'Предыдущий проход синхронизации не остановился',
          ),
        );
        await SyncRecoveryGuard.markFailed(
          message: report.firstFailure!.message,
        );
        return report;
      }
    }

    _RecoverySnapshot before;
    try {
      before = await _capture(target);
      await _persistBackup(runId, startedAt, before);
    } catch (error) {
      final report = failed(
        SyncFailure(
          'RECOVERY_BACKUP_FAILED',
          'Не удалось создать локальную резервную копию: $error',
        ),
      );
      if (manageSafety) {
        await SyncRecoveryGuard.markFailed(
          message: report.firstFailure!.message,
        );
      }
      return report;
    }

    if (manageSafety) {
      await SyncRecoveryGuard.markRunning(
        runId: runId,
        startedAt: startedAt,
        counts: before.counts,
      );
    }

    for (final collection in target) {
      final localRows = before.collections[collection.name] ?? const {};
      final one = await _uploadAndVerify(collection, localRows, t);
      reports.add(one);
      if (!one.ok) {
        final report = failed(
          one.failure ??
              const SyncFailure(
                'RECOVERY_VERIFY_FAILED',
                'Серверная копия не совпала с локальной',
              ),
        );
        if (manageSafety) {
          await SyncRecoveryGuard.markFailed(
            message: report.firstFailure!.message,
          );
        }
        return report;
      }
    }

    try {
      final after = await _capture(target);
      if (!_sameSnapshot(before, after)) {
        final report = failed(
          const SyncFailure(
            'LOCAL_CHANGED_DURING_RECOVERY',
            'Локальные данные изменились во время переноса; созданная копия сохранена, запустите безопасный перенос ещё раз',
          ),
        );
        if (manageSafety) {
          await SyncRecoveryGuard.markFailed(
            message: report.firstFailure!.message,
          );
        }
        return report;
      }
    } catch (error) {
      final report = failed(
        SyncFailure(
          'RECOVERY_LOCAL_RECHECK_FAILED',
          'Не удалось повторно проверить локальные данные: $error',
        ),
      );
      if (manageSafety) {
        await SyncRecoveryGuard.markFailed(
          message: report.firstFailure!.message,
        );
      }
      return report;
    }

    final report = SyncRecoveryReport(
      runId: runId,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      collections: List.unmodifiable(reports),
    );
    if (manageSafety) {
      await SyncRecoveryGuard.markVerified(
        message: report.describe(),
        counts: before.counts,
        finishedAt: report.finishedAt,
      );
    }
    return report;
  }

  /// Unlocks manual/normal sync only after a fully verified recovery. Automatic
  /// sync remains disabled until the user explicitly turns it on again.
  static Future<void> releaseVerifiedSafetyLock() async {
    if (!verified) {
      throw StateError('Server copy is not verified');
    }
    SyncAuto.stop(force: true);
    await SyncEndpoint.setEnabled(false);
    await SyncRecoveryGuard.unlockVerified();
  }

  static List<SyncCollection<dynamic>>? _resolveProtectedCollections() {
    final out = <SyncCollection<dynamic>>[];
    for (final name in protectedCollections) {
      final collection = SyncCodec.byName(name);
      if (collection == null) return null;
      out.add(collection);
    }
    return out;
  }

  static Future<_RecoverySnapshot> _capture(
    List<SyncCollection<dynamic>> collections,
  ) async {
    final result = <String, Map<String, Map<String, dynamic>>>{};
    for (final collection in collections) {
      await collection.ensureBox();
      final local = collection.local();
      final rows = <String, Map<String, dynamic>>{};
      for (final entry in local.entries) {
        final id = entry.key.trim();
        if (id.isEmpty) {
          throw StateError('${collection.name}: empty sync id');
        }
        final encoded = Map<String, dynamic>.from(
          collection.encode(entry.value),
        );
        if (encoded.isEmpty) {
          throw StateError(
            '${collection.name}:$id encoded to an empty payload',
          );
        }
        if (encoded['id'] != null && '${encoded['id']}' != id) {
          throw StateError('${collection.name}:$id payload id mismatch');
        }
        if (encoded['key'] != null && '${encoded['key']}' != id) {
          throw StateError('${collection.name}:$id payload key mismatch');
        }
        // Ensures the durable backup can be reconstructed without adapters.
        jsonEncode(encoded);
        rows[id] = encoded;
      }
      result[collection.name] = rows;
    }
    return _RecoverySnapshot(result);
  }

  static Future<void> _persistBackup(
    String runId,
    DateTime startedAt,
    _RecoverySnapshot snapshot,
  ) async {
    final box = Hive.isBoxOpen(backupBoxName)
        ? Hive.box<dynamic>(backupBoxName)
        : await Hive.openBox<dynamic>(backupBoxName);

    for (final entry in snapshot.collections.entries) {
      final rows = <Map<String, dynamic>>[
        for (final row in entry.value.entries)
          <String, dynamic>{'id': row.key, 'fields': row.value},
      ];
      await box.put('collection::$runId::${entry.key}', jsonEncode(rows));
    }

    // The manifest is written LAST. Its presence means every collection blob
    // for this run was persisted successfully.
    await box.put(
      'manifest::$runId',
      jsonEncode(<String, dynamic>{
        'version': 1,
        'runId': runId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'complete': true,
        'count': snapshot.count,
        'collections': snapshot.counts,
      }),
    );
  }

  static Future<SyncRecoveryCollectionReport> _uploadAndVerify(
    SyncCollection<dynamic> collection,
    Map<String, Map<String, dynamic>> localRows,
    SyncTransport transport,
  ) async {
    if (localRows.isEmpty) {
      return SyncRecoveryCollectionReport(
        collection: collection.name,
        local: 0,
        verified: 0,
      );
    }

    final before = await transport.fetch(collection.name);
    if (!before.ok) {
      return SyncRecoveryCollectionReport(
        collection: collection.name,
        local: localRows.length,
        failure: before.failure,
      );
    }

    final remoteBefore = before.value!;
    final serverNow = DateTime.now().add(SyncClock.offset).toUtc();
    final maxSafeFuture = serverNow.add(
      const Duration(minutes: 4, seconds: 30),
    );
    var logicalMs = serverNow.millisecondsSinceEpoch;
    final toPush = <SyncRecord>[];

    for (final entry in localRows.entries) {
      final remote = remoteBefore[entry.key];
      if (remote != null &&
          !remote.deleted &&
          samePayloadForVerification(collection, remote.fields, entry.value)) {
        continue;
      }

      var desiredMs = logicalMs + 1;
      if (remote != null) {
        final beatRemote = remote.updatedAt.toUtc().millisecondsSinceEpoch + 1;
        if (beatRemote > desiredMs) desiredMs = beatRemote;
      }
      final desired = DateTime.fromMillisecondsSinceEpoch(
        desiredMs,
        isUtc: true,
      );
      if (desired.isAfter(maxSafeFuture)) {
        return SyncRecoveryCollectionReport(
          collection: collection.name,
          local: localRows.length,
          failure: SyncFailure(
            'RECOVERY_REMOTE_CLOCK_AHEAD',
            'Серверная версия ${collection.name}:${entry.key} имеет небезопасно далёкую временную метку',
          ),
        );
      }
      logicalMs = desiredMs;
      toPush.add(
        SyncRecord(
          id: entry.key,
          fields: entry.value,
          updatedAt: desired,
          deleted: false,
        ),
      );
    }

    SyncPushResult pushed = const SyncPushResult();
    if (toPush.isNotEmpty) {
      pushed = await transport.push(collection.name, toPush);
      if (pushed.forbiddenIds.isNotEmpty) {
        return SyncRecoveryCollectionReport(
          collection: collection.name,
          local: localRows.length,
          uploaded: pushed.sent,
          failure: SyncFailure(
            'RECOVERY_FORBIDDEN',
            'Сервер запретил перенос ${collection.name}:${pushed.forbiddenIds.first}',
          ),
        );
      }
    }

    // Verification is authoritative. Even if a POST experienced a transient
    // response error, a successful fetch proving every local payload exists on
    // the server is sufficient; no local state is ever rolled back here.
    final after = await transport.fetch(collection.name);
    if (!after.ok) {
      return SyncRecoveryCollectionReport(
        collection: collection.name,
        local: localRows.length,
        uploaded: pushed.sent,
        failure: after.failure ?? pushed.failure,
      );
    }

    var verified = 0;
    String? firstMismatch;
    String? firstMismatchDetail;
    for (final entry in localRows.entries) {
      final remote = after.value![entry.key];
      if (remote != null &&
          !remote.deleted &&
          samePayloadForVerification(collection, remote.fields, entry.value)) {
        verified++;
      } else if (firstMismatch == null) {
        firstMismatch = entry.key;
        firstMismatchDetail = remote == null
            ? 'запись отсутствует на сервере'
            : remote.deleted
            ? 'сервер пометил запись удалённой'
            : _verificationDifference(collection, remote.fields, entry.value);
      }
    }

    if (verified != localRows.length) {
      final detail = firstMismatchDetail;
      return SyncRecoveryCollectionReport(
        collection: collection.name,
        local: localRows.length,
        uploaded: pushed.sent,
        verified: verified,
        failure: SyncFailure(
          'RECOVERY_VERIFY_FAILED',
          'Сервер вернул другую версию записи в разделе '
              '«${_collectionLabel(collection.name)}»'
              '${detail == null ? '' : ' — $detail'}',
        ),
      );
    }

    return SyncRecoveryCollectionReport(
      collection: collection.name,
      local: localRows.length,
      uploaded: pushed.sent,
      verified: verified,
    );
  }

  @visibleForTesting
  static bool samePayloadForVerification(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    if (_sameValue(remote, local)) return true;
    final a = _verificationPayload(collection, remote);
    final b = _verificationPayload(collection, local);
    return a != null && b != null && _sameValue(a, b);
  }

  static Map<String, dynamic>? _verificationPayload(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> fields,
  ) {
    if (collection.name != 'organizations') {
      return Map<String, dynamic>.from(fields);
    }
    try {
      final model = collection.decode(Map<String, dynamic>.from(fields));
      if (model == null) return null;
      final out = Map<String, dynamic>.from(collection.encode(model));
      final currency = '${out['baseCurrency'] ?? ''}'.trim();
      if (currency.isEmpty) out['baseCurrency'] = 'RUB';
      final createdBy = '${out['createdBy'] ?? ''}'.trim();
      if (createdBy.isEmpty) out['createdBy'] = 'sync-server';
      return out;
    } catch (_) {
      return null;
    }
  }

  static String _collectionLabel(String name) {
    const labels = <String, String>{
      'organizations': 'Организации',
      'employees': 'Сотрудники',
      'organization_grants': 'Права сотрудников',
      'accounts': 'Счета',
      'finance_categories': 'Финансовые категории',
      'transactions': 'Операции',
      'inter_org_transfers': 'Переводы между организациями',
      'tasks': 'Задачи',
      'task_ai_memory': 'Память задач',
      'roadmap_projects': 'Roadmap',
      'roadmap_items': 'Roadmap',
      'crm_clients': 'CRM',
      'crm_deals': 'CRM',
      'crm_interactions': 'CRM',
      'sandbox_transactions': 'Песочница',
      'what_if_presets': 'Сценарии What-if',
      'transaction_audit': 'История финансов',
      'critical_audit': 'Журнал безопасности',
    };
    return labels[name] ?? 'Данные WesiOS';
  }

  static String? _verificationDifference(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    final a = _verificationPayload(collection, remote);
    final b = _verificationPayload(collection, local);
    if (a == null || b == null) return 'некорректная структура ответа';
    final keys = <String>{...a.keys, ...b.keys}.toList()..sort();
    const labels = <String, String>{
      'id': 'идентификатор',
      'name': 'название',
      'parentId': 'родительская организация',
      'isRoot': 'тип организации',
      'baseCurrency': 'валюта',
      'status': 'статус',
      'createdAt': 'дата создания',
      'updatedAt': 'дата изменения',
      'createdBy': 'источник создания',
      'code': 'код',
      'description': 'описание',
      'colorValue': 'цвет',
      'sortOrder': 'порядок',
    };
    for (final key in keys) {
      if (!_sameValue(a[key], b[key])) return labels[key] ?? 'данные записи';
    }
    return null;
  }

  static bool _sameSnapshot(_RecoverySnapshot a, _RecoverySnapshot b) {
    if (a.collections.length != b.collections.length) return false;
    for (final collection in a.collections.entries) {
      final other = b.collections[collection.key];
      if (other == null || other.length != collection.value.length)
        return false;
      for (final row in collection.value.entries) {
        final otherFields = other[row.key];
        if (otherFields == null || !_sameValue(row.value, otherFields)) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _sameValue(Object? a, Object? b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        final key = '${entry.key}';
        var found = false;
        Object? other;
        for (final candidate in b.entries) {
          if ('${candidate.key}' == key) {
            found = true;
            other = candidate.value;
            break;
          }
        }
        if (!found || !_sameValue(entry.value, other)) return false;
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
    return a == b;
  }
}
