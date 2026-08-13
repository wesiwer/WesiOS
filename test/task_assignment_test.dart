import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_assignment.dart';
import 'package:wesios/features/tasks/services/task_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 4, 12);

  EmployeeModel person(
    String id, {
    String name = 'Человек',
    bool owner = false,
    bool canAssign = false,
    Uint8List? photo,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: name,
        isOwner: owner,
        permissions: owner
            ? TeamPermissions.owner
            : TeamPermissions(
                moduleList: const ['tasks'], canAssignTasksRaw: canAssign),
        createdAt: base,
        photo: photo,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_assign');
    Hive.init(dir.path);
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(OrganizationAccessGrantAdapter());
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await OrganizationService.ensureBaseline();
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<TaskModel>('wesios_tasks');
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box('wesios_settings').clear();
  });

  group('право ставить задачи другим', () {
    test('по умолчанию сотруднику не открыто', () {
      expect(TeamPermissions.employeeDefault.canAssignTasks, isFalse);
    });

    test('у владельца открыто', () {
      expect(TeamPermissions.owner.canAssignTasks, isTrue);
    });

    test('старая карточка без этого поля читается, а не падает', () {
      const old = TeamPermissions(moduleList: ['tasks']);
      expect(old.canAssignTasksRaw, isNull);
      expect(old.canAssignTasks, isFalse);
    });

    test('переживает круг через JSON', () {
      final json = TeamPermissions.owner.toJson();
      expect(TeamPermissions.fromJson(json).canAssignTasks, isTrue);
      expect(
        TeamPermissions.fromJson(
                const TeamPermissions(moduleList: ['tasks']).toJson())
            .canAssignTasks,
        isFalse,
      );
    });
  });

  group('назначение исполнителя', () {
    test('без права исполнитель принудительно становится собой', () async {
      final me = person('e1', name: 'Пётр', canAssign: false);
      await TeamService.save(me);
      await TeamService.save(person('e2', name: 'Иван'));
      await TeamService.signIn(me);

      expect(TaskAssignment.canAssignToOthers, isFalse);
      expect(TaskAssignment.coerce('e2'), 'e1',
          reason: 'иначе право соблюдал бы только диалог, а не система');
    });

    test('с правом исполнитель остаётся тем, кого выбрали', () async {
      final boss = person('e1', name: 'Пётр', canAssign: true);
      await TeamService.save(boss);
      await TeamService.save(person('e2', name: 'Иван'));
      await TeamService.signIn(boss);

      expect(TaskAssignment.canAssignToOthers, isTrue);
      expect(TaskAssignment.coerce('e2'), 'e2');
    });

    test('сервис переписывает исполнителя, а не только диалог', () async {
      final me = person('e1', canAssign: false);
      await TeamService.save(me);
      await TeamService.save(person('e2'));
      await TeamService.signIn(me);
      await OrganizationAccessService.grant(
        employeeId: me.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        permissions: const [OrganizationPermissions.view],
        enforceActor: false,
      );

      final service = TaskService();
      await service.save(TaskModel(
        id: 'k1',
        title: 'Чужая задача',
        createdAt: base,
        assignee: 'e2',
      ));

      final stored = Hive.box<TaskModel>('wesios_tasks').get('k1')!;
      expect(stored.assignee, 'e1',
          reason: 'задача с чужим исполнителем может приехать из '
              'синхронизации, минуя диалог');
    });

    test('без входа локальный владелец не даёт административных прав', () async {
      await TeamService.save(person('own', owner: true));
      await TeamService.save(person('e2'));
      await TeamService.signOut();

      expect(TaskAssignment.canAssignToOthers, isFalse);
      expect(TaskAssignment.currentId, isNull);
      expect(TaskAssignment.coerce('e2'), isNull);
      expect(TaskAssignment.candidates(), isEmpty);
    });

    test('имя исполнителя берётся из состава', () async {
      await TeamService.save(person('e1', name: 'Пётр Иванов'));
      expect(TaskAssignment.displayName('e1'), 'Пётр Иванов');
    });

    test('старая задача с именем строкой продолжает читаться', () {
      expect(TaskAssignment.displayName('Вася из типографии'),
          'Вася из типографии');
      expect(TaskAssignment.displayName(null), '');
      expect(TaskAssignment.displayName('  '), '');
    });

    test('себя показываем первым в списке', () async {
      final me = person('e2', name: 'Я');
      await TeamService.save(person('e1', name: 'Алексей'));
      await TeamService.save(me);
      await TeamService.signIn(me);

      expect(TaskAssignment.candidates().first.id, 'e2',
          reason: 'чаще всего задачу заводят себе');
    });

    test('снять исполнителя действительно можно', () {
      final task = TaskModel(
          id: 'k', title: 'x', createdAt: base, assignee: 'e1');
      expect(task.copyWith(assignee: null).assignee, 'e1',
          reason: 'без флага null означает «не менять» — так работает copyWith');
      expect(task.copyWith(clearAssignee: true).assignee, isNull);
    });
  });

  group('снимок сотрудника', () {
    test('едет на сервер вместе с карточкой', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 250]);
      final c = EmployeesSync();
      final back = c.decode(c.encode(person('e1', photo: bytes)))!;
      expect(back.photo, bytes,
          reason: 'без снимка на втором устройстве у всех безликие кружки');
    });

    test('карточка без снимка не ломает разбор', () {
      final c = EmployeesSync();
      final back = c.decode(c.encode(person('e1')))!;
      expect(back.photo, isNull);
    });

    test('испорченный снимок не роняет всю карточку', () {
      final c = EmployeesSync();
      final fields = c.encode(person('e1'))..['photo'] = 'не base64 вовсе!!';
      final back = c.decode(fields);
      expect(back, isNotNull, reason: 'человек важнее его фотографии');
      expect(back!.photo, isNull);
    });

    test('снимок можно убрать, а не только заменить', () {
      final e = person('e1', photo: Uint8List.fromList([1, 2, 3]));
      expect(e.copyWith(fullName: 'Другое имя').photo, isNotNull);
      expect(e.copyWith(clearPhoto: true).photo, isNull);
    });
  });
}
