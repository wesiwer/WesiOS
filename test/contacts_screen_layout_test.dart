import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/team/contacts_screen.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

/// Раскладка контактов на узком экране.
///
/// Карточка человека — самое тесное место в приложении: в одну строку
/// втискиваются снимок, имя, метка «владелец» и кнопка правки, а под ними
/// произвольное число ссылок. `flutter analyze` такого не ловит вообще:
/// переполнение — ошибка времени раскладки, и видно её только на живом
/// экране либо здесь.
///
/// Про строгость: в тестах шрифт квадратный — каждый знак ровно в ширину
/// кегля, поэтому русская строка здесь заметно шире, чем на устройстве.
/// Проверка получается строже реальности, и это к лучшему: она заставляет
/// ограничивать текст по ширине везде, а не только там, где сегодня хватает
/// места. Строка без предела всё равно за него выйдет — на английском, при
/// увеличенном системном шрифте или у человека с длинной фамилией.
///
/// ВАЖНО, и это стоило отдельного разбора: запись в Hive делается **только**
/// в `setUp`, никогда в теле `testWidgets`. Тело крутится в `FakeAsync` с
/// поддельными часами, а Hive пишет на настоящий диск — такой `Future` под
/// фейковым временем не завершается никогда. Тест не падает и ничего не
/// сообщает, он просто виснет: ни ошибки, ни стека, ни срабатывания
/// таймаута. Ровно на это и ушла предыдущая попытка написать этот файл.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_contacts_layout');
    Hive.init(dir.path);
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> only(List<EmployeeModel> people) async {
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    for (final e in people) {
      await TeamService.save(e);
    }
  }

  EmployeeModel person({
    required String id,
    required String name,
    String position = '',
    String nickname = '',
    String phone = '',
    String email = '',
    Map<String, String> socials = const {},
    String notes = '',
    bool owner = false,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: name,
        position: position,
        nickname: nickname,
        phone: phone,
        email: email,
        socials: socials,
        notes: notes,
        isOwner: owner,
        permissions: owner ? TeamPermissions.owner : const TeamPermissions(),
        createdAt: DateTime.utc(2026),
      );

  /// Ставит размер экрана и строит экран контактов.
  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ContactsScreen()));
    await tester.pump();
  }

  group('узкий телефон', () {
    setUp(() => only([
          person(
            id: 'own',
            name: 'Владелец Проверочный',
            position: 'Директор',
            phone: '+7 900 000-00-00',
            email: 'owner@example.com',
            owner: true,
          ),
        ]));

    testWidgets('карточка помещается в 360 точек', (tester) async {
      await show(tester, const Size(360, 740));
      expect(find.text('Владелец Проверочный'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('и в 320 тоже', (tester) async {
      // Самые узкие живые экраны. Если ломается — ломается здесь.
      await show(tester, const Size(320, 640));
      expect(tester.takeException(), isNull);
    });
  });

  /// Каждое длинное поле проверяется отдельно.
  ///
  /// Одна карточка «со всем сразу» показывала бы, что где-то сломалось, но не
  /// говорила бы где: переполнение сообщает только число точек.
  void tight(String what, EmployeeModel Function() make) {
    group(what, () {
      setUp(() => only([make()]));

      for (final width in const [360.0, 320.0]) {
        testWidgets('помещается в ${width.toInt()} точек', (tester) async {
          await show(tester, Size(width, 740));
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  tight(
    'очень длинное имя и метка владельца',
    () => person(
      id: 'own',
      name: 'Иннокентий Александрович Подберёзовиков-Загряжский',
      owner: true,
    ),
  );

  tight(
    'очень длинная должность',
    () => person(
      id: 'own',
      name: 'Иннокентий',
      position: 'Заместитель руководителя направления по внешним связям',
      owner: true,
    ),
  );

  tight(
    'длинное имя в одно слово',
    () => person(
      id: 'own',
      name: 'Подберёзовиков-Загряжский-Кропоткин-Оболенский',
      nickname: 'innokentiy_the_longest_nickname_ever_written',
      owner: true,
    ),
  );

  tight(
    'длинная почта',
    () => person(
      id: 'own',
      name: 'Иннокентий',
      email: 'innokentiy.podberezovikov@очень-длинный-домен.example.com',
      owner: true,
    ),
  );

  tight(
    'пять ссылок',
    () => person(
      id: 'own',
      name: 'Иннокентий',
      phone: '+7 900 000-00-00',
      email: 'i@example.com',
      socials: const {
        'telegram': '@innokentiy',
        'whatsapp': '+79000000000',
        'vk': 'id123456789',
        'instagram': 'innokentiy',
        'linkedin': 'in/innokentiy',
      },
      owner: true,
    ),
  );

  tight(
    'подпись о заметке',
    () => person(
      id: 'own',
      name: 'Иннокентий',
      notes: 'Заметка, которую видно только с правом на заметки',
      owner: true,
    ),
  );

  tight(
    'всё длинное сразу',
    () => person(
      id: 'own',
      name: 'Иннокентий Александрович Подберёзовиков-Загряжский',
      position: 'Заместитель руководителя направления по внешним связям',
      nickname: 'innokentiy_the_longest_nickname_ever',
      phone: '+7 900 000-00-00',
      email: 'innokentiy.podberezovikov@очень-длинный-домен.example.com',
      socials: const {
        'telegram': '@innokentiy',
        'whatsapp': '+79000000000',
        'vk': 'id123456789',
        'instagram': 'innokentiy',
        'linkedin': 'in/innokentiy',
      },
      notes: 'Заметка, которую видно только с правом на заметки',
      owner: true,
    ),
  );

  group('список из нескольких человек', () {
    setUp(() => only([
          person(id: 'own', name: 'Владелец', owner: true),
          person(
              id: 'e2',
              name: 'Иван Петров',
              position: 'Логистика',
              phone: '+7 900 111-11-11'),
          person(
              id: 'e3',
              name: 'Мария Сидорова',
              position: 'Бухгалтерия',
              email: 'maria@example.com'),
        ]));

    testWidgets('все трое строятся без переполнения', (tester) async {
      await show(tester, const Size(360, 740));
      expect(find.text('Иван Петров'), findsOneWidget);
      expect(find.text('Мария Сидорова'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('низкий экран не ломает список', (tester) async {
      // Меньше высоты, чем занимают карточки: должен появиться скролл, а не
      // жёлто-чёрная полоса.
      await show(tester, const Size(360, 420));
      expect(tester.takeException(), isNull);
    });
  });

  group('пусто', () {
    // Владелец сохранён нарочно: без него `ensureOwner` заводит его сам —
    // то есть **пишет в Hive прямо во время теста**, под фейковым временем.
    // Такая запись не завершается, и на ней потом навсегда виснет
    // `Hive.close()` в tearDownAll. Пустой список получаем поиском, который
    // ничего не находит, — раскладка при этом та же самая.
    setUp(() => only([person(id: 'own', name: 'Владелец', owner: true)]));

    testWidgets('пустой результат поиска строится', (tester) async {
      await show(tester, const Size(360, 740));
      await tester.enterText(find.byType(TextField), 'щщщ-такого-нет');
      await tester.pump();

      expect(find.text('Владелец'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
