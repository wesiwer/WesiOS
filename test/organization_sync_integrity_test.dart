import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';

void main() {
  test('legacy account and transaction sync records become physical Wesi Inc records', () {
    final account = AccountsSync().decode({
      'id': 'legacy-main',
      'name': 'Legacy',
      'kind': 'cash',
      'openingBalance': 0,
      'colorValue': 0,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'archived': false,
      'currency': 'RUB',
    });
    expect(account, isNotNull);
    expect(account!.organizationId, OrganizationModel.rootId);

    final tx = TransactionsSync().decode({
      'id': 'legacy-tx',
      'title': 'Legacy',
      'amount': 100,
      'type': 'income',
      'date': DateTime(2026, 1, 2).toIso8601String(),
    });
    expect(tx, isNotNull);
    expect(tx!.organizationId, OrganizationModel.rootId);
  });

  test('task sync recovers stable ownership from compatibility tags', () {
    final task = TasksSync().decode({
      'id': 'task-1',
      'title': 'Cash task',
      'status': 'backlog',
      'priority': 'normal',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'tags': [
        '${TaskModel.organizationTagPrefix}org-studio-a',
        '${TaskModel.employeeTagPrefix}employee-a',
      ],
      'subtasks': const [],
      'order': 0,
    });
    expect(task, isNotNull);
    expect(task!.organizationId, 'org-studio-a');
    expect(task.responsibleEmployeeId, 'employee-a');
  });

  test('sync gateway keeps structural ancestors out of business data scope', () {
    final context = File('server/pb_hooks/wesi_sync_context.pb.js').readAsStringSync();
    final read = File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();

    expect(context, contains('const structuralOrgIds = {};'));
    expect(context, contains('"structuralOrgIds": structuralOrgIds'));
    expect(
      context,
      isNot(contains('allowedOrgIds[cursor] = true;')),
      reason: 'Ancestor organizations must not be promoted into the business-data scope.',
    );
    expect(
      read,
      contains('ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true'),
      reason: 'Organization metadata may include ancestors needed to render the hierarchy.',
    );
    expect(
      read,
      contains('ctx.allowedOrgIds[orgId] === true && taskOwned(p)'),
      reason: 'Task visibility must stay on the strict data scope.',
    );
    expect(
      read,
      contains('const allowedOrg = (row) => ctx.allowedOrgIds['),
      reason: 'Legacy CRM visibility must stay on the strict data scope.',
    );
  });

  test('stats visibility cannot widen task, CRM, or audit permissions', () {
    final read = File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();
    final write = File('server/pb_hooks/wesi_sync_write.pb.js').readAsStringSync();
    final policy =
        File('server/pb_hooks/wesi_sync_generic_policy.js').readAsStringSync();
    final crm =
        File('server/pb_hooks/wesi_sync_crm_runtime.js').readAsStringSync();

    expect(
      read,
      contains('"demoStats": (self || ctx.canSeeOthersStats)'),
      reason: 'canSeeOthersStats remains valid only for employee indicators.',
    );
    expect(
      read,
      isNot(contains('ctx.canAssignTasks || ctx.canSeeOthersStats')),
      reason: 'Viewing other employee indicators must not expose their tasks.',
    );
    expect(
      write,
      isNot(contains('ctx.canAssignTasks || ctx.canSeeOthersStats')),
      reason: 'Viewing other employee indicators must not allow editing their tasks.',
    );
    expect(
      policy,
      contains('ctx.isOwner || ctx.canManageTeam || ctx.canAssignTasks'),
      reason: 'Task write scope may widen only for actual task/team managers.',
    );
    expect(policy, isNot(contains('canSeeOthersStats')),
        reason: 'Stats permission must never participate in transaction-time writes.');
    expect(
      crm,
      contains('return ctx.isOwner || ctx.canManageTeam === true;'),
      reason: 'Dedicated CRM scope widens only for explicit team management.',
    );
    expect(crm, isNot(contains('ctx.canSeeOthersStats === true')),
        reason: 'Stats permission must not expose or make the whole CRM writable.');
    expect(
      read,
      contains('collection === "critical_audit" && !ctx.isOwner && !ctx.canManageTeam'),
      reason: 'Critical audit visibility must require an actual management permission.',
    );
  });
}