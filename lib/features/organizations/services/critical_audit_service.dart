import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../team/services/team_service.dart';
import '../models/organization_model.dart';

/// Immutable append-only audit events for critical organization/security/
/// finance mutations that are broader than a single Treasury transaction.
class CriticalAuditService {
  CriticalAuditService._();

  static const String boxName = 'wesios_critical_audit';

  static Future<Box<String>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  static Future<void> record({
    required String event,
    required String entityType,
    required String entityId,
    String? organizationId,
    Object? before,
    Object? after,
    String? reason,
    String? actorId,
    String source = 'app',
  }) async {
    final now = DateTime.now();
    final actor = actorId ?? TeamService.current?.id ?? 'system';
    final payload = <String, dynamic>{
      'id': 'critical_audit_${now.microsecondsSinceEpoch}',
      'event': event,
      'entityType': entityType,
      'entityId': entityId,
      'organizationId': organizationId ?? OrganizationModel.rootId,
      'actorId': actor,
      'timestamp': now.toIso8601String(),
      'source': source,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (before != null) 'before': before,
      if (after != null) 'after': after,
    };
    final id = payload['id'] as String;
    await (await _open()).put(id, jsonEncode(payload));
  }

  static Future<List<Map<String, dynamic>>> all({String? entityId}) async {
    final rows = <Map<String, dynamic>>[];
    for (final raw in (await _open()).values) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final row = Map<String, dynamic>.from(decoded);
        if (entityId != null && row['entityId'] != entityId) continue;
        rows.add(row);
      } catch (_) {}
    }
    rows.sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));
    return rows;
  }

  static Future<void> clearForTest() async => (await _open()).clear();
}
