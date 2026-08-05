import 'dart:typed_data';

import 'package:hive/hive.dart';

/// Приватные документы сотрудника: договоры, соглашения и другие файлы,
/// доступные только владельцу на его устройствах.
///
/// Хранилище отделено от публичной карточки сотрудника, поэтому байты файлов
/// не попадают в контакты и не видны самому сотруднику. Синхронизацию этого
/// архива можно подключить отдельно к защищённому серверному endpoint.
class EmployeeDocumentsService {
  EmployeeDocumentsService._();

  static const String boxName = 'wesios_employee_documents';
  static const int maxFileBytes = 10 * 1024 * 1024;

  static Box<dynamic>? _box() {
    try {
      return Hive.box(boxName);
    } catch (_) {
      return null;
    }
  }

  static List<EmployeeDocument> forEmployee(String employeeId) {
    final raw = _box()?.get(employeeId);
    if (raw is! List) return const [];
    final result = <EmployeeDocument>[];
    for (final item in raw) {
      if (item is Map) {
        final doc = EmployeeDocument.fromMap(item.cast<dynamic, dynamic>());
        if (doc != null) result.add(doc);
      }
    }
    result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return result;
  }

  static Future<void> add({
    required String employeeId,
    required String name,
    required Uint8List bytes,
    String extension = '',
  }) async {
    if (bytes.length > maxFileBytes) {
      throw ArgumentError('file_too_large');
    }
    final docs = forEmployee(employeeId).toList();
    docs.add(EmployeeDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      extension: extension.trim().toLowerCase(),
      bytes: bytes,
      addedAt: DateTime.now(),
    ));
    await _box()?.put(employeeId, docs.map((e) => e.toMap()).toList());
  }

  static Future<void> remove(String employeeId, String documentId) async {
    final docs = forEmployee(employeeId)
        .where((item) => item.id != documentId)
        .toList();
    if (docs.isEmpty) {
      await _box()?.delete(employeeId);
    } else {
      await _box()?.put(employeeId, docs.map((e) => e.toMap()).toList());
    }
  }

  static Future<void> clearEmployee(String employeeId) =>
      _box()?.delete(employeeId) ?? Future.value();
}

class EmployeeDocument {
  final String id;
  final String name;
  final String extension;
  final Uint8List bytes;
  final DateTime addedAt;

  const EmployeeDocument({
    required this.id,
    required this.name,
    required this.extension,
    required this.bytes,
    required this.addedAt,
  });

  int get sizeBytes => bytes.length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'extension': extension,
        'bytes': bytes,
        'addedAt': addedAt.toIso8601String(),
      };

  static EmployeeDocument? fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final name = map['name'];
    final bytes = map['bytes'];
    final addedAt = DateTime.tryParse(map['addedAt']?.toString() ?? '');
    if (id is! String || name is! String || bytes is! Uint8List || addedAt == null) {
      return null;
    }
    return EmployeeDocument(
      id: id,
      name: name,
      extension: map['extension']?.toString() ?? '',
      bytes: bytes,
      addedAt: addedAt,
    );
  }
}
