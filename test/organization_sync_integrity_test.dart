import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';

void main() {
  test('legacy account and transaction sync records become physical Wesi Beats records', () {
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
    expect(account!.organizationId, OrganizationModel.wesiBeatsId);

    final tx = TransactionsSync().decode({
      'id': 'legacy-tx',
      'title': 'Legacy',
      'amount': 100,
      'type': 'income',
      'date': DateTime(2026, 1, 2).toIso8601String(),
    });
    expect(tx, isNotNull);
    expect(tx!.organizationId, OrganizationModel.wesiBeatsId);
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
}
