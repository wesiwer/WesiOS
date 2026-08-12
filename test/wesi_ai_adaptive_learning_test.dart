import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/ai/models/ai_learning_profile.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/ai/services/task_template_catalog.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_adaptive_policy.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_task_engine.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';

void main() {
  final now = DateTime(2026, 8, 12, 12);

  EmployeeModel employee(String id, String position) => EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        position: position,
        createdAt: DateTime(2026, 1, 1),
      );

  TaskModel task({
    required String id,
    required String title,
    required String employeeId,
    required DateTime createdAt,
    TaskStatus status = TaskStatus.done,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
    List<String> tags = const [],
  }) =>
      TaskModel(
        id: id,
        title: title,
        createdAt: createdAt,
        status: status,
        priority: priority,
        dueDate: dueDate,
        organizationId: 'org_wesi_beats',
        responsibleEmployeeId: employeeId,
        assignee: employeeId,
        tags: tags,
      );

  WesiAiAnalysisInput input({
    required List<TaskModel> tasks,
    required List<EmployeeModel> employees,
    AiBusinessSignal signal = const AiBusinessSignal(),
    AiLearningProfile learning = const AiLearningProfile(),
  }) =>
      WesiAiAnalysisInput(
        tasks: tasks,
        employees: employees,
        eligibleEmployeeIds: employees.map((e) => e.id).toSet(),
        organizationId: 'org_wesi_beats',
        organizationName: 'Wesi Beats',
        organizationDescription: 'Продажа битов артистам',
        currentEmployeeId: employees.first.id,
        canAssignToOthers: true,
        businessSignal: signal,
        learningProfile: learning,
        now: now,
      );

  AiTaskTemplate template(String id) =>
      WesiAiTaskCatalog.all.firstWhere((item) => item.id == id);

  test('learns recurring organization cadence without becoming too aggressive', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    final history = [
      task(
        id: 'b1',
        title: 'Сделать новый бит',
        employeeId: beatmaker.id,
        createdAt: now.subtract(const Duration(days: 16)),
      ),
      task(
        id: 'b2',
        title: 'Сделать новый бит',
        employeeId: beatmaker.id,
        createdAt: now.subtract(const Duration(days: 12)),
      ),
      task(
        id: 'b3',
        title: 'Сделать новый бит',
        employeeId: beatmaker.id,
        createdAt: now.subtract(const Duration(days: 8)),
      ),
      task(
        id: 'b4',
        title: 'Сделать новый бит',
        employeeId: beatmaker.id,
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ];

    final cadence = WesiAiAdaptivePolicy.cadenceFor(
      template('beat_create'),
      history,
      now,
    );

    expect(cadence.learned, isTrue);
    expect(cadence.learnedMedianDays, 4);
    expect(cadence.effectiveDays, greaterThanOrEqualTo(4));
    expect(cadence.effectiveDays, lessThanOrEqualTo(6));
  });

  test('repeated rejection suppresses routine suggestion noise', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    const learning = AiLearningProfile(
      templates: {
        'beat_create': AiTemplateLearning(rejected: 4),
      },
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 'old',
          title: 'Сделать новый бит',
          employeeId: beatmaker.id,
          createdAt: now.subtract(const Duration(days: 12)),
        ),
      ],
      employees: [beatmaker],
      learning: learning,
    ));

    expect(result.where((item) => item.templateId == 'beat_create'), isEmpty);
  });

  test('accepted priority correction influences future proposals', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    const learning = AiLearningProfile(
      templates: {
        'beat_create': AiTemplateLearning(
          accepted: 2,
          averagePriorityDelta: -1,
        ),
      },
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 'old',
          title: 'Сделать новый бит',
          employeeId: beatmaker.id,
          createdAt: now.subtract(const Duration(days: 18)),
        ),
      ],
      employees: [beatmaker],
      learning: learning,
    ));
    final beat = result.firstWhere((item) => item.templateId == 'beat_create');

    expect(beat.priority.index, lessThan(TaskPriority.high.index));
  });

  test('historical work can qualify an employee even with a generic title', () {
    final specialist = employee('specialist', 'Специалист');
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: -100,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 's1',
          title: 'Сделать рассылку артистам',
          employeeId: specialist.id,
          createdAt: now.subtract(const Duration(days: 20)),
        ),
        task(
          id: 's2',
          title: 'Follow-up артистам после рассылки',
          employeeId: specialist.id,
          createdAt: now.subtract(const Duration(days: 12)),
        ),
      ],
      employees: [specialist],
      signal: signal,
    ));

    expect(result.any((item) => item.category == AiTaskCategory.sales), isTrue);
    expect(
      result.where((item) => item.category == AiTaskCategory.sales).first.assigneeId,
      specialist.id,
    );
  });

  test('accepted assignee preference breaks an otherwise equal tie', () {
    final first = employee('sales-a', 'Sales manager');
    final preferred = employee('sales-b', 'Sales manager');
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: -100,
    );
    const learning = AiLearningProfile(
      templates: {
        'artist_outreach_20': AiTemplateLearning(
          accepted: 4,
          acceptedAssignees: {'sales-b': 4},
        ),
      },
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: const [],
      employees: [first, preferred],
      signal: signal,
      learning: learning,
    ));
    final outreach =
        result.firstWhere((item) => item.templateId == 'artist_outreach_20');

    expect(outreach.assigneeId, preferred.id);
  });

  test('fatigue signal protects a heavily loaded producer from heavy new work', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    final recent = List.generate(
      5,
      (index) => task(
        id: 'heavy-$index',
        title: 'Сделать новый бит $index',
        employeeId: beatmaker.id,
        createdAt: now.subtract(Duration(days: index + 1)),
        status: TaskStatus.done,
        priority: TaskPriority.high,
      ),
    );
    final capacity = WesiAiAdaptivePolicy.capacityFor(
      beatmaker.id,
      recent,
      now,
    );

    expect(capacity.fatigueRisk, isTrue);

    final result = WesiAiTaskEngine.analyze(input(
      tasks: recent,
      employees: [beatmaker],
    ));
    expect(result.where((item) => item.templateId == 'beat_create'), isEmpty);
  });

  test('underutilized employee is preferred over a busier equal-role colleague', () {
    final busy = employee('sales-a', 'Sales manager');
    final free = employee('sales-b', 'Sales manager');
    final busyTasks = [
      task(
        id: 'active-1',
        title: 'Клиентская работа',
        employeeId: busy.id,
        createdAt: now.subtract(const Duration(days: 1)),
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
      ),
      task(
        id: 'active-2',
        title: 'Подготовить оффер',
        employeeId: busy.id,
        createdAt: now.subtract(const Duration(days: 2)),
        status: TaskStatus.inProgress,
        priority: TaskPriority.normal,
      ),
    ];
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: -100,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: busyTasks,
      employees: [busy, free],
      signal: signal,
    ));

    final sales = result.firstWhere((item) => item.category == AiTaskCategory.sales);
    expect(sales.assigneeId, free.id);
  });
}
