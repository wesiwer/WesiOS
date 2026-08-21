/// Reader for the original human-readable WesiOS JSON backup introduced in
/// July 2026. It converts that immutable v1 schema into current sync payloads;
/// LocalBackupService then decodes/encodes them through today's codecs before
/// touching Hive.
class LegacyJsonBackup {
  final DateTime createdAt;
  final Map<String, List<Map<String, dynamic>>> collections;

  const LegacyJsonBackup({required this.createdAt, required this.collections});

  static bool looksLike(Object? raw) {
    if (raw is! Map) return false;
    final version = raw['format'];
    return version is num &&
        version.toInt() == 1 &&
        '${raw['app'] ?? ''}' == 'WesiOS' &&
        raw.containsKey('transactions') &&
        raw.containsKey('tasks') &&
        raw.containsKey('accounts') &&
        raw.containsKey('articles');
  }

  static LegacyJsonBackup parse(Map<dynamic, dynamic> raw) {
    if (!looksLike(raw)) {
      throw const FormatException('Это не старая резервная копия WesiOS');
    }
    final exportedAt = DateTime.tryParse('${raw['exportedAt'] ?? ''}');
    if (exportedAt == null) {
      throw const FormatException('В старой копии повреждена дата экспорта');
    }

    final accounts = <Map<String, dynamic>>[];
    for (final row in _rows(raw, 'accounts')) {
      final kind = _text(row, 'kind', 'счета');
      if (!const <String>{
        'main',
        'card',
        'cash',
        'savings',
        'project',
        'reserve',
        'other',
      }.contains(kind)) {
        throw const FormatException('В старой копии неизвестный тип счёта');
      }
      accounts.add({
        'id': _text(row, 'id', 'счета'),
        'name': _text(row, 'name', 'счета'),
        'kind': kind,
        'openingBalance': _number(row, 'openingBalance', 'счета'),
        'colorValue': row['colorValue'] is num
            ? (row['colorValue'] as num).toInt()
            : 0xFFF97316,
        'createdAt': _date(row, 'createdAt', 'счета').toIso8601String(),
        'archived': row['archived'] == true,
        'note': _optionalText(row['note']),
        'organizationId': 'org_wesi_inc',
        'minimumBalance': 0.0,
        'allowNetting': true,
        'currency': 'RUB',
        'fxHaircut': 0.03,
        'transferDelayDays': 0,
      });
    }

    final transactions = <Map<String, dynamic>>[];
    for (final row in _rows(raw, 'transactions')) {
      final type = _text(row, 'type', 'операции');
      if (type != 'income' && type != 'expense') {
        throw const FormatException('В старой копии неизвестный тип операции');
      }
      final recurring = row['isRecurring'] == true;
      final period = _optionalText(row['recurringPeriod']);
      if (period != null &&
          !const <String>{
            'daily',
            'weekly',
            'monthly',
            'yearly',
          }.contains(period)) {
        throw const FormatException(
          'В старой копии неизвестный период регулярной операции',
        );
      }
      final amount = _number(row, 'amount', 'операции');
      transactions.add({
        'id': _text(row, 'id', 'операции'),
        'title': _text(row, 'title', 'операции'),
        'amount': amount,
        'type': type,
        'date': _date(row, 'date', 'операции').toIso8601String(),
        'category': _optionalText(row['category']),
        'description': _optionalText(row['description']),
        'isRecurring': recurring,
        'recurringPeriod': recurring ? period : null,
        'isAnomaly': row['isAnomaly'] == true,
        'zScore': null,
        'accountId': _optionalText(row['accountId']),
        'organizationId': 'org_wesi_inc',
        'projectId': null,
        'counterpartyId': null,
        'source': 'import',
        'createdBy': 'legacy-backup-v1',
        'updatedBy': 'legacy-backup-v1',
        'updatedAt': exportedAt.toUtc().toIso8601String(),
        'ownerEmployeeId': null,
        'interOrgTransferId': null,
        'createdByEmployeeId': null,
        'originalAmount': amount,
        'originalCurrency': 'RUB',
        'organizationBaseAmount': amount,
        'organizationBaseCurrency': 'RUB',
        'fxRateToReporting': 1.0,
        'fxRateAt': null,
        'fxSource': 'legacy-backup-v1',
      });
    }

    final tasks = <Map<String, dynamic>>[];
    for (final row in _rows(raw, 'tasks')) {
      final status = _text(row, 'status', 'задачи');
      final priority = _text(row, 'priority', 'задачи');
      if (!const <String>{
        'backlog',
        'inProgress',
        'review',
        'done',
      }.contains(status)) {
        throw const FormatException('В старой копии неизвестный статус задачи');
      }
      if (!const <String>{
        'low',
        'normal',
        'high',
        'urgent',
      }.contains(priority)) {
        throw const FormatException(
          'В старой копии неизвестный приоритет задачи',
        );
      }
      final subtasks = <Map<String, dynamic>>[];
      final rawSubtasks = row['subtasks'];
      if (rawSubtasks is List) {
        for (final value in rawSubtasks) {
          if (value is! Map || value['title'] is! String) {
            throw const FormatException(
              'В старой копии повреждён список подзадач',
            );
          }
          subtasks.add({
            'title': value['title'],
            'done': value['done'] == true,
          });
        }
      }
      final rawTags = row['tags'];
      tasks.add({
        'id': _text(row, 'id', 'задачи'),
        'title': _text(row, 'title', 'задачи'),
        'description': _optionalText(row['description']),
        'status': status,
        'priority': priority,
        'createdAt': _date(row, 'createdAt', 'задачи').toIso8601String(),
        'dueDate': _optionalDate(row, 'dueDate', 'задачи')?.toIso8601String(),
        'assignee': _optionalText(row['assignee']),
        'subtasks': subtasks,
        'tags': rawTags is List
            ? [for (final tag in rawTags) '$tag']
            : <String>[],
        'order': 0,
        'organizationId': 'org_wesi_inc',
        'responsibleEmployeeId': null,
      });
    }

    final articles = <Map<String, dynamic>>[];
    for (final row in _rows(raw, 'articles')) {
      final section = _text(row, 'section', 'база знаний');
      if (!const <String>{
        'about',
        'playbook',
        'guide',
        'finance',
        'personal',
      }.contains(section)) {
        throw const FormatException(
          'В старой копии неизвестный раздел базы знаний',
        );
      }
      final rawTags = row['tags'];
      articles.add({
        'id': _text(row, 'id', 'база знаний'),
        'title': _text(row, 'title', 'база знаний'),
        'body': row['body'] is String ? row['body'] : '',
        'section': section,
        'tags': rawTags is List
            ? [for (final tag in rawTags) '$tag']
            : <String>[],
        'createdAt': _date(row, 'createdAt', 'база знаний').toIso8601String(),
        'updatedAt': _date(row, 'updatedAt', 'база знаний').toIso8601String(),
        'builtIn': false,
        'pinned': row['pinned'] == true,
        'parentId': null,
        'isFolder': false,
        'orderRaw': null,
      });
    }

    List<Map<String, dynamic>> pack(List<Map<String, dynamic>> values) => [
      for (final fields in values) {'id': fields['id'], 'fields': fields},
    ];

    return LegacyJsonBackup(
      createdAt: exportedAt,
      collections: {
        // Dependencies first: transactions keep their old accountId.
        'accounts': pack(accounts),
        'transactions': pack(transactions),
        'tasks': pack(tasks),
        'articles': pack(articles),
      },
    );
  }

  static List<Map<String, dynamic>> _rows(
    Map<dynamic, dynamic> raw,
    String key,
  ) {
    final source = raw[key];
    if (source is! List) {
      throw FormatException('Раздел $key в старой копии повреждён');
    }
    final out = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (var i = 0; i < source.length; i++) {
      final value = source[i];
      if (value is! Map) {
        throw FormatException('Запись ${i + 1} в разделе $key повреждена');
      }
      final row = Map<String, dynamic>.from(value);
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty || !ids.add(id)) {
        throw FormatException(
          'В разделе $key найден пустой или повторяющийся идентификатор',
        );
      }
      out.add(row);
    }
    return out;
  }

  static String _text(Map<String, dynamic> row, String key, String section) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Повреждено поле $key раздела $section');
  }

  static double _number(Map<String, dynamic> row, String key, String section) {
    final value = row[key];
    if (value is num) return value.toDouble();
    throw FormatException('Повреждено числовое поле $key раздела $section');
  }

  static DateTime _date(Map<String, dynamic> row, String key, String section) {
    final value = row[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed != null) return parsed;
    throw FormatException('Повреждена дата $key раздела $section');
  }

  static DateTime? _optionalDate(
    Map<String, dynamic> row,
    String key,
    String section,
  ) {
    if (row[key] == null) return null;
    return _date(row, key, section);
  }

  static String? _optionalText(Object? value) => value is String ? value : null;
}
