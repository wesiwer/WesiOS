import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

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

  static Future<List<CrmClient>> clients() async {
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

  static Future<List<CrmDeal>> deals() async {
    final box = await _open();
    final list = _decodeList(box.get(_dealsKey), CrmDeal.tryParse);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<List<CrmInteraction>> interactions() async {
    final box = await _open();
    final list =
        _decodeList(box.get(_interactionsKey), CrmInteraction.tryParse);
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

  static Future<void> _write<T>(
    String key,
    List<T> values,
    Map<String, dynamic> Function(T) encode,
  ) async {
    final box = await _open();
    await box.put(key, jsonEncode([for (final value in values) encode(value)]));
    revision.value++;
  }

  static Future<void> saveClient(CrmClient client) async {
    final all = await clients();
    final now = DateTime.now();
    final normalized = client.copyWith(updatedAt: now);
    final index = all.indexWhere((value) => value.id == client.id);
    if (index < 0) {
      all.add(normalized);
    } else {
      all[index] = normalized;
    }
    await _write(_clientsKey, all, (value) => value.toJson());
  }

  static Future<void> archiveClient(String id) async {
    final all = await clients();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    all[index] = all[index].copyWith(
      status: CrmClientStatus.archived,
      clearNextContact: true,
      updatedAt: DateTime.now(),
    );
    await _write(_clientsKey, all, (value) => value.toJson());
  }

  static Future<void> deleteClient(String id) async {
    final allClients = await clients();
    final allDeals = await deals();
    final allInteractions = await interactions();
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
    final all = await deals();
    final now = DateTime.now();
    var next = deal.copyWith(updatedAt: now);
    if (next.stage == DealStage.won || next.stage == DealStage.lost) {
      next = next.copyWith(closedAt: next.closedAt ?? now);
    } else if (next.closedAt != null) {
      next = next.copyWith(clearClosedAt: true);
    }
    final index = all.indexWhere((value) => value.id == deal.id);
    if (index < 0) {
      all.add(next);
    } else {
      all[index] = next;
    }
    await _write(_dealsKey, all, (value) => value.toJson());
  }

  static Future<void> moveDeal(String id, DealStage stage) async {
    final all = await deals();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    await saveDeal(all[index].copyWith(stage: stage));
  }

  static Future<void> deleteDeal(String id) async {
    final all = await deals();
    final allInteractions = await interactions();
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
    final all = await interactions();
    final index = all.indexWhere((value) => value.id == interaction.id);
    if (index < 0) {
      all.add(interaction);
    } else {
      all[index] = interaction;
    }
    await _write(_interactionsKey, all, (value) => value.toJson());

    if (interaction.nextActionAt != null) {
      final allClients = await clients();
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
    final all = await interactions();
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
    final box = await _open();
    await box.clear();
    revision.value++;
  }
}