import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../sync/sync_auto.dart';
import '../sync/sync_clock.dart';
import '../sync/sync_codec.dart';
import '../sync/sync_endpoint.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_journal.dart';
import '../sync/sync_recovery_guard.dart';

class LocalBackupException implements Exception {
  final String code;
  final String message;

  const LocalBackupException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class LocalBackupBundle {
  final Uint8List bytes;
  final DateTime createdAt;
  final Map<String, int> counts;
  final int settingsCount;

  const LocalBackupBundle({
    required this.bytes,
    required this.createdAt,
    required this.counts,
    required this.settingsCount,
  });

  int get records => counts.values.fold(0, (sum, value) => sum + value);

  String get fileName {
    String two(int value) => value.toString().padLeft(2, '0');
    final at = createdAt.toLocal();
    return 'WesiOS-backup-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}.wesibackup';
  }
}

class LocalBackupInspection {
  final DateTime createdAt;
  final Map<String, int> counts;
  final int settingsCount;

  const LocalBackupInspection({
    required this.createdAt,
    required this.counts,
    required this.settingsCount,
  });

  int get records => counts.values.fold(0, (sum, value) => sum + value);
}

class LocalRestoreReport {
  final bool ok;
  final int restored;
  final Map<String, int> counts;
  final String? errorCode;
  final String? message;

  const LocalRestoreReport({
    required this.ok,
    this.restored = 0,
    this.counts = const {},
    this.errorCode,
    this.message,
  });
}

class _DecodedBackup {
  final DateTime createdAt;
  final Map<String, List<Map<String, dynamic>>> collections;
  final Map<String, dynamic> settings;

  const _DecodedBackup({
    required this.createdAt,
    required this.collections,
    required this.settings,
  });
}

/// Portable, server-independent backup of local WesiOS business state.
///
/// The file contains only data exposed through SyncCodec plus an allowlisted
/// subset of business settings. Authentication/session secrets are never
/// exported. Restore is fail-closed: normal pull is disabled first, every
/// restored sync row receives a fresh local journal stamp, and the recovery
/// lock stays active until the server copy is verified separately.
class LocalBackupService {
  LocalBackupService._();

  static const String format = 'WESIOS_LOCAL_BACKUP';
  static const int schemaVersion = 1;
  static const int maxBackupBytes = 128 * 1024 * 1024;

  static const List<String> _businessSettingPrefixes = <String>[
    'categories_',
    'finance_',
    'treasury_',
    'sandbox_',
    'what_if_',
    'horizon_',
    'forecast_',
    'roadmap_',
    'crm_',
    'task_',
  ];

  static bool _businessSetting(Object? key) {
    final value = '$key';
    for (final prefix in _businessSettingPrefixes) {
      if (value.startsWith(prefix)) return true;
    }
    return false;
  }

  static Future<LocalBackupBundle> create({
    List<SyncCollection<dynamic>>? collections,
    bool includeBusinessSettings = true,
  }) async {
    final target = collections ?? SyncCodec.collections;
    if (target.isEmpty) {
      throw const LocalBackupException(
        'BACKUP_NO_COLLECTIONS',
        'Нет зарегистрированных локальных коллекций для резервного копирования',
      );
    }

    final createdAt = DateTime.now();
    final encodedCollections = <String, List<Map<String, dynamic>>>{};
    final counts = <String, int>{};

    for (final collection in target) {
      await collection.ensureBox();
      final rows = <Map<String, dynamic>>[];
      for (final entry in collection.local().entries) {
        final id = entry.key.trim();
        if (id.isEmpty) {
          throw LocalBackupException(
            'BACKUP_EMPTY_ID',
            '${collection.name}: найдена запись без идентификатора',
          );
        }
        final fields = Map<String, dynamic>.from(collection.encode(entry.value));
        if (fields.isEmpty) {
          throw LocalBackupException(
            'BACKUP_EMPTY_PAYLOAD',
            '${collection.name}:$id не удалось сериализовать',
          );
        }
        jsonEncode(fields);
        rows.add(<String, dynamic>{'id': id, 'fields': fields});
      }
      encodedCollections[collection.name] = rows;
      counts[collection.name] = rows.length;
    }

    final settings = <String, dynamic>{};
    if (includeBusinessSettings && Hive.isBoxOpen('wesios_settings')) {
      final box = Hive.box<dynamic>('wesios_settings');
      for (final key in box.keys) {
        if (!_businessSetting(key)) continue;
        final value = box.get(key);
        try {
          jsonEncode(value);
          settings['$key'] = value;
        } catch (_) {
          throw LocalBackupException(
            'BACKUP_SETTING_NOT_SERIALIZABLE',
            'Не удалось сохранить локальную настройку $key',
          );
        }
      }
    }

    final payload = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'collections': encodedCollections,
      'businessSettings': settings,
    };
    final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final envelope = <String, dynamic>{
      'format': format,
      'schemaVersion': schemaVersion,
      'payloadEncoding': 'base64+json',
      'payloadSha256': sha256.convert(payloadBytes).toString(),
      'payload': base64Encode(payloadBytes),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    if (bytes.length > maxBackupBytes) {
      throw LocalBackupException(
        'BACKUP_TOO_LARGE',
        'Резервная копия превышает ${maxBackupBytes ~/ (1024 * 1024)} МБ',
      );
    }

    return LocalBackupBundle(
      bytes: bytes,
      createdAt: createdAt,
      counts: Map.unmodifiable(counts),
      settingsCount: settings.length,
    );
  }

  static LocalBackupInspection inspect(Uint8List bytes) {
    final decoded = _decode(bytes);
    return LocalBackupInspection(
      createdAt: decoded.createdAt,
      counts: Map.unmodifiable(<String, int>{
        for (final entry in decoded.collections.entries)
          entry.key: entry.value.length,
      }),
      settingsCount: decoded.settings.length,
    );
  }

  static Future<LocalRestoreReport> restore(
    Uint8List bytes, {
    List<SyncCollection<dynamic>>? collections,
    bool manageSafety = true,
  }) async {
    _DecodedBackup backup;
    try {
      backup = _decode(bytes);
    } on LocalBackupException catch (error) {
      return LocalRestoreReport(
        ok: false,
        errorCode: error.code,
        message: error.message,
      );
    } catch (error) {
      return LocalRestoreReport(
        ok: false,
        errorCode: 'BACKUP_INVALID',
        message: 'Не удалось прочитать резервную копию: $error',
      );
    }

    final available = <String, SyncCollection<dynamic>>{
      for (final collection in collections ?? SyncCodec.collections)
        collection.name: collection,
    };
    for (final name in backup.collections.keys) {
      if (!available.containsKey(name)) {
        return LocalRestoreReport(
          ok: false,
          errorCode: 'BACKUP_COLLECTION_UNSUPPORTED',
          message: 'Эта версия WesiOS не умеет восстановить раздел $name',
        );
      }
    }

    if (manageSafety) {
      final previousEnabled = SyncRecoveryGuard.active
          ? SyncRecoveryGuard.previousEnabled
          : SyncEndpoint.enabled;
      await SyncRecoveryGuard.lock(
        previousEnabled: previousEnabled,
        reason: 'local-backup-restore-v1',
      );
      await SyncEndpoint.setEnabled(false);
      SyncAuto.stop(force: true);
      SyncEngine.invalidateActiveRun();
      for (var i = 0; i < 100 && SyncEngine.busy.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (SyncEngine.busy.value) {
        return const LocalRestoreReport(
          ok: false,
          errorCode: 'BACKUP_SYNC_BUSY',
          message: 'Синхронизация не остановилась; локальные данные не изменены',
        );
      }
    }

    final before = <String, Map<String, Map<String, dynamic>>>{};
    final beforeSettings = <String, dynamic>{};
    try {
      for (final name in backup.collections.keys) {
        final collection = available[name]!;
        await collection.ensureBox();
        before[name] = <String, Map<String, dynamic>>{
          for (final entry in collection.local().entries)
            entry.key: Map<String, dynamic>.from(collection.encode(entry.value)),
        };
      }
      if (Hive.isBoxOpen('wesios_settings')) {
        final settings = Hive.box<dynamic>('wesios_settings');
        for (final key in backup.settings.keys) {
          if (settings.containsKey(key)) beforeSettings[key] = settings.get(key);
        }
      }
    } catch (error) {
      return LocalRestoreReport(
        ok: false,
        errorCode: 'BACKUP_ROLLBACK_CAPTURE_FAILED',
        message: 'Не удалось подготовить безопасное восстановление: $error',
      );
    }

    final appliedIds = <String, Set<String>>{};
    final counts = <String, int>{};
    try {
      for (final entry in backup.collections.entries) {
        final collection = available[entry.key]!;
        final applied = <String>{};
        appliedIds[entry.key] = applied;
        for (final row in entry.value) {
          final id = '${row['id']}';
          final rawFields = row['fields'];
          if (id.isEmpty || rawFields is! Map) {
            throw LocalBackupException(
              'BACKUP_ROW_INVALID',
              '${entry.key}: повреждённая запись',
            );
          }
          final fields = Map<String, dynamic>.from(rawFields);
          final accepted = await collection.applyFields(fields);
          if (!accepted) {
            throw LocalBackupException(
              'BACKUP_ROW_REJECTED',
              'Не удалось восстановить ${entry.key}:$id',
            );
          }
          final restored = collection.local()[id];
          if (restored == null || !_sameValue(collection.encode(restored), fields)) {
            throw LocalBackupException(
              'BACKUP_VERIFY_FAILED',
              'Проверка восстановленной записи ${entry.key}:$id не прошла',
            );
          }
          applied.add(id);
        }
        counts[entry.key] = applied.length;
        if (applied.isNotEmpty) collection.notifyChanged();
      }

      if (backup.settings.isNotEmpty) {
        if (!Hive.isBoxOpen('wesios_settings')) {
          await Hive.openBox<dynamic>('wesios_settings');
        }
        final settings = Hive.box<dynamic>('wesios_settings');
        await settings.putAll(backup.settings);
      }

      // Explicit fresh stamps make restored rows ordinary local edits for the
      // normal sync engine. The safety lock still prevents a pull until the
      // user has verified/uploaded the restored snapshot.
      await SyncJournal.open();
      var stampMs = SyncClock.now().toUtc().millisecondsSinceEpoch;
      for (final entry in appliedIds.entries) {
        for (final id in entry.value) {
          stampMs++;
          await SyncJournal.record(
            entry.key,
            id,
            SyncStamp(
              DateTime.fromMillisecondsSinceEpoch(stampMs, isUtc: true),
            ),
          );
        }
      }

      if (manageSafety) {
        await SyncRecoveryGuard.markRunning(
          runId: 'backup-${DateTime.now().toUtc().toIso8601String()}',
          startedAt: DateTime.now(),
          counts: counts,
        );
        await SyncRecoveryGuard.markFailed(
          message:
              'Локальная резервная копия восстановлена. Серверная копия ещё не проверена.',
        );
      }

      return LocalRestoreReport(
        ok: true,
        restored: counts.values.fold(0, (sum, value) => sum + value),
        counts: Map.unmodifiable(counts),
        message:
            'Локальные данные восстановлены. Обычная синхронизация оставлена заблокированной до проверки сервера.',
      );
    } catch (error) {
      try {
        await _rollback(
          available: available,
          before: before,
          appliedIds: appliedIds,
          backupSettingKeys: backup.settings.keys,
          beforeSettings: beforeSettings,
        );
      } catch (_) {
        return LocalRestoreReport(
          ok: false,
          errorCode: 'BACKUP_ROLLBACK_FAILED',
          message:
              'Восстановление остановилось и автоматический откат не завершился. Не запускайте синхронизацию; используйте исходный файл резервной копии.',
        );
      }
      final message = error is LocalBackupException
          ? error.message
          : 'Восстановление остановлено: $error';
      return LocalRestoreReport(
        ok: false,
        errorCode: error is LocalBackupException
            ? error.code
            : 'BACKUP_RESTORE_FAILED',
        message: '$message. Исходное локальное состояние возвращено.',
      );
    }
  }

  static _DecodedBackup _decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const LocalBackupException(
        'BACKUP_SIZE_INVALID',
        'Некорректный размер файла резервной копии',
      );
    }
    dynamic envelopeRaw;
    try {
      envelopeRaw = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const LocalBackupException(
        'BACKUP_JSON_INVALID',
        'Файл не является резервной копией WesiOS',
      );
    }
    if (envelopeRaw is! Map || envelopeRaw['format'] != format) {
      throw const LocalBackupException(
        'BACKUP_FORMAT_INVALID',
        'Неверный формат резервной копии',
      );
    }
    final version = envelopeRaw['schemaVersion'];
    if (version is! num || version.toInt() != schemaVersion) {
      throw LocalBackupException(
        'BACKUP_VERSION_UNSUPPORTED',
        'Версия резервной копии $version пока не поддерживается',
      );
    }
    final encoded = envelopeRaw['payload'];
    final expectedHash = envelopeRaw['payloadSha256'];
    if (encoded is! String || expectedHash is! String) {
      throw const LocalBackupException(
        'BACKUP_PAYLOAD_MISSING',
        'В резервной копии отсутствуют данные или контрольная сумма',
      );
    }

    Uint8List payloadBytes;
    try {
      payloadBytes = Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      throw const LocalBackupException(
        'BACKUP_PAYLOAD_INVALID',
        'Данные резервной копии повреждены',
      );
    }
    final actualHash = sha256.convert(payloadBytes).toString();
    if (actualHash != expectedHash.toLowerCase()) {
      throw const LocalBackupException(
        'BACKUP_CHECKSUM_MISMATCH',
        'Контрольная сумма не совпадает: файл повреждён или изменён',
      );
    }

    dynamic payloadRaw;
    try {
      payloadRaw = jsonDecode(utf8.decode(payloadBytes));
    } catch (_) {
      throw const LocalBackupException(
        'BACKUP_PAYLOAD_JSON_INVALID',
        'Внутренние данные резервной копии повреждены',
      );
    }
    if (payloadRaw is! Map) {
      throw const LocalBackupException(
        'BACKUP_PAYLOAD_TYPE_INVALID',
        'Некорректная структура резервной копии',
      );
    }
    final createdAt = DateTime.tryParse('${payloadRaw['createdAt']}');
    final rawCollections = payloadRaw['collections'];
    if (createdAt == null || rawCollections is! Map) {
      throw const LocalBackupException(
        'BACKUP_MANIFEST_INVALID',
        'Некорректный манифест резервной копии',
      );
    }

    final collections = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawCollections.entries) {
      if (entry.value is! List) {
        throw LocalBackupException(
          'BACKUP_COLLECTION_INVALID',
          'Повреждён раздел ${entry.key}',
        );
      }
      final rows = <Map<String, dynamic>>[];
      for (final raw in entry.value as List) {
        if (raw is! Map || raw['fields'] is! Map || '${raw['id']}'.isEmpty) {
          throw LocalBackupException(
            'BACKUP_ROW_INVALID',
            'Повреждена запись в разделе ${entry.key}',
          );
        }
        rows.add(Map<String, dynamic>.from(raw));
      }
      collections['${entry.key}'] = rows;
    }

    final rawSettings = payloadRaw['businessSettings'];
    final settings = rawSettings is Map
        ? <String, dynamic>{
            for (final entry in rawSettings.entries)
              if (_businessSetting(entry.key)) '${entry.key}': entry.value,
          }
        : <String, dynamic>{};

    return _DecodedBackup(
      createdAt: createdAt,
      collections: collections,
      settings: settings,
    );
  }

  static Future<void> _rollback({
    required Map<String, SyncCollection<dynamic>> available,
    required Map<String, Map<String, Map<String, dynamic>>> before,
    required Map<String, Set<String>> appliedIds,
    required Iterable<String> backupSettingKeys,
    required Map<String, dynamic> beforeSettings,
  }) async {
    for (final entry in appliedIds.entries.toList().reversed) {
      final collection = available[entry.key]!;
      final old = before[entry.key] ?? const <String, Map<String, dynamic>>{};
      final box = collection.box() ?? await collection.ensureBox();
      for (final id in entry.value) {
        final previous = old[id];
        if (previous != null) {
          final accepted = await collection.applyFields(previous);
          if (!accepted) throw StateError('rollback rejected ${entry.key}:$id');
        } else {
          await box.delete(id);
        }
      }
      collection.notifyChanged();
    }

    if (Hive.isBoxOpen('wesios_settings')) {
      final settings = Hive.box<dynamic>('wesios_settings');
      for (final key in backupSettingKeys) {
        if (beforeSettings.containsKey(key)) {
          await settings.put(key, beforeSettings[key]);
        } else {
          await settings.delete(key);
        }
      }
    }
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
