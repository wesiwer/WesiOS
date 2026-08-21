import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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

void main() {
  late Directory tempDir;
  late _JsonCollection collection;
  late Box<String> business;

  String row(String id, String value) => jsonEncode(<String, dynamic>{
        'id': id,
        'value': value,
      });

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_local_backup_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    final settings = Hive.isBoxOpen('wesios_settings')
        ? Hive.box<dynamic>('wesios_settings')
        : await Hive.openBox<dynamic>('wesios_settings');
    await settings.clear();
    collection = _JsonCollection('tasks', 'test_backup_tasks');
    business = await collection.ensureBox();
    await business.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('portable backup restores deleted local rows and business settings', () async {
    await business.put('a', row('a', 'phone-a'));
    await business.put('b', row('b', 'phone-b'));
    final settings = Hive.box<dynamic>('wesios_settings');
    await settings.put('categories_income_ru', <String>['Продажи', 'Другое']);
    await settings.put('sync_session_token', 'must-not-leave-device');

    final backup = await LocalBackupService.create(
      collections: <SyncCollection<dynamic>>[collection],
    );

    expect(backup.records, 2);
    expect(backup.settingsCount, 1);
    expect(backup.fileName, endsWith('.wesibackup'));

    await business.clear();
    await settings.delete('categories_income_ru');

    final report = await LocalBackupService.restore(
      backup.bytes,
      collections: <SyncCollection<dynamic>>[collection],
      manageSafety: false,
    );

    expect(report.ok, isTrue);
    expect(report.restored, 2);
    expect(jsonDecode(business.get('a')!)['value'], 'phone-a');
    expect(jsonDecode(business.get('b')!)['value'], 'phone-b');
    expect(settings.get('categories_income_ru'), <String>['Продажи', 'Другое']);
    expect(settings.get('sync_session_token'), isNull);
  });

  test('checksum mismatch is rejected before local data changes', () async {
    await business.put('a', row('a', 'safe-local'));
    final backup = await LocalBackupService.create(
      collections: <SyncCollection<dynamic>>[collection],
      includeBusinessSettings: false,
    );
    final envelope = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(backup.bytes)) as Map,
    );
    envelope['payloadSha256'] = '0' * 64;
    final corrupted = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));

    final report = await LocalBackupService.restore(
      corrupted,
      collections: <SyncCollection<dynamic>>[collection],
      manageSafety: false,
    );

    expect(report.ok, isFalse);
    expect(report.errorCode, 'BACKUP_CHECKSUM_MISMATCH');
    expect(jsonDecode(business.get('a')!)['value'], 'safe-local');
  });
}
