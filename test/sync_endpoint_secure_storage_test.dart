import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_secure_session_test');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  setUp(() async {
    await SyncEndpoint.clearSession();
    await Hive.box<dynamic>('wesios_settings').clear();
  });

  tearDownAll(() async {
    await SyncEndpoint.clearSession();
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('WesiOS auth token and session id are never persisted in Hive', () async {
    const token = 'secret-pocketbase-token-for-test';
    const sessionId = 'secure-session-id-for-test-1234567890';

    await SyncEndpoint.saveSession(
      token: token,
      userId: 'user-1',
      sessionId: sessionId,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    expect(SyncEndpoint.isConnected, isTrue);

    final box = Hive.box<dynamic>('wesios_settings');
    expect(box.get('sync_session'), isNull,
        reason: 'legacy plaintext session key must never be recreated');

    final strings = box.values.whereType<String>().toList(growable: false);
    expect(strings.any((value) => value.contains(token)), isFalse,
        reason: 'PocketBase token leaked into ordinary Hive settings');
    expect(strings.any((value) => value.contains(sessionId)), isFalse,
        reason: 'revocable WesiOS session id leaked into ordinary Hive settings');
  });
}
