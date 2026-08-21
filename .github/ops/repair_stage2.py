from pathlib import Path

# Recovery: semantic organization verification after server-side legacy normalization.
p = Path('lib/core/sync/sync_recovery.dart')
s = p.read_text(encoding='utf-8')
target = '_sameValue(remote.fields, entry.value)'
if s.count(target) != 2:
    raise SystemExit(f'unexpected raw verification comparisons: {s.count(target)}')
s = s.replace(target, 'samePayloadForVerification(collection, remote.fields, entry.value)')

anchor = '  static bool _sameSnapshot(_RecoverySnapshot a, _RecoverySnapshot b) {'
if anchor not in s:
    raise SystemExit('recovery helper anchor missing')
helper = r'''  @visibleForTesting
  static bool samePayloadForVerification(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    if (_sameValue(remote, local)) return true;
    final a = _verificationPayload(collection, remote);
    final b = _verificationPayload(collection, local);
    return a != null && b != null && _sameValue(a, b);
  }

  static Map<String, dynamic>? _verificationPayload(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> fields,
  ) {
    if (collection.name != 'organizations') {
      return Map<String, dynamic>.from(fields);
    }
    try {
      final model = collection.decode(Map<String, dynamic>.from(fields));
      if (model == null) return null;
      final out = Map<String, dynamic>.from(collection.encode(model));
      final currency = '${out['baseCurrency'] ?? ''}'.trim();
      if (currency.isEmpty) out['baseCurrency'] = 'RUB';
      final createdBy = '${out['createdBy'] ?? ''}'.trim();
      if (createdBy.isEmpty) out['createdBy'] = 'sync-server';
      return out;
    } catch (_) {
      return null;
    }
  }

  static String _collectionLabel(String name) {
    const labels = <String, String>{
      'organizations': 'Организации',
      'employees': 'Сотрудники',
      'organization_grants': 'Права сотрудников',
      'accounts': 'Счета',
      'finance_categories': 'Финансовые категории',
      'transactions': 'Операции',
      'inter_org_transfers': 'Переводы между организациями',
      'tasks': 'Задачи',
      'task_ai_memory': 'Память задач',
      'roadmap_projects': 'Roadmap',
      'roadmap_items': 'Roadmap',
      'crm_clients': 'CRM',
      'crm_deals': 'CRM',
      'crm_interactions': 'CRM',
      'sandbox_transactions': 'Песочница',
      'what_if_presets': 'Сценарии What-if',
      'transaction_audit': 'История финансов',
      'critical_audit': 'Журнал безопасности',
    };
    return labels[name] ?? 'Данные WesiOS';
  }

  static String? _verificationDifference(
    SyncCollection<dynamic> collection,
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    final a = _verificationPayload(collection, remote);
    final b = _verificationPayload(collection, local);
    if (a == null || b == null) return 'некорректная структура ответа';
    final keys = <String>{...a.keys, ...b.keys}.toList()..sort();
    const labels = <String, String>{
      'id': 'идентификатор',
      'name': 'название',
      'parentId': 'родительская организация',
      'isRoot': 'тип организации',
      'baseCurrency': 'валюта',
      'status': 'статус',
      'createdAt': 'дата создания',
      'updatedAt': 'дата изменения',
      'createdBy': 'источник создания',
      'code': 'код',
      'description': 'описание',
      'colorValue': 'цвет',
      'sortOrder': 'порядок',
    };
    for (final key in keys) {
      if (!_sameValue(a[key], b[key])) return labels[key] ?? 'данные записи';
    }
    return null;
  }

'''
s = s.replace(anchor, helper + anchor, 1)

old = '''    var verified = 0;\n    String? firstMismatch;\n    for (final entry in localRows.entries) {\n      final remote = after.value![entry.key];\n      if (remote != null &&\n          !remote.deleted &&\n          samePayloadForVerification(collection, remote.fields, entry.value)) {\n        verified++;\n      } else {\n        firstMismatch ??= entry.key;\n      }\n    }\n\n    if (verified != localRows.length) {\n      final rejected = pushed.authoritativeIds.isNotEmpty\n          ? pushed.authoritativeIds.first\n          : firstMismatch;\n      return SyncRecoveryCollectionReport(\n        collection: collection.name,\n        local: localRows.length,\n        uploaded: pushed.sent,\n        verified: verified,\n        failure: SyncFailure(\n          'RECOVERY_VERIFY_FAILED',\n          'После отправки не совпала ${collection.name}:${rejected ?? '?'}',\n        ),\n      );\n    }\n'''
new = '''    var verified = 0;\n    String? firstMismatch;\n    String? firstMismatchDetail;\n    for (final entry in localRows.entries) {\n      final remote = after.value![entry.key];\n      if (remote != null &&\n          !remote.deleted &&\n          samePayloadForVerification(collection, remote.fields, entry.value)) {\n        verified++;\n      } else if (firstMismatch == null) {\n        firstMismatch = entry.key;\n        firstMismatchDetail = remote == null\n            ? 'запись отсутствует на сервере'\n            : remote.deleted\n            ? 'сервер пометил запись удалённой'\n            : _verificationDifference(collection, remote.fields, entry.value);\n      }\n    }\n\n    if (verified != localRows.length) {\n      final detail = firstMismatchDetail;\n      return SyncRecoveryCollectionReport(\n        collection: collection.name,\n        local: localRows.length,\n        uploaded: pushed.sent,\n        verified: verified,\n        failure: SyncFailure(\n          'RECOVERY_VERIFY_FAILED',\n          'Сервер вернул другую версию записи в разделе '\n              '«${_collectionLabel(collection.name)}»'\n              '${detail == null ? '' : ' — $detail'}',\n        ),\n      );\n    }\n'''
if old not in s:
    raise SystemExit('verification result block missing')
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')

# Sync settings backup UX and human-readable collection labels.
p = Path('lib/features/settings/sync_screen.dart')
s = p.read_text(encoding='utf-8')
old = "allowedExtensions: const <String>['wesibackup', 'json'],"
if old not in s:
    raise SystemExit('backup picker anchor missing')
s = s.replace(old, "allowedExtensions: const <String>['wesibackup'],", 1)
old = "? 'Резервная копия подготовлена: ${backup.records} записей и ${backup.settingsCount} бизнес-настроек. Сохраните файл в «Файлы» или другое надёжное место.'"
new = "? 'Резервная копия ${backup.fileName} подготовлена: ${backup.records} записей и ${backup.settingsCount} бизнес-настроек. Сохраните именно этот файл .wesibackup в надёжное место.'"
if old not in s:
    raise SystemExit('backup success text missing')
s = s.replace(old, new, 1)
old = '''    } catch (error) {\n      _say(\n        _ru\n            ? 'Этот файл нельзя восстановить: $error'\n            : 'This file cannot be restored: $error',\n        error: true,\n      );\n      return;\n    }\n'''
new = '''    } on LocalBackupException catch (error) {\n      final text = error.code == 'BACKUP_FORMAT_INVALID'\n          ? (_ru\n                ? 'Выберите файл .wesibackup, созданный кнопкой экспорта резервной копии. Служебный JSON восстановить здесь нельзя.'\n                : 'Choose a .wesibackup file created by Backup export. Internal JSON files cannot be restored here.')\n          : (_ru\n                ? 'Резервная копия не прошла проверку: ${error.message}'\n                : 'Backup validation failed: ${error.message}');\n      _say(text, error: true);\n      return;\n    } catch (_) {\n      _say(\n        _ru\n            ? 'Не удалось прочитать выбранную резервную копию.'\n            : 'Could not read the selected backup.',\n        error: true,\n      );\n      return;\n    }\n'''
if old not in s:
    raise SystemExit('backup error block missing')
s = s.replace(old, new, 1)
s = s.replace("? 'Восстановить из локальной копии'", "? 'Импортировать резервную копию (.wesibackup)'", 1)
s = s.replace("'Restore local backup'", "'Import backup (.wesibackup)'", 1)
old = '''        ? const {\n            'accounts': 'Счета',\n            'transactions': 'Операции',\n            'tasks': 'Задачи',\n            'articles': 'Ваши статьи',\n            'employees': 'Состав',\n          }\n'''
new = '''        ? const {\n            'organizations': 'Организации',\n            'organization_grants': 'Права сотрудников',\n            'accounts': 'Счета',\n            'transactions': 'Операции',\n            'tasks': 'Задачи',\n            'articles': 'База знаний',\n            'employees': 'Сотрудники',\n            'calendar_events': 'Календарь',\n            'user_profiles': 'Профили',\n            'task_ai_memory': 'Память задач',\n            'inter_org_transfers': 'Переводы между организациями',\n            'transaction_audit': 'История финансов',\n            'critical_audit': 'Журнал безопасности',\n            'roadmap_projects': 'Roadmap — проекты',\n            'roadmap_items': 'Roadmap — элементы',\n            'crm_clients': 'CRM — клиенты',\n            'crm_deals': 'CRM — сделки',\n            'crm_interactions': 'CRM — взаимодействия',\n            'finance_categories': 'Финансовые категории',\n            'sandbox_transactions': 'Песочница — операции',\n            'what_if_presets': 'Сценарии What-if',\n          }\n'''
if old not in s:
    raise SystemExit('russian collection map missing')
s = s.replace(old, new, 1)
old = 'names[collection.name] ?? collection.name'
new = "names[collection.name] ?? (_ru ? 'Системные данные WesiOS' : 'WesiOS system data')"
if old not in s:
    raise SystemExit('collection fallback missing')
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')

# Regression test for production read-hook canonicalization.
p = Path('test/core/sync/sync_recovery_test.dart')
s = p.read_text(encoding='utf-8')
marker = "  test('empty server receives snapshot without changing local bytes', () async {"
if marker not in s:
    raise SystemExit('recovery test anchor missing')
test = r'''  test('organization verification accepts server canonical transport shape', () {
    final collection = OrganizationsSync();
    final local = <String, dynamic>{
      'id': 'org_1786636872294887',
      'name': 'Local organization',
      'parentId': 'org_wesi_inc',
      'isRoot': false,
      'baseCurrency': '',
      'status': 'active',
      'createdAt': '2026-08-17T13:19:24.672Z',
      'updatedAt': '2026-08-17T13:19:24.672Z',
      'createdBy': '',
      'code': null,
      'description': null,
      'colorValue': null,
      'sortOrder': 0,
    };
    final remote = <String, dynamic>{
      ...local,
      'baseCurrency': 'RUB',
      'createdBy': 'sync-server',
      'created': '2026-08-17T13:19:24.672Z',
      'updated': '2026-08-17T13:19:24.672Z',
      'archived': false,
    };
    expect(
      SyncRecovery.samePayloadForVerification(collection, remote, local),
      isTrue,
    );
    remote['name'] = 'Different business name';
    expect(
      SyncRecovery.samePayloadForVerification(collection, remote, local),
      isFalse,
    );
  });

'''
s = s.replace(marker, test + marker, 1)
p.write_text(s, encoding='utf-8')
