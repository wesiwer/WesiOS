import 'dart:convert';

import '../../features/roadmap/models/roadmap_models.dart';
import '../../features/roadmap/services/roadmap_service.dart';
import 'sync_codec.dart';

/// Проекты и вехи дорожной карты в синхронизации.
///
/// Живут отдельным файлом намеренно: [SyncCodec] сейчас переписывается
/// параллельно под организационную иерархию, и лишняя правка того же файла
/// стоила бы тяжёлого слияния на ровном месте. Здесь — только эти две
/// коллекции, в общий список они попадают одной строкой.
///
/// Хранятся как строки JSON: модели дорожной карты — обычные классы с
/// `toJson`/`tryParse`, без Hive-адаптеров, и заводить адаптеры ради
/// синхронизации значило бы менять формат хранения у всех сразу.
class RoadmapProjectsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => RoadmapService.revision.value++;

  @override
  String get name => 'roadmap_projects';

  @override
  String get boxName => RoadmapService.projectsBoxName;

  @override
  String idOf(String value) => _idOf(value);

  @override
  Map<String, dynamic> encode(String value) => _decodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    // Проверяем разбором, а не доверием: битую или чужую по формату запись
    // лучше пропустить, чем положить в бокс строку, которую потом никто не
    // сможет прочитать.
    final project = RoadmapProject.tryParse(fields);
    if (project == null) return null;
    return jsonEncode(project.toJson());
  }

  @override
  bool shouldSync(String value) => _idOf(value).isNotEmpty;
}

class RoadmapItemsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => RoadmapService.revision.value++;

  @override
  String get name => 'roadmap_items';

  @override
  String get boxName => RoadmapService.itemsBoxName;

  @override
  String idOf(String value) => _idOf(value);

  @override
  Map<String, dynamic> encode(String value) => _decodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final item = RoadmapItem.tryParse(fields);
    if (item == null) return null;
    return jsonEncode(item.toJson());
  }

  @override
  bool shouldSync(String value) => _idOf(value).isNotEmpty;
}

Map<String, dynamic>? _decodeJson(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Идентификатор берётся из самой записи, а не из ключа бокса.
///
/// Ключ и поле `id` обязаны совпадать — так их и пишет сервис, — но полагаться
/// на это в обе стороны нельзя: приехавшая с сервера запись кладётся по своему
/// собственному `id`, и если бы он расходился с ключом, на устройстве завелась
/// бы вторая копия того же проекта.
String _idOf(String raw) {
  final json = _decodeJson(raw);
  final id = json?['id'];
  return id is String ? id.trim() : '';
}
