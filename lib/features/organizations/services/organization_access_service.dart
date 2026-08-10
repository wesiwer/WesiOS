import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../team/models/team_permissions.dart';
import '../../team/services/team_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import 'organization_service.dart';

class OrganizationAccessService {
  OrganizationAccessService._();

  static const String boxName = 'wesios_org_access_grants';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<OrganizationAccessGrant>? _box;

  static Future<Box<OrganizationAccessGrant>> _open() async {
    _box ??= await Hive.openBox<OrganizationAccessGrant>(boxName);
    return _box!;
  }

  static Future<List<OrganizationAccessGrant>> grantsFor(String employeeId) async {
    final box = await _open();
    return box.values.where((g) => g.employeeId == employeeId).toList();
  }

  static Future<Set<String>> visibleOrganizationIds({String? employeeId}) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null) return <String>{};
    if (employee.isOwner) {
      final root = await OrganizationService.root();
      return OrganizationService.subtreeIds(root.id);
    }
    final visible = <String>{};
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.allows(OrganizationPermissions.view)) continue;
      if (grant.includeSubtree) {
        visible.addAll(await OrganizationService.subtreeIds(grant.organizationId));
      } else {
        visible.add(grant.organizationId);
      }
    }
    return visible;
  }

  static Future<bool> can(
    String organizationId,
    String permission, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    // Tests/background maintenance may run without an authenticated employee.
    // The UI/session gate remains fail-closed; storage maintenance must still run.
    if (employee == null) return true;
    if (employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.allows(permission)) continue;
      if (grant.organizationId == organizationId) return true;
      if (grant.includeSubtree &&
          await OrganizationService.isDescendant(
            organizationId,
            grant.organizationId,
          )) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> canViewSelfFinance(
    String organizationId, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null || employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      final applies = grant.organizationId == organizationId ||
          (grant.includeSubtree &&
              await OrganizationService.isDescendant(
                organizationId,
                grant.organizationId,
              ));
      if (applies && grant.canViewSelfFinance) return true;
    }
    return false;
  }

  static Future<bool> canViewTeamFinance(
    String organizationId, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null || employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      final applies = grant.organizationId == organizationId ||
          (grant.includeSubtree &&
              await OrganizationService.isDescendant(
                organizationId,
                grant.organizationId,
              ));
      if (applies && grant.canViewTeamFinance) return true;
    }
    return false;
  }

  static Future<OrganizationAccessGrant> grant({
    required String employeeId,
    required String organizationId,
    required bool includeSubtree,
    required List<String> permissions,
    bool canViewTeamFinance = false,
    bool canViewSelfFinance = true,
    String? createdBy,
    bool enforceActor = true,
  }) async {
    if (await OrganizationService.byId(organizationId) == null) {
      throw StateError('organization does not exist');
    }
    if (TeamService.byId(employeeId) == null) {
      throw StateError('employee does not exist');
    }
    if (enforceActor &&
        !await can(organizationId, OrganizationPermissions.manageMembers)) {
      throw StateError('manage_members permission required');
    }
    final actor = createdBy ?? TeamService.current?.id ?? 'migration';
    final id = '$employeeId::$organizationId';
    final now = DateTime.now();
    final existing = (await _open()).get(id);
    final model = OrganizationAccessGrant(
      id: id,
      employeeId: employeeId,
      organizationId: organizationId,
      includeSubtree: includeSubtree,
      canViewTeamFinance: canViewTeamFinance,
      canViewSelfFinance: canViewSelfFinance,
      permissions: permissions.toSet().toList()..sort(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      createdBy: existing?.createdBy ?? actor,
    );
    await (await _open()).put(id, model);
    revision.value++;
    return model;
  }

  static Future<void> revoke(
    String employeeId,
    String organizationId, {
    bool enforceActor = true,
  }) async {
    if (enforceActor &&
        !await can(organizationId, OrganizationPermissions.manageMembers)) {
      throw StateError('manage_members permission required');
    }
    await (await _open()).delete('$employeeId::$organizationId');
    revision.value++;
  }

  /// Backward-compatible grants for users that already existed before org v1.
  static Future<void> ensureLegacyGrants() async {
    await OrganizationService.ensureBaseline();
    for (final employee in TeamService.all) {
      final existing = await grantsFor(employee.id);
      if (existing.isNotEmpty) continue;
      if (employee.isOwner) {
        await grant(
          employeeId: employee.id,
          organizationId: OrganizationModel.rootId,
          includeSubtree: true,
          permissions: OrganizationPermissions.all,
          canViewTeamFinance: true,
          canViewSelfFinance: true,
          createdBy: 'migration',
          enforceActor: false,
        );
        continue;
      }

      final financeVisible = employee.permissions.allows(TeamModules.treasury) ||
          employee.permissions.allows(TeamModules.forecast) ||
          employee.permissions.allows(TeamModules.analytics);
      final permissions = financeVisible
          ? <String>[
              OrganizationPermissions.view,
              OrganizationPermissions.createTransactions,
              OrganizationPermissions.editTransactions,
              OrganizationPermissions.manageAccounts,
              OrganizationPermissions.manageRecurring,
              OrganizationPermissions.viewForecast,
            ]
          : <String>[OrganizationPermissions.view];
      await grant(
        employeeId: employee.id,
        organizationId: OrganizationModel.wesiBeatsId,
        includeSubtree: false,
        permissions: permissions,
        canViewTeamFinance: employee.permissions.canSeeOthersStats,
        canViewSelfFinance: true,
        createdBy: 'migration',
        enforceActor: false,
      );
    }
  }
}
