import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class HorizonContractMemory {
  final String beatId;
  final String leaseId;
  final double renewalProbability;
  final double renewalAmountRub;
  final double expectedRoyaltyRub;
  final DateTime? royaltyDueAt;
  final double royaltyProbability;
  final DateTime updatedAt;

  const HorizonContractMemory({
    required this.beatId,
    required this.leaseId,
    this.renewalProbability = 0.35,
    this.renewalAmountRub = 0,
    this.expectedRoyaltyRub = 0,
    this.royaltyDueAt,
    this.royaltyProbability = 0.65,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'beatId': beatId,
        'leaseId': leaseId,
        'renewalProbability': renewalProbability,
        'renewalAmountRub': renewalAmountRub,
        'expectedRoyaltyRub': expectedRoyaltyRub,
        'royaltyDueAt': royaltyDueAt?.toIso8601String(),
        'royaltyProbability': royaltyProbability,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory HorizonContractMemory.fromJson(Map<String, dynamic> json) =>
      HorizonContractMemory(
        beatId: '${json['beatId'] ?? ''}',
        leaseId: '${json['leaseId'] ?? ''}',
        renewalProbability:
            ((json['renewalProbability'] as num?)?.toDouble() ?? 0.35)
                .clamp(0, 1)
                .toDouble(),
        renewalAmountRub:
            (json['renewalAmountRub'] as num?)?.toDouble() ?? 0,
        expectedRoyaltyRub:
            (json['expectedRoyaltyRub'] as num?)?.toDouble() ?? 0,
        royaltyDueAt:
            DateTime.tryParse('${json['royaltyDueAt'] ?? ''}'),
        royaltyProbability:
            ((json['royaltyProbability'] as num?)?.toDouble() ?? 0.65)
                .clamp(0, 1)
                .toDouble(),
        updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Domain memory for Audio Vault contracts without changing the existing
/// BeatLease serialization. This lets old installations read the same beats,
/// while Horizon can learn expected renewals/royalties as uncertain cash.
class HorizonContractMemoryService {
  HorizonContractMemoryService._();

  static const String boxName = 'wesios_horizon_contracts';
  static const String _key = 'contracts_v1';

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<Map<String, HorizonContractMemory>> all() async {
    try {
      final raw = (await _open()).get(_key);
      if (raw is! String || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, HorizonContractMemory>{};
      for (final value in decoded.values) {
        if (value is! Map) continue;
        final memory = HorizonContractMemory.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (memory.leaseId.isNotEmpty) result[memory.leaseId] = memory;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<HorizonContractMemory?> byLease(String leaseId) async =>
      (await all())[leaseId];

  static Future<void> save(HorizonContractMemory memory) async {
    final map = await all();
    map[memory.leaseId] = memory;
    await (await _open()).put(
      _key,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  static Future<void> removeLease(String leaseId) async {
    final map = await all();
    if (map.remove(leaseId) == null) return;
    await (await _open()).put(
      _key,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}
