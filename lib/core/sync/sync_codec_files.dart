import 'dart:convert';

import '../../features/files/models/file_share_models.dart';
import '../../features/files/services/file_share_service.dart';
import 'sync_codec.dart';

/// Запросы на файлы, открытые доступы и журнал выдач.
///
/// В обмене ходит только описание: «кто что просит», «кому что открыто»,
/// «что кому отдали». Сами файлы не едут никогда — они передаются отдельно и
/// только после подтверждения владельца.
///
/// Без синхронизации этих записей вся затея не работает: запрос, сделанный с
/// телефона, обязан появиться у владельца на компьютере, а отозванный доступ
/// — исчезнуть на всех устройствах сразу.
class FileRequestsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => FileShareService.revision.value++;

  @override
  String get name => 'file_requests';

  @override
  String get boxName => FileShareService.requestsBoxName;

  @override
  String idOf(String value) => _idOf(value);

  @override
  bool shouldSync(String value) => _idOf(value).isNotEmpty;

  @override
  Map<String, dynamic> encode(String value) => _decode(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final request = FileShareRequest.tryParse(fields);
    if (request == null) return null;
    return jsonEncode(request.toJson());
  }
}

class FileGrantsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => FileShareService.revision.value++;

  @override
  String get name => 'file_grants';

  @override
  String get boxName => FileShareService.grantsBoxName;

  @override
  String idOf(String value) => _idOf(value);

  @override
  bool shouldSync(String value) => _idOf(value).isNotEmpty;

  @override
  Map<String, dynamic> encode(String value) => _decode(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final grant = FileAccessGrant.tryParse(fields);
    if (grant == null) return null;
    return jsonEncode(grant.toJson());
  }
}

/// Журнал выдач.
///
/// Едет вместе со всем остальным, но никогда не удаляется: запись о том, что
/// файл ушёл, важнее места, которое она занимает. Вопрос «откуда у него wav»
/// однажды окажется важным.
class FileHandoversSync extends SyncCollection<String> {
  @override
  void notifyChanged() => FileShareService.revision.value++;

  @override
  String get name => 'file_handovers';

  @override
  String get boxName => FileShareService.handoversBoxName;

  @override
  String idOf(String value) => _idOf(value);

  @override
  bool shouldSync(String value) => _idOf(value).isNotEmpty;

  @override
  Map<String, dynamic> encode(String value) => _decode(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final handover = FileHandover.tryParse(fields);
    if (handover == null) return null;
    return jsonEncode(handover.toJson());
  }
}

Map<String, dynamic>? _decode(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String _idOf(String raw) {
  final id = _decode(raw)?['id'];
  return id is String ? id.trim() : '';
}
