import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/services/team_skill_service.dart';
import 'package:wesios/features/team/services/team_workload_service.dart';

void main() {
  final now = DateTime(2026, 8, 13, 12);

  EmployeeModel employee({
    String id = 'e1',
    List<String> skills = const [],
    double capacity = 10,
    double min = .65,
    double max = 1.10,
    String? managerId,
    String alertTarget = 'manager',
    bool owner = false,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        createdAt: DateTime(2026, 1, 1),
        skills: skills,
        weeklyCapacityPoints: capacity,
        workloadMinRatio: min,
        workloadMaxRatio: max,
        managerEmployeeId: managerId,
        workloadAlertTarget: alertTarget,
        isOwner: owner,
      );

  TaskModel task({
    required String id,
    required String employeeId,
    TaskStatus status = TaskStatus.inProgress,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
  }) =>
      TaskModel(
        id: id,
        title: id,
        createdAt: now.subtract(const Duration(days: 1)),
        status: status,
        priority: priority,
        dueDate: dueDate,
        organizationId: 'org',
        responsibleEmployeeId: employeeId,
        assignee: employeeId,
      );

  test('explicit skill can qualify employee for a matching task', () {
    final designer = employee(skills: const ['Графический дизайн', 'Motion design']);
    final score = TeamSkillService.fitForTask(
      designer,
      roleAliases: const ['designer', 'дизайнер', 'motion'],
      taskKeywords: const ['обложка', 'preview'],
    );
    expect(score, greaterThan(.8));
  });

  test('unrelated skills do not create false role fit', () {
    final finance = employee(skills: const ['Финансы', 'Аналитика']);
    final score = TeamSkillService.fitForTask(
      finance,
      roleAliases: const ['битмейкер', 'producer'],
      taskKeywords: const ['бит', 'instrumental'],
    );
    expect(score, 0);
  });

  test('workload becomes overloaded above personal capacity', () {
    final person = employee(capacity: 5, max: 1.05);
    final tasks = List.generate(
      5,
      (i) => task(
        id: 'heavy_$i',
        employeeId: person.id,
        priority: TaskPriority.high,
      ),
    );
    final snapshot = TeamWorkloadService.calculate(person, tasks, now: now);
    expect(snapshot.overloaded, isTrue);
    expect(snapshot.ratio, greaterThan(1));
  });

  test('low task pressure is marked as underload', () {
    final person = employee(capacity: 12, min: .65);
    final snapshot = TeamWorkloadService.calculate(
      person,
      [task(id: 'small', employeeId: person.id, status: TaskStatus.backlog)],
      now: now,
    );
    expect(snapshot.underloaded, isTrue);
  });

  test('manager and CEO routing follows employee settings', () {
    final ceo = employee(id: 'ceo', owner: true);
    final manager = employee(id: 'manager');
    final worker = employee(
      id: 'worker',
      capacity: 4,
      managerId: manager.id,
      alertTarget: 'both',
    );
    final tasks = List.generate(
      5,
      (i) => task(
        id: 'urgent_$i',
        employeeId: worker.id,
        priority: TaskPriority.urgent,
      ),
    );
    final employees = [ceo, manager, worker];
    expect(
      TeamWorkloadService.alertsForViewer(
        viewer: manager,
        employees: employees,
        tasks: tasks,
        now: now,
      ),
      isNotEmpty,
    );
    expect(
      TeamWorkloadService.alertsForViewer(
        viewer: ceo,
        employees: employees,
        tasks: tasks,
        now: now,
      ),
      isNotEmpty,
    );
  });
}
