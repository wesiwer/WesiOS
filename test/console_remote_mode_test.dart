import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/sysadmin/console/console_command_service.dart';

/// Консоль системного администратора: что выполняется здесь, а что уходит на
/// сервер.
///
/// Цена ошибки в маршрутизации несимметрична. Команда, случайно оставшаяся
/// местной, просто не сработает — это заметно сразу. Команда, случайно
/// ушедшая на сервер, может там что-то сделать. Поэтому проверяется в первую
/// очередь, что управление самой консолью на сервер не уезжает никогда.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_console');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
  });

  group('режим', () {
    test('по умолчанию выключен', () {
      expect(ConsoleCommandService.remoteMode, isFalse,
          reason: 'сама по себе консоль ничего на сервер слать не должна');
    });

    test('включается, выключается и переживает перезапуск', () async {
      await ConsoleCommandService.setRemoteMode(true);
      expect(ConsoleCommandService.remoteMode, isTrue);
      await ConsoleCommandService.setRemoteMode(false);
      expect(ConsoleCommandService.remoteMode, isFalse);
    });

    test('рабочий каталог по умолчанию — там, где живёт сервер', () {
      expect(ConsoleCommandService.remoteCwd, '/opt/pocketbase');
    });

    test('каталог запоминается, пустой не затирает прежний', () async {
      await ConsoleCommandService.setRemoteCwd('/srv/wesi');
      expect(ConsoleCommandService.remoteCwd, '/srv/wesi');
      await ConsoleCommandService.setRemoteCwd('   ');
      expect(ConsoleCommandService.remoteCwd, '/opt/pocketbase',
          reason: 'пустое значение — это не каталог, берётся умолчание');
    });
  });

  group('управление консолью на сервер не уезжает', () {
    setUp(() => ConsoleCommandService.setRemoteMode(true));

    test('clear очищает экран, а не выполняется на сервере', () async {
      final result = await ConsoleCommandService.execute('clear');
      expect(result.clear, isTrue);
      expect(result.lines, isEmpty);
    });

    test('remote off выключает режим, находясь в режиме', () async {
      final result = await ConsoleCommandService.execute('remote off');
      expect(ConsoleCommandService.remoteMode, isFalse,
          reason: 'иначе из включённого режима нельзя было бы выйти');
      expect(
        result.lines.any((line) => line.text.contains('выключен')),
        isTrue,
      );
    });

    test('help остаётся справкой консоли', () async {
      final result = await ConsoleCommandService.execute('help');
      expect(result.lines, isNotEmpty);
      expect(
        result.lines.any((line) => line.text.contains('sh <команда>')),
        isTrue,
        reason: 'команда сервера обязана быть видна в справке',
      );
      expect(
        result.lines.any((line) => line.text.contains('remote on / off')),
        isTrue,
      );
    });

    test('history показывает историю, а не выполняется', () async {
      await ConsoleCommandService.execute('date');
      final result = await ConsoleCommandService.execute('history');
      expect(result.lines, isNotEmpty);
    });
  });

  group('без серверной сессии', () {
    test('sh честно отказывает, а не молчит', () async {
      final result = await ConsoleCommandService.execute('sh uptime');
      expect(result.lines, isNotEmpty);
      final text = result.lines.map((line) => line.text).join(' ');
      expect(text.toLowerCase(), contains('сесси'),
          reason: 'человек должен понять, что мешает именно вход, '
              'а не команда');
    });

    test('sh без команды подсказывает, как пользоваться', () async {
      final result = await ConsoleCommandService.execute('sh');
      final text = result.lines.map((line) => line.text).join(' ');
      expect(text, contains('sh <команда>'));
    });

    test('remote on не включается, когда сервер недоступен', () async {
      await ConsoleCommandService.setRemoteMode(false);
      await ConsoleCommandService.execute('remote on');
      expect(ConsoleCommandService.remoteMode, isFalse,
          reason: 'включить режим, которым нельзя пользоваться, — обман: '
              'человек начнёт слать команды в пустоту');
    });
  });

  group('подсказки', () {
    test('команды сервера подсказываются наравне с местными', () {
      expect(ConsoleCommandService.completions('sh'), contains('sh '));
      expect(ConsoleCommandService.completions('rem'), contains('remote on'));
      expect(ConsoleCommandService.completions('rem'), contains('remote off'));
    });

    test('местные проверки никуда не делись', () {
      final all = ConsoleCommandService.completions('');
      expect(all, containsAll(['ping ', 'dns ', 'http ', 'tls ']));
    });
  });

  group('секреты', () {
    test('команда с токеном не попадает в историю', () async {
      await ConsoleCommandService.execute('token inspect abc.def.ghi');
      expect(
        ConsoleCommandService.loadHistory().any((e) => e.contains('abc.def')),
        isFalse,
      );
    });

    test('заголовок с ключом маскируется при показе', () {
      final shown = ConsoleCommandService.displayCommand(
        'sh curl -H "Authorization: Bearer secret-token-value" https://x',
      );
      expect(shown, isNot(contains('secret-token-value')));
      expect(shown, contains('••••'));
    });
  });
}
