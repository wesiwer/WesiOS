import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/tasks/ai/models/ai_fact.dart';
import 'package:wesios/features/tasks/ai/models/ai_learning_profile.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_fact_finder.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_task_engine.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';

/// «Программа видела, что бит давно не выкладывали, и не предложила его
/// написать».
///
/// Так и было, и причина не в настройке порогов. Все наблюдения о битах
/// говорили о существующем объекте: у этого нет обложки, этот застрял на
/// сведении, у этого истекает лицензия. Наблюдения об отсутствии не было
/// вообще — а отсутствие само о себе не сообщает. Каталог мог не
/// пополняться полгода, и в данных не появлялось ни одной записи, на
/// которую можно было бы показать.
///
/// Здесь проверяется само наблюдение и его границы: когда оно обязано
/// сработать, когда обязано промолчать, и почему порог считается по
/// собственному ритму, а не берётся из головы.
void main() {
  final now = DateTime(2026, 8, 13, 12);

  BeatEntry beat(
    String id, {
    required int createdDaysAgo,
    int? updatedDaysAgo,
    BeatStage stage = BeatStage.ready,
    double leaseAmount = 0,
    String author = 'wesi',
  }) =>
      BeatEntry(
        id: id,
        title: 'Бит $id',
        authorEmployeeId: author,
        stage: stage,
        coverPath: '/cover.png',
        wavPath: '/beat.wav',
        lease: leaseAmount <= 0
            ? null
            : BeatLease(
                id: 'lease-$id',
                artistName: 'Артист',
                socialUrl: '',
                startsAt: now.subtract(const Duration(days: 60)),
                // Срок в будущем и подальше: истекающая лицензия — отдельное
                // наблюдение, и оно не должно примешиваться к этому.
                endsAt: now.add(const Duration(days: 300)),
                amount: leaseAmount,
                currency: 'RUB',
                notes: '',
              ),
        createdAt: now.subtract(Duration(days: createdDaysAgo)),
        updatedAt:
            now.subtract(Duration(days: updatedDaysAgo ?? createdDaysAgo)),
      );

  List<WesiAiFact> facts(List<BeatEntry> beats, {List<TaskModel>? tasks}) =>
      WesiAiFactFinder.collect(
        WesiAiWorldState(beats: beats, tasks: tasks ?? const []),
        now: now,
      );

  WesiAiFact? silence(List<BeatEntry> beats, {List<TaskModel>? tasks}) {
    final found = facts(beats, tasks: tasks)
        .where((fact) => fact.kind == AiFactKind.beatCadenceStalled);
    return found.isEmpty ? null : found.first;
  }

  group('молчание по новым битам', () {
    test('раньше такого наблюдения не существовало вовсе', () {
      // Ровно то, на что жаловался человек: биты есть, новых давно нет,
      // и до этой правки в наборе не было ни одного факта об этом.
      expect(AiFactKind.values, contains(AiFactKind.beatCadenceStalled));
    });

    test('срабатывает, когда новых битов давно нет', () {
      final fact = silence([
        beat('a', createdDaysAgo: 120),
        beat('b', createdDaysAgo: 100),
        beat('c', createdDaysAgo: 80),
      ]);

      expect(fact, isNotNull);
      expect(fact!.title, 'Написать новый бит');
      expect(fact.category, AiTaskCategory.production);
    });

    test('молчит, пока пауза укладывается в обычный ритм', () {
      // Биты появлялись раз в двадцать дней, последний — девять дней назад.
      // Это рабочий ритм, а не простой, и напоминать здесь не о чем.
      final fact = silence([
        beat('a', createdDaysAgo: 49),
        beat('b', createdDaysAgo: 29),
        beat('c', createdDaysAgo: 9),
      ]);

      expect(fact, isNull);
    });

    test('порог берётся из собственного ритма, а не из общего числа', () {
      // Один и тот же перерыв в 30 дней. У быстрого автора это долгий
      // простой, у медленного — обычное дело. Общий порог соврал бы одному
      // из них, поэтому его нет.
      final fast = silence([
        beat('a', createdDaysAgo: 44),
        beat('b', createdDaysAgo: 37),
        beat('c', createdDaysAgo: 30),
      ]);
      final slow = silence([
        beat('a', createdDaysAgo: 150),
        beat('b', createdDaysAgo: 90),
        beat('c', createdDaysAgo: 30),
      ]);

      expect(fast, isNotNull, reason: 'семь дней ритма против тридцати пауза');
      expect(slow, isNull, reason: 'шестьдесят дней ритма — тридцать в норме');
    });

    test('молчит, пока над битом идёт работа прямо сейчас', () {
      // Новых записей нет, но материал делается: правки были на этой неделе.
      // Сказать «давно ничего не пишете» здесь означало бы соврать.
      final fact = silence([
        beat('a', createdDaysAgo: 200),
        beat('b', createdDaysAgo: 150),
        beat('c',
            createdDaysAgo: 100,
            updatedDaysAgo: 2,
            stage: BeatStage.mixing),
      ]);

      expect(fact, isNull);
    });

    test('пустой каталог — не повод: этим занимается шаблон', () {
      expect(silence(const []), isNull);
    });

    test('без сложившегося ритма работает общий порог', () {
      // Один бит — это не ритм: промежутков нет, медиану считать не из чего.
      // Тогда берётся общий порог, и в наблюдении честно сказано, что он
      // общий, а не выведен из данных.
      final early = silence([beat('a', createdDaysAgo: 10)]);
      final late = silence([beat('a', createdDaysAgo: 40)]);

      expect(early, isNull);
      expect(late, isNotNull);
      expect(
        late!.evidence.any((line) => line.contains('Ритм ещё не сложился')),
        isTrue,
      );
    });

    test('биты, которые приносили деньги, поднимают важность', () {
      // Молчание среднее: у самого дна и у потолка оба случая упираются в
      // границу, и разницу между ними там не увидеть.
      final dry = silence([
        beat('a', createdDaysAgo: 66),
        beat('b', createdDaysAgo: 51),
        beat('c', createdDaysAgo: 37),
      ])!;
      final earning = silence([
        beat('a', createdDaysAgo: 66, leaseAmount: 8000),
        beat('b', createdDaysAgo: 51),
        beat('c', createdDaysAgo: 37),
      ])!;

      expect(earning.urgency, greaterThan(dry.urgency));
      expect(earning.impact.index, greaterThan(dry.impact.index));
      expect(earning.whyNow, contains('уже приносили деньги'));
    });

    test('исполнителем становится автор последнего бита', () {
      final fact = silence([
        beat('a', createdDaysAgo: 120, author: 'старый'),
        beat('b', createdDaysAgo: 80, author: 'последний'),
      ])!;

      expect(fact.ownerEmployeeId, 'последний');
    });

    test('поставленная задача снимает наблюдение', () {
      final beats = [
        beat('a', createdDaysAgo: 120),
        beat('b', createdDaysAgo: 100),
        beat('c', createdDaysAgo: 80),
      ];
      final tag = silence(beats)!.tag;

      final covered = silence(beats, tasks: [
        TaskModel(
          id: 'task',
          title: 'Написать новый бит',
          status: TaskStatus.inProgress,
          priority: TaskPriority.normal,
          createdAt: now,
          tags: [tag],
        ),
      ]);

      expect(covered, isNull);
    });

    test('архив не считается за живой каталог', () {
      // Заархивированные биты не в счёт: их нельзя ни продать, ни показать,
      // и по ним нельзя судить о том, что работа идёт.
      final fact = silence([
        beat('a', createdDaysAgo: 120),
        beat('b', createdDaysAgo: 100),
        beat('c', createdDaysAgo: 1, stage: BeatStage.archived),
      ]);

      expect(fact, isNotNull);
    });

    test('срочность растёт вместе с длиной молчания', () {
      final short = silence([
        beat('a', createdDaysAgo: 60),
        beat('b', createdDaysAgo: 45),
        beat('c', createdDaysAgo: 30),
      ])!;
      final long = silence([
        beat('a', createdDaysAgo: 200),
        beat('b', createdDaysAgo: 185),
        beat('c', createdDaysAgo: 170),
      ])!;

      expect(long.urgency, greaterThan(short.urgency));
    });

    test('наблюдение остаётся обоснованным для движка', () {
      // Ниже 0.35 предложение теряет признак обоснованности и опускается
      // под догадки по типу работ — то есть перестаёт быть видимым ровно
      // тогда, когда оно правдиво.
      final fact = silence([
        beat('a', createdDaysAgo: 60),
        beat('b', createdDaysAgo: 45),
        beat('c', createdDaysAgo: 30),
      ])!;

      expect(fact.urgency, greaterThanOrEqualTo(.35));
    });

    test('не обгоняет поводы с настоящим сроком', () {
      // У этого наблюдения нет своего срока: завтра ничего не сломается
      // оттого, что бит не написан. У лицензии срок есть, и деньги по ней
      // теряются в конкретный день — она обязана стоять выше, сколько бы ни
      // длилось молчание.
      final fact = silence([
        beat('a', createdDaysAgo: 900, leaseAmount: 90000),
        beat('b', createdDaysAgo: 850),
        beat('c', createdDaysAgo: 800),
      ])!;

      expect(fact.urgency, lessThanOrEqualTo(.52));
    });

    test('совет без срока можно заставить замолчать отказами', () {
      // Движок перестаёт слушать отказы на наблюдениях важнее 0.55: у
      // просроченной сделки такого права нет — она не перестаёт быть
      // просроченной оттого, что напоминание закрыли крестиком. У совета
      // без срока право замолчать остаётся, и потолок это гарантирует.
      final loudest = silence([
        beat('a', createdDaysAgo: 900, leaseAmount: 90000),
        beat('b', createdDaysAgo: 850),
        beat('c', createdDaysAgo: 800),
      ])!;

      expect(loudest.urgency, lessThan(.55));
    });

    test('истекающая лицензия остаётся важнее пустого каталога', () {
      // Тот самый случай, на котором калибровка и проверилась: без потолка
      // «напишите новый бит» вытесняло «продлите лицензию на 30 000 ₽».
      final all = facts([
        BeatEntry(
          id: 'b1',
          title: 'Туман',
          authorEmployeeId: 'wesi',
          stage: BeatStage.leased,
          coverPath: '/cover.png',
          wavPath: '/beat.wav',
          lease: BeatLease(
            id: 'l1',
            artistName: 'MC Гром',
            socialUrl: '',
            startsAt: now.subtract(const Duration(days: 174)),
            endsAt: now.add(const Duration(days: 6)),
            amount: 30000,
            currency: 'RUB',
            notes: '',
          ),
          createdAt: now.subtract(const Duration(days: 180)),
          updatedAt: now.subtract(const Duration(days: 30)),
        ),
      ]);

      expect(all.first.kind, AiFactKind.leaseExpiring);
      expect(
        all.any((fact) => fact.kind == AiFactKind.beatCadenceStalled),
        isTrue,
        reason: 'наблюдение не исчезает — оно просто стоит ниже',
      );
    });
  });

  group('наблюдение доходит до панели', () {
    EmployeeModel person(String id, String position) => EmployeeModel(
          id: id,
          login: id,
          fullName: id,
          position: position,
          weeklyCapacityPoints: 20,
          createdAt: DateTime(2026, 1, 1),
        );

    test('предложение «написать новый бит» появляется в списке', () {
      // Смысл всей правки: наблюдение должно не просто существовать в
      // наборе, а дойти до человека. Между ними — отбор движка: не больше
      // пяти карточек и не больше двух на одну область работы.
      final suggestions = WesiAiTaskEngine.analyze(WesiAiAnalysisInput(
        tasks: const [],
        world: WesiAiWorldState(beats: [
          beat('a', createdDaysAgo: 120, leaseAmount: 8000),
          beat('b', createdDaysAgo: 100),
          beat('c', createdDaysAgo: 80),
        ]),
        employees: [person('wesi', 'Битмейкер')],
        eligibleEmployeeIds: const {'wesi'},
        organizationId: 'org_wesi_beats',
        organizationName: 'Wesi Beats',
        organizationDescription: 'Продажа битов артистам',
        currentEmployeeId: 'wesi',
        canAssignToOthers: true,
        businessSignal: const AiBusinessSignal(),
        learningProfile: const AiLearningProfile(),
        now: now,
      ));

      final card = suggestions
          .where((item) => item.title == 'Написать новый бит')
          .toList();

      expect(card, hasLength(1), reason: 'именно этого и не хватало');
      expect(card.single.isFact, isTrue);
      expect(card.single.assigneeId, 'wesi');
      expect(card.single.evidence.first, contains('Последний бит'));
    });
  });
}
