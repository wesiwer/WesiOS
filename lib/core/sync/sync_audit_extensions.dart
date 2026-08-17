import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../features/audio/models/audio_vault_models.dart';
import '../../features/audio/services/audio_vault_extras_service.dart';
import '../../features/audio/services/audio_vault_service.dart';
import '../../features/chats/models/chat_message.dart';
import '../../features/profile/services/profile_service.dart';
import '../../features/treasury/models/transaction_model.dart';
import '../../features/treasury/services/what_if_store.dart';
import '../security/shield_service.dart';
import 'sync_codec.dart';
import 'sync_feature_extensions.dart';

/// Дополняет базовый реестр синхронизации состояниями, которые исторически
/// жили только на одном устройстве, и заменяет lossy-кодеки на полные.
///
/// Устанавливается ДО SyncEngine.prepare(), поэтому журнал изменений сразу
/// подписывается на правильный набор боксов и не пропускает первую правку.
class SyncAuditExtensions {
  SyncAuditExtensions._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    // Старые snapshot-коллекции Roadmap/CRM больше не являются источником
    // истины: актуальные сервисы хранят запись-за-записью в *_v2 боксах.
    // Оставлять оба контура означает синхронизировать две расходящиеся копии.
    SyncCodec.collections.removeWhere(
      (c) => c.name == 'roadmap_state' || c.name == 'crm_state',
    );

    _replace('transactions', _LosslessTransactionsSync());
    _replace('messages', _PortableMessagesSync());
    _replace('audio_beats', _PortableAudioBeatsSync());

    // profile_private раньше дублировал обычный профиль и Shield в одном
    // боксе. Профиль теперь имеет единственный источник `profile`, а Shield
    // едет своим приватным каналом без гонки двух копий имени/аватарки.
    SyncCodec.collections.removeWhere((c) => c.name == 'profile_private');
    _add(_ShieldPrivateSync());

    _add(_SandboxTransactionsSync());
    _add(_WhatIfPresetsSync());
    _add(_AudioExtrasSync());
  }

  static void _replace(String name, SyncCollection<dynamic> replacement) {
    final index = SyncCodec.collections.indexWhere((c) => c.name == name);
    if (index < 0) {
      SyncCodec.collections.add(replacement);
    } else {
      SyncCodec.collections[index] = replacement;
    }
  }

  static void _add(SyncCollection<dynamic> collection) {
    if (SyncCodec.byName(collection.name) == null) {
      SyncCodec.collections.add(collection);
    }
  }
}

/// Отдельный сигнал нужен открытому SandboxScreen: локальные действия и так
/// перерисовывают экран сами, а приехавшая с другого устройства запись должна
/// заставить уже открытый экран перечитать Hive.
class SandboxSyncSignal {
  SandboxSyncSignal._();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class _LosslessTransactionsSync extends TransactionsSync {
  @override
  Map<String, dynamic> encode(TransactionModel value) => super.encode(value)
    ..['recurringAnchor'] = value.recurringAnchor?.toIso8601String();

  @override
  TransactionModel? decode(Map<String, dynamic> fields) {
    final base = super.decode(fields);
    if (base == null) return null;
    final anchor = DateTime.tryParse('${fields['recurringAnchor'] ?? ''}');
    return anchor == null ? base : base.copyWith(recurringAnchor: anchor);
  }
}

/// Путь вложения чата — адрес файла на конкретном устройстве. На сервере
/// остаётся только имя/тип/размер/checksum. Если такой же файл уже есть на
/// принимающем устройстве, его локальный путь сохраняется.
class _PortableMessagesSync extends MessagesSync {
  @override
  Map<String, dynamic> encode(ChatMessage value) {
    final out = super.encode(value);
    final raw = out['attachment'];
    if (raw is Map) {
      out['attachment'] = <String, dynamic>{
        for (final entry in raw.entries) '${entry.key}': entry.value,
        'path': '',
      };
    }
    return out;
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final target = box();
    final incoming = decode(fields);
    if (target == null || incoming == null) return false;

    var next = incoming;
    final remoteAttachment = incoming.attachment;
    final localAttachment = target.get(incoming.id)?.attachment;
    if (remoteAttachment != null &&
        localAttachment != null &&
        localAttachment.path.isNotEmpty &&
        File(localAttachment.path).existsSync() &&
        _sameAttachment(remoteAttachment, localAttachment)) {
      next = incoming.copyWith(
        attachment: remoteAttachment.withPath(localAttachment.path).toMap(),
      );
    }
    await target.put(next.id, next);
    return true;
  }

  static bool _sameAttachment(dynamic a, dynamic b) {
    final aSha = '${a.sha256}'.trim();
    final bSha = '${b.sha256}'.trim();
    if (aSha.isNotEmpty && bSha.isNotEmpty) return aSha == bSha;
    return a.name == b.name && a.sizeBytes == b.sizeBytes && a.mime == b.mime;
  }
}

/// Audio Vault по прежнему договору синхронизирует карточку и метаданные,
/// но не MP3/WAV/ALS и не локальные пути. Метаданные дополнительных файлов
/// при этом не выбрасываются: на другом устройстве видно, какой файл связан
/// с битом, даже если самого файла там ещё нет.
class _PortableAudioBeatsSync extends AudioBeatsSync {
  @override
  Map<String, dynamic> encode(String value) {
    try {
      final raw = jsonDecode(value);
      if (raw is! Map) return const {};
      final out = Map<String, dynamic>.from(raw);
      out.remove('mp3Path');
      out.remove('wavPath');
      out.remove('trackoutPath');
      out.remove('coverPath');
      final attachments = out['attachments'];
      if (attachments is List) {
        out['attachments'] = [
          for (final item in attachments)
            if (item is Map)
              <String, dynamic>{
                for (final entry in item.entries) '${entry.key}': entry.value,
                'path': '',
              },
        ];
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final target = box();
    if (target == null) return false;
    final decoded = decode(fields);
    if (decoded == null) return false;

    final remote = BeatEntry.fromJson(fields);
    BeatEntry? local;
    final localRaw = target.get(remote.id);
    if (localRaw != null && localRaw.isNotEmpty) {
      try {
        final raw = jsonDecode(localRaw);
        if (raw is Map)
          local = BeatEntry.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }

    final localAttachments = <String, BeatFileRef>{
      for (final file in local?.attachments ?? const <BeatFileRef>[])
        file.id: file,
    };
    final attachments = <BeatFileRef>[
      for (final remoteFile in remote.attachments)
        if (localAttachments[remoteFile.id] case final mine?)
          BeatFileRef(
            id: remoteFile.id,
            name: remoteFile.name,
            path: mine.path.isNotEmpty && File(mine.path).existsSync()
                ? mine.path
                : '',
            kind: remoteFile.kind,
            bytes: remoteFile.bytes,
            createdAt: remoteFile.createdAt,
          )
        else
          remoteFile.withEmptyPath(),
    ];

    final merged = <String, dynamic>{
      ...fields,
      'mp3Path': _existingPath(local?.mp3Path),
      'wavPath': _existingPath(local?.wavPath),
      'trackoutPath': _existingPath(local?.trackoutPath),
      'coverPath': _existingPath(local?.coverPath),
      'attachments': attachments.map((e) => e.toJson()).toList(),
    };
    await target.put(remote.id, jsonEncode(merged));
    return true;
  }

  static String? _existingPath(String? value) =>
      value != null && value.isNotEmpty && File(value).existsSync()
          ? value
          : null;
}

extension on BeatFileRef {
  BeatFileRef withEmptyPath() => BeatFileRef(
        id: id,
        name: name,
        path: '',
        kind: kind,
        bytes: bytes,
        createdAt: createdAt,
      );
}

class _SandboxTransactionsSync extends SyncCollection<TransactionModel> {
  @override
  String get name => 'sandbox_transactions';

  @override
  String get boxName => 'wesios_sandbox';

  @override
  String idOf(TransactionModel value) => value.id;

  @override
  Map<String, dynamic> encode(TransactionModel value) => {
        'id': value.id,
        'title': value.title,
        'amount': value.amount,
        'type': value.type.name,
        'date': value.date.toIso8601String(),
        'category': value.category,
        'description': value.description,
        'isRecurring': value.isRecurring,
        'recurringPeriod': value.recurringPeriod?.name,
        'isAnomaly': value.isAnomaly,
        'zScore': value.zScore,
        'accountId': value.accountId,
        'recurringAnchor': value.recurringAnchor?.toIso8601String(),
        'organizationId': value.organizationId,
        'projectId': value.projectId,
        'counterpartyId': value.counterpartyId,
        'source': value.source.name,
        'createdBy': value.createdBy,
        'updatedBy': value.updatedBy,
        'updatedAt': value.updatedAt?.toIso8601String(),
        'ownerEmployeeId': value.ownerEmployeeId,
        'interOrgTransferId': value.interOrgTransferId,
        'createdByEmployeeId': value.createdByEmployeeId,
        'originalAmount': value.originalAmount,
        'originalCurrency': value.originalCurrency,
        'organizationBaseAmount': value.organizationBaseAmount,
        'organizationBaseCurrency': value.organizationBaseCurrency,
        'fxRateToReporting': value.fxRateToReporting,
        'fxRateAt': value.fxRateAt?.toIso8601String(),
        'fxSource': value.fxSource,
      };

  @override
  TransactionModel? decode(Map<String, dynamic> fields) {
    double? number(Object? raw) => raw is num
        ? raw.toDouble()
        : raw is String
            ? double.tryParse(raw)
            : null;
    String? text(Object? raw) => raw is String ? raw : null;
    DateTime? date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw) : null;
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
      return fallback;
    }

    final id = text(fields['id']);
    final amount = number(fields['amount']);
    final at = date(fields['date']);
    if (id == null ||
        id.isEmpty ||
        amount == null ||
        !amount.isFinite ||
        at == null) {
      return null;
    }
    final fxRate = number(fields['fxRateToReporting']) ?? 1.0;
    if (!fxRate.isFinite || fxRate <= 0) return null;
    return TransactionModel(
      id: id,
      title: text(fields['title']) ?? '',
      amount: amount,
      type: enumValue(
        TransactionType.values,
        fields['type'],
        TransactionType.expense,
      ),
      date: at,
      category: text(fields['category']),
      description: text(fields['description']),
      isRecurring: fields['isRecurring'] == true,
      recurringPeriod: fields['recurringPeriod'] == null
          ? null
          : enumValue(
              RecurringPeriod.values,
              fields['recurringPeriod'],
              RecurringPeriod.monthly,
            ),
      isAnomaly: fields['isAnomaly'] == true,
      zScore: number(fields['zScore']),
      accountId: text(fields['accountId']),
      recurringAnchor: date(fields['recurringAnchor']),
      organizationId: text(fields['organizationId']),
      projectId: text(fields['projectId']),
      counterpartyId: text(fields['counterpartyId']),
      source: enumValue(
        TransactionSource.values,
        fields['source'],
        TransactionSource.manual,
      ),
      createdBy: text(fields['createdBy']),
      updatedBy: text(fields['updatedBy']),
      updatedAt: date(fields['updatedAt']),
      ownerEmployeeId: text(fields['ownerEmployeeId']),
      interOrgTransferId: text(fields['interOrgTransferId']),
      createdByEmployeeId: text(fields['createdByEmployeeId']),
      originalAmount: number(fields['originalAmount']),
      originalCurrency:
          (text(fields['originalCurrency']) ?? 'RUB').toUpperCase(),
      organizationBaseAmount: number(fields['organizationBaseAmount']),
      organizationBaseCurrency:
          (text(fields['organizationBaseCurrency']) ?? 'RUB').toUpperCase(),
      fxRateToReporting: fxRate,
      fxRateAt: date(fields['fxRateAt']),
      fxSource: text(fields['fxSource']) ?? 'sandbox',
    );
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final target = box();
    final value = decode(fields);
    if (target == null || value == null) return false;
    await target.put(value.id, value);
    return true;
  }

  @override
  Future<void> removeById(String id) async => box()?.delete(id);

  @override
  void notifyChanged() => SandboxSyncSignal.revision.value++;
}

class _WhatIfPresetsSync extends SyncCollection<dynamic> {
  @override
  String get name => 'what_if_presets';

  @override
  String get boxName => 'wesios_whatif';

  @override
  String idOf(dynamic value) {
    if (value is! String) return '';
    try {
      final raw = jsonDecode(value);
      return raw is Map ? '${raw['id'] ?? ''}'.trim() : '';
    } catch (_) {
      return '';
    }
  }

  @override
  Map<String, dynamic> encode(dynamic value) {
    if (value is! String) return const {};
    try {
      final raw = jsonDecode(value);
      return raw is Map ? Map<String, dynamic>.from(raw) : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  dynamic decode(Map<String, dynamic> fields) {
    final preset = WhatIfPreset.fromJson(fields);
    if (preset == null || preset.id.trim().isEmpty) return null;
    return jsonEncode(preset.toJson());
  }

  @override
  Box<dynamic>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<dynamic>(boxName);
  }

  @override
  Future<Box<dynamic>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<dynamic>(boxName)
      : await Hive.openBox<dynamic>(boxName);

  @override
  Map<String, dynamic> local() {
    final target = box();
    if (target == null) return const {};
    final out = <String, dynamic>{};
    for (final raw in target.values) {
      final id = idOf(raw);
      if (id.isNotEmpty) out[id] = raw;
    }
    return out;
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final value = decode(fields);
    final target = box();
    if (value is! String || target == null) return false;
    final id = idOf(value);
    if (id.isEmpty) return false;
    await target.put(id, value);
    return true;
  }

  @override
  void notifyChanged() => WhatIfStore.revision.value++;
}

class _PrivateKeyedValue {
  final String key;
  final dynamic value;
  const _PrivateKeyedValue(this.key, this.value);
}

/// Переносимые настройки Shield. Состояние блокировки, биометрия, счётчики
/// ошибок и локальный журнал безопасности намеренно остаются устройству.
class _ShieldPrivateSync extends SyncCollection<dynamic> {
  static const Set<String> _keys = {
    'shield_hash',
    'shield_salt',
    'shield_iterations',
    'shield_scope',
    'shield_timeout_minutes',
    'shield_wipe_after',
    'shield_password_hint',
  };

  @override
  String get name => 'shield_private';

  @override
  String get boxName => SyncFeatureExtensions.profileBoxName();

  @override
  bool watchesBoxKey(Object? key) => _keys.contains('$key');

  @override
  String syncIdForBoxKey(Object? key) =>
      SyncFeatureExtensions.privateRecordId('$key');

  @override
  String idOf(dynamic value) => value is _PrivateKeyedValue
      ? SyncFeatureExtensions.privateRecordId(value.key)
      : '';

  @override
  Box<dynamic>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<dynamic>(boxName);
  }

  @override
  Future<Box<dynamic>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<dynamic>(boxName)
      : await Hive.openBox<dynamic>(boxName);

  @override
  Map<String, dynamic> local() {
    final target = box();
    if (target == null) return const {};
    return {
      for (final key in _keys)
        if (target.containsKey(key))
          SyncFeatureExtensions.privateRecordId(key):
              _PrivateKeyedValue(key, target.get(key)),
    };
  }

  @override
  Map<String, dynamic> encode(dynamic value) => value is _PrivateKeyedValue
      ? {'key': value.key, 'value': _portableWire(value.value)}
      : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) {
    final key = fields['key'];
    if (key is! String || !_keys.contains(key)) return null;
    return _PrivateKeyedValue(key, _portableUnwire(fields['value']));
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final target = box();
    if (incoming is! _PrivateKeyedValue || target == null) return false;
    await target.put(incoming.key, incoming.value);
    if (Hive.isBoxOpen(ProfileService.settingsBoxName)) {
      await Hive.box<dynamic>(ProfileService.settingsBoxName)
          .put(incoming.key, incoming.value);
    }
    ShieldService.revision.value++;
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    final key = SyncFeatureExtensions.privateKeyFromRecordId(id);
    if (!_keys.contains(key)) return;
    await box()?.delete(key);
    if (Hive.isBoxOpen(ProfileService.settingsBoxName)) {
      await Hive.box<dynamic>(ProfileService.settingsBoxName).delete(key);
    }
    ShieldService.revision.value++;
  }
}

/// Расширенные Audio Vault метаданные (QC/analysis). Путь к Ableton-проекту
/// и sourcePath анализа являются путями конкретного устройства и не едут;
/// сами результаты анализа остаются переносимыми.
class _AudioExtrasSync extends SyncCollection<dynamic> {
  static const _metaKey = 'extended_meta_v1';

  @override
  String get name => 'audio_extras';

  @override
  String get boxName => AudioVaultService.boxName;

  @override
  bool watchesBoxKey(Object? key) => '$key' == _metaKey;

  @override
  String idOf(dynamic value) => _metaKey;

  @override
  Map<String, dynamic> encode(dynamic value) {
    if (value is! Map) return const {};
    final meta = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.value is! Map) continue;
      final one = Map<String, dynamic>.from(entry.value as Map);
      one.remove('abletonProjectPath');
      if (one['analysis'] is Map) {
        final analysis = Map<String, dynamic>.from(one['analysis'] as Map)
          ..remove('sourcePath')
          ..remove('sourceModifiedAtMs');
        one['analysis'] = analysis;
      }
      meta['${entry.key}'] = one;
    }
    return {'key': _metaKey, 'value': meta};
  }

  @override
  dynamic decode(Map<String, dynamic> fields) {
    if (fields['key'] != _metaKey || fields['value'] is! Map) return null;
    return Map<String, dynamic>.from(fields['value'] as Map);
  }

  @override
  Box<dynamic>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<dynamic>(boxName);
  }

  @override
  Future<Box<dynamic>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<dynamic>(boxName)
      : await Hive.openBox<dynamic>(boxName);

  @override
  Map<String, dynamic> local() {
    final target = box();
    final value = target?.get(_metaKey);
    return value is Map ? {_metaKey: value} : const {};
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final target = box();
    if (incoming is! Map<String, dynamic> || target == null) return false;

    // Локальные пути не стираются при приезде переносимых метаданных.
    final currentRaw = target.get(_metaKey);
    final current = currentRaw is Map
        ? Map<String, dynamic>.from(currentRaw)
        : <String, dynamic>{};
    final merged = <String, dynamic>{};
    for (final entry in incoming.entries) {
      final next = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{};
      final mineRaw = current[entry.key];
      if (mineRaw is Map) {
        final mine = Map<String, dynamic>.from(mineRaw);
        if (mine['abletonProjectPath'] != null) {
          next['abletonProjectPath'] = mine['abletonProjectPath'];
        }
        if (next['analysis'] is Map && mine['analysis'] is Map) {
          final analysis = Map<String, dynamic>.from(next['analysis'] as Map);
          final mineAnalysis =
              Map<String, dynamic>.from(mine['analysis'] as Map);
          if (mineAnalysis['sourcePath'] != null) {
            analysis['sourcePath'] = mineAnalysis['sourcePath'];
          }
          if (mineAnalysis['sourceModifiedAtMs'] != null) {
            analysis['sourceModifiedAtMs'] = mineAnalysis['sourceModifiedAtMs'];
          }
          next['analysis'] = analysis;
        }
      }
      merged[entry.key] = next;
    }
    await target.put(_metaKey, merged);
    return true;
  }

  @override
  void notifyChanged() => AudioVaultExtrasService.revision.value++;
}

dynamic _portableWire(dynamic value) {
  if (value is Uint8List || value is List<int>) {
    return {'__wesios_bytes_v1': base64Encode(value as List<int>)};
  }
  return value;
}

dynamic _portableUnwire(dynamic value) {
  if (value is Map &&
      value.length == 1 &&
      value['__wesios_bytes_v1'] is String) {
    try {
      return Uint8List.fromList(
        base64Decode(value['__wesios_bytes_v1'] as String),
      );
    } catch (_) {
      return null;
    }
  }
  return value;
}
