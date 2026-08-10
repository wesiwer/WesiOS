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
  static const String _clientsKey = 'clients_v1';
  static const String _dealsKey = 'deals_v1';
  static const String _interactionsKey = 'interactions_v1';

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
    final box = await _open();
    final list = _decodeList(box.get(_clientsKey), CrmClient.tryParse);
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
    final box = await _open();
    final list = _decodeList(box.get(_dealsKey), CrmDeal.tryParse);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<List<CrmInteraction>> interactionsRaw() async {
    final box = await _open();
    final list =
        _decodeList(box.get(_interactionsKey), CrmInteraction.tryParse);
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

  static Future<void> _write<T>(
    String key,
    List<T> values,
    Map<String, dynamic> Function(T) encode,
  ) async {
    final box = await _open();
    await box.put(key, jsonEncode([for (final value in values) encode(value)]));
    revision.value++;
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
    if (index < 0) {
      all.add(normalized);
    } else {
      all[index] = normalized;
    }
    await _write(_clientsKey, all, (value) => value.toJson());
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
    all[index] = before.copyWith(
      status: CrmClientStatus.archived,
      clearNextContact: true,
      updatedAt: DateTime.now(),
    );
    await _write(_clientsKey, all, (value) => value.toJson());
  }

  static Future<void> deleteClient(String id) async {
    final allClients = await clientsRaw();
    final target = allClients.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    await _requireOrgWrite(target.organizationId);
    if (!_clientOwnedByCurrent(target)) {
      throw StateError('CRM client belongs to another employee');
    }
    final allDeals = await dealsRaw();
    final allInteractions = await interactionsRaw();
    await _write(
      _clientsKey,
      allClients.where((value) => value.id != id).toList(),
      (value) => value.toJson(),
    );
    await _write(
      _dealsKey,
      allDeals.where((value) => value.clientId != id).toList(),
      (value) => value.toJson(),
    );
    await _write(
      _interactionsKey,
      allInteractions.where((value) => value.clientId != id).toList(),
      (value) => value.toJson(),
    );
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
    if (index < 0) {
      all.add(next);
    } else {
      all[index] = next;
    }
    await _write(_dealsKey, all, (value) => value.toJson());
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
    final allInteractions = await interactionsRaw();
    await _write(
      _dealsKey,
      all.where((value) => value.id != id).toList(),
      (value) => value.toJson(),
    );
    await _write(
      _interactionsKey,
      allInteractions.where((value) => value.dealId != id).toList(),
      (value) => value.toJson(),
    );
  }

  static Future<void> saveInteraction(CrmInteraction interaction) async {
    final clients = {for (final c in await clientsRaw()) c.id: c};
    final client = clients[interaction.clientId];
    if (client == null) throw StateError('CRM client does not exist');
    await _requireOrgWrite(client.organizationId);
    if (!_clientOwnedByCurrent(client)) {
      final deals = {for (final d in await dealsRaw()) d.id: d};
      final linked = interaction.dealId == null ? null : deals[interaction.dealId!];
      if (linked == null || !_dealOwnedByCurrent(linked, clients)) {
        throw StateError('CRM interaction parent is outside employee scope');
      }
    }

    final all = await interactionsRaw();
    final index = all.indexWhere((value) => value.id == interaction.id);
    if (index < 0) {
      all.add(interaction);
    } else {
      all[index] = interaction;
    }
    await _write(_interactionsKey, all, (value) => value.toJson());

    if (interaction.nextActionAt != null) {
      final allClients = await clientsRaw();
      final clientIndex =
          allClients.indexWhere((value) => value.id == interaction.clientId);
      if (clientIndex >= 0) {
        allClients[clientIndex] = allClients[clientIndex].copyWith(
          nextContactAt: interaction.nextActionAt,
          updatedAt: DateTime.now(),
        );
        await _write(_clientsKey, allClients, (value) => value.toJson());
      }
    }
  }

  static Future<void> deleteInteraction(String id) async {
    final all = await interactionsRaw();
    final target = all.where((value) => value.id == id).firstOrNull;
    if (target == null) return;
    final clients = {for (final c in await clientsRaw()) c.id: c};
    final client = clients[target.clientId];
    if (client == null) return;
    await _requireOrgWrite(client.organizationId);
    if (!_clientOwnedByCurrent(client)) {
      final deals = {for (final d in await dealsRaw()) d.id: d};
      final linked = target.dealId == null ? null : deals[target.dealId!];
      if (linked == null || !_dealOwnedByCurrent(linked, clients)) {
        throw StateError('CRM interaction is outside employee scope');
      }
    }
    await _write(
      _interactionsKey,
      all.where((value) => value.id != id).toList(),
      (value) => value.toJson(),
    );
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
    final box = await _open();
    await box.clear();
    revision.value++;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
