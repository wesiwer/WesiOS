import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/crm_models.dart';

/// Клиенты, сделки и касания.
///
/// Каждая запись лежит отдельно, ключ — её идентификатор. Раньше все клиенты
/// были одной строкой JSON под ключом `clients_v1`, и совместная работа при
/// таком хранении невозможна: журнал синхронизации следит за ключами бокса, а
/// ключ был один на весь список. Правка карточки одного клиента считалась бы
/// изменением всего списка и затирала бы чужую правку соседней карточки,
/// сделанную в это же время.
///
/// Старый формат читается при первом открытии и разбирается по записям —
/// данные, заведённые до этой версии, не теряются.
class CrmService {
  /// Старый бокс. Остаётся только как источник для переноса.
  static const String boxName = 'wesios_crm';
  static const String clientsBoxName = 'wesios_crm_clients';
  static const String dealsBoxName = 'wesios_crm_deals';
  static const String interactionsBoxName = 'wesios_crm_interactions';
  static const String _clientsKey = 'clients_v1';
  static const String _dealsKey = 'deals_v1';
  static const String _interactionsKey = 'interactions_v1';
  static const String _migratedKey = 'migrated_to_records_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<String, Box<String>> _boxes = {};

  static Future<Box<String>> _openRecords(String name) async {
    final cached = _boxes[name];
    if (cached != null && cached.isOpen) {
      await _migrateIfNeeded();
      return cached;
    }
    final box = Hive.isBoxOpen(name)
        ? Hive.box<String>(name)
        : await Hive.openBox<String>(name);
    _boxes[name] = box;
    await _migrateIfNeeded();
    return box;
  }

  static bool _migrating = false;

  /// Перенос со старого формата «весь список одной строкой».
  ///
  /// Отметка о переносе живёт в старом же боксе: пока её нет, перенос
  /// повторяется, поэтому оборванный на середине переезд не теряет данные, а
  /// просто случается заново. Уже перенесённое не трогается — у него мог
  /// появиться более свежий вариант с другого устройства.
  static Future<void> _migrateIfNeeded() async {
    if (_migrating) return;
    if (!Hive.isBoxOpen(boxName) && !await Hive.boxExists(boxName)) return;
    _migrating = true;
    try {
      final legacy = Hive.isBoxOpen(boxName)
          ? Hive.box<dynamic>(boxName)
          : await Hive.openBox<dynamic>(boxName);
      if (legacy.get(_migratedKey) == true) return;

      Future<void> move<T>(
        String key,
        String boxTo,
        T? Function(Map<String, dynamic>) parse,
        String Function(T) idOf,
        Map<String, dynamic> Function(T) encode,
      ) async {
        final box = _boxes[boxTo] ??= Hive.isBoxOpen(boxTo)
            ? Hive.box<String>(boxTo)
            : await Hive.openBox<String>(boxTo);
        for (final value in _decodeList(legacy.get(key), parse)) {
          final id = idOf(value);
          if (id.isEmpty || box.containsKey(id)) continue;
          await box.put(id, jsonEncode(encode(value)));
        }
      }

      await move<CrmClient>(_clientsKey, clientsBoxName, CrmClient.tryParse,
          (v) => v.id, (v) => v.toJson());
      await move<CrmDeal>(_dealsKey, dealsBoxName, CrmDeal.tryParse,
          (v) => v.id, (v) => v.toJson());
      await move<CrmInteraction>(_interactionsKey, interactionsBoxName,
          CrmInteraction.tryParse, (v) => v.id, (v) => v.toJson());
      await legacy.put(_migratedKey, true);
    } catch (_) {
      // Сломанный старый бокс не должен мешать работать дальше.
    } finally {
      _migrating = false;
    }
  }

  /// Разбор бокса, где каждая запись — своя строка JSON.
  static List<T> _decodeRecords<T>(
    Box<String> box,
    T? Function(Map<String, dynamic>) parse,
  ) {
    final out = <T>[];
    for (final raw in box.values) {
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final value = parse(Map<String, dynamic>.from(decoded));
        if (value != null) out.add(value);
      } catch (_) {
        // Одна испорченная запись не должна прятать остальные.
      }
    }
    return out;
  }

  static Future<void> _put(String boxName_, String id, Object json) async {
    final box = await _openRecords(boxName_);
    await box.put(id, jsonEncode(json));
    revision.value++;
  }

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static Future<List<CrmClient>> clients() async {
    final box = await _openRecords(clientsBoxName);
    final list = _decodeRecords(box, CrmClient.tryParse);
    list.sort((a, b) {
      final archived = a.status == CrmClientStatus.archived ? 1 : 0;
      final otherArchived = b.status == CrmClientStatus.archived ? 1 : 0;
      final byArchive = archived.compareTo(otherArchived);
      if (byArchive != 0) return byArchive;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  static Future<List<CrmDeal>> deals() async {
    final box = await _openRecords(dealsBoxName);
    final list = _decodeRecords(box, CrmDeal.tryParse);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<List<CrmInteraction>> interactions() async {
    final box = await _openRecords(interactionsBoxName);
    final list = _decodeRecords(box, CrmInteraction.tryParse);
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  static List<T> _decodeList<T>(
    Object? raw,
    T? Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! String || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return [
        for (final value in decoded)
          if (value is Map)
            if (parse(Map<String, dynamic>.from(value)) case final item?) item,
      ];
    } catch (_) {
      return <T>[];
    }
  }


  static Future<void> saveClient(CrmClient client) async {
    final normalized = client.copyWith(updatedAt: DateTime.now());
    await _put(clientsBoxName, normalized.id, normalized.toJson());
  }

  static Future<void> archiveClient(String id) async {
    final all = await clients();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    final archived = all[index].copyWith(
      status: CrmClientStatus.archived,
      clearNextContact: true,
      updatedAt: DateTime.now(),
    );
    await _put(clientsBoxName, archived.id, archived.toJson());
  }

  static Future<void> deleteClient(String id) async {
    // Сделки и касания удалённого клиента убираются поимённо: каждая обязана
    // оставить в журнале своё надгробие, иначе удаление не доедет до других
    // устройств и записи воскреснут при следующем обмене.
    final clientsBox = await _openRecords(clientsBoxName);
    final dealsBox = await _openRecords(dealsBoxName);
    final interactionsBox = await _openRecords(interactionsBoxName);
    await clientsBox.delete(id);
    for (final deal in await deals()) {
      if (deal.clientId == id) await dealsBox.delete(deal.id);
    }
    for (final touch in await interactions()) {
      if (touch.clientId == id) await interactionsBox.delete(touch.id);
    }
    revision.value++;
  }

  static Future<void> saveDeal(CrmDeal deal) async {
    final now = DateTime.now();
    var next = deal.copyWith(updatedAt: now);
    if (next.stage == DealStage.won || next.stage == DealStage.lost) {
      next = next.copyWith(closedAt: next.closedAt ?? now);
    } else if (next.closedAt != null) {
      next = next.copyWith(clearClosedAt: true);
    }
    await _put(dealsBoxName, next.id, next.toJson());
  }

  static Future<void> moveDeal(String id, DealStage stage) async {
    final all = await deals();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    await saveDeal(all[index].copyWith(stage: stage));
  }

  static Future<void> deleteDeal(String id) async {
    final dealsBox = await _openRecords(dealsBoxName);
    final interactionsBox = await _openRecords(interactionsBoxName);
    await dealsBox.delete(id);
    for (final touch in await interactions()) {
      if (touch.dealId == id) await interactionsBox.delete(touch.id);
    }
    revision.value++;
  }

  static Future<void> saveInteraction(CrmInteraction interaction) async {
    await _put(interactionsBoxName, interaction.id, interaction.toJson());

    if (interaction.nextActionAt == null) return;
    // Дата следующего касания живёт и в карточке клиента — обновляем только
    // её одну, а не весь список: иначе на сервер уехали бы все карточки
    // сразу и затёрли бы чужие правки.
    final all = await clients();
    final index = all.indexWhere((value) => value.id == interaction.clientId);
    if (index < 0) return;
    final updated = all[index].copyWith(
      nextContactAt: interaction.nextActionAt,
      updatedAt: DateTime.now(),
    );
    await _put(clientsBoxName, updated.id, updated.toJson());
  }

  static Future<void> deleteInteraction(String id) async {
    await (await _openRecords(interactionsBoxName)).delete(id);
    revision.value++;
  }

  static Future<List<CrmDeal>> dealsForClient(String clientId) async =>
      (await deals()).where((value) => value.clientId == clientId).toList();

  static Future<List<CrmInteraction>> interactionsForClient(
    String clientId,
  ) async =>
      (await interactions())
          .where((value) => value.clientId == clientId)
          .toList();

  static Future<CrmSummary> summary() async {
    final allClients = await clients();
    final allDeals = await deals();
    final visibleClients = allClients
        .where((value) => value.status != CrmClientStatus.archived)
        .toList();
    final open = allDeals.where((value) => value.isOpen).toList();
    final won = allDeals.where((value) => value.stage == DealStage.won).toList();
    return CrmSummary(
      clients: visibleClients.length,
      activeClients: visibleClients
          .where((value) => value.status == CrmClientStatus.active)
          .length,
      openDeals: open.length,
      wonDeals: won.length,
      overdueFollowUps:
          visibleClients.where((value) => value.followUpOverdue).length,
      pipelineAmount: open.fold(0, (sum, value) => sum + value.amount),
      weightedPipeline:
          open.fold(0, (sum, value) => sum + value.weightedAmount),
      wonAmount: won.fold(0, (sum, value) => sum + value.amount),
    );
  }

  static Future<void> clearForTest() async {
    for (final name in [clientsBoxName, dealsBoxName, interactionsBoxName]) {
      await (await _openRecords(name)).clear();
    }
    if (Hive.isBoxOpen(boxName)) await Hive.box<dynamic>(boxName).clear();
    revision.value++;
  }
}