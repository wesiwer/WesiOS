import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/widgets/wesi_clock.dart';
import 'package:wesios/features/home/services/alert_service.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('wesios_owner_login');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    directory.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
  });

  group('единый сервер WesiOS', () {
    test('адрес известен без ручной настройки', () {
      expect(SyncEndpoint.isConfigured, isTrue);
      expect(SyncEndpoint.url, SyncEndpoint.defaultUrl);
      expect(SyncEndpoint.rawUrl, 'https://api.wesi-inc.ru');
    });

    test('чужой адрес не заменяет корпоративный сервер', () async {
      await SyncEndpoint.configure(
        url: 'http://203.0.113.10:8090',
        login: 'WesiOff',
      );

      expect(SyncEndpoint.url, SyncEndpoint.defaultUrl);
      expect(SyncEndpoint.login, 'WesiOff');
      expect(
        Hive.box<dynamic>('wesios_settings').get('sync_server_url'),
        SyncEndpoint.defaultUrl,
      );
    });

    test('первый запуск включает безопасные значения', () async {
      await SyncEndpoint.ensureDefaults();
      final settings = Hive.box<dynamic>('wesios_settings');
      expect(settings.get('sync_server_url'), SyncEndpoint.defaultUrl);
      expect(settings.get('sync_enabled'), isTrue);
    });
  });

  test('прочитанное уведомление не возвращается после пересборки', () {
    final first = Alert(
      level: AlertLevel.warning,
      title: 'Сегодня к сроку: 1',
      detail: 'Проверить приложение',
      route: '/tasks',
    );

    AlertService.syncReadFlags([first]);
    expect(AlertService.unreadCount.value, 1);
    AlertService.markAllRead([first]);
    expect(AlertService.unreadCount.value, 0);

    final rebuilt = Alert(
      level: AlertLevel.warning,
      title: 'Сегодня к сроку: 1',
      detail: 'Проверить приложение',
      route: '/tasks',
    );
    AlertService.syncReadFlags([rebuilt]);

    expect(rebuilt.read, isTrue);
    expect(AlertService.unreadCount.value, 0);
  });

  testWidgets('часы содержат компактную сетку календаря', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 270, child: WesiClock(showSeconds: false)),
        ),
      ),
    );

    expect(find.byType(WesiClock), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
