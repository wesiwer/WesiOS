import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../tasks/models/task_model.dart';
import '../../team/services/team_service.dart';
import '../../treasury/models/account_model.dart';
import '../../treasury/models/transaction_model.dart';
import '../models/organization_model.dart';
import 'organization_access_service.dart';
import 'organization_context.dart';
import 'organization_service.dart';

class OrganizationMigrationService {
  OrganizationMigrationService._();

  static const String logBoxName = 'wesios_org_migration_log';
  static const String migrationKey = 'org_hierarchy_v1';
  static const String accountBoxName = 'wesios_accounts';
  static const String treasuryBoxName = 'wesios_treasury';
  static const String taskBoxName = 'wesios_tasks';
  static const String crmBoxName = 'wesios_crm';

  /// Existing WesiOS data predates the organization tree and belongs to the
  /// root operating contour, Wesi Inc. Wesi Beats is created as an empty child
  /// and receives data only when the user explicitly creates/moves data there.
  ///
  /// Legacy organization grants are created only during this migration. They
  /// must never be recreated on every launch because an explicit revoke is a
  /// durable security decision.
  static Future<void> runV1() async {
    await OrganizationService.ensureBaseline(createdBy: 'migration:v1');
    final log = await Hive.openBox<dynamic>(logBoxName);
    final completed = log.get(migrationKey) is Map &&
        (log.get(migrationKey) as Map)['completed'] == true;

    var accountsUpdated = 0;
    var transactionsUpdated = 0;
    var tasksUpdated = 0;
    var crmClientsUpdated = 0;
    var crmDealsUpdated = 0;

    if (!completed) {
      final accounts = await Hive.openBox<AccountModel>(accountBoxName);
      for (final key in accounts.keys.toList()) {
        final account = accounts.get(key);
        if (account == null || account.organizationId != null) continue;
        await accounts.put(
          key,
          account.copyWith(organizationId: OrganizationModel.rootId),
        );
        accountsUpdated++;
      }

      final treasury = await Hive.openBox<TransactionModel>(treasuryBoxName);
      for (final key in treasury.keys.toList()) {
        final tx = treasury.get(key);
        if (tx == null || tx.organizationId != null) continue;
        await treasury.put(
          key,
          tx.copyWith(organizationId: OrganizationModel.rootId),
        );
        transactionsUpdated++;
      }

      final tasks = await Hive.openBox<TaskModel>(taskBoxName);
      for (final key in tasks.keys.toList()) {
        final task = tasks.get(key);
        if (task == null || task.organizationId != null) continue;
        final assigneeId = task.assignee != null &&
                TeamService.byId(task.assignee!) != null
            ? task.assignee
            : null;
        await tasks.put(
          key,
          task.copyWith(
            organizationId: OrganizationModel.rootId,
            responsibleEmployeeId: task.responsibleEmployeeId ?? assigneeId,
            tags: TaskModel.withOwnershipTags(
              task.tags,
              organizationId: OrganizationModel.rootId,
              employeeId: task.responsibleEmployeeId ?? assigneeId,
            ),
          ),
        );
        tasksUpdated++;
      }

      final crm = await Hive.openBox<dynamic>(crmBoxName);
      final clientsResult = _backfillCrmJson(
        crm.get('clients_v1'),
        responsibleKey: 'ownerEmployeeId',
      );
      if (clientsResult.changed > 0) {
        await crm.put('clients_v1', clientsResult.json);
        crmClientsUpdated = clientsResult.changed;
      }
      final dealsResult = _backfillCrmJson(
        crm.get('deals_v1'),
        responsibleKey: 'responsibleEmployeeId',
      );
      if (dealsResult.changed > 0) {
        await crm.put('deals_v1', dealsResult.json);
        crmDealsUpdated = dealsResult.changed;
      }

      // Only users that already existed when organization hierarchy is first
      // introduced receive a backward-compatible Wesi Inc grant. New employees
      // are assigned explicitly by the organization-aware Contacts flow.
      await OrganizationAccessService.ensureLegacyGrants();

      await log.put(migrationKey, <String, dynamic>{
        'completed': true,
        'completedAt': DateTime.now().toIso8601String(),
        'rootId': OrganizationModel.rootId,
        'legacyOrganizationId': OrganizationModel.rootId,
        'legacyOrganizationName': 'Wesi Inc',
        'accountsUpdated': accountsUpdated,
        'transactionsUpdated': transactionsUpdated,
        'tasksUpdated': tasksUpdated,
        'crmClientsUpdated': crmClientsUpdated,
        'crmDealsUpdated': crmDealsUpdated,
        'legacyGrantsCreatedOnce': true,
      });
    }

    await OrganizationContext.initialize();
  }

  static ({String json, int changed}) _backfillCrmJson(
    Object? raw, {
    required String responsibleKey,
  }) {
    if (raw is! String || raw.trim().isEmpty) {
      return (json: raw is String ? raw : '[]', changed: 0);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return (json: raw, changed: 0);
      var changed = 0;
      final output = <dynamic>[];
      for (final item in decoded) {
        if (item is! Map) {
          output.add(item);
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final org = '${map['organizationId'] ?? ''}'.trim();
        if (org.isEmpty) {
          map['organizationId'] = OrganizationModel.rootId;
          changed++;
        }
        // Responsibility is never guessed from a display name. Existing
        // explicit stable ids are preserved; otherwise the field remains null.
        if (!map.containsKey(responsibleKey)) map[responsibleKey] = null;
        output.add(map);
      }
      return (json: jsonEncode(output), changed: changed);
    } catch (_) {
      return (json: raw, changed: 0);
    }
  }
}
