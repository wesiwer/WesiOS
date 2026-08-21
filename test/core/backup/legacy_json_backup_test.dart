import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/backup/legacy_json_backup.dart';
import 'package:wesios/core/backup/local_backup_service.dart';
import 'package:wesios/core/sync/sync_codec.dart';

class _JsonCollection extends SyncCollection<String> {
  @override
  final String name;
  @override
  final String boxName;

  _JsonCollection(this.name, this.boxName);

  Map<String, dynamic> _json(String raw) =>
      Map<String, dynamic>.from(jsonDecode(raw) as Map);

  @override
  String idOf(String value) => '${_json(value)['id']}';

  @override
  Map<String, dynamic> encode(String value) => _json(value);

  @override
  String? decode(Map<String, dynamic> fields) {
    final id = fields['id'];
    if (id is! String || id.isEmpty) return null;
    return jsonEncode(fields);
  }
}

Uint8List _officialV1() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'format': 1,
      'app': 'WesiOS',
      'exportedAt': '2026-07-29T22:16:05.000Z',
      'transactions': [
        {
          'id': 'tx-old-1',
          'title': 'Старая продажа',
          'amount': 12500,
          'type': 'income',
          'date': '2026-07-20T12:00:00.000Z',
          'category': 'Продажи',
          'description': 'Из старой JSON-копии',
          'isRecurring': false,
          'recurringPeriod': null,
          'isAnomaly': false,
          'accountId': 'main',
        },
      ],
      'tasks': [
        {
          'id': 'task-old-1',
          'title': 'Старая задача',
          'description': null,
          'status': 'done',
          'priority': 'normal',
          'createdAt': '2026-07-19T10:00:00.000Z',
          'dueDate': null,
          'assignee': null,
          'tags': ['legacy'],
          'subtasks': <Map<String, dynamic>>[],
        },
      ],
      'accounts': [
        {
          'id': 'main',
          'name': 'Основной',
          'kind': 'main',
          'openingBalance': 5000,
          'colorValue': 0xFFF97316,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'archived': false,
          'note': null,
        },
      ],
      'articles': <Map<String, dynamic>>[],
    }),
  ),
);

void main() {
  late Directory tempDir;
  late _JsonCollection transactions;
  late _JsonCollection accounts;
  late _JsonCollection tasks;
  late _JsonCollection articles;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_legacy_backup_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    final settings = Hive.isBoxOpen('wesios_settings')
        ? Hive.box<dynamic>('wesios_settings')
        : await Hive.openBox<dynamic>('wesios_settings');
    await settings.clear();

    transactions = _JsonCollection(
      'transactions',
      'test_legacy_backup_transactions',
    );
    accounts = _JsonCollection('accounts', 'test_legacy_backup_accounts');
    tasks = _JsonCollection('tasks', 'test_legacy_backup_tasks');
    articles = _JsonCollection('articles', 'test_legacy_backup_articles');
    for (final collection in [transactions, accounts, tasks, articles]) {
      final box = await collection.ensureBox();
      await box.clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('recognises the official July 2026 JSON format', () {
    final raw = jsonDecode(utf8.decode(_officialV1()));
    expect(LegacyJsonBackup.looksLike(raw), isTrue);

    final parsed = LegacyJsonBackup.parse(
      Map<dynamic, dynamic>.from(raw as Map),
    );
    expect(parsed.collections['transactions'], hasLength(1));
    final fields = parsed.collections['transactions']!.single['fields'] as Map;
    expect(fields['organizationId'], 'org_wesi_inc');
    expect(fields['source'], 'import');
    expect(fields['originalCurrency'], 'RUB');
    expect(fields['organizationBaseAmount'], 12500.0);
    expect(fields['fxRateToReporting'], 1.0);
  });

  test(
    'legacy JSON restores finance and keeps unrelated current rows',
    () async {
      final transactionBox = await transactions.ensureBox();
      await transactionBox.put(
        'current-only',
        jsonEncode({'id': 'current-only', 'value': 'must-survive'}),
      );

      final backup = _officialV1();
      final inspection = LocalBackupService.inspect(backup);
      expect(inspection.records, 3);
      expect(inspection.counts['transactions'], 1);
      expect(inspection.counts['accounts'], 1);

      final report = await LocalBackupService.restore(
        backup,
        collections: <SyncCollection<dynamic>>[
          accounts,
          transactions,
          tasks,
          articles,
        ],
        manageSafety: false,
      );

      expect(report.ok, isTrue, reason: report.message);
      expect(report.restored, 3);
      expect(transactionBox.containsKey('current-only'), isTrue);
      expect(transactionBox.containsKey('tx-old-1'), isTrue);

      final restored = jsonDecode(transactionBox.get('tx-old-1')!) as Map;
      expect(restored['amount'], 12500.0);
      expect(restored['organizationId'], 'org_wesi_inc');
      expect(restored['source'], 'import');
    },
  );

  test('unrelated JSON is rejected instead of guessed', () {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode({'format': 1, 'app': 'Other'})),
    );
    expect(
      () => LocalBackupService.inspect(bytes),
      throwsA(
        isA<LocalBackupException>().having(
          (error) => error.code,
          'code',
          'BACKUP_FORMAT_INVALID',
        ),
      ),
    );
  });
}
