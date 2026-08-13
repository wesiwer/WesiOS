import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/files/models/file_share_models.dart';
import 'package:wesios/features/roadmap/models/roadmap_models.dart';
import 'package:wesios/features/tasks/ai/models/ai_fact.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_fact_finder.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

/// Поиск фактов — та часть, где система перестаёт угадывать.
///
/// Здесь проверяется не «выдало хоть что-то», а конкретное: назван ли реальный
/// объект, посчитан ли срок по его собственной дате и не выдумано ли основание.
void main() {
  final now = DateTime(2026, 8, 13, 12);

  CrmClient client(
    String id,
    String name, {
    DateTime? nextContactAt,
    String? ownerEmployeeId,
    CrmClientStatus status = CrmClientStatus.active,
    DateTime? createdAt,
  }) =>
      CrmClient(
        id: id,
        name: name,
        status: status,
        ownerEmployeeId: ownerEmployeeId,
        nextContactAt: nextContactAt,
        createdAt: createdAt ?? now.subtract(const Duration(days: 60)),
        updatedAt: now.subtract(const Duration(days: 30)),
      );

  CrmDeal deal(
    String id, {
    String clientId = 'c1',
    String title = 'Сделка',
    double amount = 50000,
    DealStage stage = DealStage.negotiation,
    DateTime? expectedCloseAt,
    DateTime? updatedAt,
    String? responsibleEmployeeId,
  }) =>
      CrmDeal(
        id: id,
        clientId: clientId,
        title: title,
        amount: amount,
        stage: stage,
        responsibleEmployeeId: responsibleEmployeeId,
        expectedCloseAt: expectedCloseAt,
        createdAt: now.subtract(const Duration(days: 40)),
        updatedAt: updatedAt ?? now.subtract(const Duration(days: 2)),
      );

  BeatEntry beat(
    String id,
    String title, {
    BeatStage stage = BeatStage.ready,
    String? coverPath = '/cover.png',
    String? wavPath = '/beat.wav',
    BeatLease? lease,
    DateTime? updatedAt,
    String author = 'wesi',
  }) =>
      BeatEntry(
        id: id,
        title: title,
        authorEmployeeId: author,
        stage: stage,
        coverPath: coverPath,
        wavPath: wavPath,
        lease: lease,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: updatedAt ?? now.subtract(const Duration(days: 3)),
      );

  RoadmapItem milestone(
    String id, {
    required DateTime endDate,
    RoadmapItemStatus status = RoadmapItemStatus.inProgress,
    int progress = 30,
    String assignee = '',
    DateTime? updatedAt,
  }) =>
      RoadmapItem(
        id: id,
        projectId: 'p1',
        title: 'Веха $id',
        kind: RoadmapItemKind.milestone,
        status: status,
        assignee: assignee,
        progress: progress,
        startDate: now.subtract(const Duration(days: 30)),
        endDate: endDate,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: updatedAt ?? now.subtract(const Duration(days: 5)),
      );

  List<WesiAiFact> find(WesiAiWorldState world) =>
      WesiAiFactFinder.collect(world, now: now);

  WesiAiFact? pick(List<WesiAiFact> facts, AiFactKind kind, [String? id]) {
    for (final fact in facts) {
      if (fact.kind != kind) continue;
      if (id != null && fact.subjectId != id) continue;
      return fact;
    }
    return null;
  }

  group('клиенты и сделки', () {
    test('просроченный контакт называет клиента и считает просрочку', () {
      final facts = find(WesiAiWorldState(
        clients: [
          client('c1', 'Артур',
              nextContactAt: now.subtract(const Duration(days: 7)),
              ownerEmployeeId: 'ivan'),
        ],
      ));

      final fact = pick(facts, AiFactKind.clientFollowUpOverdue);
      expect(fact, isNotNull, reason: 'просроченный контакт обязан всплыть');
      expect(fact!.title, contains('Артур'),
          reason: 'без имени клиента задача бесполезна');
      expect(fact.whyNow, contains('7 дней'));
      expect(fact.ownerEmployeeId, 'ivan',
          reason: 'у клиента есть свой менеджер — он и должен звонить');
      expect(fact.deadline!.isAfter(now), isTrue);
    });

    test('архивный клиент не тревожат', () {
      final facts = find(WesiAiWorldState(
        clients: [
          client('c1', 'Ушедший',
              status: CrmClientStatus.archived,
              nextContactAt: now.subtract(const Duration(days: 30))),
        ],
      ));
      expect(pick(facts, AiFactKind.clientFollowUpOverdue), isNull);
    });

    test('клиент без единого касания попадает в работу', () {
      final facts = find(WesiAiWorldState(
        clients: [
          client('c1', 'Новичок',
              createdAt: now.subtract(const Duration(days: 9))),
        ],
      ));
      final fact = pick(facts, AiFactKind.clientNeverContacted);
      expect(fact, isNotNull);
      expect(fact!.evidence, contains('Касаний в карточке: 0'));
    });

    test('заведённый вчера клиент ещё не повод', () {
      final facts = find(WesiAiWorldState(
        clients: [
          client('c1', 'Вчерашний',
              createdAt: now.subtract(const Duration(days: 1))),
        ],
      ));
      expect(pick(facts, AiFactKind.clientNeverContacted), isNull,
          reason: 'напоминать через сутки — это шум, а не помощь');
    });

    test('просроченное закрытие сделки называет сумму и стадию', () {
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [
          deal('d1',
              title: 'Пакет из 5 битов',
              amount: 180000,
              expectedCloseAt: now.subtract(const Duration(days: 9)),
              responsibleEmployeeId: 'ivan'),
        ],
      ));

      final fact = pick(facts, AiFactKind.dealCloseDatePassed);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Пакет из 5 битов'));
      expect(fact.title, contains('180 000 ₽'),
          reason: 'сумма на кону — это и есть причина заняться этим первым');
      expect(fact.evidence.any((e) => e.contains('переговоры')), isTrue);
      expect(fact.ownerEmployeeId, 'ivan');
    });

    test('закрытая сделка не тревожит', () {
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [
          deal('d1',
              stage: DealStage.won,
              expectedCloseAt: now.subtract(const Duration(days: 30))),
        ],
      ));
      expect(pick(facts, AiFactKind.dealCloseDatePassed), isNull);
      expect(pick(facts, AiFactKind.dealStalled), isNull);
    });

    test('застой считается от последнего касания, а не от даты сделки', () {
      // Сделка заведена сорок дней назад, но разговор был вчера — это живая
      // работа, а не застой.
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [deal('d1', updatedAt: now.subtract(const Duration(days: 35)))],
        interactions: [
          CrmInteraction(
            id: 'i1',
            clientId: 'c1',
            title: 'Созвон',
            at: now.subtract(const Duration(days: 1)),
          ),
        ],
      ));
      expect(pick(facts, AiFactKind.dealStalled), isNull,
          reason: 'вчерашний созвон снимает вопрос о застое');
    });

    test('молчание дольше десяти дней на активной стадии — повод', () {
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [deal('d1', updatedAt: now.subtract(const Duration(days: 21)))],
      ));
      final fact = pick(facts, AiFactKind.dealStalled);
      expect(fact, isNotNull);
      expect(fact!.whyNow, isNotEmpty);
    });

    test('новый лид без движения застоем не считается', () {
      // На стадии «новый лид» тишина — это ещё не потеря: работа просто
      // не начиналась.
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [
          deal('d1',
              stage: DealStage.newLead,
              updatedAt: now.subtract(const Duration(days: 30))),
        ],
      ));
      expect(pick(facts, AiFactKind.dealStalled), isNull);
    });

    test('крупная сделка без ответственного всплывает, мелкая — нет', () {
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [
          deal('big',
              title: 'Альбом',
              amount: 400000,
              updatedAt: now.subtract(const Duration(days: 1))),
          deal('small',
              title: 'Мелочь',
              amount: 3000,
              updatedAt: now.subtract(const Duration(days: 1))),
        ],
      ));
      expect(pick(facts, AiFactKind.dealWithoutOwner, 'big'), isNotNull);
      expect(pick(facts, AiFactKind.dealWithoutOwner, 'small'), isNull,
          reason: 'на каждую мелкую сделку ответственного не назначают');
    });

    test('крупность считается по меркам организации, а не по числу', () {
      // Одна и та же сумма в разных студиях значит разное. Здесь 20 000 —
      // самая крупная сделка организации, и она обязана всплыть.
      final facts = find(WesiAiWorldState(
        clients: [client('c1', 'Артур')],
        deals: [
          deal('a', amount: 20000, updatedAt: now.subtract(const Duration(days: 1))),
          deal('b', amount: 3000, updatedAt: now.subtract(const Duration(days: 1))),
          deal('c', amount: 2000, updatedAt: now.subtract(const Duration(days: 1))),
        ],
      ));
      expect(pick(facts, AiFactKind.dealWithoutOwner, 'a'), isNotNull,
          reason: 'абсолютный порог здесь не сработал бы вовсе');
    });
  });

  group('дорожная карта', () {
    test('просроченная веха на высокой готовности — «дожать»', () {
      final facts = find(WesiAiWorldState(
        projects: [
          RoadmapProject(
            id: 'p1',
            title: 'EP «Полночь»',
            startDate: now.subtract(const Duration(days: 60)),
            endDate: now.add(const Duration(days: 30)),
            createdAt: now.subtract(const Duration(days: 60)),
            updatedAt: now,
          ),
        ],
        roadmapItems: [
          milestone('r1',
              endDate: now.subtract(const Duration(days: 4)), progress: 85),
        ],
      ));
      final fact = pick(facts, AiFactKind.roadmapItemOverdue);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Дожать'));
      expect(fact.evidence.any((e) => e.contains('85%')), isTrue);
    });

    test('просроченная веха на нуле — «пересобрать срок»', () {
      final facts = find(WesiAiWorldState(
        roadmapItems: [
          milestone('r1',
              endDate: now.subtract(const Duration(days: 4)), progress: 5),
        ],
      ));
      expect(pick(facts, AiFactKind.roadmapItemOverdue)!.title,
          contains('Пересобрать срок'),
          reason: 'дожимать нечего — надо разбираться с планом');
    });

    test('срок ещё не прошёл, но при такой готовности не успеть', () {
      final facts = find(WesiAiWorldState(
        roadmapItems: [
          milestone('r1',
              endDate: now.add(const Duration(days: 2)), progress: 10),
        ],
      ));
      final fact = pick(facts, AiFactKind.roadmapDeadlineNear);
      expect(fact, isNotNull,
          reason: 'предупредить заранее дешевле, чем зафиксировать провал');
      expect(fact!.deadline, milestone('r1',
              endDate: now.add(const Duration(days: 2)), progress: 10)
          .endDate);
    });

    test('веха почти готова и в срок — молчим', () {
      final facts = find(WesiAiWorldState(
        roadmapItems: [
          milestone('r1',
              endDate: now.add(const Duration(days: 3)), progress: 90),
        ],
      ));
      expect(facts, isEmpty);
    });

    test('заблокированная веха всплывает отдельно от просрочки', () {
      final facts = find(WesiAiWorldState(
        roadmapItems: [
          milestone('r1',
              endDate: now.add(const Duration(days: 20)),
              status: RoadmapItemStatus.blocked,
              updatedAt: now.subtract(const Duration(days: 9))),
        ],
      ));
      final fact = pick(facts, AiFactKind.roadmapItemBlocked);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Разблокировать'));
    });

    test('веха архивного проекта не тревожит', () {
      final facts = find(WesiAiWorldState(
        projects: [
          RoadmapProject(
            id: 'p1',
            title: 'Закрытый',
            archived: true,
            startDate: now.subtract(const Duration(days: 90)),
            endDate: now.subtract(const Duration(days: 30)),
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now,
          ),
        ],
        roadmapItems: [
          milestone('r1', endDate: now.subtract(const Duration(days: 20))),
        ],
      ));
      expect(facts, isEmpty);
    });

    test('готовая веха не всплывает даже с прошедшим сроком', () {
      final facts = find(WesiAiWorldState(
        roadmapItems: [
          milestone('r1',
              endDate: now.subtract(const Duration(days: 10)),
              status: RoadmapItemStatus.done,
              progress: 100),
        ],
      ));
      expect(facts, isEmpty);
    });
  });

  group('биты и лицензии', () {
    test('готовый бит без обложки называет бит по имени', () {
      final facts = find(WesiAiWorldState(
        beats: [beat('b1', 'Ночной', coverPath: null)],
      ));
      final fact = pick(facts, AiFactKind.beatMissingCover);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Ночной'));
      expect(fact.category.name, 'design',
          reason: 'обложку делает дизайнер, а не битмейкер');
    });

    test('черновик без обложки — не повод', () {
      final facts = find(WesiAiWorldState(
        beats: [beat('b1', 'Набросок', stage: BeatStage.draft,
            coverPath: null, updatedAt: now)],
      ));
      expect(pick(facts, AiFactKind.beatMissingCover), isNull,
          reason: 'обложка нужна готовому биту, а не идее');
    });

    test('отданный по лицензии бит без WAV — критично', () {
      final facts = find(WesiAiWorldState(
        beats: [beat('b1', 'Туман', stage: BeatStage.leased, wavPath: null)],
      ));
      final fact = pick(facts, AiFactKind.beatMissingMaster);
      expect(fact, isNotNull);
      expect(fact!.priority.name, 'urgent',
          reason: 'артист уже платит, а отдать нечего');
      expect(fact.ownerEmployeeId, 'wesi');
    });

    test('лицензия на исходе предупреждает заранее', () {
      final facts = find(WesiAiWorldState(
        beats: [
          beat('b1', 'Туман',
              stage: BeatStage.leased,
              lease: BeatLease(
                id: 'l1',
                artistName: 'MC Гром',
                socialUrl: '',
                startsAt: now.subtract(const Duration(days: 175)),
                endsAt: now.add(const Duration(days: 4)),
                amount: 25000,
                currency: 'RUB',
                notes: '',
              )),
        ],
      ));
      final fact = pick(facts, AiFactKind.leaseExpiring);
      expect(fact, isNotNull);
      expect(fact!.title, contains('MC Гром'));
      expect(fact.whyNow, contains('4 дня'));
      expect(fact.deadline, now.add(const Duration(days: 4)),
          reason: 'срок берётся у самой лицензии, а не из таблицы важности');
    });

    test('истёкшая лицензия требует решения', () {
      final facts = find(WesiAiWorldState(
        beats: [
          beat('b1', 'Туман',
              stage: BeatStage.leased,
              lease: BeatLease(
                id: 'l1',
                artistName: 'MC Гром',
                socialUrl: '',
                startsAt: now.subtract(const Duration(days: 200)),
                endsAt: now.subtract(const Duration(days: 6)),
                amount: 25000,
                currency: 'RUB',
                notes: '',
              )),
        ],
      ));
      final fact = pick(facts, AiFactKind.leaseExpired);
      expect(fact, isNotNull);
      expect(fact!.priority.name, anyOf('urgent', 'high'));
    });

    test('лицензия на полгода вперёд не тревожит', () {
      final facts = find(WesiAiWorldState(
        beats: [
          beat('b1', 'Туман',
              stage: BeatStage.leased,
              lease: BeatLease(
                id: 'l1',
                artistName: 'MC Гром',
                socialUrl: '',
                startsAt: now,
                endsAt: now.add(const Duration(days: 180)),
                amount: 25000,
                currency: 'RUB',
                notes: '',
              )),
        ],
      ));
      expect(pick(facts, AiFactKind.leaseExpiring), isNull);
    });

    test('бит, застрявший в сведении, напоминает о себе', () {
      final facts = find(WesiAiWorldState(
        beats: [
          beat('b1', 'Забытый',
              stage: BeatStage.mixing,
              coverPath: null,
              wavPath: null,
              updatedAt: now.subtract(const Duration(days: 40))),
        ],
      ));
      expect(pick(facts, AiFactKind.beatStalled), isNotNull);
    });

    test('архивный бит не трогают', () {
      final facts = find(WesiAiWorldState(
        beats: [
          beat('b1', 'Старьё',
              stage: BeatStage.archived,
              coverPath: null,
              wavPath: null,
              updatedAt: now.subtract(const Duration(days: 300))),
        ],
      ));
      expect(facts, isEmpty);
    });
  });

  group('задачи, файлы и платежи', () {
    TaskModel task(
      String id, {
      String title = 'Задача',
      TaskStatus status = TaskStatus.inProgress,
      DateTime? dueDate,
      String? responsible = 'wesi',
      DateTime? createdAt,
      List<String> tags = const [],
    }) =>
        TaskModel(
          id: id,
          title: title,
          status: status,
          dueDate: dueDate,
          responsibleEmployeeId: responsible,
          assignee: responsible,
          tags: tags,
          createdAt: createdAt ?? now.subtract(const Duration(days: 10)),
        );

    test('давно просроченная задача становится поводом разобраться', () {
      final facts = find(WesiAiWorldState(
        tasks: [
          task('t1',
              title: 'Свести трек',
              dueDate: now.subtract(const Duration(days: 8))),
        ],
      ));
      final fact = pick(facts, AiFactKind.taskOverdue);
      expect(fact, isNotNull);
      expect(fact!.title, contains('Свести трек'));
    });

    test('вчерашняя просрочка ещё не повод', () {
      final facts = find(WesiAiWorldState(
        tasks: [task('t1', dueDate: now.subtract(const Duration(days: 1)))],
      ));
      expect(pick(facts, AiFactKind.taskOverdue), isNull,
          reason: 'однодневная просрочка разбирается сама');
    });

    test('задача, выросшая из наблюдения, не порождает следующее', () {
      // Иначе «разобрать просроченное» через неделю само станет поводом
      // разобрать «разобрать просроченное».
      final facts = find(WesiAiWorldState(
        tasks: [
          task('t1',
              title: 'Разобрать просроченное: «Свести трек»',
              dueDate: now.subtract(const Duration(days: 9)),
              tags: const ['wesi-ai:fact:taskOverdue:t0']),
        ],
      ));
      expect(pick(facts, AiFactKind.taskOverdue), isNull);
    });

    test('срок близко, а ответственного нет', () {
      final facts = find(WesiAiWorldState(
        tasks: [
          task('t1',
              title: 'Отправить артисту',
              responsible: null,
              dueDate: now.add(const Duration(days: 2))),
        ],
      ));
      final fact = pick(facts, AiFactKind.taskWithoutOwner);
      expect(fact, isNotNull);
      expect(fact!.deadline, now.add(const Duration(days: 2)));
    });

    test('запрос файла без ответа поднимается', () {
      final facts = find(WesiAiWorldState(
        fileRequests: [
          FileShareRequest(
            id: 'R1',
            subjectKind: ShareSubjectKind.beat,
            subjectId: 'b1',
            fileKind: ShareFileKind.wav,
            requesterId: 'ivan',
            holderId: 'wesi',
            createdAt: now.subtract(const Duration(days: 4)),
          ),
        ],
      ));
      final fact = pick(facts, AiFactKind.fileRequestWaiting);
      expect(fact, isNotNull);
      expect(fact!.ownerEmployeeId, 'wesi');
      expect(fact.whyNow, contains('4 дня'));
    });

    test('вчерашний запрос ещё ждёт спокойно', () {
      final facts = find(WesiAiWorldState(
        fileRequests: [
          FileShareRequest(
            id: 'R1',
            subjectKind: ShareSubjectKind.beat,
            subjectId: 'b1',
            fileKind: ShareFileKind.wav,
            requesterId: 'ivan',
            holderId: 'wesi',
            createdAt: now.subtract(const Duration(hours: 20)),
          ),
        ],
      ));
      expect(facts, isEmpty);
    });

    test('крупный регулярный платёж на носу — повод проверить деньги', () {
      final facts = find(WesiAiWorldState(
        transactions: [
          TransactionModel(
            id: 'x1',
            title: 'Аренда студии',
            amount: 60000,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 15),
            isRecurring: true,
            recurringPeriod: RecurringPeriod.monthly,
          ),
          TransactionModel(
            id: 'x2',
            title: 'Подписка на плагины',
            amount: 900,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 15),
            isRecurring: true,
            recurringPeriod: RecurringPeriod.monthly,
          ),
        ],
      ));
      final fact = pick(facts, AiFactKind.recurringPaymentDue);
      expect(fact, isNotNull, reason: 'платёж 15.08 — через два дня');
      expect(fact!.title, contains('Аренда студии'));
      expect(pick(facts, AiFactKind.recurringPaymentDue, 'x2'), isNull,
          reason: 'мелкая подписка не стоит отдельной задачи');
    });

    test('регулярный доход не превращается в задачу', () {
      final facts = find(WesiAiWorldState(
        transactions: [
          TransactionModel(
            id: 'x1',
            title: 'Подписка на биты',
            amount: 60000,
            type: TransactionType.income,
            date: DateTime(2026, 7, 15),
            isRecurring: true,
            recurringPeriod: RecurringPeriod.monthly,
          ),
        ],
      ));
      expect(facts, isEmpty);
    });
  });

  group('общие правила', () {
    test('поставленная работа снимает наблюдение', () {
      final world = WesiAiWorldState(
        beats: [beat('b1', 'Ночной', coverPath: null)],
      );
      expect(pick(find(world), AiFactKind.beatMissingCover), isNotNull);

      final covered = WesiAiFactFinder.collect(
        world,
        now: now,
        coverTasks: [
          TaskModel(
            id: 't1',
            title: 'Обложка для бита «Ночной»',
            status: TaskStatus.backlog,
            createdAt: now,
            tags: const ['wesi-ai:fact:beatMissingCover:b1'],
          ),
        ],
      );
      expect(pick(covered, AiFactKind.beatMissingCover), isNull,
          reason: 'система напоминает о проблеме, а не о том, что о ней помнят');
    });

    test('закрытая задача наблюдение обратно не удерживает', () {
      final world = WesiAiWorldState(
        beats: [beat('b1', 'Ночной', coverPath: null)],
      );
      final facts = WesiAiFactFinder.collect(
        world,
        now: now,
        coverTasks: [
          TaskModel(
            id: 't1',
            title: 'Обложка',
            status: TaskStatus.done,
            createdAt: now.subtract(const Duration(days: 30)),
            tags: const ['wesi-ai:fact:beatMissingCover:b1'],
          ),
        ],
      );
      expect(pick(facts, AiFactKind.beatMissingCover), isNotNull,
          reason: 'обложки всё ещё нет — значит вопрос открыт');
    });

    test('пустое приложение фактов не выдумывает', () {
      expect(find(const WesiAiWorldState()), isEmpty);
    });

    test('факты приходят от срочных к спокойным', () {
      final facts = find(WesiAiWorldState(
        clients: [
          client('c1', 'Свежий',
              nextContactAt: now.subtract(const Duration(days: 1))),
        ],
        deals: [
          deal('d1',
              amount: 300000,
              expectedCloseAt: now.subtract(const Duration(days: 20))),
        ],
      ));
      expect(facts.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < facts.length; i++) {
        expect(facts[i - 1].urgency, greaterThanOrEqualTo(facts[i].urgency));
      }
    });
  });

  group('счёт срочности', () {
    test('просрочка растёт, но не разгоняется бесконечно', () {
      final one = AiFactMath.lateness(1);
      final ten = AiFactMath.lateness(10);
      final hundred = AiFactMath.lateness(100);
      expect(one, greaterThan(0));
      expect(ten, greaterThan(one));
      expect(hundred, greaterThan(ten));
      expect(hundred - ten, lessThan(ten - one),
          reason: 'разница между 40 и 60 днями в жизни почти не ощущается');
      expect(hundred, lessThanOrEqualTo(1));
    });

    test('масштаб — медиана, её не сдвигает одна крупная сделка', () {
      expect(AiFactMath.scaleOf([1000, 2000, 3000]), 2000);
      expect(AiFactMath.scaleOf([1000, 2000, 3000, 10000000]), 2500,
          reason: 'среднее здесь дало бы два с половиной миллиона');
      expect(AiFactMath.scaleOf(const []), 0);
    });

    test('вес суммы относителен и всегда в пределах ноль-один', () {
      expect(AiFactMath.moneyWeight(50000, 50000), closeTo(.5, .001));
      expect(AiFactMath.moneyWeight(500, 500), closeTo(.5, .001),
          reason: 'та же доля при другом масштабе даёт тот же вес');
      expect(AiFactMath.moneyWeight(0, 1000), 0);
      expect(AiFactMath.moneyWeight(1000000, 1000), lessThan(1));
    });

    test('деньги усиливают просрочку, но не заменяют её', () {
      final cheapLate = AiFactMath.blend(AiFactMath.lateness(30), 0);
      final richFresh = AiFactMath.blend(AiFactMath.lateness(1), 1);
      expect(cheapLate, greaterThan(richFresh),
          reason: 'дорогая сделка со вчерашним сроком не важнее месячной '
              'просрочки');
    });

    test('дни склоняются по-русски', () {
      expect(AiFactMath.days(1), '1 день');
      expect(AiFactMath.days(3), '3 дня');
      expect(AiFactMath.days(5), '5 дней');
      expect(AiFactMath.days(11), '11 дней');
      expect(AiFactMath.days(21), '21 день');
      expect(AiFactMath.days(112), '112 дней');
    });

    test('перевод часов не меняет число дней', () {
      // Между этими датами ровно трое суток по календарю, но 71 час по
      // времени: в ночь на 29 марта часы переводят вперёд.
      final before = DateTime(2026, 3, 27, 12);
      final after = DateTime(2026, 3, 30, 12);
      expect(AiFactMath.daysBetween(before, after), 3);
    });
  });
}
