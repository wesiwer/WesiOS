import 'dart:convert';

import '../../features/audio/models/audio_vault_models.dart';
import '../../features/audio/services/audio_vault_service.dart';
import '../../features/crm/models/crm_models.dart';
import '../../features/crm/services/crm_service.dart';
import '../../features/profile/services/profile_service.dart';
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

/// Профиль человека — одна запись на все его устройства.
///
/// Имя, почта, дата рождения, страна и аватарка лежали в `wesios_settings`
/// вместе с адресом сервера и пропуском сессии, а тот бокс не
/// синхронизируется — и не должен. Из-за этого профиль, заполненный на
/// компьютере, на телефоне выглядел пустым.
class ProfileSync extends SyncCollection<String> {
  @override
  String get name => 'profile';

  @override
  String get boxName => ProfileService.boxName;

  @override
  String idOf(String value) => ProfileService.recordKey;

  @override
  Map<String, dynamic> encode(String value) => crmDecodeJson(value) ?? const {};

  @override
  String? decode(Map<String, dynamic> fields) {
    if (fields.isEmpty) return null;
    return jsonEncode(fields);
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final ok = await super.applyFields(fields);
    // Интерфейс читает профиль из настроек, поэтому приехавшую запись надо
    // сразу разложить по их ключам: иначе профиль доедет до устройства, а на
    // экране останется прежним.
    if (ok) await ProfileService.spreadToSettings();
    return ok;
  }

  @override
  void notifyChanged() => ProfileService.revision.value++;
}

/// Каталог битов.
///
/// Синхронизируется то, **что за бит**: название, темп, тональность, стадия,
/// комментарии, условия аренды. Пути к файлам — нет, и это главное здесь.
///
/// Путь вида `/data/.../AudioVault/<id>/mp3_...` — свойство устройства, а не
/// карточки. Приехав на другой телефон, он указывал бы в пустоту: приложение
/// считало бы, что файл есть, показывало бы кнопку воспроизведения и молча
/// не работало. Поэтому пути вычищаются при отправке, а при получении
/// подставляются свои — те, что уже есть на этом устройстве.
class AudioBeatsSync extends SyncCollection<String> {
  @override
  void notifyChanged() => AudioVaultService.revision.value++;

  @override
  String get name => 'audio_beats';

  @override
  String get boxName => AudioVaultService.beatsBoxName;

  @override
  String idOf(String value) => crmIdOf(value);

  @override
  bool shouldSync(String value) => crmIdOf(value).isNotEmpty;

  /// Поля, которые указывают на файл на диске этого устройства.
  static const List<String> _localOnly = [
    'mp3Path',
    'wavPath',
    'trackoutPath',
    'coverPath',
    'attachments',
  ];

  @override
  Map<String, dynamic> encode(String value) {
    final json = crmDecodeJson(value);
    if (json == null) return const {};
    final out = Map<String, dynamic>.of(json);
    for (final key in _localOnly) {
      out.remove(key);
    }
    return out;
  }

  @override
  String? decode(Map<String, dynamic> fields) {
    final id = fields['id'];
    if (id is! String || id.trim().isEmpty) return null;
    try {
      // Разбираем через модель: так запись из более новой версии, которую эта
      // не понимает, будет пропущена, а не положена в бокс мусором.
      BeatEntry.fromJson(fields);
    } catch (_) {
      return null;
    }
    return jsonEncode(fields);
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final box = this.box();
    if (box == null) return false;
    final decoded = decode(fields);
    if (decoded == null) return false;

    final id = '${fields['id']}';
    final merged = Map<String, dynamic>.of(fields);
    // Свои файлы остаются своими: приехавшая карточка описывает бит, а где
    // его файлы лежат на этом устройстве — знает только это устройство.
    final mine = crmDecodeJson(box.get(id) ?? '');
    if (mine != null) {
      for (final key in _localOnly) {
        if (mine[key] != null) merged[key] = mine[key];
      }
    }
    await box.put(id, jsonEncode(merged));
    return true;
  }
}
