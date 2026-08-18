import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_run_summary_chip.dart';

// Итог прохода отвечает на вопрос «что он поменял», а не «сколько работал».
//
// В длинном проходе шагов два десятка, и прокручивать ход мыслей ради этого
// ответа — работа. Поэтому в плашку идут только применённые изменения:
// чтения и неудачные попытки в счёт не берутся, иначе число рядом со
// значком перестаёт что-либо означать.
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
    expect(changes, hasLength(1), reason: 'чтение или неудачная правка попали в итог');
    expect(changes.single.label, 'tasks_create');
    expect(changes.single.module, 'tasks');
  });

  test('без изменений итога нет', () {
    final readOnly = runChangesFrom([timeline.first]);
    expect(readOnly, isEmpty);
  });

  test('модуль назван по-русски, незнакомый остаётся как есть', () {
    expect(moduleTitle('treasury'), 'Казна');
    expect(moduleTitle('tasks'), 'Задачи');
    expect(moduleTitle('придуманный_модуль'), 'придуманный_модуль');
    expect(moduleTitle(''), 'WesiOS');
  });

  Future<void> pump(WidgetTester tester, List<WesiAiRunChange> changes) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WesiAiRunSummaryChip(changes: changes)),
      ));

  testWidgets('плашка показывает счётчик и открывает список', (tester) async {
    await pump(tester, runChangesFrom(timeline));
    expect(find.textContaining('Изменено · Задачи'), findsOneWidget);
    expect(find.text('· 1'), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.text('Что изменил проход'), findsOneWidget);
    expect(find.text('tasks_create'), findsOneWidget);
    expect(find.textContaining('Проверить рекламу'), findsOneWidget);
  });

  testWidgets('без изменений плашки не видно', (tester) async {
    await pump(tester, const <WesiAiRunChange>[]);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('изменения в разных модулях подписаны обобщённо',
      (tester) async {
    await pump(tester, const <WesiAiRunChange>[
      WesiAiRunChange(label: 'tasks_create', module: 'tasks'),
      WesiAiRunChange(label: 'finance_transaction_create', module: 'treasury'),
    ]);
    expect(find.text('Изменения за проход'), findsOneWidget);
    expect(find.text('· 2'), findsOneWidget);
  });
}
