import 'dart:math';

import '../../../audio/models/audio_vault_models.dart';
import '../../../crm/models/crm_models.dart';
import '../../../files/models/file_share_models.dart';
import '../../../roadmap/models/roadmap_models.dart';
import '../../../treasury/models/transaction_model.dart';
import '../../../treasury/services/recurring_engine.dart';
import '../../models/task_model.dart';
import '../models/ai_fact.dart';
import '../models/ai_task_template.dart';

/// Всё, что система знает о текущем состоянии организации.
///
/// Собирается один раз и передаётся целиком: поиск фактов не должен ходить
/// в хранилище сам, иначе его нельзя ни проверить, ни объяснить.
class WesiAiWorldState {
  final List<TaskModel> tasks;
  final List<CrmClient> clients;
  final List<CrmDeal> deals;
  final List<CrmInteraction> interactions;
  final List<RoadmapProject> projects;
  final List<RoadmapItem> roadmapItems;
  final List<BeatEntry> beats;
  final List<FileShareRequest> fileRequests;
  final List<TransactionModel> transactions;

  const WesiAiWorldState({
    this.tasks = const [],
    this.clients = const [],
    this.deals = const [],
    this.interactions = const [],
    this.projects = const [],
    this.roadmapItems = const [],
    this.beats = const [],
    this.fileRequests = const [],
    this.transactions = const [],
  });

  bool get isEmpty =>
      clients.isEmpty &&
      deals.isEmpty &&
      roadmapItems.isEmpty &&
      beats.isEmpty &&
      fileRequests.isEmpty &&
      transactions.isEmpty;
}

/// Находит в живых данных то, что уже требует действия.
///
/// Ни одного придуманного повода: каждый факт указывает на существующий
/// объект и приводит числа, которые можно перепроверить руками.
class WesiAiFactFinder {
  WesiAiFactFinder._();

  /// Сколько дней сделка может стоять без касаний, прежде чем это станет
  /// поводом. Меньше недели — это ещё не застой, а обычный рабочий ритм.
  static const int dealSilenceDays = 10;

  /// Сколько дней бит может лежать в работе, не двигаясь по стадиям.
  static const int beatStallDays = 21;

  /// [coverTasks] — задачи, которые снимают факт. По умолчанию это задачи
  /// самой организации, но дорожная карта и каталог битов общие на всё
  /// приложение, поэтому сюда стоит передавать задачи всех организаций:
  /// иначе поставленная в одной организации работа не закроет наблюдение в
  /// соседней, и одна и та же обложка будет предложена дважды.
  static List<WesiAiFact> collect(
    WesiAiWorldState world, {
    required DateTime now,
    List<TaskModel>? coverTasks,
  }) {
    final facts = <WesiAiFact>[
      ..._crmFacts(world, now),
      ..._roadmapFacts(world, now),
      ..._beatFacts(world, now),
      ..._taskFacts(world, now),
      ..._fileFacts(world, now),
      ..._financeFacts(world, now),
    ];

    // Работа, уже поставленная по этому объекту, снимает факт: система
    // напоминает о проблеме, а не о том, что о ней уже помнят.
    final covered = <String>{};
    for (final task in coverTasks ?? world.tasks) {
      if (task.status == TaskStatus.done) continue;
      for (final tag in task.tags) {
        if (tag.startsWith('wesi-ai:fact:')) covered.add(tag);
      }
    }

    final live = facts.where((fact) => !covered.contains(fact.tag)).toList()
      ..sort((a, b) => b.urgency.compareTo(a.urgency));
    return live;
  }

  // --------------------------------------------------------------- клиенты

  static List<WesiAiFact> _crmFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    if (world.clients.isEmpty && world.deals.isEmpty) return facts;

    // Масштаб денег берётся у самой организации: и открытые сделки, и
    // закрытые. Без этого «крупная сделка» пришлось бы задавать числом,
    // одинаковым для студии с оборотом 30 000 и для студии с оборотом 3 млн.
    final scale = AiFactMath.scaleOf(world.deals.map((deal) => deal.amount));

    final lastTouch = <String, DateTime>{};
    for (final touch in world.interactions) {
      final known = lastTouch[touch.clientId];
      if (known == null || touch.at.isAfter(known)) {
        lastTouch[touch.clientId] = touch.at;
      }
    }
    final clientById = {for (final c in world.clients) c.id: c};
    final openDealsByClient = <String, List<CrmDeal>>{};
    for (final deal in world.deals.where((deal) => deal.isOpen)) {
      openDealsByClient.putIfAbsent(deal.clientId, () => []).add(deal);
    }

    for (final client in world.clients) {
      if (client.status == CrmClientStatus.archived) continue;

      final pipeline = (openDealsByClient[client.id] ?? const <CrmDeal>[])
          .fold<double>(0, (sum, deal) => sum + deal.amount);
      final money = AiFactMath.moneyWeight(pipeline, scale);

      final next = client.nextContactAt;
      if (next != null && next.isBefore(now)) {
        final late = max(1, AiFactMath.daysBetween(next, now));
        final urgency = AiFactMath.blend(AiFactMath.lateness(late), money);
        facts.add(WesiAiFact(
          kind: AiFactKind.clientFollowUpOverdue,
          category: AiTaskCategory.customer,
          subjectId: client.id,
          subjectTitle: client.displayName,
          title: 'Связаться: ${client.displayName}',
          description: 'Контакт был назначен на ${_date(next)} и не состоялся. '
              'Вернуть разговор в работу и назначить следующий шаг.',
          urgency: urgency,
          deadline: _soon(now, urgency),
          ownerEmployeeId: client.ownerEmployeeId,
          roleAliases: const ['менеджер', 'manager', 'sales', 'продажи'],
          whyNow: 'Назначенный контакт просрочен на ${AiFactMath.days(late)}.',
          evidence: [
            'Контакт был назначен на ${_date(next)}',
            if (pipeline > 0)
              'В работе сделок на ${_money(pipeline)}'
            else if (lastTouch[client.id] != null)
              'Последнее касание: ${_date(lastTouch[client.id]!)}',
          ],
          impact: pipeline > 0
              ? AiForecastImpact.high
              : AiForecastImpact.medium,
          effortPoints: .5,
          money: pipeline,
        ));
        continue;
      }

      // Клиент заведён, но разговора не было ни разу. Это не «когда-нибудь
      // напомним», это незакрытый вход в воронку.
      //
      // Сделка, ушедшая дальше первой стадии, сама по себе доказывает, что
      // разговор был: касания просто не завели в карточку. Объявлять такого
      // клиента «нетронутым» — значит спорить с очевидным.
      final working = (openDealsByClient[client.id] ?? const <CrmDeal>[])
          .any((deal) => deal.stage != DealStage.newLead);
      final touched = lastTouch.containsKey(client.id);
      if (!touched &&
          !working &&
          next == null &&
          client.status != CrmClientStatus.paused) {
        final age = AiFactMath.daysBetween(client.createdAt, now);
        if (age >= 3) {
          // Остывший лид — это повод вернуться к нему, а не тревога. Через
          // три месяца молчания он не становится срочнее всего в компании,
          // поэтому верхняя граница здесь ниже, чем у просрочек по срокам.
          final urgency = AiFactMath.blend(
                  AiFactMath.lateness(age, halfLife: 10), money)
              .clamp(0.0, .62)
              .toDouble();
          facts.add(WesiAiFact(
            kind: AiFactKind.clientNeverContacted,
            category: AiTaskCategory.customer,
            subjectId: client.id,
            subjectTitle: client.displayName,
            title: 'Первый контакт: ${client.displayName}',
            description:
                'Клиент заведён ${AiFactMath.days(age)} назад, но ни одного '
                'касания в карточке нет. Провести первый разговор и назначить '
                'дату следующего.',
            urgency: urgency,
            deadline: _soon(now, urgency),
            ownerEmployeeId: client.ownerEmployeeId,
            roleAliases: const ['менеджер', 'manager', 'sales', 'продажи'],
            whyNow:
                'Карточка заведена, но работа по ней ещё ни разу не началась.',
            evidence: [
              'Заведён: ${_date(client.createdAt)}',
              'Касаний в карточке: 0',
            ],
            impact: AiForecastImpact.medium,
            effortPoints: .5,
            money: pipeline,
          ));
        }
      }
    }

    for (final deal in world.deals) {
      if (!deal.isOpen) continue;
      final client = clientById[deal.clientId];
      final name = client?.displayName ?? deal.clientId;
      final money = AiFactMath.moneyWeight(deal.amount, scale);
      final label = deal.amount > 0
          ? '«${deal.title}» (${_money(deal.amount)})'
          : '«${deal.title}»';

      final close = deal.expectedCloseAt;
      if (close != null && close.isBefore(now)) {
        final late = max(1, AiFactMath.daysBetween(close, now));
        final urgency = AiFactMath.blend(
          AiFactMath.lateness(late, halfLife: 5),
          money,
          moneyShare: .38,
        );
        facts.add(WesiAiFact(
          kind: AiFactKind.dealCloseDatePassed,
          category: AiTaskCategory.sales,
          subjectId: deal.id,
          subjectTitle: deal.title,
          title: 'Закрыть сделку $label',
          description:
              'Сделка с «$name» должна была закрыться ${_date(close)}, но всё '
              'ещё на стадии «${_stage(deal.stage)}». Уточнить решение или '
              'перенести срок осознанно.',
          urgency: urgency,
          deadline: _soon(now, urgency),
          ownerEmployeeId: deal.responsibleEmployeeId ?? client?.ownerEmployeeId,
          roleAliases: const ['менеджер', 'manager', 'sales', 'продажи'],
          whyNow: 'Срок закрытия прошёл ${AiFactMath.days(late)} назад.',
          evidence: [
            'Ожидаемое закрытие: ${_date(close)}',
            'Стадия сейчас: ${_stage(deal.stage)}',
            if (deal.amount > 0) 'Сумма сделки: ${_money(deal.amount)}',
          ],
          impact: money >= .5
              ? AiForecastImpact.critical
              : AiForecastImpact.high,
          effortPoints: 1,
          money: deal.amount,
        ));
        continue;
      }

      // Застой считается от последнего касания именно по этому клиенту, а не
      // от даты создания сделки: сделка может быть старой и при этом живой.
      final touch = lastTouch[deal.clientId] ?? deal.updatedAt;
      final silence = AiFactMath.daysBetween(touch, now);
      final advanced = deal.stage != DealStage.newLead;
      if (silence >= dealSilenceDays && advanced) {
        final urgency = AiFactMath.blend(
          AiFactMath.lateness(silence - dealSilenceDays + 1, halfLife: 8),
          money,
          moneyShare: .40,
        );
        facts.add(WesiAiFact(
          kind: AiFactKind.dealStalled,
          category: AiTaskCategory.sales,
          subjectId: deal.id,
          subjectTitle: deal.title,
          title: 'Сдвинуть сделку $label',
          description:
              'По «$name» нет касаний ${AiFactMath.days(silence)}, а сделка '
              'уже на стадии «${_stage(deal.stage)}». Напомнить о себе и '
              'договориться о следующем шаге.',
          urgency: urgency,
          deadline: _soon(now, urgency),
          ownerEmployeeId: deal.responsibleEmployeeId ?? client?.ownerEmployeeId,
          roleAliases: const ['менеджер', 'manager', 'sales', 'продажи'],
          whyNow: 'Сделка на активной стадии стоит без движения.',
          evidence: [
            'Последнее касание: ${_date(touch)}',
            'Стадия: ${_stage(deal.stage)}, вероятность ${deal.probability}%',
            if (deal.amount > 0) 'Сумма сделки: ${_money(deal.amount)}',
          ],
          impact: money >= .5 ? AiForecastImpact.high : AiForecastImpact.medium,
          effortPoints: .8,
          money: deal.amount,
        ));
        continue;
      }

      // Дорогая сделка без ответственного — это не «мелочь оформления»:
      // ровно такие сделки и теряются, потому что каждый думает на другого.
      if ((deal.responsibleEmployeeId ?? '').isEmpty &&
          (client?.ownerEmployeeId ?? '').isEmpty &&
          money >= .5) {
        facts.add(WesiAiFact(
          kind: AiFactKind.dealWithoutOwner,
          category: AiTaskCategory.sales,
          subjectId: deal.id,
          subjectTitle: deal.title,
          title: 'Назначить ответственного за сделку $label',
          description:
              'У сделки с «$name» нет ответственного, поэтому за неё никто не '
              'отвечает по умолчанию. Закрепить человека и следующий шаг.',
          urgency: AiFactMath.blend(.45, money, moneyShare: .5),
          deadline: _after(now, 2),
          roleAliases: const ['менеджер', 'manager', 'sales', 'продажи'],
          whyNow: 'Крупная для этой организации сделка идёт без владельца.',
          evidence: [
            'Сумма сделки: ${_money(deal.amount)}',
            'Ответственный не назначен',
          ],
          impact: AiForecastImpact.high,
          effortPoints: .3,
          money: deal.amount,
        ));
      }
    }
    return facts;
  }

  // ---------------------------------------------------------- дорожная карта

  static List<WesiAiFact> _roadmapFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    final projectById = {for (final p in world.projects) p.id: p};

    for (final item in world.roadmapItems) {
      final project = projectById[item.projectId];
      if (project != null && project.archived) continue;
      if (item.status == RoadmapItemStatus.done || item.progress >= 100) {
        continue;
      }
      final where = project == null ? '' : ' · ${project.title}';
      final kindWord =
          item.kind == RoadmapItemKind.milestone ? 'Веха' : 'Этап';

      if (item.status == RoadmapItemStatus.blocked) {
        final stuck = max(1, AiFactMath.daysBetween(item.updatedAt, now));
        if (stuck >= 3) {
          final urgency = AiFactMath.lateness(stuck, halfLife: 7);
          facts.add(WesiAiFact(
            kind: AiFactKind.roadmapItemBlocked,
            category: AiTaskCategory.product,
            subjectId: item.id,
            subjectTitle: item.title,
            title: 'Разблокировать: «${item.title}»',
            description:
                '$kindWord «${item.title}»$where стоит в статусе «заблокировано» '
                '${AiFactMath.days(stuck)}. Разобрать причину и снять блок или '
                'перенести срок.',
            urgency: urgency,
            deadline: _soon(now, urgency),
            ownerEmployeeId: _employeeRef(item.assignee),
            roleAliases: const ['менеджер', 'manager', 'руководитель', 'lead'],
            whyNow: 'Блок держится дольше, чем это можно считать рабочим.',
            evidence: [
              'В блоке с ${_date(item.updatedAt)}',
              'Готовность: ${item.progress}%',
            ],
            impact: AiForecastImpact.high,
            effortPoints: 1,
          ));
          continue;
        }
      }

      final late = AiFactMath.daysBetween(item.endDate, now);
      if (late > 0) {
        // Просрочка при высокой готовности — это «дожать», при нулевой —
        // «пересобрать план». Это разные задачи, и текст должен различаться.
        final urgency = AiFactMath.lateness(late, halfLife: 5) *
            (item.progress >= 70 ? .85 : 1.0);
        facts.add(WesiAiFact(
          kind: AiFactKind.roadmapItemOverdue,
          category: AiTaskCategory.product,
          subjectId: item.id,
          subjectTitle: item.title,
          title: item.progress >= 70
              ? 'Дожать: «${item.title}»'
              : 'Пересобрать срок: «${item.title}»',
          description: item.progress >= 70
              ? '$kindWord «${item.title}»$where просрочен на '
                  '${AiFactMath.days(late)} при готовности ${item.progress}%. '
                  'Закрыть остаток и отметить выполнение.'
              : '$kindWord «${item.title}»$where просрочен на '
                  '${AiFactMath.days(late)}, готовность ${item.progress}%. '
                  'Разобрать, что мешает, и назначить реальный срок.',
          urgency: urgency,
          deadline: _soon(now, urgency),
          ownerEmployeeId: _employeeRef(item.assignee),
          roleAliases: const ['менеджер', 'manager', 'руководитель', 'lead'],
          whyNow: 'Срок по плану прошёл, а работа не закрыта.',
          evidence: [
            'Срок по плану: ${_date(item.endDate)}',
            'Готовность: ${item.progress}%',
            if (project != null) 'Проект: ${project.title}',
          ],
          impact: item.kind == RoadmapItemKind.milestone
              ? AiForecastImpact.high
              : AiForecastImpact.medium,
          effortPoints: item.progress >= 70 ? 1 : 1.5,
        ));
        continue;
      }

      // Срок ещё не прошёл, но при нынешней готовности успеть уже нельзя.
      // Предупредить сейчас дешевле, чем зафиксировать провал потом.
      final left = -late;
      if (left <= 5 && item.progress < 60) {
        final urgency = AiFactMath.approaching(left, horizon: 7) *
            (1 - item.progress / 140);
        if (urgency >= .30) {
          facts.add(WesiAiFact(
            kind: AiFactKind.roadmapDeadlineNear,
            category: AiTaskCategory.product,
            subjectId: item.id,
            subjectTitle: item.title,
            title: 'Успеть в срок: «${item.title}»',
            description:
                '$kindWord «${item.title}»$where должен быть готов через '
                '${AiFactMath.days(left)}, а готовность ${item.progress}%. '
                'Либо усилить, либо честно перенести срок сейчас.',
            urgency: urgency,
            deadline: item.endDate,
            ownerEmployeeId: _employeeRef(item.assignee),
            roleAliases: const ['менеджер', 'manager', 'руководитель', 'lead'],
            whyNow: 'При текущей готовности срок под угрозой.',
            evidence: [
              'Срок: ${_date(item.endDate)} (через ${AiFactMath.days(left)})',
              'Готовность: ${item.progress}%',
            ],
            impact: AiForecastImpact.medium,
            effortPoints: 1,
          ));
        }
      }
    }
    return facts;
  }

  // ------------------------------------------------------------------- биты

  static const _readyStages = {
    BeatStage.ready,
    BeatStage.negotiating,
    BeatStage.leased,
    BeatStage.sold,
    BeatStage.exclusive,
  };

  static const _inWorkStages = {
    BeatStage.draft,
    BeatStage.production,
    BeatStage.mixing,
    BeatStage.mastering,
  };

  static List<WesiAiFact> _beatFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    final leaseScale = AiFactMath.scaleOf(
      world.beats.map((beat) => beat.lease?.amount ?? 0),
    );

    for (final beat in world.beats) {
      if (beat.stage == BeatStage.archived) continue;

      final lease = beat.lease;
      if (lease != null) {
        final left = AiFactMath.daysBetween(now, lease.endsAt);
        final money = AiFactMath.moneyWeight(lease.amount, leaseScale);
        if (left < 0) {
          final over = -left;
          final urgency = AiFactMath.blend(
            AiFactMath.lateness(over, halfLife: 4),
            money,
          );
          facts.add(WesiAiFact(
            kind: AiFactKind.leaseExpired,
            category: AiTaskCategory.sales,
            subjectId: beat.id,
            subjectTitle: beat.title,
            title: 'Лицензия истекла: «${beat.title}» — ${lease.artistName}',
            description:
                'Срок лицензии закончился ${_date(lease.endsAt)}. Решить: '
                'продлевать, отпускать бит обратно в каталог или переводить '
                'в эксклюзив.',
            urgency: urgency,
            deadline: _soon(now, urgency),
            ownerEmployeeId: _employeeRef(beat.authorEmployeeId),
            roleAliases: const ['менеджер', 'manager', 'продюсер', 'producer'],
            whyNow: 'Лицензия закончилась ${AiFactMath.days(over)} назад.',
            evidence: [
              'Артист: ${lease.artistName}',
              'Срок закончился: ${_date(lease.endsAt)}',
              if (lease.amount > 0) 'Сумма лицензии: ${_money(lease.amount)}',
            ],
            impact: AiForecastImpact.high,
            effortPoints: .5,
            money: lease.amount,
          ));
        } else if (left <= 14) {
          final urgency =
              AiFactMath.blend(AiFactMath.approaching(left), money);
          facts.add(WesiAiFact(
            kind: AiFactKind.leaseExpiring,
            category: AiTaskCategory.sales,
            subjectId: beat.id,
            subjectTitle: beat.title,
            title: 'Продление лицензии: «${beat.title}» — ${lease.artistName}',
            description:
                'Лицензия заканчивается ${_date(lease.endsAt)}. Предложить '
                'продление заранее — после окончания разговор начинается '
                'с нуля.',
            urgency: urgency,
            deadline: lease.endsAt,
            ownerEmployeeId: _employeeRef(beat.authorEmployeeId),
            roleAliases: const ['менеджер', 'manager', 'продюсер', 'producer'],
            whyNow: 'До конца лицензии ${AiFactMath.days(left)}.',
            evidence: [
              'Артист: ${lease.artistName}',
              'Действует до: ${_date(lease.endsAt)}',
              if (lease.amount > 0) 'Сумма лицензии: ${_money(lease.amount)}',
            ],
            impact: AiForecastImpact.high,
            effortPoints: .5,
            money: lease.amount,
          ));
        }
      }

      final ready = _readyStages.contains(beat.stage);
      if (ready && (beat.coverPath == null || beat.coverPath!.trim().isEmpty)) {
        final age = max(1, AiFactMath.daysBetween(beat.updatedAt, now));
        facts.add(WesiAiFact(
          kind: AiFactKind.beatMissingCover,
          category: AiTaskCategory.design,
          subjectId: beat.id,
          subjectTitle: beat.title,
          title: 'Обложка для бита «${beat.title}»',
          description:
              'Бит готов (${_beatStage(beat.stage)}), но обложки нет — его '
              'нельзя выложить и нельзя показать артисту в нормальном виде. '
              'Сделать превью в фирменном стиле.',
          // Потолок сознательно ниже тревоги: без обложки бит не выложить,
          // это мешает, но никого не подводит и никому не стоит денег
          // прямо сейчас.
          urgency: AiFactMath.lateness(age, halfLife: 9).clamp(.35, .68),
          deadline: _after(now, 3),
          roleAliases: const ['дизайнер', 'designer', 'art', 'graphic'],
          whyNow: 'Готовый бит нельзя показать без обложки.',
          evidence: [
            'Стадия: ${_beatStage(beat.stage)}',
            'Обложка не приложена',
            if (beat.bpm > 0) 'BPM ${beat.bpm}, тональность '
                '${beat.musicalKey.isEmpty ? "не указана" : beat.musicalKey}',
          ],
          impact: AiForecastImpact.medium,
          effortPoints: 1.5,
        ));
      }

      if (ready && (beat.wavPath == null || beat.wavPath!.trim().isEmpty)) {
        facts.add(WesiAiFact(
          kind: AiFactKind.beatMissingMaster,
          category: AiTaskCategory.production,
          subjectId: beat.id,
          subjectTitle: beat.title,
          title: 'Экспорт WAV для бита «${beat.title}»',
          description:
              'Бит помечен как ${_beatStage(beat.stage)}, но WAV не приложен. '
              'По лицензии отдать нечего — подготовить мастер-файл.',
          urgency: beat.stage == BeatStage.ready ? .62 : .88,
          deadline: _after(now, 2),
          ownerEmployeeId: _employeeRef(beat.authorEmployeeId),
          roleAliases: const [
            'битмейкер',
            'beatmaker',
            'продюсер',
            'producer',
            'звукорежиссер',
          ],
          whyNow: beat.stage == BeatStage.ready
              ? 'Готовый бит без мастер-файла нельзя продать.'
              : 'Бит уже отдан артисту, а мастер-файла нет.',
          evidence: [
            'Стадия: ${_beatStage(beat.stage)}',
            'WAV не приложен',
          ],
          impact: beat.stage == BeatStage.ready
              ? AiForecastImpact.medium
              : AiForecastImpact.critical,
          effortPoints: 1,
        ));
      }

      if (_inWorkStages.contains(beat.stage)) {
        final still = AiFactMath.daysBetween(beat.updatedAt, now);
        if (still >= beatStallDays) {
          facts.add(WesiAiFact(
            kind: AiFactKind.beatStalled,
            category: AiTaskCategory.production,
            subjectId: beat.id,
            subjectTitle: beat.title,
            title: 'Вернуться к биту «${beat.title}»',
            description:
                'Бит стоит на стадии «${_beatStage(beat.stage)}» '
                '${AiFactMath.days(still)} без правок. Довести до готовности '
                'или осознанно отправить в архив.',
            // Самый спокойный повод во всём наборе: незаконченный черновик
            // никого не подводит и ничего не срывает. Поэтому его потолок
            // ниже порога, за которым система перестаёт слушать отказы, —
            // если такие напоминания раздражают, они замолкают насовсем.
            urgency: AiFactMath.lateness(still - beatStallDays + 1,
                    halfLife: 14)
                .clamp(.30, .50),
            deadline: _after(now, 5),
            ownerEmployeeId: _employeeRef(beat.authorEmployeeId),
            roleAliases: const [
              'битмейкер',
              'beatmaker',
              'продюсер',
              'producer',
            ],
            whyNow: 'Незавершённый материал копится и не приносит ничего.',
            evidence: [
              'Последняя правка: ${_date(beat.updatedAt)}',
              'Стадия: ${_beatStage(beat.stage)}',
            ],
            impact: AiForecastImpact.low,
            effortPoints: 2.5,
          ));
        }
      }
    }
    return facts;
  }

  // ----------------------------------------------------------------- задачи

  static List<WesiAiFact> _taskFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    for (final task in world.tasks) {
      if (task.status == TaskStatus.done) continue;
      // Задача, которая сама выросла из наблюдения о задаче, не должна
      // порождать следующее такое же: иначе «разобрать просроченное» через
      // неделю станет поводом разобрать «разобрать просроченное».
      if (task.tags.any((tag) => tag.startsWith('wesi-ai:fact:task'))) {
        continue;
      }
      final due = task.dueDate;

      if (due != null) {
        final late = AiFactMath.daysBetween(due, now);
        // Просрочка в один день — обычное дело и разбирается сама. Повод
        // появляется, когда задача просрочена настолько, что о ней забыли.
        if (late >= 3) {
          facts.add(WesiAiFact(
            kind: AiFactKind.taskOverdue,
            category: AiTaskCategory.operations,
            subjectId: task.id,
            subjectTitle: task.title,
            title: 'Разобрать просроченное: «${task.title}»',
            description:
                'Задача просрочена на ${AiFactMath.days(late)} и не двигается. '
                'Закрыть, переназначить или перенести срок — но не оставлять '
                'висеть.',
            urgency: AiFactMath.lateness(late, halfLife: 7).clamp(.30, .90),
            deadline: _after(now, 1),
            ownerEmployeeId: _employeeRef(task.effectiveResponsibleEmployeeId),
            roleAliases: const ['менеджер', 'manager', 'руководитель', 'lead'],
            whyNow: 'Просроченная задача тянет за собой оценку всей загрузки.',
            evidence: [
              'Срок был: ${_date(due)}',
              'Статус: ${_status(task.status)}',
            ],
            impact: AiForecastImpact.medium,
            effortPoints: .3,
          ));
          continue;
        }
      }

      if (task.status == TaskStatus.review) {
        // Момент перехода в проверку задача не хранит, поэтому единственная
        // честная опора — её возраст. Так и написано в основании: система не
        // утверждает того, чего не знает.
        final age = AiFactMath.daysBetween(task.createdAt, now);
        if (age >= 5) {
          facts.add(WesiAiFact(
            kind: AiFactKind.taskStuckInReview,
            category: AiTaskCategory.quality,
            subjectId: task.id,
            subjectTitle: task.title,
            title: 'Проверить и закрыть: «${task.title}»',
            description:
                'Задача стоит на проверке. Работа уже сделана — без ответа '
                'она просто не считается сделанной.',
            urgency:
                AiFactMath.lateness(age - 4, halfLife: 6).clamp(.35, .80),
            deadline: _after(now, 1),
            roleAliases: const ['руководитель', 'lead', 'менеджер', 'manager'],
            whyNow: 'Работа ждёт проверки, а задача заведена '
                '${AiFactMath.days(age)} назад.',
            evidence: [
              'Заведена: ${_date(task.createdAt)}',
              'Статус: на проверке',
            ],
            impact: AiForecastImpact.medium,
            effortPoints: .3,
          ));
        }
        continue;
      }

      // Задача со сроком, но без ответственного — самый частый способ
      // «потерять» работу: срок наступит, а спросить будет не с кого.
      if (due != null &&
          (task.effectiveResponsibleEmployeeId ?? '').trim().isEmpty) {
        final left = AiFactMath.daysBetween(now, due);
        if (left >= 0 && left <= 7) {
          facts.add(WesiAiFact(
            kind: AiFactKind.taskWithoutOwner,
            category: AiTaskCategory.operations,
            subjectId: task.id,
            subjectTitle: task.title,
            title: 'Назначить исполнителя: «${task.title}»',
            description:
                'У задачи есть срок (${_date(due)}), но нет ответственного. '
                'Закрепить человека, пока срок не наступил.',
            urgency: AiFactMath.approaching(left, horizon: 8).clamp(.30, .85),
            deadline: due,
            roleAliases: const ['менеджер', 'manager', 'руководитель', 'lead'],
            whyNow: 'Срок приближается, а ответственного нет.',
            evidence: [
              'Срок: ${_date(due)}',
              'Ответственный не назначен',
            ],
            impact: AiForecastImpact.medium,
            effortPoints: .2,
          ));
        }
      }
    }
    return facts;
  }

  // ------------------------------------------------------------------ файлы

  static List<WesiAiFact> _fileFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    for (final request in world.fileRequests) {
      if (!request.isOpen) continue;
      final waiting = AiFactMath.daysBetween(request.createdAt, now);
      if (waiting < 2) continue;
      facts.add(WesiAiFact(
        kind: AiFactKind.fileRequestWaiting,
        category: AiTaskCategory.operations,
        subjectId: request.id,
        subjectTitle: request.subjectId,
        title: 'Ответить на запрос файла',
        description:
            'Запрос на файл ждёт решения ${AiFactMath.days(waiting)}. '
            'Отдать файл или отказать с причиной — молчание тормозит работу '
            'другого человека.',
        urgency: AiFactMath.lateness(waiting - 1, halfLife: 3).clamp(.35, .88),
        deadline: _after(now, 1),
        ownerEmployeeId: _employeeRef(request.holderId),
        roleAliases: const [],
        whyNow: 'Человек ждёт файл ${AiFactMath.days(waiting)}.',
        evidence: [
          'Запрошено: ${_date(request.createdAt)}',
          'Запросил: ${request.requesterId}',
        ],
        impact: AiForecastImpact.medium,
        effortPoints: .2,
      ));
    }
    return facts;
  }

  // ---------------------------------------------------------------- финансы

  static List<WesiAiFact> _financeFacts(WesiAiWorldState world, DateTime now) {
    final facts = <WesiAiFact>[];
    final recurring = world.transactions
        .where((tx) => tx.isRecurring && tx.recurringPeriod != null)
        .toList();
    if (recurring.isEmpty) return facts;

    final scale = AiFactMath.scaleOf(recurring.map((tx) => tx.amount));
    for (final tx in recurring) {
      if (tx.type != TransactionType.expense) continue;
      final anchor = tx.recurringAnchorDate;
      final next = RecurringEngine.nextOccurrenceAfter(
        anchor,
        tx.recurringPeriod!,
        now.subtract(const Duration(days: 1)),
      );
      final left = AiFactMath.daysBetween(now, next);
      if (left < 0 || left > 3) continue;
      // Крупный по меркам организации регулярный платёж на носу — это повод
      // проверить, что деньги на него есть, а не узнать об этом постфактум.
      final money = AiFactMath.moneyWeight(tx.amount, scale);
      if (money < .45) continue;
      facts.add(WesiAiFact(
        kind: AiFactKind.recurringPaymentDue,
        category: AiTaskCategory.finance,
        subjectId: tx.id,
        subjectTitle: tx.title,
        title: 'Обеспечить платёж: ${tx.title}',
        description:
            'Регулярный платёж «${tx.title}» на ${_money(tx.amount)} '
            'наступает ${_date(next)}. Проверить, что средства на счёте есть.',
        urgency: AiFactMath.blend(
          AiFactMath.approaching(left, horizon: 4),
          money,
          moneyShare: .35,
        ),
        deadline: next,
        roleAliases: const ['бухгалтер', 'финанс', 'finance', 'руководитель'],
        whyNow: left == 0
            ? 'Платёж наступает сегодня.'
            : 'До платежа ${AiFactMath.days(left)}.',
        evidence: [
          'Дата платежа: ${_date(next)}',
          'Сумма: ${_money(tx.amount)}',
        ],
        impact: AiForecastImpact.high,
        effortPoints: .3,
        money: tx.amount,
      ));
    }
    return facts;
  }

  // ------------------------------------------------------------ вспомогательное

  /// Срок для «сделать сейчас»: чем срочнее, тем ближе, но не в прошлом.
  static DateTime _soon(DateTime now, double urgency) {
    final days = urgency >= .80
        ? 1
        : urgency >= .55
            ? 2
            : 4;
    return _after(now, days);
  }

  static DateTime _after(DateTime now, int days) =>
      DateTime(now.year, now.month, now.day).add(Duration(days: days));

  static String? _employeeRef(String? raw) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  static String _money(double value) {
    final rounded = value.round().abs();
    final text = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    return '${value < 0 ? '-' : ''}$buffer ₽';
  }

  static String _stage(DealStage stage) => switch (stage) {
        DealStage.newLead => 'новый лид',
        DealStage.qualification => 'квалификация',
        DealStage.proposal => 'предложение',
        DealStage.negotiation => 'переговоры',
        DealStage.won => 'выиграна',
        DealStage.lost => 'проиграна',
      };

  static String _beatStage(BeatStage stage) => switch (stage) {
        BeatStage.idea => 'идея',
        BeatStage.draft => 'черновик',
        BeatStage.production => 'продакшн',
        BeatStage.mixing => 'сведение',
        BeatStage.mastering => 'мастеринг',
        BeatStage.ready => 'готов',
        BeatStage.negotiating => 'переговоры',
        BeatStage.leased => 'в лицензии',
        BeatStage.sold => 'продан',
        BeatStage.exclusive => 'эксклюзив',
        BeatStage.archived => 'архив',
      };

  static String _status(TaskStatus status) => switch (status) {
        TaskStatus.backlog => 'в очереди',
        TaskStatus.inProgress => 'в работе',
        TaskStatus.review => 'на проверке',
        TaskStatus.done => 'готова',
      };
}
