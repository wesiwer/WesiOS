import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/ai/widgets/wesi_ai_suggestion_card.dart';
import 'package:wesios/features/tasks/models/task_model.dart';

/// Кнопки предложения обязаны оставаться внутри карточки.
///
/// Утром этого дня они перестали нажиматься. Выглядели как обычно — и не
/// работали: в карточку добавилась строка со сроком, содержимое переросло
/// отведённую высоту и вытолкнуло ряд кнопок за пределы родителя, а Flutter
/// не ищет попадания за его границами. Человек видит кнопку и жмёт в
/// пустоту.
///
/// Тогда высоту просто увеличили. Это лечило симптом: любая следующая
/// строка — или включённый крупный шрифт — вернули бы всё обратно. Теперь
/// высоту первым забирает ряд кнопок, а содержимому достаётся остаток, и
/// вытолкнуть их нельзя в принципе. Здесь это проверяется нажатием.
void main() {
  AiTaskSuggestion suggestion({
    String title = 'Написать новый бит',
    String whyNow = 'Каталог перестал расти.',
    String strategicReason = '',
    DateTime? dueDate,
    List<String> evidence = const [],
  }) =>
      AiTaskSuggestion(
        id: 's1',
        fingerprint: 'f1',
        templateId: 't1',
        category: AiTaskCategory.production,
        organizationId: 'org_wesi_beats',
        title: title,
        description: '',
        assigneeId: null,
        priority: TaskPriority.urgent,
        forecastImpact: AiForecastImpact.high,
        needScore: .8,
        confidence: .9,
        effortPoints: 3,
        strategicReason: strategicReason,
        dueDate: dueDate,
        whyNow: whyNow,
        evidence: evidence,
        factTag: 'wesi-ai:fact:beatCadenceStalled:beat-cadence',
      );

  /// Карточка в той же обёртке, в какой живёт в панели: полоса заданной
  /// высоты, горизонтальный список. Проверять её вне этой обёртки
  /// бессмысленно — ломалась она именно от неё.
  Future<Map<String, bool>> pressAll(
    WidgetTester tester,
    AiTaskSuggestion item, {
    double textScale = 1.0,
    bool compact = true,
  }) async {
    final pressed = <String, bool>{
      'Создать': false,
      'Изменить': false,
      'Не сейчас': false,
    };

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Builder(
            builder: (context) => SizedBox(
              height:
                  WesiAiSuggestionCard.stripHeight(context, compact: compact),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                children: [
                  WesiAiSuggestionCard(
                    suggestion: item,
                    width: 300,
                    compact: compact,
                    onAccept: () => pressed['Создать'] = true,
                    onEdit: () => pressed['Изменить'] = true,
                    onSnooze: () => pressed['Не сейчас'] = true,
                    onReject: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    for (final label in pressed.keys) {
      final button = find.text(label);
      expect(button, findsOneWidget, reason: 'кнопка «$label» пропала');
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
    }
    return pressed;
  }

  testWidgets('обычная карточка: все три кнопки нажимаются', (tester) async {
    final pressed = await pressAll(tester, suggestion());
    expect(pressed.values, everyElement(isTrue));
  });

  testWidgets('карточка со всем сразу: кнопки всё равно нажимаются',
      (tester) async {
    // Сроки, стратегическая полоса, длинные строки — всё, что вообще может
    // попасть в карточку, разом. Именно накопление строк её и сломало.
    final pressed = await pressAll(
      tester,
      suggestion(
        title: 'Очень длинное название задачи, которое занимает две строки '
            'и ещё немного сверх того',
        whyNow: 'Причина, объясняющая срочность, тоже занимающая две строки '
            'целиком и без остатка',
        strategicReason: 'Стратегическое обоснование на две строки, которое '
            'добавляет высоты ровно там, где её и не хватало',
        dueDate: DateTime(2026, 8, 20),
        evidence: const ['Последний бит: 13.04.2026', 'Всего битов: 12'],
      ),
    );
    expect(pressed.values, everyElement(isTrue));
  });

  testWidgets('крупный системный шрифт не выталкивает кнопки', (tester) async {
    // Второй способ получить ту же поломку, и на чужом устройстве он
    // включён постоянно.
    final pressed = await pressAll(
      tester,
      suggestion(
        title: 'Длинное название задачи на две строки',
        strategicReason: 'Стратегическое обоснование',
        dueDate: DateTime(2026, 8, 20),
        evidence: const ['Последний бит: 13.04.2026'],
      ),
      textScale: 1.6,
    );
    expect(pressed.values, everyElement(isTrue));
  });

  testWidgets('кнопки лежат внутри карточки, а не под её краем',
      (tester) async {
    await pressAll(
      tester,
      suggestion(
        title: 'Длинное название задачи на две полные строки текста',
        whyNow: 'Причина на две строки, чтобы карточка была полной',
        strategicReason: 'Стратегическое обоснование на две строки',
        dueDate: DateTime(2026, 8, 20),
        evidence: const ['Последний бит: 13.04.2026'],
      ),
    );

    final card = tester.getRect(find.byType(WesiAiSuggestionCard));
    for (final label in ['Не сейчас', 'Изменить', 'Создать']) {
      final button = tester.getRect(find.text(label));
      expect(button.bottom, lessThanOrEqualTo(card.bottom + 0.5),
          reason: '«$label» вылезла снизу за карточку');
      expect(button.top, greaterThanOrEqualTo(card.top - 0.5),
          reason: '«$label» вылезла сверху за карточку');
    }
  });

  testWidgets('в широкой раскладке кнопки тоже на месте', (tester) async {
    final pressed = await pressAll(
      tester,
      suggestion(
        dueDate: DateTime(2026, 8, 20),
        strategicReason: 'Стратегическое обоснование',
        evidence: const ['Последний бит: 13.04.2026'],
      ),
      compact: false,
    );
    expect(pressed.values, everyElement(isTrue));
  });

  testWidgets('высота полосы растёт вместе с системным шрифтом',
      (tester) async {
    late double normal;
    late double large;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        normal = WesiAiSuggestionCard.stripHeight(context, compact: true);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Builder(builder: (context) {
          large = WesiAiSuggestionCard.stripHeight(context, compact: true);
          return const SizedBox();
        }),
      ),
    ));

    expect(large, greaterThan(normal));
  });
}
