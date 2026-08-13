import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/sysadmin/services/network_probe.dart';

/// «Агент указан, но не отвечает по этому адресу».
///
/// Эта фраза была неправдой в самом частом случае. Сервер уводил каждый
/// неизвестный адрес на портал, `/wesios-status.json` отвечал перенаправлением
/// и отдавал HTML страницы, приложение не могло разобрать его как JSON — и
/// сообщало, что агент молчит. Агент при этом мог работать безупречно: до
/// его файла просто не доходил запрос.
///
/// Цена такой формулировки — потерянное время: человек идёт чинить агент,
/// перезапускает таймер, смотрит логи, а чинить надо было адрес.
///
/// Здесь поднимается настоящий HTTP-сервер и проверяется, что каждая
/// причина названа своим именем.
void main() {
  late HttpServer server;
  late String base;
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      await handler(request);
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  test('исправный агент читается', () async {
    handler = (request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'at': DateTime.now().toUtc().toIso8601String(),
          'load1': 0.42,
          'cores': 4,
          'mem_used_mb': 1200,
          'mem_total_mb': 4096,
          'disk_used_gb': 12,
          'disk_total_gb': 40,
          'uptime_sec': 90000,
        }));
    };

    final probe = await NetworkProbe.load('$base/wesios-status.json');

    expect(probe.isOk, isTrue);
    expect(probe.load!.cores, 4);
    expect(probe.load!.cpuFraction, closeTo(.105, .001));
  });

  test('страница вместо агента — это не молчание агента', () async {
    // Ровно то, что происходило на живом сервере: 200 и HTML портала.
    handler = (request) async {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<!DOCTYPE html><html><body>портал</body></html>');
    };

    final probe = await NetworkProbe.load('$base/wesios-status.json');

    expect(probe.isOk, isFalse);
    expect(probe.failure, ServerLoadFailure.notJson);
    expect(probe.detail, contains('веб-страница'));
  });

  test('файла нет — это 404, а не молчание', () async {
    handler = (request) async {
      request.response.statusCode = 404;
    };

    final probe = await NetworkProbe.load('$base/wesios-status.json');

    expect(probe.failure, ServerLoadFailure.httpError);
    expect(probe.statusCode, 404);
  });

  test('JSON без полей агента отличается от чужой страницы', () async {
    handler = (request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok'}));
    };

    final probe = await NetworkProbe.load('$base/wesios-status.json');

    expect(probe.failure, ServerLoadFailure.wrongShape);
    expect(probe.detail, contains('load1'));
  });

  test('узел действительно не отвечает', () async {
    await server.close(force: true);

    final probe = await NetworkProbe.load(
      '$base/wesios-status.json',
      timeout: const Duration(seconds: 2),
    );

    expect(probe.failure, ServerLoadFailure.unreachable);
  });

  test('мусор вместо адреса', () async {
    final probe = await NetworkProbe.load('не адрес');
    expect(probe.failure, ServerLoadFailure.badAddress);
  });

  test('перенаправление на страницу тоже опознаётся', () async {
    // Живой случай целиком: 308 на портал, портал отдаёт HTML.
    handler = (request) async {
      if (request.uri.path == '/wesios-status.json') {
        request.response
          ..statusCode = 308
          ..headers.set(HttpHeaders.locationHeader, '/portal/');
        return;
      }
      request.response
        ..headers.contentType = ContentType.html
        ..write('<!DOCTYPE html><html><body>портал</body></html>');
    };

    final probe = await NetworkProbe.load('$base/wesios-status.json');

    expect(probe.isOk, isFalse);
    expect(probe.failure, ServerLoadFailure.notJson,
        reason: 'перенаправление доводит до страницы, а не до агента');
  });
}
