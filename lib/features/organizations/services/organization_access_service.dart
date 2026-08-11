import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../team/models/team_permissions.dart';
import '../../team/services/team_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import 'critical_audit_service.dart';
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

  static Map<String, dynamic> _auditJson(OrganizationAccessGrant value) => {
        'id': value.id,
        'employeeId': value.employeeId,
        'organizationId': value.organizationId,
        'includeSubtree': value.includeSubtree,
        'canViewTeamFinance': value.canViewTeamFinance,
        'canViewSelfFinance': value.canViewSelfFinance,
        'permissions': [...value.permissions]..sort(),
        'createdAt': value.createdAt.toIso8601String(),
        'updatedAt': value.updatedAt.toIso8601String(),
        'createdBy': value.createdBy,
      };

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

  static Future<Set<String>> organizationIdsFor(
    String permission, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null) return <String>{};
    if (employee.isOwner) {
      final root = await OrganizationService.root();
      return OrganizationService.subtreeIds(root.id);
    }
    final result = <String>{};
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.allows(permission)) continue;
      if (grant.includeSubtree) {
        result.addAll(await OrganizationService.subtreeIds(grant.organizationId));
      } else {
        result.add(grant.organizationId);
      }
    }
    return result;
  }

  static Future<bool> can(
    String organizationId,
    String permission, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    // Internal maintenance/test code may run before an authenticated session
    // exists. Production write APIs that need an actor must explicitly require
    // one; read/UI boundaries remain fail-closed through OrganizationContext.
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
      if (!grant.allows(OrganizationPermissions.view)) continue;
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

  /// Aggregate finance visibility for an organization. This intentionally does
  /// not grant access to per-employee rows; that remains canViewTeamFinance.
  static Future<bool> canViewOrganizationFinance(
    String organizationId, {
    String? employeeId,
  }) =>
      can(
        organizationId,
        OrganizationPermissions.viewFinance,
        employeeId: employeeId,
      );

  static Future<bool> canViewTeamFinance(
    String organizationId, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null || employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      // Person-level rows are deliberately stricter than aggregate finance:
      // the same grant must carry both finance visibility and the explicit
      // team-finance flag. A stray boolean can never expose coworker rows.
      if (!grant.allows(OrganizationPermissions.viewFinance) ||
          !grant.canViewTeamFinance) {
        continue;
      }
      final applies = grant.organizationId == organizationId ||
          (grant.includeSubtree &&
              await OrganizationService.isDescendant(
                organizationId,
                grant.organizationId,
              ));
      if (applies) return true;
    }
    return false;
  }

  /// Whether the current employee owns an explicit subtree grant that covers
  /// [organizationId]. Owner/root always has this capability.
  static Future<bool> canUseSubtreeFinance(
    String organizationId, {
    String? employeeId,
  }) async {
    final employee = employeeId == null
        ? TeamService.current
        : TeamService.byId(employeeId);
    if (employee == null || employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.includeSubtree ||
          !grant.allows(OrganizationPermissions.viewFinance)) {
        continue;
      }
      if (grant.organizationId == organizationId ||
          await OrganizationService.isDescendant(
            organizationId,
            grant.organizationId,
          )) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _hasSubtreePermissionCapability(
    String organizationId,
    String permission, {
    required String employeeId,
  }) async {
    final employee = TeamService.byId(employeeId);
    if (employee == null) return false;
    if (employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.includeSubtree || !grant.allows(permission)) continue;
      if (grant.organizationId == organizationId ||
          await OrganizationService.isDescendant(
            organizationId,
            grant.organizationId,
          )) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _hasSubtreeTeamFinanceCapability(
    String organizationId, {
    required String employeeId,
  }) async {
    final employee = TeamService.byId(employeeId);
    if (employee == null) return false;
    if (employee.isOwner) return true;
    for (final grant in await grantsFor(employee.id)) {
      if (!grant.includeSubtree ||
          !grant.canViewTeamFinance ||
          !grant.allows(OrganizationPermissions.viewFinance)) {
        continue;
      }
      if (grant.organizationId == organizationId ||
          await OrganizationService.isDescendant(
            organizationId,
            grant.organizationId,
          )) {
        return true;
      }
    }
    return false;
  }

  static void _validateNoSelfElevation(
    OrganizationAccessGrant? existing, {
    required bool includeSubtree,
    required List<String> permissions,
    required bool canViewTeamFinance,
    required bool canViewSelfFinance,
  }) {
    if (existing == null) {
      throw StateError('cannot create own organization grant');
    }
    if (includeSubtree && !existing.includeSubtree) {
      throw StateError('cannot elevate own organization scope');
    }
    final existingPermissions = existing.permissions.toSet();
    for (final permission in permissions) {
      if (!existingPermissions.contains(permission)) {
        throw StateError('cannot add permission to own organization grant');
      }
    }
    if (canViewTeamFinance && !existing.canViewTeamFinance) {
      throw StateError('cannot elevate own team finance access');
    }
    if (canViewSelfFinance && !existing.canViewSelfFinance) {
      throw StateError('cannot elevate own self finance access');
    }
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

    final normalizedPermissions = permissions.toSet().toList()..sort();
    for (final permission in normalizedPermissions) {
      if (!OrganizationPermissions.all.contains(permission)) {
        throw StateError('unknown organization permission: $permission');
      }
    }
    if (canViewTeamFinance &&
        !normalizedPermissions.contains(OrganizationPermissions.viewFinance)) {
      throw StateError('team finance access requires view_finance');
    }

    final id = '$employeeId::$organizationId';
    final box = await _open();
    final existing = box.get(id);
    String actor;

    if (enforceActor) {
      final currentActor = TeamService.current;
      if (currentActor == null) {
        throw StateError('authenticated actor required');
      }
      actor = currentActor.id;

      if (!currentActor.isOwner) {
        if (!await can(
          organizationId,
          OrganizationPermissions.manageMembers,
          employeeId: currentActor.id,
        )) {
          throw StateError('manage_members permission required');
        }

        if (employeeId == currentActor.id) {
          _validateNoSelfElevation(
            existing,
            includeSubtree: includeSubtree,
            permissions: normalizedPermissions,
            canViewTeamFinance: canViewTeamFinance,
            canViewSelfFinance: canViewSelfFinance,
          );
        }

        for (final permission in normalizedPermissions) {
          if (!await can(
            organizationId,
            permission,
            employeeId: currentActor.id,
          )) {
            throw StateError(
              'cannot grant permission not held by actor: $permission',
            );
          }
          if (includeSubtree &&
              !await _hasSubtreePermissionCapability(
                organizationId,
                permission,
                employeeId: currentActor.id,
              )) {
            throw StateError(
              'cannot grant subtree permission outside actor scope: $permission',
            );
          }
        }

        if (canViewTeamFinance) {
          if (!await OrganizationAccessService.canViewTeamFinance(
            organizationId,
            employeeId: currentActor.id,
          )) {
            throw StateError('cannot grant team finance access not held by actor');
          }
          if (includeSubtree &&
              !await _hasSubtreeTeamFinanceCapability(
                organizationId,
                employeeId: currentActor.id,
              )) {
            throw StateError(
              'cannot grant subtree team finance access outside actor scope',
            );
          }
        }
      }
    } else {
      actor = createdBy ?? TeamService.current?.id ?? 'migration';
    }

    final now = DateTime.now();
    final model = OrganizationAccessGrant(
      id: id,
      employeeId: employeeId,
      organizationId: organizationId,
      includeSubtree: includeSubtree,
      canViewTeamFinance: canViewTeamFinance,
      canViewSelfFinance: canViewSelfFinance,
      permissions: normalizedPermissions,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      createdBy: existing?.createdBy ?? actor,
    );
    await box.put(id, model);
    await CriticalAuditService.record(
      event: existing == null ? 'grant.create' : 'grant.update',
      entityType: 'organization_access_grant',
      entityId: id,
      organizationId: organizationId,
      before: existing == null ? null : _auditJson(existing),
      after: _auditJson(model),
      actorId: actor,
      source: enforceActor ? 'user' : 'migration/internal',
    );
    revision.value++;
    return model;
  }

  static Future<void> revoke(
    String employeeId,
    String organizationId, {
    bool enforceActor = true,
  }) async {
    String actor = TeamService.current?.id ?? 'system';
    if (enforceActor) {
      final currentActor = TeamService.current;
      if (currentActor == null) {
        throw StateError('authenticated actor required');
      }
      actor = currentActor.id;
      if (!currentActor.isOwner &&
          !await can(
            organizationId,
            OrganizationPermissions.manageMembers,
            employeeId: currentActor.id,
          )) {
        throw StateError('manage_members permission required');
      }
    }
    final box = await _open();
    final id = '$employeeId::$organizationId';
    final before = box.get(id);
    await box.delete(id);
    if (before != null) {
      await CriticalAuditService.record(
        event: 'grant.revoke',
        entityType: 'organization_access_grant',
        entityId: id,
        organizationId: organizationId,
        before: _auditJson(before),
        after: null,
        actorId: actor,
        source: enforceActor ? 'user' : 'migration/internal',
      );
    }
    revision.value++;
  }

  /// Backward-compatible grants for users that already existed before org v1.
  /// Existing users belong to Wesi Inc. Child organizations are granted only
  /// explicitly, except for the root owner who always owns the whole subtree.
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
              OrganizationPermissions.viewFinance,
              OrganizationPermissions.createTransactions,
              OrganizationPermissions.editTransactions,
              OrganizationPermissions.manageAccounts,
              OrganizationPermissions.manageRecurring,
              OrganizationPermissions.viewForecast,
            ]
          : <String>[OrganizationPermissions.view];
      await grant(
        employeeId: employee.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        permissions: permissions,
        canViewTeamFinance:
            financeVisible && employee.permissions.canSeeOthersStats,
        canViewSelfFinance: true,
        createdBy: 'migration',
        enforceActor: false,
      );
    }
  }
}
