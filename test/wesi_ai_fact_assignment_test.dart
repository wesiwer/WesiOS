import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/files/models/file_share_models.dart';
import 'package:wesios/features/tasks/ai/models/ai_learning_profile.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_fact_finder.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_strategy_planner.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_task_engine.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';

/// Назначение задач: кому именно система предлагает работу и почему.
///
/// Раньше движок знал только два источника — список задач и денежные итоги.
/// Всё остальное в приложении (клиенты, сделки, вехи, биты, лицензии) он не
/// видел, поэтому предлагал типовые формулировки вроде «сделать превью для
/// готового бита», не зная ни одного бита по имени. Здесь проверяется, что
/// теперь предложение указывает на существующий объект и достаётся тому, за
/// кем этот объект закреплён.
void main() {
  final now = DateTime(2026, 8, 13, 12);

  EmployeeModel person(
    String id, {
    String position = '',
    double capacity = 20,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        position: position,
        weeklyCapacityPoints: capacity,
        createdAt: DateTime(2026, 1, 1),
      );

  TaskModel task(
    String id, {
    String title = 'Задача',
    required String employeeId,
    TaskStatus status = TaskStatus.inProgress,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
    DateTime? createdAt,
    List<String> tags = const [],
  }) =>
      TaskModel(
        id: id,
        title: title,
        status: status,
        priority: priority,
        dueDate: dueDate,
        createdAt: createdAt ?? now.subtract(const Duration(days: 1)),
        organizationId: 'org_wesi_beats',
        responsibleEmployeeId: employeeId,
        assignee: employeeId,
        tags: tags,
      );

  CrmClient client(String id, String name, {String? owner}) => CrmClient(
        id: id,
        name: name,
        status: CrmClientStatus.active,
        ownerEmployeeId: owner,
        createdAt: now.subtract(const Duration(days: 90)),
        updatedAt: now.subtract(const Duration(days: 30)),
      );

  CrmDeal overdueDeal(String id, {String? owner, double amount = 200000}) =>
      CrmDeal(
        id: id,
        clientId: 'c1',
        title: 'Пакет из 5 битов',
        amount: amount,
        stage: DealStage.negotiation,
        responsibleEmployeeId: owner,
        createdAt: now.subtract(const Duration(days: 40)),
        updatedAt: now.subtract(const Duration(days: 3)),
        expectedCloseAt: now.subtract(const Duration(days: 12)),
      );

  List<AiTaskSuggestion> analyze({
    required List<EmployeeModel> employees,
    List<TaskModel> tasks = const [],
    WesiAiWorldState world = const WesiAiWorldState(),
    bool canAssignToOthers = true,
    String? currentEmployeeId,
    AiLearningProfile learning = const AiLearningProfile(),
    AiBusinessSignal signal = const AiBusinessSignal(),
  }) =>
      WesiAiTaskEngine.analyze(WesiAiAnalysisInput(
        tasks: tasks,
        world: world,
        employees: employees,
        eligibleEmployeeIds: employees.map((e) => e.id).toSet(),
        organizationId: 'org_wesi_beats',
        organizationName: 'Wesi Beats',
        organizationDescription: 'Продажа битов артистам',
        currentEmployeeId: currentEmployeeId ?? employees.first.id,
        canAssignToOthers: canAssignToOthers,
        businessSignal: signal,
        learningProfile: learning,
        now: now,
      ));

  AiTaskSuggestion? firstFact(List<AiTaskSuggestion> list) {
    for (final item in list) {
      if (item.isFact) return item;
    }
    return null;
  }

  group('данные приложения важнее шаблона', () {
    test('просроченная сделка обгоняет предложение «по типу работ»', () {
      final result = analyze(
        employees: [person('wesi', position: 'продюсер'),
            person('ivan', position: 'менеджер')],
        tasks: [
          task('t1',
              title: 'Сделать бит',
              employeeId: 'wesi',
              status: TaskStatus.done,
              createdAt: now.subtract(const Duration(days: 3)),
              tags: const ['wesi-ai:category:production']),
        ],
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур', owner: 'ivan')],
          deals: [overdueDeal('d1', owner: 'ivan')],
        ),
        signal: const AiBusinessSignal(
          financeAvailable: true,
          recentIncome: 10000,
          previousIncome: 90000,
          recentNet: -20000,
          incomeGrowth: -.88,
        ),
      );

      expect(result.first.isFact, isTrue,
          reason: 'пока в приложении есть незакрытая сделка, придумывать '
              'новую работу поверх неё неправильно');
      expect(result.first.title, contains('Пакет из 5 битов'));
    });

    test('предложение из факта называет объект, а не тип работы', () {
      final result = analyze(
        employees: [person('olga', position: 'дизайнер')],
        world: WesiAiWorldState(
          beats: [
            BeatEntry(
              id: 'b1',
              title: 'Ночной',
              authorEmployeeId: 'wesi',
              stage: BeatStage.ready,
              wavPath: '/n.wav',
              createdAt: now.subtract(const Duration(days: 20)),
              updatedAt: now.subtract(const Duration(days: 12)),
            ),
          ],
        ),
      );

      final fact = firstFact(result);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Ночной'),
          reason: '«сделать превью для готового бита» не говорит, для какого');
      expect(fact.factTag, 'wesi-ai:fact:beatMissingCover:b1');
    });

    test('без живых данных система не молчит, а возвращается к шаблонам', () {
      final result = analyze(
        employees: [person('wesi', position: 'продюсер')],
        tasks: [
          task('t1',
              title: 'Сделать бит',
              employeeId: 'wesi',
              status: TaskStatus.done,
              createdAt: now.subtract(const Duration(days: 5)),
              tags: const ['wesi-ai:category:production']),
        ],
      );
      expect(result, isNotEmpty,
          reason: 'в новой организации фактов ещё нет, и это рабочий случай');
      expect(result.every((item) => !item.isFact), isTrue);
    });

    test('срок берётся у объекта, а не из таблицы важности', () {
      final leaseEnd = now.add(const Duration(days: 6));
      final result = analyze(
        employees: [person('wesi', position: 'продюсер')],
        world: WesiAiWorldState(
          beats: [
            BeatEntry(
              id: 'b1',
              title: 'Туман',
              authorEmployeeId: 'wesi',
              stage: BeatStage.leased,
              wavPath: '/t.wav',
              coverPath: '/t.png',
              lease: BeatLease(
                id: 'l1',
                artistName: 'MC Гром',
                socialUrl: '',
                startsAt: now.subtract(const Duration(days: 174)),
                endsAt: leaseEnd,
                amount: 30000,
                currency: 'RUB',
                notes: '',
              ),
              createdAt: now.subtract(const Duration(days: 180)),
              updatedAt: now.subtract(const Duration(days: 30)),
            ),
          ],
        ),
      );
      expect(firstFact(result)!.dueDate, leaseEnd);
    });
  });

  group('кому достаётся работа', () {
    test('объект достаётся тому, за кем он закреплён', () {
      final result = analyze(
        employees: [
          person('wesi', position: 'продюсер'),
          person('ivan', position: 'менеджер'),
          person('olga', position: 'дизайнер'),
        ],
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур', owner: 'ivan')],
          deals: [overdueDeal('d1', owner: 'ivan')],
        ),
      );
      final fact = firstFact(result)!;
      expect(fact.assigneeId, 'ivan');
      expect(fact.evidence, contains('ivan: объект закреплён за ним'));
    });

    test('заваленный владелец уступает тому, кто успеет', () {
      // Преимущество владельца большое, но не безусловное: пять просроченных
      // задач и полная загрузка перевешивают его.
      final overdue = [
        for (var i = 0; i < 5; i++)
          task('o$i',
              employeeId: 'ivan',
              priority: TaskPriority.urgent,
              dueDate: now.subtract(Duration(days: 5 + i))),
      ];
      final result = analyze(
        employees: [
          person('ivan', position: 'кладовщик', capacity: 4),
          person('petr', position: 'менеджер', capacity: 30),
        ],
        tasks: overdue,
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур', owner: 'ivan')],
          deals: [overdueDeal('d1', owner: 'ivan')],
        ),
      );

      final fact = firstFact(result)!;
      expect(fact.assigneeId, 'petr',
          reason: 'закрепление за человеком не помогает, если он не успеет');
      expect(fact.alternativeAssigneeIds, contains('ivan'),
          reason: 'владелец обязан остаться в списке — решение всё равно за '
              'человеком');
    });

    test('наблюдение не пропадает, когда нет подходящей должности', () {
      // У проблемы есть срок независимо от того, совпала ли у кого-то запись
      // в поле «должность».
      final result = analyze(
        employees: [person('kto_to'), person('drugoy')],
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур')],
          deals: [overdueDeal('d1')],
        ),
      );
      final fact = firstFact(result);
      expect(fact, isNotNull);
      expect(fact!.assigneeId, isNotNull,
          reason: 'иначе просроченная сделка исчезла бы из виду');
    });

    test('без права назначать другим работа остаётся на себе', () {
      final result = analyze(
        employees: [
          person('wesi', position: 'продюсер'),
          person('ivan', position: 'менеджер'),
        ],
        canAssignToOthers: false,
        currentEmployeeId: 'wesi',
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур', owner: 'ivan')],
          deals: [overdueDeal('d1', owner: 'ivan')],
        ),
      );
      for (final item in result) {
        expect(item.assigneeId, 'wesi');
      }
    });

    test('запрос файла адресуется тому, у кого файл', () {
      final result = analyze(
        employees: [person('wesi'), person('ivan')],
        world: WesiAiWorldState(
          fileRequests: [
            FileShareRequest(
              id: 'R1',
              subjectKind: ShareSubjectKind.beat,
              subjectId: 'b1',
              fileKind: ShareFileKind.wav,
              requesterId: 'ivan',
              holderId: 'wesi',
              createdAt: now.subtract(const Duration(days: 3)),
            ),
          ],
        ),
      );
      expect(firstFact(result)!.assigneeId, 'wesi');
    });
  });

  group('поток предложений остаётся читаемым', () {
    test('одно направление не занимает весь список', () {
      final clients = [
        for (var i = 0; i < 6; i++)
          CrmClient(
            id: 'c$i',
            name: 'Клиент $i',
            status: CrmClientStatus.active,
            nextContactAt: now.subtract(Duration(days: 5 + i)),
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 30)),
          ),
      ];
      final result = analyze(
        employees: [person('ivan', position: 'менеджер')],
        world: WesiAiWorldState(clients: clients),
      );
      final customer = result
          .where((item) => item.category.name == 'customer')
          .length;
      expect(customer, lessThanOrEqualTo(2),
          reason: 'шесть карточек подряд — это уже не помощь, а список дел');
      expect(result.length, lessThanOrEqualTo(5));
    });

    test('повторный отказ приглушает наблюдение, но не самое срочное', () {
      final quiet = AiLearningProfile(templates: {
        'fact:beatStalled': const AiTemplateLearning(rejected: 3),
        'fact:dealCloseDatePassed': const AiTemplateLearning(rejected: 3),
      });
      final world = WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [overdueDeal('d1', amount: 500000)],
        beats: [
          BeatEntry(
            id: 'b1',
            title: 'Забытый',
            authorEmployeeId: 'wesi',
            stage: BeatStage.mixing,
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 45)),
          ),
        ],
      );

      final result = analyze(
        employees: [person('wesi', position: 'продюсер'),
            person('ivan', position: 'менеджер')],
        world: world,
        learning: quiet,
      );

      final tags = result.map((item) => item.factTag).toList();
      expect(tags.any((tag) => tag.startsWith('wesi-ai:fact:beatStalled')),
          isFalse,
          reason: 'отказы учтены: спокойное наблюдение замолкает');
      expect(
          tags.any((tag) => tag.startsWith('wesi-ai:fact:dealCloseDatePassed')),
          isTrue,
          reason: 'сделка на полмиллиона не перестаёт быть просроченной '
              'оттого, что напоминания закрывали крестиком');
    });

    test('уже поставленная работа исчезает из предложений', () {
      final world = WesiAiWorldState(
        clients: [client('c1', 'Артур', owner: 'ivan')],
        deals: [overdueDeal('d1', owner: 'ivan')],
      );
      final before = analyze(
        employees: [person('ivan', position: 'менеджер')],
        world: world,
      );
      expect(firstFact(before), isNotNull);

      final after = analyze(
        employees: [person('ivan', position: 'менеджер')],
        tasks: [
          task('t1',
              title: 'Закрыть сделку',
              employeeId: 'ivan',
              status: TaskStatus.backlog,
              tags: const ['wesi-ai:fact:dealCloseDatePassed:d1']),
        ],
        world: world,
      );
      expect(
        after.where((item) =>
            item.factTag == 'wesi-ai:fact:dealCloseDatePassed:d1'),
        isEmpty,
      );
    });
  });

  group('стратегический разбор не портит факты', () {
    test('форма цепочки не отменяет просроченную сделку', () {
      // У планировщика есть правило «в этом направлении и так много задач —
      // не добавляй». К наблюдению оно не относится: очередь в продажах не
      // делает просроченную сделку менее просроченной.
      final busy = [
        for (var i = 0; i < 4; i++)
          task('s$i',
              title: 'Продажи $i',
              employeeId: 'ivan',
              tags: const ['wesi-ai:category:sales']),
      ];
      final suggestions = analyze(
        employees: [person('ivan', position: 'менеджер')],
        tasks: busy,
        world: WesiAiWorldState(
          clients: [client('c1', 'Артур', owner: 'ivan')],
          deals: [overdueDeal('d1', owner: 'ivan')],
        ),
      );
      final fact = firstFact(suggestions)!;

      final ranked = WesiAiStrategyPlanner.rank(
        suggestions: suggestions,
        tasks: busy,
        organizationId: 'org_wesi_beats',
        organizationName: 'Wesi Beats',
        organizationDescription: 'Продажа битов артистам',
        businessSignal: const AiBusinessSignal(),
        now: now,
      );

      final same = ranked.firstWhere((item) => item.factTag == fact.factTag);
      expect(same.needScore, fact.needScore,
          reason: 'срочность наблюдения считается по его собственным числам');
      expect(same.strategicScore, fact.strategicScore,
          reason: 'вес наблюдения задаёт сам объект, а не форма цепочки задач');
      expect(same.dueDate, fact.dueDate);
      expect(ranked.first.isFact, isTrue);
    });
  });
}
