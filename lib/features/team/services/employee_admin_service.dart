import 'package:hive/hive.dart';

import '../models/employee_model.dart';

/// Закрытые административные данные о сотрудниках.
///
/// Они лежат в настройках владельца, а не в публичной карточке сотрудника:
/// коллеги не должны видеть ни статус выдачи доступа, ни причины увольнения.
class EmployeeAdminService {
  EmployeeAdminService._();

  static const String _settingsBox = 'wesios_settings';
  static const String _activationKey = 'team_account_activation';
  static const String _deletedKey = 'team_deleted_archive';

  static Box<dynamic>? _box() {
    try {
      return Hive.box(_settingsBox);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _activationMap() {
    final raw = _box()?.get(_activationKey);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// Успешно ли создана и проверена серверная учётная запись.
  static bool isActivated(String employeeId) =>
      _activationMap()[employeeId] == true;

  static Future<void> setActivated(String employeeId, bool value) async {
    final box = _box();
    if (box == null) return;
    final map = _activationMap();
    map[employeeId] = value;
    await box.put(_activationKey, map);
  }

  static List<Map<String, dynamic>> get deleted {
    final raw = _box()?.get(_deletedKey);
    final rows = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    rows.sort((a, b) =>
        '${b['deletedAt']}'.compareTo('${a['deletedAt']}'));
    return rows;
  }

  /// Сохраняет административный снимок перед удалением рабочей карточки.
  /// Пароль, хеш, соль, права и личная заметка намеренно не архивируются.
  static Future<void> archive(
    EmployeeModel employee, {
    String reason = '',
  }) async {
    final box = _box();
    if (box == null || employee.isOwner) return;

    final rows = deleted.where((e) => e['id'] != employee.id).toList();
    rows.add({
      'id': employee.id,
      'login': employee.login,
      'fullName': employee.fullName,
      'nickname': employee.nickname,
      'position': employee.position,
      'phone': employee.phone,
      'email': employee.email,
      'socials': Map<String, String>.from(employee.socials),
      'createdAt': employee.createdAt.toIso8601String(),
      'deletedAt': DateTime.now().toIso8601String(),
      'reason': reason.trim(),
      'wasActivated': isActivated(employee.id),
    });
    await box.put(_deletedKey, rows);

    final activation = _activationMap()..remove(employee.id);
    await box.put(_activationKey, activation);
  }

  static Future<void> deleteArchiveEntry(String employeeId) async {
    final box = _box();
    if (box == null) return;
    final rows = deleted.where((e) => e['id'] != employeeId).toList();
    await box.put(_deletedKey, rows);
  }
}
