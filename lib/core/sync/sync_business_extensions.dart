import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../../features/tasks/ai/services/wesi_ai_task_service.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/team/models/employee_model.dart';
import '../../features/team/services/team_service.dart';
import '../../features/team/services/team_skill_service.dart';
import '../../features/time_center/services/time_center_service.dart';
import '../../features/treasury/services/category_service.dart';
import '../../features/treasury/services/horizon_contract_memory.dart';
import '../../features/treasury/services/horizon_engine_competition.dart';
import '../../features/treasury/services/horizon_learning_service.dart';
import '../../features/treasury/services/horizon_prediction_registry.dart';
import '../../features/treasury/services/treasury_service.dart';
import 'sync_codec.dart';

/// Второй слой аудита: небольшие бизнес-хранилища, которые не были частью
/// первоначального SyncCodec, но меняют фактическое поведение модулей.
///
/// Это не UI-настройки вроде темы или закрытого баннера обновления. Здесь
/// только переносимое пользовательское/обученное состояние, от которого
/// зависит содержание Tasks, Finance/Horizon, Contacts и Time Center.
class SyncBusinessExtensions {
  SyncBusinessExtensions._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    _replace('employees', _LosslessEmployeesSync());
    _add(_FinanceCategoriesSync());
    _add(_TeamSkillsSync());
    _add(_TimeCenterSync());
    _add(_HorizonPredictionSync());
    _add(_HorizonLearningSync());
    _add(_HorizonCompetitionSync());
    _add(_HorizonContractMemorySync());
    _add(_WesiTaskAiMemorySync());
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

/// EmployeeModel вырос после появления первого sync-кодека. Без этого слоя
/// навыки и параметры рабочей нагрузки физически терялись при round-trip.
class _LosslessEmployeesSync extends EmployeesSync {
  @override
  Map<String, dynamic> encode(EmployeeModel value) => super.encode(value)
    ..addAll(<String, dynamic>{
      'skills': value.skills,
      'weeklyCapacityPoints': value.weeklyCapacityPoints,
      'workloadMinRatio': value.workloadMinRatio,
      'workloadMaxRatio': value.workloadMaxRatio,
      'managerEmployeeId': value.managerEmployeeId,
      'workloadAlertTarget': value.workloadAlertTarget,
    });

  @override
  EmployeeModel? decode(Map<String, dynamic> fields) {
    final base = super.decode(fields);
    if (base == null) return null;
    final skills = fields['skills'];
    return base.copyWith(
      skills: skills is List ? skills.map((e) => '$e').toList() : const [],
      weeklyCapacityPoints:
          _finite(fields['weeklyCapacityPoints'], 10, min: 0.1),
      workloadMinRatio: _finite(fields['workloadMinRatio'], .65, min: 0),
      workloadMaxRatio: _finite(fields['workloadMaxRatio'], 1.10, min: 0),
      managerEmployeeId: _nullableText(fields['managerEmployeeId']),
      clearManager: fields['managerEmployeeId'] == null,
      workloadAlertTarget: _text(fields['workloadAlertTarget'], 'manager'),
    );
  }
}

class _BoxValue {
  final String key;
  final dynamic value;
  const _BoxValue(this.key, this.value);
}

/// Универсальный key/value codec. В отличие от SyncCollection.local() он
/// использует именно ключ Hive: у таких боксов значение само по себе не знает,
/// под каким id его надо хранить на сервере.
abstract class _KeyedBoxSync extends SyncCollection<dynamic> {
  bool includeKey(String key) => true;

  @override
  String idOf(dynamic value) => value is _BoxValue ? value.key : '';

  @override
  bool watchesBoxKey(Object? key) => includeKey('$key');

  @override
  String syncIdForBoxKey(Object? key) => '$key';

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
    final result = <String, dynamic>{};
    for (final rawKey in target.keys) {
      final key = '$rawKey';
      if (!includeKey(key)) continue;
      result[key] = _BoxValue(key, target.get(rawKey));
    }
    return result;
  }

  @override
  Map<String, dynamic> encode(dynamic value) => value is _BoxValue
      ? <String, dynamic>{'key': value.key, 'value': _wire(value.value)}
      : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) {
    final key = fields['key'];
    if (key is! String || key.isEmpty || !includeKey(key)) return null;
    return _BoxValue(key, _unwire(fields['value']));
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final target = box();
    if (incoming is! _BoxValue || target == null) return false;
    await target.put(incoming.key, incoming.value);
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    if (includeKey(id)) await box()?.delete(id);
  }
}

class _FinanceCategoriesSync extends _KeyedBoxSync {
  @override
  String get name => 'finance_categories';

  @override
  String get boxName => 'wesios_settings';

  @override
  bool includeKey(String key) => key.startsWith('categories_');

  @override
  void notifyChanged() => CategoryService.revision.value++;
}

class _TeamSkillsSync extends _KeyedBoxSync {
  @override
  String get name => 'team_skills';

  @override
  String get boxName => TeamSkillService.boxName;

  @override
  void notifyChanged() => TeamService.revision.value++;
}

class _TimeCenterSync extends _KeyedBoxSync {
  static const Set<String> _keys = {
    'alarms',
    'reminders',
    'timer',
    'stopwatch',
  };

  @override
  String get name => 'time_center';

  @override
  String get boxName => TimeCenterService.boxName;

  @override
  bool includeKey(String key) => _keys.contains(key);

  @override
  void notifyChanged() {
    TimeCenterService.revision.value++;
    unawaited(TimeCenterService().restoreSchedules());
  }
}

class _HorizonPredictionSync extends _KeyedBoxSync {
  @override
  String get name => 'horizon_predictions';

  @override
  String get boxName => HorizonPredictionRegistry.boxName;

  @override
  void notifyChanged() => TreasuryService.revision.value++;
}

class _HorizonLearningSync extends _KeyedBoxSync {
  @override
  String get name => 'horizon_learning';

  @override
  String get boxName => HorizonLearningService.boxName;

  @override
  void notifyChanged() => TreasuryService.revision.value++;
}

class _HorizonCompetitionSync extends _KeyedBoxSync {
  @override
  String get name => 'horizon_competition';

  @override
  String get boxName => HorizonEngineCompetitionService.boxName;

  @override
  void notifyChanged() => TreasuryService.revision.value++;
}

class _HorizonContractMemorySync extends _KeyedBoxSync {
  @override
  String get name => 'horizon_contracts';

  @override
  String get boxName => HorizonContractMemoryService.boxName;

  @override
  void notifyChanged() => TreasuryService.revision.value++;
}

/// Решения «принять/отклонить/отложить» и learning events старого AI-помощника
/// Tasks. Это не история Wesi AI Chat и не попадает в облачный full-history;
/// это компактное состояние конкретного пользователя, которое должно давать
/// одинаковые предложения на его телефоне и компьютере.
class _WesiTaskAiMemorySync extends _KeyedBoxSync {
  @override
  String get name => 'task_ai_memory';

  @override
  String get boxName => WesiAiTaskService.memoryBoxName;

  @override
  void notifyChanged() => TaskService.revision.value++;
}

double _finite(
  Object? raw,
  double fallback, {
  required double min,
}) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || !value.isFinite || value < min) return fallback;
  return value;
}

String _text(Object? raw, String fallback) =>
    raw is String && raw.isNotEmpty ? raw : fallback;

String? _nullableText(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

dynamic _wire(dynamic value) {
  if (value is Uint8List || value is List<int>) {
    return <String, dynamic>{
      '__wesios_bytes_v1': base64Encode(value as List<int>),
    };
  }
  if (value is DateTime) {
    return <String, dynamic>{'__wesios_datetime_v1': value.toIso8601String()};
  }
  if (value is List) return value.map(_wire).toList();
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) '${entry.key}': _wire(entry.value),
    };
  }
  return value;
}

dynamic _unwire(dynamic value) {
  if (value is Map) {
    if (value.length == 1 && value['__wesios_bytes_v1'] is String) {
      try {
        return Uint8List.fromList(
          base64Decode(value['__wesios_bytes_v1'] as String),
        );
      } catch (_) {
        return null;
      }
    }
    if (value.length == 1 && value['__wesios_datetime_v1'] is String) {
      return DateTime.tryParse(value['__wesios_datetime_v1'] as String);
    }
    return <String, dynamic>{
      for (final entry in value.entries) '${entry.key}': _unwire(entry.value),
    };
  }
  if (value is List) return value.map(_unwire).toList();
  return value;
}
