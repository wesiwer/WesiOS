import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/what_if_store.dart';

void main() {
  group('TaskModel', () {
    TaskModel make({
      DateTime? due,
      TaskStatus status = TaskStatus.backlog,
      List<SubTask> subtasks = const [],
    }) =>
        TaskModel(
          id: 't',
          title: 'task',
          status: status,
          createdAt: DateTime(2026, 1, 1),
          dueDate: due,
          subtasks: subtasks,
        );

    test('a past due date marks the task overdue', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      expect(make(due: past).isOverdue, isTrue);
    });

    test('a finished task is never overdue — otherwise the board turns red '
        'from work that is already done', () {
      final past = DateTime.now().subtract(const Duration(days: 30));
      expect(make(due: past, status: TaskStatus.done).isOverdue, isFalse);
    });

    test('today is due-today, not overdue', () {
      final t = make(due: DateTime.now());
      expect(t.isDueToday, isTrue);
      expect(t.isOverdue, isFalse);
    });

    test('no due date means neither overdue nor due today', () {
      final t = make();
      expect(t.isOverdue, isFalse);
      expect(t.isDueToday, isFalse);
    });

    test('checklist progress counts only finished items', () {
      final t = make(subtasks: const [
        SubTask(title: 'a', done: true),
        SubTask(title: 'b'),
        SubTask(title: 'c', done: true),
        SubTask(title: 'd'),
      ]);
      expect(t.checklistProgress, 0.5);
      expect(make().checklistProgress, 0);
    });

    test('copyWith(clearDueDate) actually clears it — a plain null argument '
        'is indistinguishable from "not passed" and would keep the old date',
        () {
      final t = make(due: DateTime(2026, 5, 1));
      expect(t.copyWith(dueDate: null).dueDate, isNotNull);
      expect(t.copyWith(clearDueDate: true).dueDate, isNull);
    });

    test('copyWith preserves id and createdAt', () {
      final t = make(due: DateTime(2026, 5, 1));
      final moved = t.copyWith(status: TaskStatus.done, order: 4);
      expect(moved.id, t.id);
      expect(moved.createdAt, t.createdAt);
      expect(moved.status, TaskStatus.done);
      expect(moved.order, 4);
    });
  });

  group('WhatIfPreset', () {
    WhatIfPreset preset(WhatIfScenario s) => WhatIfPreset(
          id: 'p1',
          name: 'План Б',
          scenario: s,
          createdAt: DateTime(2026, 2, 2),
        );

    test('round-trips through JSON with multipliers intact', () {
      final p = preset(const WhatIfScenario(
        incomeMultiplier: 0.8,
        expenseMultiplier: 1.3,
      ));
      final back = WhatIfPreset.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>)!;
      expect(back.id, 'p1');
      expect(back.name, 'План Б');
      expect(back.scenario.incomeMultiplier, closeTo(0.8, 1e-9));
      expect(back.scenario.expenseMultiplier, closeTo(1.3, 1e-9));
    });

    test('an event is stored as a day offset, so a saved scenario stays in the '
        'future instead of silently falling out of the forecast horizon once '
        'its hard-coded date passes', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final p = preset(WhatIfScenario(events: [
        WhatIfEvent(
          title: 'Закупка',
          amount: 50000,
          type: TransactionType.expense,
          date: today.add(const Duration(days: 14)),
        ),
      ]));

      final json = p.toJson();
      expect((json['events'] as List).first['dayOffset'], 14);

      final back = WhatIfPreset.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>)!;
      final e = back.scenario.events.single;
      expect(e.title, 'Закупка');
      expect(e.amount, 50000);
      expect(e.type, TransactionType.expense);
      expect(e.date.difference(today).inDays, 14);
      expect(e.date.isAfter(today), isTrue);
    });

    test('an offset that would land in the past is pulled forward to day 1 — '
        'the engine ignores events at or before today, so storing 0 or a '
        'negative offset would silently disable the scenario', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final p = preset(WhatIfScenario(events: [
        WhatIfEvent(
          title: 'Вчерашнее',
          amount: 100,
          type: TransactionType.income,
          date: today.subtract(const Duration(days: 5)),
        ),
      ]));
      expect((p.toJson()['events'] as List).first['dayOffset'], 1);
    });

    test('a malformed entry yields null instead of throwing — one corrupt '
        'record must not take the whole scenario list down', () {
      expect(WhatIfPreset.fromJson({'name': 'no id'}), isNull);
    });

    test('summary describes what the scenario changes', () {
      final ru = preset(const WhatIfScenario(
        incomeMultiplier: 0.8,
        expenseMultiplier: 1.2,
      )).summary('₽', true);
      expect(ru, contains('доходы -20%'));
      expect(ru, contains('расходы +20%'));

      final empty = preset(WhatIfScenario.none).summary('₽', true);
      expect(empty, 'Без изменений');
    });
  });
}
