import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/ai/services/task_template_catalog.dart';
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
    bool canAssignToOthers = true,
    String? currentEmployeeId,
  }) =>
      WesiAiAnalysisInput(
        tasks: tasks,
        employees: employees,
        eligibleEmployeeIds: employees.map((e) => e.id).toSet(),
        organizationId: 'org_wesi_beats',
        organizationName: 'Wesi Beats',
        organizationDescription: 'Продажа битов артистам',
        currentEmployeeId: currentEmployeeId ?? employees.first.id,
        canAssignToOthers: canAssignToOthers,
        businessSignal: signal,
        now: now,
      );

  test('catalog is broad enough to cover multiple business areas', () {
    expect(WesiAiTaskCatalog.all.length, greaterThanOrEqualTo(25));
    expect(
      WesiAiTaskCatalog.all.map((e) => e.category).toSet().length,
      greaterThanOrEqualTo(8),
    );
  });

  test('long beat gap becomes high priority but keeps low forecast impact', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 'old-beat',
          title: 'Сделать бит',
          employeeId: beatmaker.id,
          createdAt: now.subtract(const Duration(days: 20)),
        ),
      ],
      employees: [beatmaker],
    ));
    final suggestion =
        result.firstWhere((item) => item.templateId == 'beat_create');
    expect(suggestion.priority.index, greaterThanOrEqualTo(TaskPriority.high.index));
    expect(suggestion.forecastImpact, AiForecastImpact.low);
  });

  test('sole beatmaker is not pushed into daily beat production', () {
    final beatmaker = employee('beatmaker', 'Beatmaker');
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 'fresh-beat',
          title: 'New beat instrumental',
          employeeId: beatmaker.id,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      employees: [beatmaker],
    ));
    expect(result.where((item) => item.templateId == 'beat_create'), isEmpty);
  });

  test('completed beat can trigger designer preview chain', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    final designer = employee('designer', 'Дизайнер');
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [
        task(
          id: 'done-beat',
          title: 'Сделать новый бит',
          employeeId: beatmaker.id,
          createdAt: now.subtract(const Duration(days: 2)),
        ),
      ],
      employees: [beatmaker, designer],
    ));
    final preview =
        result.firstWhere((item) => item.templateId == 'beat_preview');
    expect(preview.assigneeId, designer.id);
    expect(preview.sourceTaskId, 'done-beat');
    expect(preview.priority.index, greaterThanOrEqualTo(TaskPriority.high.index));
  });

  test('zero income creates high-impact sales action', () {
    final sales = employee('sales', 'Менеджер по рассылкам артистам');
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      previousIncome: 10000,
      recentNet: -5000,
      incomeGrowth: -1,
      forecastTrendPerDay: -100,
      maximumCashRisk: .35,
      forecastInsufficient: false,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: const [],
      employees: [sales],
      signal: signal,
    ));
    final outreach =
        result.firstWhere((item) => item.templateId == 'artist_outreach_20');
    expect(outreach.forecastImpact.index,
        greaterThanOrEqualTo(AiForecastImpact.high.index));
    expect(outreach.priority.index,
        greaterThanOrEqualTo(TaskPriority.high.index));
  });

  test('least loaded suitable employee is preferred', () {
    final overloaded = employee('sales-a', 'Sales manager');
    final free = employee('sales-b', 'Sales manager');
    final active = List.generate(
      4,
      (i) => task(
        id: 'active-$i',
        title: 'Клиентская работа $i',
        employeeId: overloaded.id,
        createdAt: now.subtract(Duration(days: i + 1)),
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
      ),
    );
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: 0,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: active,
      employees: [overloaded, free],
      signal: signal,
    ));
    final salesSuggestion =
        result.firstWhere((item) => item.category == AiTaskCategory.sales);
    expect(salesSuggestion.assigneeId, free.id);
  });

  test('heavily overdue employee is not selected just to raise activity', () {
    final struggling = employee('sales-a', 'Sales manager');
    final available = employee('sales-b', 'Sales manager');
    final overdue = List.generate(
      4,
      (i) => task(
        id: 'overdue-$i',
        title: 'Продажи $i',
        employeeId: struggling.id,
        createdAt: now.subtract(Duration(days: 20 + i)),
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        dueDate: DateTime(2000, 1, 1),
      ),
    );
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: -1,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: overdue,
      employees: [struggling, available],
      signal: signal,
    ));
    expect(
      result.where((item) => item.category == AiTaskCategory.sales).every(
            (item) => item.assigneeId == available.id,
          ),
      isTrue,
    );
  });

  test('open equivalent task suppresses duplicate suggestion', () {
    final beatmaker = employee('beatmaker', 'Битмейкер');
    final open = task(
      id: 'open-beat',
      title: 'Сделать новый бит',
      employeeId: beatmaker.id,
      createdAt: now.subtract(const Duration(days: 20)),
      status: TaskStatus.inProgress,
      tags: const ['wesi-ai:template:beat_create'],
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: [open],
      employees: [beatmaker],
    ));
    expect(result.where((item) => item.templateId == 'beat_create'), isEmpty);
  });

  test('no permission to assign others never proposes another employee', () {
    final current = employee('beatmaker', 'Битмейкер');
    final sales = employee('sales', 'Sales manager');
    const signal = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      recentNet: -1,
    );
    final result = WesiAiTaskEngine.analyze(input(
      tasks: const [],
      employees: [current, sales],
      signal: signal,
      canAssignToOthers: false,
      currentEmployeeId: current.id,
    ));
    expect(result.any((item) => item.assigneeId == sales.id), isFalse);
  });
}
