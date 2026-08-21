import 'dart:convert';

import 'package:hive/hive.dart';

/// Persistent fail-closed state for the one-way local -> server recovery flow.
///
/// The flag lives in the already-open settings box so it is available before
/// any normal sync attempt after an app restart. Business boxes are never
/// mutated by this class.
class SyncRecoveryGuard {
  SyncRecoveryGuard._();

  static const String _settingsBox = 'wesios_settings';
  static const String _activeKey = 'sync_recovery_active_v1';
  static const String _migrationCheckedKey =
      'sync_recovery_migration_checked_v1';
  static const String _reasonKey = 'sync_recovery_reason_v1';
  static const String _previousEnabledKey =
      'sync_recovery_previous_enabled_v1';
  static const String _lastRunIdKey = 'sync_recovery_last_run_id_v1';
  static const String _lastStatusKey = 'sync_recovery_last_status_v1';
  static const String _lastMessageKey = 'sync_recovery_last_message_v1';
  static const String _lastStartedAtKey =
      'sync_recovery_last_started_at_v1';
  static const String _lastFinishedAtKey =
      'sync_recovery_last_finished_at_v1';
  static const String _lastCountsKey = 'sync_recovery_last_counts_v1';

  static Box<dynamic>? get _box {
    if (!Hive.isBoxOpen(_settingsBox)) return null;
    try {
      return Hive.box<dynamic>(_settingsBox);
    } catch (_) {
      return null;
    }
  }

  static bool get active => _box?.get(_activeKey) == true;
  static bool get migrationChecked =>
      _box?.get(_migrationCheckedKey) == true;
  static bool get previousEnabled =>
      _box?.get(_previousEnabledKey) != false;
  static String get reason => '${_box?.get(_reasonKey) ?? ''}';
  static String get lastRunId => '${_box?.get(_lastRunIdKey) ?? ''}';
  static String get lastStatus => '${_box?.get(_lastStatusKey) ?? ''}';
  static String get lastMessage => '${_box?.get(_lastMessageKey) ?? ''}';

  static DateTime? get lastStartedAt =>
      DateTime.tryParse('${_box?.get(_lastStartedAtKey) ?? ''}');
  static DateTime? get lastFinishedAt =>
      DateTime.tryParse('${_box?.get(_lastFinishedAtKey) ?? ''}');

  static Map<String, int> get lastCounts {
    final raw = _box?.get(_lastCountsKey);
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return <String, int>{
        for (final entry in decoded.entries)
          '${entry.key}': entry.value is num
              ? (entry.value as num).toInt()
              : int.tryParse('${entry.value}') ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<void> lock({
    required bool previousEnabled,
    required String reason,
  }) async {
    final box = _box;
    if (box == null) return;
    if (!active) {
      await box.put(_previousEnabledKey, previousEnabled);
    }
    await box.put(_activeKey, true);
    await box.put(_reasonKey, reason);
  }

  static Future<void> markMigrationChecked() async {
    await _box?.put(_migrationCheckedKey, true);
  }

  static Future<void> markRunning({
    required String runId,
    required DateTime startedAt,
    required Map<String, int> counts,
  }) async {
    final box = _box;
    if (box == null) return;
    await box.put(_lastRunIdKey, runId);
    await box.put(_lastStatusKey, 'running');
    await box.put(_lastMessageKey, '');
    await box.put(_lastStartedAtKey, startedAt.toIso8601String());
    await box.delete(_lastFinishedAtKey);
    await box.put(_lastCountsKey, jsonEncode(counts));
  }

  static Future<void> markFailed({
    required String message,
    DateTime? finishedAt,
  }) async {
    final box = _box;
    if (box == null) return;
    await box.put(_lastStatusKey, 'failed');
    await box.put(_lastMessageKey, message);
    await box.put(
      _lastFinishedAtKey,
      (finishedAt ?? DateTime.now()).toIso8601String(),
    );
  }

  static Future<void> markVerified({
    required String message,
    required Map<String, int> counts,
    DateTime? finishedAt,
  }) async {
    final box = _box;
    if (box == null) return;
    await box.put(_lastStatusKey, 'verified');
    await box.put(_lastMessageKey, message);
    await box.put(_lastCountsKey, jsonEncode(counts));
    await box.put(
      _lastFinishedAtKey,
      (finishedAt ?? DateTime.now()).toIso8601String(),
    );
  }

  /// Releases only the recovery lock. Normal automatic sync stays disabled
  /// until the user explicitly enables it again in Sync settings.
  static Future<void> unlockVerified() async {
    if (lastStatus != 'verified') {
      throw StateError('Recovery cannot be unlocked before verification');
    }
    await _box?.put(_activeKey, false);
    await _box?.put(_reasonKey, '');
  }

  @override
  static String toString() =>
      'SyncRecoveryGuard(active=$active, status=$lastStatus, run=$lastRunId)';
}
