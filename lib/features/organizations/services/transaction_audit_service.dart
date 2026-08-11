import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../team/services/team_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import '../models/transaction_audit_model.dart';
import 'organization_access_service.dart';

class TransactionAuditService {
  TransactionAuditService._();

  static const String boxName = 'wesios_transaction_audit';
  static Box<TransactionAuditModel>? _box;

  static Future<Box<TransactionAuditModel>> _open() async {
    _box ??= await Hive.openBox<TransactionAuditModel>(boxName);
    return _box!;
  }

  static Future<void> record({
    required String transactionId,
    TransactionModel? before,
    TransactionModel? after,
    String? reason,
    String? changedBy,
  }) async {
    final now = DateTime.now();
    final orgId =
        (after ?? before)?.effectiveOrganizationId ?? OrganizationModel.rootId;
    final entry = TransactionAuditModel(
      id: 'audit_${now.microsecondsSinceEpoch}',
      transactionId: transactionId,
      changedBy: changedBy ?? TeamService.current?.id ?? 'system',
      changedAt: now,
      beforeJson: before == null ? null : jsonEncode(before.toJson()),
      afterJson: after == null ? null : jsonEncode(after.toJson()),
      reason: reason,
      organizationId: orgId,
    );
    await (await _open()).put(entry.id, entry);
  }

  static Future<List<TransactionAuditModel>> forTransaction(String id) async {
    final box = await _open();
    final list = box.values.where((a) => a.transactionId == id).toList();
    if (TeamService.current != null) {
      final allowed = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewFinance,
      );
      list.removeWhere((a) => !allowed.contains(a.organizationId));
    }
    list.sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return list;
  }

  static Future<List<TransactionAuditModel>> forOrganizations(
    Set<String> organizationIds,
  ) async {
    var ids = organizationIds;
    if (TeamService.current != null) {
      ids = ids.intersection(
        await OrganizationAccessService.organizationIdsFor(
          OrganizationPermissions.viewFinance,
        ),
      );
    }
    final list = (await _open())
        .values
        .where((a) => ids.contains(a.organizationId))
        .toList()
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return list;
  }
}
