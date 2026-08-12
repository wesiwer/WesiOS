import 'dart:convert';

import '../../features/crm/models/crm_models.dart';
import '../../features/crm/services/crm_service.dart';
import 'sync_codec.dart';

/// Клиенты, сделки и касания в синхронизации.
///
/// Отдельным файлом по той же причине, что и дорожная карта: [SyncCodec]
/// сейчас переписывается параллельно под организационную иерархию.
///
/// Хранятся строками JSON — модели CRM обычные классы с `toJson`/`tryParse`,
/// без Hive-адаптеров.
class CrmClientsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => CrmService.revision.value++;

  @override
  String get name => 'crm_clients';

  @override
  String get boxName => CrmService.clientsBoxName;

  @override
  String idOf(String value) => crmIdOf(value);

  @override
  Map<String, dynamic> encode(String value) => crmDecodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final client = CrmClient.tryParse(fields);
    if (client == null) return null;
    return jsonEncode(client.toJson());
  }

  @override
  bool shouldSync(String value) => crmIdOf(value).isNotEmpty;
}

class CrmDealsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => CrmService.revision.value++;

  @override
  String get name => 'crm_deals';

  @override
  String get boxName => CrmService.dealsBoxName;

  @override
  String idOf(String value) => crmIdOf(value);

  @override
  Map<String, dynamic> encode(String value) => crmDecodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final deal = CrmDeal.tryParse(fields);
    if (deal == null) return null;
    return jsonEncode(deal.toJson());
  }

  @override
  bool shouldSync(String value) => crmIdOf(value).isNotEmpty;
}

class CrmInteractionsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => CrmService.revision.value++;

  @override
  String get name => 'crm_interactions';

  @override
  String get boxName => CrmService.interactionsBoxName;

  @override
  String idOf(String value) => crmIdOf(value);

  @override
  Map<String, dynamic> encode(String value) => crmDecodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    final touch = CrmInteraction.tryParse(fields);
    if (touch == null) return null;
    return jsonEncode(touch.toJson());
  }

  @override
  bool shouldSync(String value) => crmIdOf(value).isNotEmpty;
}

Map<String, dynamic>? crmDecodeJson(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Идентификатор берётся из самой записи, а не из ключа бокса: приехавшая с
/// сервера запись кладётся по своему `id`, и расхождение с ключом завело бы
/// на устройстве вторую копию того же клиента.
String crmIdOf(String raw) {
  final id = crmDecodeJson(raw)?['id'];
  return id is String ? id.trim() : '';
}
