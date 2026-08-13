import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

/// Выбранная организация может выпасть из дерева — и это не должно ломать
/// всё финансовое разом.
///
/// Так и случилось. Проверка при запуске считала сохранённую организацию
/// годной, если у человека есть на неё право. У владельца право есть на
/// любую, поэтому проверка ничего не проверяла: организация с исчезнувшим
/// родителем проходила её насквозь.
///
/// Дальше `effectiveOrganizationIds` пересекает выбранное с тем, что видно
/// из корня, получает пусто — и прогноз бросает «нет права на прогноз».
/// Сообщение вводит в заблуждение вдвойне: у владельца право есть, а
/// настоящая причина в том, что выбирать оказалось нечего.
void main() {
  late Directory dir;

  EmployeeModel owner() => EmployeeModel(
        id: 'owner',
        login: 'wesi',
        fullName: 'Веси',
        isOwner: true,
        permissions: const TeamPermissions(moduleList: TeamModules.all),
        createdAt: DateTime.utc(2025, 1, 1),
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_org_ctx');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(TeamPermissionsAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(EmployeeModelAdapter());
    }
    if (!Hive.isAdapterRegistered(80)) {
      Hive.registerAdapter(OrganizationStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(81)) {
      Hive.registerAdapter(OrganizationModelAdapter());
    }
    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  test('обычный случай: выбран корень — организация одна и та же', () async {
    final ids = await OrganizationContext.effectiveOrganizationIds();
    expect(ids, isNotEmpty);
    expect(ids, contains(OrganizationModel.rootId));
  });

  test('осиротевшая организация не оставляет владельца без данных', () async {
    final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
    await Hive.box<EmployeeModel>(TeamService.boxName).put('owner', owner());
    await TeamService.signIn(owner());

    // Организация, чей родитель исчез: из корня до неё не дойти.
    final orphan = OrganizationModel(
      id: 'org_orphan',
      name: 'Осиротевшая',
      parentId: 'org_deleted',
      isRoot: false,
      baseCurrency: 'RUB',
      createdBy: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await box.put(orphan.id, orphan);
    await _putContext(orphan.id);

    final ids = await OrganizationContext.effectiveOrganizationIds();

    expect(ids, isNotEmpty,
        reason: 'пустой список означает «финансов нет вообще» — и каждый '
            'финансовый экран падает с сообщением про отсутствие прав, '
            'которых у владельца на самом деле в избытке');
    expect(ids, contains(OrganizationModel.rootId),
        reason: 'починка должна вернуть человека к корню, а не оставить '
            'в подвешенном состоянии');
  });

  test('после починки выбранной снова числится достижимая', () async {
    await Hive.box<EmployeeModel>(TeamService.boxName).put('owner', owner());
    await TeamService.signIn(owner());
    await _putContext('org_orphan');

    await OrganizationContext.initialize();

    expect(OrganizationContext.currentOrganizationId,
        OrganizationModel.rootId,
        reason: 'запомнить недостижимую организацию значит вернуть поломку '
            'при следующем запуске');
  });

  test('исчезнувшая организация тоже не ломает контекст', () async {
    await Hive.box<EmployeeModel>(TeamService.boxName).put('owner', owner());
    await TeamService.signIn(owner());
    await _putContext('org_which_never_existed');

    final ids = await OrganizationContext.effectiveOrganizationIds();
    expect(ids, contains(OrganizationModel.rootId));
  });
}

/// Записать выбранную организацию так же, как это делает само приложение:
/// ключ зависит от того, кто вошёл.
Future<void> _putContext(String organizationId) async {
  final user = TeamService.current?.id ?? 'local';
  await Hive.box('wesios_settings')
      .put('organization_context.$user.organization', organizationId);
}
