import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../organizations/models/organization_access_grant.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../organizations/services/organization_service.dart';
import '../../team/models/team_permissions.dart';
import '../../team/services/team_service.dart';
import '../models/crm_models.dart';

class CrmService {
  static const String boxName = 'wesios_crm';
  /// Старый бокс. Остаётся источником для переноса.
  static const String clientsBoxName = 'wesios_crm_clients';
  static const String dealsBoxName = 'wesios_crm_deals';
  static const String interactionsBoxName = 'wesios_crm_interactions';
  static const String _clientsKey = 'clients_v1';
  static const String _dealsKey = 'deals_v1';
  static const String _interactionsKey = 'interactions_v1';
  static const String _migratedKey = 'migrated_to_records_v1';

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
  /// Хранить каталог одной строкой нельзя: журнал синхронизации следит за
  /// ключами бокса, и правка карточки одного клиента считалась бы изменением
  /// всего списка — то есть затирала бы чужую правку соседней карточки.
  ///
  /// Отметка о переносе живёт в старом же боксе: пока её нет, перенос
  /// повторяется, поэтому оборванный на середине переезд не теряет данные.
  static Future<void> _migrateIfNeeded() async {
    if (_migrating) return;
    if (!Hive.isBoxOpen(boxName) && !await Hive.boxExists(boxName)) return;
    _migrating = true;
    try {
      final legacy = await _open();
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
          // Уже перенесённое не трогаем: у него мог появиться более свежий
          // вариант с другого устройства.
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

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<dynamic>? _box;

  static Future<Box<dynamic>> _open() async {
    _box ??= await Hive.openBox<dynamic>(boxName);
    return _box!;
  }

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static bool _moduleAllowed() {
    final current = TeamService.current;
    return current == null ||
        current.isOwner ||
        current.permissions.allows(TeamModules.crm);
  }

  static bool _manager() {
    final current = TeamService.current;
    if (current == null || current.isOwner) return true;
    return current.permissions.canManageTeam ||
        current.permissions.canSeeOthersStats;
  }

  static Future<Set<String>> _visibleOrganizationIds({
    Set<String>? requested,
    bool honorCurrentContext = false,
  }) async {
    if (!_moduleAllowed()) return <String>{};
    final current = TeamService.current;
    Set<String> allowed;
    if (current == null) {
      allowed = (await OrganizationService.all()).map((e) => e.id).toSet();
    } else if (current.isOwner) {
      final root = await OrganizationService.root();
      allowed = await OrganizationService.subtreeIds(root.id);
    } else {
      allowed = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.view,
        employeeId: current.id,
      );
    }
    if (honorCurrentContext) {
      allowed = allowed.intersection(
        await OrganizationContext.effectiveOrganizationIds(),
      );
    }
    return requested == null ? allowed : allowed.intersection(requested);
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

  static Future<List<CrmClient>> clientsRaw() async {
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

  static Future<List<CrmDeal>> dealsRaw() async {
    final box = await _openRecords(dealsBoxName);
    final list = _decodeRecords(box, CrmDeal.tryParse);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<List<CrmInteraction>> interactionsRaw() async {
    final box = await _openRecords(interactionsBoxName);
    final list = _decodeRecords(box, CrmInteraction.tryParse);
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  static bool _clientOwnedByCurrent(CrmClient client) {
    final current = TeamService.current;
    if (current == null || current.isOwner || _manager()) return true;
    return client.ownerEmployeeId == current.id;
  }

  static bool _dealOwnedByCurrent(
    CrmDeal deal,
    Map<String, CrmClient> clients,
  ) {
    final current = TeamService.current;
    if (current == null || current.isOwner || _manager()) return true;
    return deal.responsibleEmployeeId == current.id ||
        clients[deal.clientId]?.ownerEmployeeId == current.id;
  }

  static Future<List<CrmClient>> _scopedClients(
    Set<String> organizationIds,
  ) async {
    if (organizationIds.isEmpty) return const <CrmClient>[];
    final allClients = await clientsRaw();
    if (_manager() || TeamService.current == null) {
      return allClients
          .where((c) => organizationIds.contains(c.organizationId))
          .toList();
    }
    final current = TeamService.current!;
    final ownDealClientIds = (await dealsRaw())
        .where((d) =>
            organizationIds.contains(d.organizationId) &&
            d.responsibleEmployeeId == current.id)
        .map((d) => d.clientId)
        .toSet();
    return allClients
        .where((c) =>
            organizationIds.contains(c.organizationId) &&
            (c.ownerEmployeeId == current.id || ownDealClientIds.contains(c.id)))
        .toList();
  }

  static Future<List<CrmDeal>> _scopedDeals(
    Set<String> organizationIds,
  ) async {
    if (organizationIds.isEmpty) return const <CrmDeal>[];
    final clients = {
      for (final c in await clientsRaw()) c.id: c,
    };
    return (await dealsRaw())
        .where((d) =>
            organizationIds.contains(d.organizationId) &&
            _dealOwnedByCurrent(d, clients))
        .toList();
  }

  static Future<List<CrmClient>> clients() async => _scopedClients(
        await _visibleOrganizationIds(honorCurrentContext: true),
      );

  static Future<List<CrmDeal>> deals() async => _scopedDeals(
        await _visibleOrganizationIds(honorCurrentContext: true),
      );

  static Future<List<CrmClient>> clientsForOrganizations(
    Set<String> organizationIds,
  ) async =>
      _scopedClients(
        await _visibleOrganizationIds(requested: organizationIds),
      );

  static Future<List<CrmDeal>> dealsForOrganizations(
    Set<String> organizationIds,
  ) async =>
      _scopedDeals(
        await _visibleOrganizationIds(requested: organizationIds),
      );

  static Future<List<CrmInteraction>> interactions() async {
    final visibleClients = {for (final c in await clients()) c.id};
    final visibleDeals = {for (final d in await deals()) d.id};
    return (await interactionsRaw())
        .where((i) =>
            visibleClients.contains(i.clientId) &&
            (i.dealId == null || visibleDeals.contains(i.dealId)))
        .toList();
  }

  static Future<void> _requireOrgWrite(String organizationId) async {
    final org = await OrganizationService.byId(organizationId);
    if (org == null || org.archived) {
      throw StateError('CRM organization unavailable');
    }
    final current = TeamService.current;
    if (current == null || current.isOwner) return;
    if (!current.permissions.allows(TeamModules.crm)) {
      throw StateError('CRM module access required');
    }
    final contextIds = await OrganizationContext.effectiveOrganizationIds();
    if (!contextIds.contains(organizationId) ||
        !await OrganizationAccessService.can(
          organizationId,
          OrganizationPermissions.view,
          employeeId: current.id,
        )) {
      throw StateError('CRM organization access denied');
    }
  }

  static Future<void> saveClient(CrmClient client) async {
    final all = await clientsRaw();
    final now = DateTime.now();
    final index = all.indexWhere((value) => value.id == client.id);
    final previous = index < 0 ? null : all[index];
    final orgId = client.organizationId.isEmpty
        ? (previous?.organizationId ?? OrganizationContext.currentOrganizationId)
        : client.organizationId;
    await _requireOrgWrite(orgId);
    if (previous != null) await _requireOrgWrite(previous.organizationId);

    final current = TeamService.current;
    if (current != null && !current.isOwner && !_manager()) {
      if (previous != null && !_clientOwnedByCurrent(previous)) {
        throw StateError('CRM client belongs to another employee');
      }
      if (client.ownerEmployeeId != null &&
          client.ownerEmployeeId != current.id) {
        throw StateError('cannot assign CRM client to another employee');
      }
    }

    final normalized = client.copyWith(
      updatedAt: now,
      organizationId: orgId,
      ownerEmployeeId: current != null && !current.isOwner && !_manager()
          ? current.id
          : client.ownerEmployeeId,
      clearOwnerEmployee: current == null || current.isOwner || _manager()
          ? client.ownerEmployeeId == null
          : false,
    );
    await _put(clientsBoxName, normalized.id, normalized.toJson());
  }

  static Future<void> archiveClient(String id) async {
    final all = await clientsRaw();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    final before = all[index];
    await _requireOrgWrite(before.organizationId);
    if (!_clientOwnedByCurrent(before)) {
      throw StateError('CRM client belongs to another employee');
    }
    final archived = before.copyWith(
      status: CrmClientStatus.archived,
      clearNextContact: true,
      updatedAt: DateTime.now(),
    );
    await _put(clientsBoxName, archived.id, archived.toJson());
  }

  static Future<void> deleteClient(String id) async {
    final allClients = await clientsRaw();
    final target = allClients.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    await _requireOrgWrite(target.organizationId);
    if (!_clientOwnedByCurrent(target)) {
      throw StateError('CRM client belongs to another employee');
    }
    // Сделки и касания удалённого клиента убираются поимённо: каждая обязана
    // оставить в журнале своё надгробие, иначе удаление не доедет до других
    // устройств и записи воскреснут при следующем обмене.
    final dealsBox = await _openRecords(dealsBoxName);
    final interactionsBox = await _openRecords(interactionsBoxName);
    await (await _openRecords(clientsBoxName)).delete(id);
    for (final deal in await dealsRaw()) {
      if (deal.clientId == id) await dealsBox.delete(deal.id);
    }
    for (final touch in await interactionsRaw()) {
      if (touch.clientId == id) await interactionsBox.delete(touch.id);
    }
    revision.value++;
  }

  static Future<void> saveDeal(CrmDeal deal) async {
    final all = await dealsRaw();
    final clients = {for (final c in await clientsRaw()) c.id: c};
    final client = clients[deal.clientId];
    if (client == null) throw StateError('CRM client does not exist');
    final now = DateTime.now();
    final index = all.indexWhere((value) => value.id == deal.id);
    final previous = index < 0 ? null : all[index];
    final orgId = deal.organizationId.isEmpty
        ? (previous?.organizationId ?? client.organizationId)
        : deal.organizationId;
    if (orgId != client.organizationId) {
      throw StateError('CRM deal and client must belong to the same organization');
    }
    await _requireOrgWrite(orgId);
    if (previous != null) await _requireOrgWrite(previous.organizationId);

    final current = TeamService.current;
    if (current != null && !current.isOwner && !_manager()) {
      if (previous != null && !_dealOwnedByCurrent(previous, clients)) {
        throw StateError('CRM deal belongs to another employee');
      }
      if (deal.responsibleEmployeeId != null &&
          deal.responsibleEmployeeId != current.id) {
        throw StateError('cannot assign CRM deal to another employee');
      }
      if (!_clientOwnedByCurrent(client) && previous == null) {
        throw StateError('CRM client belongs to another employee');
      }
    }

    var next = deal.copyWith(
      updatedAt: now,
      organizationId: orgId,
      responsibleEmployeeId:
          current != null && !current.isOwner && !_manager()
              ? current.id
              : deal.responsibleEmployeeId,
      clearResponsibleEmployee: current == null || current.isOwner || _manager()
          ? deal.responsibleEmployeeId == null
          : false,
    );
    if (next.stage == DealStage.won || next.stage == DealStage.lost) {
      next = next.copyWith(closedAt: next.closedAt ?? now);
    } else if (next.closedAt != null) {
      next = next.copyWith(clearClosedAt: true);
    }
    await _put(dealsBoxName, next.id, next.toJson());
  }

  static Future<void> moveDeal(String id, DealStage stage) async {
    final all = await dealsRaw();
    final target = all.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    await saveDeal(target.copyWith(stage: stage));
  }

  static Future<void> deleteDeal(String id) async {
    final all = await dealsRaw();
    final target = all.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    await _requireOrgWrite(target.organizationId);
    final clients = {for (final c in await clientsRaw()) c.id: c};
    if (!_dealOwnedByCurrent(target, clients)) {
      throw StateError('CRM deal belongs to another employee');
    }
    final interactionsBox = await _openRecords(interactionsBoxName);
    await (await _openRecords(dealsBoxName)).delete(id);
    for (final touch in await interactionsRaw()) {
      if (touch.dealId == id) await interactionsBox.delete(touch.id);
    }
    revision.value++;
  }

  static Future<void> _requireInteractionWrite(
    CrmInteraction interaction,
    Map<String, CrmClient> clients,
    Map<String, CrmDeal> deals,
  ) async {
    final client = clients[interaction.clientId];
    if (client == null) throw StateError('CRM client does not exist');
    await _requireOrgWrite(client.organizationId);

    CrmDeal? linked;
    if (interaction.dealId != null) {
      linked = deals[interaction.dealId!];
      if (linked == null ||
          linked.clientId != client.id ||
          linked.organizationId != client.organizationId) {
        throw StateError('CRM interaction deal/client mismatch');
      }
    }

    if (!_clientOwnedByCurrent(client) &&
        (linked == null || !_dealOwnedByCurrent(linked, clients))) {
      throw StateError('CRM interaction parent is outside employee scope');
    }
  }

  static Future<void> saveInteraction(CrmInteraction interaction) async {
    final clients = {for (final c in await clientsRaw()) c.id: c};
    final deals = {for (final d in await dealsRaw()) d.id: d};
    await _requireInteractionWrite(interaction, clients, deals);

    final all = await interactionsRaw();
    final existing = all.where((v) => v.id == interaction.id).firstOrNull;
    if (existing != null) {
      // Re-authorize the old parent before replacing by id. Re-parenting an
      // inaccessible row must never become an ownership bypass.
      await _requireInteractionWrite(existing, clients, deals);
    }
    await _put(interactionsBoxName, interaction.id, interaction.toJson());

    if (interaction.nextActionAt == null) return;
    // Дата следующего касания живёт и в карточке клиента — обновляем только
    // её одну, а не весь список: иначе на сервер уехали бы все карточки
    // сразу и затёрли бы чужие правки.
    final client = clients[interaction.clientId];
    if (client == null) return;
    final updated = client.copyWith(
      nextContactAt: interaction.nextActionAt,
      updatedAt: DateTime.now(),
    );
    await _put(clientsBoxName, updated.id, updated.toJson());
  }

  static Future<void> deleteInteraction(String id) async {
    final all = await interactionsRaw();
    final target = all.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    final clients = {for (final c in await clientsRaw()) c.id: c};
    final deals = {for (final d in await dealsRaw()) d.id: d};
    await _requireInteractionWrite(target, clients, deals);
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

  static Future<CrmSummary> summary({Set<String>? organizationIds}) async {
    final allClients = organizationIds == null
        ? await clients()
        : await clientsForOrganizations(organizationIds);
    final allDeals = organizationIds == null
        ? await deals()
        : await dealsForOrganizations(organizationIds);
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
