import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_service.dart';
import 'package:wesios/features/tasks/tasks_screen.dart';

/// Доска задач — единственный экран, где четыре колонки делят ширину и
/// каждая скроллится сама. Здесь легко получить RenderFlex overflow, а
/// `flutter analyze` такого не ловит вообще: это ошибка времени раскладки.
void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('wesios_tasks_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Засев доски.
  Future<void> prepare(int perColumn) async {
    final box = await Hive.openBox<TaskModel>('wesios_tasks');
    final orgBox =
        await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await box.clear();
    await orgBox.clear();
    await OrganizationService.ensureBaseline();
    final service = TaskService();
    for (final status in TaskStatus.values) {
      for (var i = 0; i < perColumn; i++) {
        await service.save(TaskModel(
          id: '${status.name}_$i',
          title: 'Задача ${status.name} $i с довольно длинным названием',
          description: 'Описание задачи, тоже не короткое',
          status: status,
          priority: TaskPriority.values[i % TaskPriority.values.length],
          createdAt: DateTime(2026, 1, 1).add(Duration(days: i)),
          dueDate: DateTime.now().add(Duration(days: i - 2)),
          assignee: 'Исполнитель $i',
          subtasks: [
            SubTask(title: 'пункт 1', done: i.isEven),
            const SubTask(title: 'пункт 2'),
          ],
          order: i,
        ));
      }
    }
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('board with a handful of tasks per column', () {
    setUp(() => prepare(6));

    testWidgets('renders four columns side by side on a desktop-width window '
        'without overflowing', (tester) async {
      await pumpAt(tester, const Size(1280, 800));

      expect(find.text('Бэклог'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to stacked columns on a phone-width window '
        'without overflowing — four columns side by side are unreadable there',
        (tester) async {
      await pumpAt(tester, const Size(390, 844));

      expect(find.text('Бэклог'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('board with far more tasks than fit on screen', () {
    setUp(() => prepare(30));

    testWidgets('a column scrolls internally instead of overflowing',
        (tester) async {
      await pumpAt(tester, const Size(1280, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the stacked phone layout also survives it', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
    });
  });

  group('empty board', () {
    setUp(() => prepare(0));

    testWidgets('shows the empty placeholder in every column', (tester) async {
      await pumpAt(tester, const Size(1280, 800));
      expect(find.text('Пусто'), findsNWidgets(TaskStatus.values.length));
      expect(tester.takeException(), isNull);
    });
  });
}
