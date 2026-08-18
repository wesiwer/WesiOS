import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  testWidgets('activity row opens full technical drilldown', (tester) async {
    final start = DateTime(2026, 8, 19, 8, 0, 0);
    final event = WesiAiActivityEvent(
      id: 'step-1',
      kind: WesiAiActivityKind.tool,
      label: 'Инструмент · github_write',
      detail: 'Обновляет два файла и проверяет результат.',
      status: 'result',
      sourceName: 'github_write',
      startedAt: start,
      completedAt: start.add(const Duration(seconds: 3)),
      additions: 12,
      deletions: 4,
      files: const ['lib/a.dart', 'test/a_test.dart'],
      input: '{"branch":"main","path":"lib/a.dart"}',
      output: '{"ok":true,"sha":"abc123"}',
      mutation: true,
      succeeded: true,
      module: 'github',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: WesiAiActivityRow(event: event)),
        ),
      ),
    );

    await tester.tap(find.text('Инструмент · github_write'));
    await tester.pumpAndSettle();

    expect(find.text('Успешно'), findsOneWidget);
    expect(find.text('3.0 с'), findsOneWidget);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('Что происходило'), findsOneWidget);
    expect(find.text('Изменения'), findsOneWidget);
    expect(find.text('+12'), findsWidgets);
    expect(find.text('-4'), findsWidgets);
    expect(find.text('Запрос'), findsOneWidget);
    expect(find.text('Ответ'), findsOneWidget);
    expect(find.textContaining('branch'), findsOneWidget);
    expect(find.textContaining('abc123'), findsOneWidget);
  });

  testWidgets('compact agent row keeps summary visible and opens sheet',
      (tester) async {
    const event = WesiAiActivityEvent(
      id: 'agent-1',
      kind: WesiAiActivityKind.agent,
      label: 'Зову специалиста · Security Reviewer',
      detail: 'Проверить права доступа и регрессии.',
      sourceName: 'Security Reviewer',
      status: 'start',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WesiAiActivityRow(event: event, compact: true),
        ),
      ),
    );

    expect(find.text('Проверить права доступа и регрессии.'), findsOneWidget);
    await tester.tap(find.text('Зову специалиста · Security Reviewer'));
    await tester.pumpAndSettle();
    expect(find.text('Выполняется'), findsOneWidget);
    expect(find.textContaining('Security Reviewer'), findsWidgets);
  });
}
