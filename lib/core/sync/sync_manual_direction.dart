import 'dart:convert';

import 'package:hive/hive.dart';

import '../../features/team/services/team_service.dart';
import '../backup/local_backup_service.dart';
import 'pocketbase_transport.dart';
import 'sync_auto.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';
import 'sync_recovery.dart';
import 'sync_recovery_guard.dart';
import 'sync_transport.dart';

class ManualDirectionalSyncReport {
  final bool ok;
  final bool upload;
  final int changed;
  final int backupRecords;
  final SyncFailure? failure;

  const ManualDirectionalSyncReport({
    required this.ok,
    required this.upload,
    this.changed = 0,
    this.backupRecords = 0,
    this.failure,
  });

  String describe({bool russian = true}) {
    final problem = failure;
    if (problem != null) return problem.describe(russian: russian);
    if (upload) {
      return russian
          ? 'Данные устройства отправлены и проверены на сервере: $changed записей. Перед отправкой сохранена защитная копия на $backupRecords записей.'
          : 'Device data was uploaded and verified on the server: $changed records. A $backupRecords-record safety backup was saved first.';
    }
    return russian
        ? 'С сервера принято $changed записей. Перед применением сохранена защитная копия на $backupRecords записей. Локальные записи, которых нет на сервере, не удалялись.'
        : 'Received $changed records from the server. A $backupRecords-record safety backup was saved first. Local rows absent from the server were not deleted.';
  }
}

/// Explicit manual direction for the first safe exchange.
///
/// This intentionally does not call the normal bidirectional merge:
/// - uploadDeviceAuthoritative: local business state is authoritative;
/// - downloadServerAuthoritative: remote rows are applied locally and nothing
///   is uploaded during that pass.
class SyncManualDirection {
  SyncManualDirection._();

  static const String safetyBackupBoxName =
      'wesios_manual_sync_safety_backups_v1';

  static Future<ManualDirectionalSyncReport> uploadDeviceAuthoritative() async {
    if (TeamService.current?.isOwner != true) {
      return const ManualDirectionalSyncReport(
        ok: false,
        upload: true,
        failure: SyncFailure(
          'OWNER_REQUIRED',
          'Отправить устройство как источник истины может только владелец WesiOS',
        ),
      );
    }
    if (!SyncEndpoint.isConnected) {
      return const ManualDirectionalSyncReport(
        ok: false,
        upload: true,
        failure: SyncFailure.notSignedIn,
      );
    }

    LocalBackupBundle backup;
    try {
      backup = await LocalBackupService.create();
      await _persistSafetyBackup(backup, reason: 'before-device-upload');
    } catch (error) {
      return ManualDirectionalSyncReport(
        ok: false,
        upload: true,
        failure: SyncFailure(
          'MANUAL_BACKUP_FAILED',
          'Перед отправкой не удалось создать резервную копию: $error',
        ),
      );
    }

    final recovery = await SyncRecovery.run();
    if (!recovery.ok) {
      return ManualDirectionalSyncReport(
        ok: false,
        upload: true,
        backupRecords: backup.records,
        failure:
            recovery.firstFailure ??
            const SyncFailure(
              'MANUAL_UPLOAD_FAILED',
              'Не удалось проверить серверную копию после отправки',
            ),
      );
    }

    // A successful recovery has already fetched every uploaded row back and
    // compared its payload. At this point normal synchronization can safely be
    // released. Restore the previous automatic-sync preference if it was on.
    final resumeAutomatic = SyncRecoveryGuard.previousEnabled;
    if (SyncRecovery.verified) {
      await SyncRecovery.releaseVerifiedSafetyLock();
    }
    if (resumeAutomatic) {
      await SyncEndpoint.setEnabled(true);
      SyncAuto.start();
    }

    return ManualDirectionalSyncReport(
      ok: true,
      upload: true,
      changed: recovery.verified,
      backupRecords: backup.records,
    );
  }

  static Future<ManualDirectionalSyncReport>
  downloadServerAuthoritative() async {
    if (TeamService.current == null || !SyncEndpoint.isConnected) {
      return const ManualDirectionalSyncReport(
        ok: false,
        upload: false,
        failure: SyncFailure.notSignedIn,
      );
    }

    LocalBackupBundle backup;
    try {
      backup = await LocalBackupService.create();
      await _persistSafetyBackup(backup, reason: 'before-server-download');
    } catch (error) {
      return ManualDirectionalSyncReport(
        ok: false,
        upload: false,
        failure: SyncFailure(
          'MANUAL_BACKUP_FAILED',
          'Перед загрузкой с сервера не удалось создать резервную копию: $error',
        ),
      );
    }

    final automaticWasEnabled = SyncEndpoint.enabled;
    SyncAuto.stop(force: true);
    SyncEngine.invalidateActiveRun();
    for (var i = 0; i < 100 && SyncEngine.busy.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (SyncEngine.busy.value) {
      return ManualDirectionalSyncReport(
        ok: false,
        upload: false,
        backupRecords: backup.records,
        failure: const SyncFailure(
          'MANUAL_SYNC_BUSY',
          'Предыдущая синхронизация не остановилась; данные не изменены',
        ),
      );
    }

    final transport = PocketBaseTransport.fromSettings();
    if (!transport.isSignedIn) {
      return ManualDirectionalSyncReport(
        ok: false,
        upload: false,
        backupRecords: backup.records,
        failure: SyncFailure.notSignedIn,
      );
    }

    try {
      final report = await SyncEngine.run(
        transport: transport,
        remoteAuthoritative: true,
      );
      final problem = report.firstFailure;
      if (problem != null) {
        return ManualDirectionalSyncReport(
          ok: false,
          upload: false,
          changed: report.applied,
          backupRecords: backup.records,
          failure: problem,
        );
      }
      return ManualDirectionalSyncReport(
        ok: true,
        upload: false,
        changed: report.applied,
        backupRecords: backup.records,
      );
    } finally {
      if (automaticWasEnabled && !SyncRecoveryGuard.active) {
        SyncAuto.start();
      }
    }
  }

  static Future<void> _persistSafetyBackup(
    LocalBackupBundle backup, {
    required String reason,
  }) async {
    final box = Hive.isBoxOpen(safetyBackupBoxName)
        ? Hive.box<dynamic>(safetyBackupBoxName)
        : await Hive.openBox<dynamic>(safetyBackupBoxName);
    await box.put('latest_bytes', base64Encode(backup.bytes));
    await box.put(
      'latest_created_at',
      backup.createdAt.toUtc().toIso8601String(),
    );
    await box.put('latest_reason', reason);
    await box.put('latest_records', backup.records);
  }
}
