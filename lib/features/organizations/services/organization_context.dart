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

    // Организация должна не только существовать и быть разрешённой, но и
    // находиться в дереве — то есть быть достижимой от корня.
    //
    // Без этой проверки у владельца проверка вырождалась в ничто: право на
    // просмотр у него есть на любую организацию, поэтому запись с исчезнувшим
    // родителем проходила насквозь. Дальше её пересекали с деревом, получали
    // пусто, и каждый финансовый экран падал с «нет права на прогноз» — при
    // том, что прав у владельца в избытке, а не было как раз организации.
    final visible = employee == null
        ? await _rootSubtree()
        : await OrganizationAccessService.visibleOrganizationIds();

    if (org != null &&
        !org.archived &&
        visible.contains(org.id) &&
        (employee == null ||
            await OrganizationAccessService.can(
              org.id,
              OrganizationPermissions.view,
            ))) {
      return;
    }
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
    if (org == null || org.archived) {
      throw StateError('organization unavailable');
    }
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

  static Set<String> _failClosedFallback() {
    final employee = TeamService.current;
    if (employee == null || employee.isOwner) {
      return <String>{OrganizationModel.rootId};
    }
    return <String>{};
  }

  static Future<Set<String>> effectiveOrganizationIds() async {
    try {
      await initialize();
      final current = currentOrganizationId;
      final requested = scope == OrganizationScope.subtree
          ? await OrganizationService.subtreeIds(current)
          : <String>{current};
      if (TeamService.current == null) return requested;
      final allowed = await OrganizationAccessService.visibleOrganizationIds();
      final result = requested.intersection(allowed);
      // Пусто при непустом `allowed` — это не «доступа нет», а «выбранная
      // организация устарела»: её удалили, заархивировали или у неё исчез
      // родитель. Возвращать пустой список в этом случае нельзя: для всего
      // финансового он означает «данных нет вообще», и человек получает
      // отказ по правам там, где права ни при чём.
      if (result.isEmpty && allowed.isNotEmpty) {
        return <String>{
          allowed.contains(OrganizationModel.rootId)
              ? OrganizationModel.rootId
              : allowed.first,
        };
      }
      return result;
    } catch (_) {
      // During early UI bootstrap/tests organization Hive adapters may not yet
      // be available. Never broaden a normal employee's access on that path.
      return _failClosedFallback();
    }
  }

  /// Всё дерево от корня. Нужно, чтобы отличить существующую организацию
  /// от достижимой: запись может лежать в хранилище и при этом не иметь пути
  /// до корня — например, когда её родителя удалили.
  static Future<Set<String>> _rootSubtree() async {
    final root = await OrganizationService.root();
    return OrganizationService.subtreeIds(root.id);
  }

  static Future<OrganizationModel> currentOrganization() async {
    await initialize();
    return await OrganizationService.byId(currentOrganizationId) ??
        await OrganizationService.root();
  }
}
