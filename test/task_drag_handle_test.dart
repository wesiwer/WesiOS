import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/widgets/task_drag_handle.dart';

/// Прокрутка доски задач против перетаскивания карточки.
///
/// Оба жеста на сенсорном экране начинаются одинаково: касание и движение
/// вниз. Пока карточка захватывалась сразу, побеждала всегда она — любая
/// попытка пролистать доску уносила задачу в соседний этап, и прокрутить
/// экран было почти невозможно.
///
/// Проверка настоящая, а не по исходнику: карточки кладутся в список,
/// список проматывается пальцем, и смотрится, сдвинулся ли он.
/// Погашенная карточка на своём месте — признак того, что её взяли.
///
/// Искать по всему дереву, а не под конкретной карточкой: гаснет та, за
/// которую взялись, и заранее известно только то, что она одна.
final Finder _dimmedCard = find.byWidgetPredicate(
  (widget) => widget is Opacity && widget.opacity == 0.35,
);

void main() {
  TaskModel task(int i) => TaskModel(
        id: 't$i',
        title: 'Задача $i',
        status: TaskStatus.backlog,
        priority: TaskPriority.normal,
        createdAt: DateTime(2026, 1, 1),
      );

  Widget board({required bool requireLongPress}) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                TaskDragHandle(
                  task: task(i),
                  requireLongPress: requireLongPress,
                  feedback: const SizedBox(width: 240, height: 60),
                  child: SizedBox(height: 60, child: Text('Задача $i')),
                ),
            ],
          ),
        ),
      );

  double offsetOf(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable).first).controller!.offset;

  testWidgets('с удержанием список проматывается пальцем', (tester) async {
    await tester.pumpWidget(board(requireLongPress: true));

    await tester.drag(find.text('Задача 1'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(offsetOf(tester), greaterThan(0),
        reason: 'ради этого всё и делалось — доска должна прокручиваться');
  });

  testWidgets('без удержания прокрутка не работает — так и было', (tester) async {
    // Тот же жест по той же карточке, разница только в способе захвата.
    // Если этот случай когда-нибудь начнёт прокручивать сам по себе, значит
    // поломка ушла и различие потеряло смысл.
    await tester.pumpWidget(board(requireLongPress: false));

    await tester.drag(find.text('Задача 1'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(offsetOf(tester), 0,
        reason: 'карточка забирала вертикальный жест себе');
  });

  testWidgets('после удержания карточка всё-таки берётся', (tester) async {
    await tester.pumpWidget(board(requireLongPress: true));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Задача 1')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    expect(_dimmedCard, findsOneWidget,
        reason: 'взятая карточка гаснет на своём месте');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('короткое касание не начинает перетаскивание', (tester) async {
    await tester.pumpWidget(board(requireLongPress: true));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Задача 1')));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    expect(_dimmedCard, findsNothing,
        reason: 'ничего не взято — карточка не гаснет');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('когда нужно удержание', () {
    test('на телефоне — да', () {
      expect(TaskDragHandle.needsLongPress(TargetPlatform.android), isTrue);
      expect(TaskDragHandle.needsLongPress(TargetPlatform.iOS), isTrue);
    });

    test('на мыши — нет', () {
      // Колесо прокручивает, кнопка тянет: заставлять мышь ждать полсекунды
      // значит портить то, что и так работало.
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(TaskDragHandle.needsLongPress(platform), isFalse,
            reason: '$platform');
      }
    });
  });
}
