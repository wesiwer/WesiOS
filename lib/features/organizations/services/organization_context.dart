import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../team/services/team_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import 'organization_access_service.dart';
import 'organization_service.dart';

enum OrganizationScope { only, subtree }

class OrganizationContext {
  OrganizationContext._();

  static const String settingsBox = 'wesios_settings';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? get _settings {
    try {
      return Hive.box<dynamic>(settingsBox);
    } catch (_) {
      return null;
    }
  }

  static String get _userKey => TeamService.current?.id ?? 'local';
  static String get _orgKey => 'organization_context.$_userKey.organization';
  static String get _scopeKey => 'organization_context.$_userKey.scope';

  static String get currentOrganizationId {
    final value = _settings?.get(_orgKey);
    if (value is String && value.isNotEmpty) return value;
    return OrganizationModel.rootId;
  }

  static OrganizationScope get scope {
    final raw = _settings?.get(_scopeKey);
    return raw == OrganizationScope.subtree.name
        ? OrganizationScope.subtree
        : OrganizationScope.only;
  }

  static Future<void> initialize() async {
    await OrganizationService.ensureBaseline();

    final stored = currentOrganizationId;
    final org = await OrganizationService.byId(stored);
    final employee = TeamService.current;
    if (org != null &&
        !org.archived &&
        (employee == null ||
            await OrganizationAccessService.can(
              org.id,
              OrganizationPermissions.view,
            ))) {
      return;
    }

    final visible = employee == null
        ? <String>{OrganizationModel.rootId}
        : await OrganizationAccessService.visibleOrganizationIds();
    String fallback;
    if (visible.contains(OrganizationModel.rootId)) {
      fallback = OrganizationModel.rootId;
    } else if (visible.isNotEmpty) {
      fallback = visible.first;
    } else {
      // Keep a deterministic local context even when the signed-in employee
      // currently has no organization grant. Data services remain fail-closed,
      // so this does not create access to Wesi Inc.
      fallback = OrganizationModel.rootId;
    }
    await _settings?.put(_orgKey, fallback);
    await _settings?.put(_scopeKey, OrganizationScope.only.name);
    revision.value++;
  }

  static Future<void> selectOrganization(String organizationId) async {
    final org = await OrganizationService.byId(organizationId);
    if (org == null || org.archived) throw StateError('organization unavailable');
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          organizationId,
          OrganizationPermissions.view,
        )) {
      throw StateError('organization access denied');
    }
    await _settings?.put(_orgKey, organizationId);
    revision.value++;
  }

  static Future<void> setScope(OrganizationScope value) async {
    await _settings?.put(_scopeKey, value.name);
    revision.value++;
  }

  static Future<Set<String>> effectiveOrganizationIds() async {
    await initialize();
    final current = currentOrganizationId;
    final requested = scope == OrganizationScope.subtree
        ? await OrganizationService.subtreeIds(current)
        : <String>{current};
    if (TeamService.current == null) return requested;
    final allowed = await OrganizationAccessService.visibleOrganizationIds();
    return requested.intersection(allowed);
  }

  static Future<OrganizationModel> currentOrganization() async {
    await initialize();
    return await OrganizationService.byId(currentOrganizationId) ??
        await OrganizationService.root();
  }
}
