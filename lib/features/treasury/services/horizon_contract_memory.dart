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

class HorizonContractOutcome {
  final String id;
  final String beatId;
  final String artistKey;
  final DateTime closedAt;
  final double amountRub;
  final bool renewed;

  const HorizonContractOutcome({
    required this.id,
    required this.beatId,
    required this.artistKey,
    required this.closedAt,
    required this.amountRub,
    required this.renewed,
  });

  HorizonContractOutcome copyWith({bool? renewed}) => HorizonContractOutcome(
        id: id,
        beatId: beatId,
        artistKey: artistKey,
        closedAt: closedAt,
        amountRub: amountRub,
        renewed: renewed ?? this.renewed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'beatId': beatId,
        'artistKey': artistKey,
        'closedAt': closedAt.toIso8601String(),
        'amountRub': amountRub,
        'renewed': renewed,
      };

  factory HorizonContractOutcome.fromJson(Map<String, dynamic> json) =>
      HorizonContractOutcome(
        id: '${json['id'] ?? ''}',
        beatId: '${json['beatId'] ?? ''}',
        artistKey: '${json['artistKey'] ?? ''}',
        closedAt: DateTime.tryParse('${json['closedAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        amountRub: (json['amountRub'] as num?)?.toDouble() ?? 0,
        renewed: json['renewed'] == true,
      );
}

/// Domain memory for Audio Vault contracts without changing BeatLease.
/// Active assumptions and realized outcomes are kept separately: the first is
/// editable forecasting metadata; the second is evidence used to learn future
/// renewal probabilities.
class HorizonContractMemoryService {
  HorizonContractMemoryService._();

  static const String boxName = 'wesios_horizon_contracts';
  static const String _key = 'contracts_v1';
  static const String _outcomesKey = 'contract_outcomes_v1';

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static String normalizeArtist(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

  static Future<List<HorizonContractOutcome>> outcomes() async {
    try {
      final raw = (await _open()).get(_outcomesKey);
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final value in decoded)
          if (value is Map)
            HorizonContractOutcome.fromJson(
              Map<String, dynamic>.from(value),
            ),
      ];
    } catch (_) {
      return const [];
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

  static Future<void> recordClosedLease({
    required String beatId,
    required String leaseId,
    required String artistName,
    required DateTime closedAt,
    required double amountRub,
  }) async {
    final history = await outcomes();
    if (history.any((e) => e.id == leaseId)) return;
    history.add(HorizonContractOutcome(
      id: leaseId,
      beatId: beatId,
      artistKey: normalizeArtist(artistName),
      closedAt: closedAt,
      amountRub: amountRub,
      renewed: false,
    ));
    if (history.length > 250) history.removeRange(0, history.length - 250);
    await _saveOutcomes(history);
  }

  /// A new lease shortly after a previous close for the same beat or artist is
  /// evidence of renewal. We only change the most recent plausible outcome.
  static Future<void> markRenewalIfApplicable({
    required String beatId,
    required String artistName,
    required DateTime startedAt,
  }) async {
    final history = await outcomes();
    final artist = normalizeArtist(artistName);
    var bestIndex = -1;
    var bestDistance = 181;
    for (var i = 0; i < history.length; i++) {
      final outcome = history[i];
      if (outcome.renewed) continue;
      if (outcome.beatId != beatId &&
          (artist.isEmpty || outcome.artistKey != artist)) continue;
      final distance = startedAt.difference(outcome.closedAt).inDays;
      if (distance < 0 || distance > 180) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) return;
    history[bestIndex] = history[bestIndex].copyWith(renewed: true);
    await _saveOutcomes(history);
  }

  /// Beta-smoothed empirical renewal probability. Exact beat history is given
  /// double weight, artist history one weight. With no evidence the prior is
  /// 35%, but it is no longer a permanent magic constant.
  static Future<double> learnedRenewalProbability({
    required String beatId,
    required String artistName,
  }) async {
    final history = await outcomes();
    final artist = normalizeArtist(artistName);
    var successes = 3.5;
    var trials = 10.0; // prior mean 35%
    for (final outcome in history) {
      final exactBeat = outcome.beatId == beatId;
      final sameArtist = artist.isNotEmpty && outcome.artistKey == artist;
      if (!exactBeat && !sameArtist) continue;
      final weight = exactBeat ? 2.0 : 1.0;
      trials += weight;
      if (outcome.renewed) successes += weight;
    }
    return (successes / trials).clamp(0.05, 0.95).toDouble();
  }

  static Future<void> _saveOutcomes(List<HorizonContractOutcome> history) async {
    await (await _open()).put(
      _outcomesKey,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}
