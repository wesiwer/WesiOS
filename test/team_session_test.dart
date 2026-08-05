import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/login_pool_service.dart';
import 'package:wesios/features/team/services/team_service.dart';

/// Вход, «запомнить меня» и смена логина.
///
/// «Запомнить меня» здесь управляло только входом в Firebase, а сотрудник
/// запоминался всегда. Снятая галочка не значила ничего — и это худший вид
/// управления: на него рассчитывают.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 5);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_session');
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
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box('wesios_settings').clear();
  });

  Future<EmployeeModel> person(String id, String login) async {
    final e = EmployeeModel(
      id: id,
      login: login,
      fullName: 'Человек $id',
      permissions: const TeamPermissions(),
      createdAt: base,
    );
    await TeamService.save(e);
    await LoginPoolService.reserve(login);
    return e;
  }

  group('запомнить меня', () {
    test('с галочкой вход переживает перезапуск', () async {
      final e = await person('a', 'wesioff');
      await TeamService.signIn(e, remember: true);

      // Перезапуск программы — это ровно этот вызов на старте.
      await TeamService.forgetUnrememberedSession();
      expect(TeamService.current?.id, 'a');
    });

    test('без галочки вход не переживает перезапуск', () async {
      final e = await person('a', 'wesioff');
      await TeamService.signIn(e, remember: false);
      // До перезапуска вход работает: «не запоминать» означает «до
      // закрытия», а не «на один экран».
      expect(TeamService.current?.id, 'a');

      await TeamService.forgetUnrememberedSession();
      expect(TeamService.current, isNull);
    });

    test('по умолчанию запоминаем', () async {
      final e = await person('a', 'wesioff');
      await TeamService.signIn(e);
      await TeamService.forgetUnrememberedSession();
      expect(TeamService.current?.id, 'a');
    });
  });

  group('смена логина', () {
    test('логин меняется, старый возвращается в свободные', () async {
      // Список занятых ведётся отдельно от списка людей ровно затем, чтобы
      // освобождение было видимым событием. Забыть его здесь значило бы
      // медленно вычерпать пул.
      final e = await person('a', 'sokol');
      expect(await TeamService.setLogin(e.id, 'WesiOff'), TeamService.loginOk);

      expect(TeamService.byId('a')!.login, 'wesioff');
      expect(LoginPoolService.isTaken('wesioff'), isTrue);
      expect(LoginPoolService.isTaken('sokol'), isFalse);
    });

    test('вход работает под новым логином и не работает под старым', () async {
      final e = await person('a', 'sokol');
      await TeamService.setPassword(e.id, 'пароль-подлиннее');
      await TeamService.setLogin(e.id, 'WesiOff');

      expect(TeamService.verify('WesiOff', 'пароль-подлиннее')?.id, 'a');
      expect(TeamService.verify('sokol', 'пароль-подлиннее'), isNull);
    });

    test('занятый чужим логин не отдаётся', () async {
      await person('a', 'wesioff');
      final b = await person('b', 'sokol');
      expect(await TeamService.setLogin(b.id, 'wesioff'),
          TeamService.loginTaken);
      expect(TeamService.byId('b')!.login, 'sokol');
    });

    test('слишком короткий логин не принимается', () async {
      final e = await person('a', 'sokol');
      expect(await TeamService.setLogin(e.id, 'ab'), TeamService.loginBad);
      expect(TeamService.byId('a')!.login, 'sokol');
    });

    test('тот же логин — не ошибка и ничего не ломает', () async {
      // Иначе «сохранить», не меняя поля, освободило бы собственный логин.
      final e = await person('a', 'wesioff');
      expect(await TeamService.setLogin(e.id, 'WesiOff'), TeamService.loginOk);
      expect(TeamService.byId('a')!.login, 'wesioff');
      expect(LoginPoolService.isTaken('wesioff'), isTrue);
    });

    test('несуществующему человеку логин не меняется', () async {
      expect(await TeamService.setLogin('нет-такого', 'wesioff'),
          TeamService.loginNoSuchPerson);
    });
  });
}
