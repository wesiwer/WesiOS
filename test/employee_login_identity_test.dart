import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/portal_account_service.dart';
import 'package:wesios/features/team/services/team_service.dart';

/// Вход в свой профиль: что приходит с сервера и что при этом происходит с
/// уже заведённой карточкой.
///
/// Сервер присылает только опознавательную часть — логин, имя, права. Всё
/// остальное (телефон, фото, навыки, хеш пароля) живёт на устройствах и
/// ездит синхронизацией. Значит вход не должен ничего из этого стирать: для
/// человека это выглядит как «зашёл — и пропало полкарточки».
void main() {
  late Directory dir;

  PortalAppIdentity identity({
    String id = 'E1',
    String login = 'anna',
    String fullName = 'Анна',
    String email = 'anna@wesi.local',
    bool isOwner = false,
    TeamPermissions? permissions,
  }) =>
      PortalAppIdentity(
        employeeId: id,
        login: login,
        fullName: fullName,
        nickname: '',
        position: 'менеджер',
        email: email,
        avatarIndex: 2,
        createdAt: DateTime.utc(2025, 11, 2),
        isOwner: isOwner,
        permissions: permissions ??
            const TeamPermissions(
              moduleList: [TeamModules.tasks, TeamModules.crm],
            ),
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_login');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(TeamPermissionsAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(EmployeeModelAdapter());
    }
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    SyncJournal.clearExpectations();
  });

  test('разбор ответа сервера: права и владение читаются как есть', () {
    final parsed = PortalAppIdentity.tryParse({
      'employeeId': 'E1',
      'login': 'anna',
      'fullName': 'Анна',
      'email': 'anna@wesi.local',
      'avatarIndex': 2,
      'createdAt': '2025-11-02T00:00:00Z',
      'owner': false,
      'permissions': {
        'modules': ['tasks', 'crm'],
        'canManageTeam': false,
        'canSeeOthersStats': true,
      },
    });

    expect(parsed, isNotNull);
    expect(parsed!.login, 'anna');
    expect(parsed.permissions.allows(TeamModules.tasks), isTrue);
    expect(parsed.permissions.allows(TeamModules.crm), isTrue);
    expect(parsed.permissions.allows(TeamModules.treasury), isFalse,
        reason: 'лишних прав появиться не должно');
    expect(parsed.permissions.canSeeOthersStats, isTrue);
    expect(parsed.permissions.canManageTeam, isFalse);
    expect(parsed.isOwner, isFalse);
  });

  test('ответ без прав не принимается', () {
    // Пустой ответ лучше отвергнуть, чем впустить человека без прав и
    // оставить его гадать, почему приложение пустое.
    expect(
      PortalAppIdentity.tryParse({'employeeId': 'E1', 'login': 'anna'}),
      isNull,
    );
    expect(
      PortalAppIdentity.tryParse({'login': 'anna', 'permissions': {}}),
      isNull,
    );
  });

  test('вход обновляет права, не трогая остальную карточку', () async {
    final box = Hive.box<EmployeeModel>(TeamService.boxName);
    await box.put(
      'E1',
      EmployeeModel(
        id: 'E1',
        login: 'anna',
        fullName: 'Анна',
        phone: '+7 900 000-00-00',
        email: 'anna@wesi.local',
        socials: const {'tg': '@ann'},
        notes: 'важная заметка',
        permissions: const TeamPermissions(moduleList: [TeamModules.tasks]),
        passwordHash: 'hash',
        passwordSalt: 'salt',
        photo: Uint8List.fromList([1, 2, 3]),
        skills: const ['сведение'],
        weeklyCapacityPoints: 6,
        createdAt: DateTime.utc(2025, 11, 2),
      ),
    );

    final applied = await TeamService.applyServerIdentity(identity());

    expect(applied, isNotNull);
    // Пришло с сервера — обновилось.
    expect(applied!.permissions.allows(TeamModules.crm), isTrue,
        reason: 'новые права обязаны примениться');
    expect(applied.position, 'менеджер');

    // Не приходило — сохранилось.
    expect(applied.phone, '+7 900 000-00-00');
    expect(applied.photo, isNotNull, reason: 'фото не приходит с сервера');
    expect(applied.skills, ['сведение']);
    expect(applied.weeklyCapacityPoints, 6);
    expect(applied.notes, 'важная заметка');
    expect(applied.passwordHash, 'hash');
    expect(applied.passwordSalt, 'salt');
  });

  test('вход делает человека текущим', () async {
    await TeamService.applyServerIdentity(identity());
    expect(TeamService.current?.id, 'E1');
    expect(TeamService.currentPermissions.allows(TeamModules.crm), isTrue);
    expect(TeamService.isOwnerSession, isFalse);
  });

  test('вход на новом устройстве не выдаёт себя за правку человека', () async {
    // Здесь профиля ещё не было, и карточка собирается из опознавательных
    // данных — без телефона, фото и навыков. Если объявить её своей правкой,
    // она уедет в синхронизацию и затрёт полную карточку у всех остальных.
    SyncJournal.attach(
      'employees',
      Hive.box<EmployeeModel>(TeamService.boxName),
    );
    final before = SyncJournal.localChanges.value;

    await TeamService.applyServerIdentity(identity());
    await Future<void>.delayed(Duration.zero);

    expect(SyncJournal.localChanges.value, before,
        reason: 'вход не должен считаться правкой — иначе неполная карточка '
            'уедет ко всем');
    final stamp = SyncJournal.stampOf('employees', 'E1');
    expect(stamp, isNotNull);
    expect(stamp!.updatedAt, DateTime.utc(2025, 11, 2),
        reason: 'отметка — дата заведения профиля, поэтому полная карточка '
            'с сервера победит на ближайшем обмене');
    await SyncJournal.detach();
  });

  test('поиск по логину не зависит от регистра и пробелов', () async {
    final box = Hive.box<EmployeeModel>(TeamService.boxName);
    await box.put(
      'E1',
      EmployeeModel(
        id: 'E1',
        login: 'anna',
        fullName: 'Анна',
        email: 'anna@wesi.local',
        createdAt: DateTime.utc(2025, 11, 2),
      ),
    );

    expect(TeamService.byLogin('anna')?.id, 'E1');
    expect(TeamService.byLogin('ANNA')?.id, 'E1',
        reason: 'человек набирает логин как придётся');
    expect(TeamService.byLogin('  Anna  ')?.id, 'E1');
    expect(TeamService.byLogin('anna2'), isNull);

    expect(TeamService.byEmail('ANNA@WESI.LOCAL')?.id, 'E1',
        reason: 'на почту приходит код входа — регистр там не значим');
    expect(TeamService.byEmail('  anna@wesi.local ')?.id, 'E1');
    expect(TeamService.byEmail(''), isNull);
  });

  test('пароль проверяется по соли и не хранится открытым', () async {
    final created = await TeamService.create(
      fullName: 'Анна',
      email: 'anna2@example.com',
      login: 'anna2',
      password: 'ПравильныйПароль1',
    );

    expect(created, isNotNull, reason: 'профиль обязан завестись локально');
    final person = created!.employee;
    expect(person.passwordHash, isNotEmpty);
    expect(person.passwordSalt, isNotEmpty);
    expect(person.passwordHash, isNot(contains('ПравильныйПароль1')),
        reason: 'открытый пароль на устройстве храниться не должен');

    expect(TeamService.verify('anna2', 'ПравильныйПароль1')?.id, person.id);
    expect(TeamService.verify('anna2', 'ПравильныйПароль2'), isNull);
    expect(TeamService.verify('anna2', ''), isNull);
    expect(TeamService.verify('нет-такого', 'ПравильныйПароль1'), isNull);
  });

  test('профиль без пароля не пускает по пустому паролю', () async {
    // У карточки, собранной из серверных данных, локального хеша нет. Пустое
    // сравнение не должно случайно совпасть.
    await TeamService.applyServerIdentity(identity(id: 'E9', login: 'petr'));
    expect(TeamService.byId('E9')?.passwordHash, isEmpty);
    expect(TeamService.verify('petr', ''), isNull);
    expect(TeamService.verify('petr', 'что-угодно'), isNull);
  });
}
