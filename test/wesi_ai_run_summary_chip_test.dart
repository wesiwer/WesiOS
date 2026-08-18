import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_run_summary_chip.dart';

void main() {
  const timeline = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'r1',
      'kind': 'tool',
      'label': 'Инструмент · finance_summary',
      'sourceName': 'finance_summary',
      'status': 'result',
      'ok': true,
      'module': 'treasury',
    },
    <String, dynamic>{
      'id': 'w1',
      'kind': 'tool',
      'label': 'Инструмент · tasks_create',
      'sourceName': 'tasks_create',
      'detail': 'Проверить рекламу',
      'status': 'result',
      'ok': true,
      'mutation': true,
      'module': 'tasks',
    },
    <String, dynamic>{
      'id': 'w2',
      'kind': 'tool',
      'label': 'Инструмент · tasks_update',
      'sourceName': 'tasks_update',
      'status': 'result',
      'ok': false,
      'mutation': true,
      'module': 'tasks',
    },
  ];

  test('в итог идут только применённые изменения', () {
    final changes = runChangesFrom(timeline);
    expect(changes, hasLength(1),
        reason: 'чтение или неудачная правка попали в итог');
    expect(changes.single.label, 'tasks_create');
    expect(changes.single.module, 'tasks');
  });

  test('без изменений итога нет', () {
    final readOnly = runChangesFrom([timeline.first]);
    expect(readOnly, isEmpty);
  });

  test('человеческие названия покрывают инженерный длинный проход', () {
    expect(moduleTitle('treasury'), 'Казна');
    expect(moduleTitle('tasks'), 'Задачи');
    expect(moduleTitle('github'), 'GitHub');
    expect(moduleTitle('git'), 'GitHub');
    expect(moduleTitle('deploy'), 'Deploy');
    expect(moduleTitle('sync'), 'Синхронизация');
    expect(moduleTitle('files'), 'Файлы');
    expect(moduleTitle('security'), 'Безопасность');
    expect(moduleTitle('придуманный_модуль'), 'придуманный_модуль');
    expect(moduleTitle(''), 'WesiOS');
  });

  test('изменения группируются по модулю и синонимы объединяются', () {
    final groups = runGroupsFromChanges(const <WesiAiRunChange>[
      WesiAiRunChange(label: 'create_pr', module: 'github'),
      WesiAiRunChange(label: 'merge_pr', module: 'git'),
      WesiAiRunChange(label: 'tasks_create', module: 'tasks'),
      WesiAiRunChange(label: 'deploy_prod', module: 'deploy'),
    ]);
    expect(groups, hasLength(3));
    expect(groups[0].title, 'GitHub');
    expect(groups[0].count, 2);
    expect(groups[1].title, 'Задачи');
    expect(groups[1].count, 1);
    expect(groups[2].title, 'Deploy');
  });

  Future<void> pump(WidgetTester tester, List<WesiAiRunChange> changes) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WesiAiRunSummaryChip(changes: changes)),
      ));

  testWidgets('плашка показывает счётчик и открывает итог прохода',
      (tester) async {
    await pump(tester, runChangesFrom(timeline));
    expect(find.textContaining('Изменено · Задачи'), findsOneWidget);
    expect(find.text('· 1'), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.text('Итог прохода'), findsOneWidget);
    expect(find.text('Задачи · 1'), findsOneWidget);
    expect(find.text('tasks_create'), findsOneWidget);
    expect(find.textContaining('Проверить рекламу'), findsOneWidget);
  });

  testWidgets('без изменений плашки не видно', (tester) async {
    await pump(tester, const <WesiAiRunChange>[]);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('несколько модулей показываются группами с отдельными счётчиками',
      (tester) async {
    await pump(tester, const <WesiAiRunChange>[
      WesiAiRunChange(label: 'create_pr', module: 'github'),
      WesiAiRunChange(label: 'merge_pr', module: 'git'),
      WesiAiRunChange(label: 'tasks_create', module: 'tasks'),
      WesiAiRunChange(label: 'deploy_prod', module: 'deploy'),
    ]);
    expect(find.text('Изменено за проход'), findsOneWidget);
    expect(find.text('· 4'), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.text('GitHub · 2'), findsOneWidget);
    expect(find.text('Задачи · 1'), findsOneWidget);
    expect(find.text('Deploy · 1'), findsOneWidget);
    expect(find.text('4 изменения · 3 модуля'), findsOneWidget);
  });
}
