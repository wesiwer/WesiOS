import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/credentials_generator.dart';
import 'package:wesios/features/team/services/login_pool_service.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  late Directory dir;
  var emailCounter = 0;

  Future<CreatedEmployee?> create(
    String fullName, {
    String? password,
    String notes = '',
  }) {
    emailCounter++;
    return TeamService.create(
      fullName: fullName,
      email: 'employee$emailCounter@example.com',
      password: password,
      notes: notes,
    );
  }

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_team_test');
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

  setUp(() async {
    emailCounter = 0;
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box('wesios_settings').clear();
  });

  group('база логинов', () {
    test('сначала свободны все слова словаря', () {
      expect(LoginPoolService.freeCount, CredentialsGenerator.words.length);
      expect(LoginPoolService.taken, isEmpty);
    });

    test('занятый логин исчезает из свободных', () async {
      await LoginPoolService.reserve('amber');
      expect(LoginPoolService.isTaken('amber'), isTrue);
      expect(LoginPoolService.free.contains('amber'), isFalse);
      expect(LoginPoolService.freeCount,
          CredentialsGenerator.words.length - 1);
    });

    test('дважды занять один логин нельзя', () async {
      expect(await LoginPoolService.reserve('amber'), isTrue);
      expect(await LoginPoolService.reserve('amber'), isFalse);
    });

    test('регистр не создаёт второй логин', () async {
      await LoginPoolService.reserve('Amber');
      expect(LoginPoolService.isTaken('amber'), isTrue);
      expect(await LoginPoolService.reserve('AMBER'), isFalse);
    });

    test('освобождение возвращает логин в свободные', () async {
      await LoginPoolService.reserve('amber');
      await LoginPoolService.release('amber');
      expect(LoginPoolService.isTaken('amber'), isFalse);
      expect(LoginPoolService.free.contains('amber'), isTrue);
    });

    test('предложенный логин ещё не занят', () async {
      await LoginPoolService.reserve('amber');
      for (var i = 0; i < 50; i++) {
        final s = LoginPoolService.suggest();
        expect(s, isNotNull);
        expect(LoginPoolService.isTaken(s!), isFalse);
      }
    });

    test('сверка приводит список занятых к реальному составу', () async {
      await LoginPoolService.reserve('amber');
      await LoginPoolService.reserve('cedar');
      await LoginPoolService.reconcile(['cedar', 'delta']);
      expect(LoginPoolService.isTaken('amber'), isFalse);
      expect(LoginPoolService.isTaken('cedar'), isTrue);
      expect(LoginPoolService.isTaken('delta'), isTrue);
    });
  });

  group('создание сотрудника', () {
    test('логин занимается, пароль возвращается один раз', () async {
      final created = await create('Иван Петров');
      expect(created, isNotNull);
      expect(created!.password.length,
          CredentialsGenerator.defaultPasswordLength);
      expect(LoginPoolService.isTaken(created.employee.login), isTrue);
    });

    test('электронная почта обязательна', () async {
      final created = await TeamService.create(
        fullName: 'Без почты',
        email: '',
      );
      expect(created, isNull);
    });

    test('невалидная почта не принимается', () async {
      final created = await TeamService.create(
        fullName: 'Ошибка',
        email: 'это-не-почта',
      );
      expect(created, isNull);
    });

    test('одну почту нельзя выдать двум сотрудникам', () async {
      final first = await TeamService.create(
        fullName: 'Первый',
        email: 'same@example.com',
      );
      final second = await TeamService.create(
        fullName: 'Второй',
        email: 'SAME@example.com',
      );
      expect(first, isNotNull);
      expect(second, isNull);
    });

    test('пароль в базе не хранится — только хеш', () async {
      final created = await create('Иван');
      final stored = TeamService.byId(created!.employee.id)!;
      expect(stored.passwordHash, isNotEmpty);
      expect(stored.passwordSalt, isNotEmpty);
      expect(stored.passwordHash, isNot(contains(created.password)));
      expect(stored.toPublicJson().toString(),
          isNot(contains(created.password)));
    });

    test('у двух сотрудников разные логины', () async {
      final a = await create('А');
      final b = await create('Б');
      expect(a!.employee.login, isNot(b!.employee.login));
    });

    test('одинаковый пароль даёт разные хеши — соль своя у каждого', () async {
      final a = await create('А', password: 'один-и-тот-же');
      final b = await create('Б', password: 'один-и-тот-же');
      expect(a!.employee.passwordHash, isNot(b!.employee.passwordHash));
    });

    test('по умолчанию открыты только задачи', () async {
      final created = await create('Новичок');
      final p = created!.employee.permissions;
      expect(p.allows(TeamModules.tasks), isTrue);
      expect(p.allows(TeamModules.treasury), isFalse);
      expect(p.allows(TeamModules.shield), isFalse);
      expect(p.canManageTeam, isFalse);
    });

    test('новый профиль не содержит случайных/demo показателей', () async {
      final created = await create('Новичок');
      expect(created!.employee.demoStats, isEmpty);
      expect(TeamService.generateDemoStats(random: Random(1)), isEmpty);
    });

    test('когда словарь логинов кончился — используется уникальный вариант', () async {
      await LoginPoolService.reconcile(CredentialsGenerator.words);
      final created = await create('Ещё один');
      expect(created, isNotNull);
      expect(LoginPoolService.isTaken(created!.employee.login), isTrue);
    });
  });

  group('локальный хеш пароля — только совместимость', () {
    test('верная пара сверяется локально', () async {
      final created = await create('Иван');
      final ok = TeamService.verify(created!.employee.login, created.password);
      expect(ok, isNotNull);
      expect(ok!.id, created.employee.id);
    });

    test('неверный пароль не проходит', () async {
      final created = await create('Иван');
      expect(TeamService.verify(created!.employee.login, 'не-тот'), isNull);
    });

    test('несуществующий логин не проходит', () {
      expect(TeamService.verify('никого-нет', 'пароль'), isNull);
    });

    test('регистр логина не мешает сверке', () async {
      final created = await create('Иван');
      final upper = created!.employee.login.toUpperCase();
      expect(TeamService.verify(upper, created.password), isNotNull);
    });

    test('пустой пароль не подходит к владельцу без локального пароля', () async {
      await TeamService.ensureOwner();
      expect(TeamService.verify('owner', ''), isNull);
    });
  });

  group('локальная смена пароля', () {
    test('старый перестаёт подходить, новый подходит', () async {
      final created = await create('Иван');
      final id = created!.employee.id;
      await TeamService.setPasswordLocally(id, 'новый-пароль-123');
      expect(TeamService.verify(created.employee.login, created.password), isNull);
      expect(TeamService.verify(created.employee.login, 'новый-пароль-123'),
          isNotNull);
    });
  });

  group('удаление', () {
    test('логин возвращается в свободные в локальном режиме', () async {
      final created = await create('Иван');
      final login = created!.employee.login;
      await TeamService.remove(created.employee.id);
      expect(LoginPoolService.isTaken(login), isFalse);
      expect(LoginPoolService.free.contains(login), isTrue);
    });

    test('удалённый локальный профиль больше не сверяется', () async {
      final created = await create('Иван');
      await TeamService.remove(created!.employee.id);
      expect(TeamService.verify(created.employee.login, created.password), isNull);
    });

    test('владельца удалить нельзя', () async {
      final ownerEmployee = await TeamService.ensureOwner();
      expect(await TeamService.remove(ownerEmployee!.id), isFalse);
      expect(TeamService.owner, isNotNull);
    });

    test('удаление текущего сотрудника очищает локальную роль', () async {
      final created = await create('Иван');
      await TeamService.signIn(created!.employee);
      expect(TeamService.current, isNotNull);
      await TeamService.remove(created.employee.id);
      expect(TeamService.current, isNull);
    });
  });

  group('кто вошёл и что ему открыто', () {
    test('без входа нет ни роли владельца, ни административных прав', () {
      expect(TeamService.current, isNull);
      expect(TeamService.currentPermissions.canManageTeam, isFalse);
      expect(TeamService.currentPermissions.canAssignTasks, isFalse);
      expect(TeamService.currentPermissions.modules, isEmpty);
      expect(TeamService.isOwnerSession, isFalse);
    });

    test('после локальной установки сотрудника права его', () async {
      final created = await create('Иван');
      await TeamService.signIn(created!.employee);
      final p = TeamService.currentPermissions;
      expect(p.allows(TeamModules.tasks), isTrue);
      expect(p.allows(TeamModules.treasury), isFalse);
      expect(TeamService.isOwnerSession, isFalse);
    });

    test('выход возвращает в состояние без привилегий', () async {
      final created = await create('Иван');
      await TeamService.signIn(created!.employee);
      await TeamService.signOut();
      expect(TeamService.current, isNull);
      expect(TeamService.currentPermissions.canManageTeam, isFalse);
      expect(TeamService.currentPermissions.modules, isEmpty);
      expect(TeamService.isOwnerSession, isFalse);
    });

    test('правка прав действует на текущего сразу', () async {
      final created = await create('Иван');
      await TeamService.signIn(created!.employee);
      await TeamService.save(created.employee.copyWith(
        permissions: created.employee.permissions
            .withModule(TeamModules.treasury, true),
      ));
      expect(TeamService.currentPermissions.allows(TeamModules.treasury),
          isTrue);
    });
  });

  group('список состава', () {
    test('владелец идёт первым', () async {
      await create('Аня');
      await TeamService.ensureOwner(name: 'Яков');
      expect(TeamService.all.first.isOwner, isTrue);
    });

    test('остальные по алфавиту', () async {
      await create('Яна');
      await create('Анна');
      final names = TeamService.all
          .where((e) => !e.isOwner)
          .map((e) => e.displayName)
          .toList();
      expect(names, ['Анна', 'Яна']);
    });

    test('владелец заводится один раз', () async {
      final a = await TeamService.ensureOwner();
      final b = await TeamService.ensureOwner();
      expect(a!.id, b!.id);
      expect(TeamService.all.where((e) => e.isOwner).length, 1);
    });
  });

  group('карточка сотрудника', () {
    test('имя для показа падает на ник, потом на логин', () {
      final withName = EmployeeModel(
          id: '1', login: 'amber', fullName: 'Иван', createdAt: DateTime(2026));
      final withNick = EmployeeModel(
          id: '2',
          login: 'cedar',
          fullName: '',
          nickname: 'wesi',
          createdAt: DateTime(2026));
      final bare = EmployeeModel(
          id: '3', login: 'delta', fullName: '', createdAt: DateTime(2026));
      expect(withName.displayName, 'Иван');
      expect(withNick.displayName, 'wesi');
      expect(bare.displayName, 'delta');
    });

    test('в открытую карточку не попадают заметки и хеш', () async {
      final created = await create(
        'Иван',
        notes: 'ставка 200к, не любит созвоны',
      );
      final json = created!.employee.toPublicJson().toString();
      expect(json.contains('ставка'), isFalse);
      expect(json.contains(created.employee.passwordHash), isFalse);
    });

    test('почта сохраняется в карточке', () async {
      final created = await TeamService.create(
        fullName: 'Почтовый сотрудник',
        email: 'person@example.com',
      );
      expect(created!.employee.email, 'person@example.com');
      expect(TeamService.byId(created.employee.id)!.email, 'person@example.com');
    });
  });
}
