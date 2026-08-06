import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/sysadmin/console/console_command_service.dart';
import 'package:wesios/features/sysadmin/console/console_templates.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_console_test');
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

  test('help перечисляет реальные диагностические команды', () async {
    final result = await ConsoleCommandService.execute('help');
    final text = result.lines.map((line) => line.text).join('\n');

    expect(text, contains('probe all'));
    expect(text, contains('ping <host>'));
    expect(text, contains('tls <host>'));
    expect(text, contains('ssh-check'));
    expect(text, contains('token inspect'));
    expect(text, contains('Ctrl+A/C/X/V'));
  });

  test('echo учитывает кавычки и сохраняет историю', () async {
    final result = await ConsoleCommandService.execute('echo "hello wesi"');

    expect(result.lines.single.text, 'hello wesi');
    expect(ConsoleCommandService.loadHistory(), ['echo "hello wesi"']);
  });

  test('повтор команды не дублируется в истории', () async {
    await ConsoleCommandService.execute('date');
    await ConsoleCommandService.execute('help');
    await ConsoleCommandService.execute('date');

    expect(ConsoleCommandService.loadHistory(), ['help', 'date']);
  });

  test('токен не попадает в историю и маскируется для экрана', () async {
    const secret = 'header.payload.signature-secret';
    await ConsoleCommandService.execute('token hash $secret');

    expect(ConsoleCommandService.loadHistory(), isEmpty);
    expect(
      ConsoleCommandService.displayCommand('token hash $secret'),
      'token hash ••••••••',
    );
  });

  test('JWT разбирается локально без вывода полного секрета', () async {
    String segment(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

    final token = '${segment({'alg': 'none', 'typ': 'JWT'})}.'
        '${segment({'sub': 'owner', 'exp': 4102444800})}.signature';
    final result =
        await ConsoleCommandService.execute('token inspect $token');
    final text = result.lines.map((line) => line.text).join('\n');

    expect(text, contains('owner'));
    expect(text, contains('действует'));
    expect(text, isNot(contains(token)));
    expect(ConsoleCommandService.loadHistory(), isEmpty);
  });

  test('отпечаток токена имеет SHA-256 и не раскрывает токен', () async {
    final result = await ConsoleCommandService.execute('token hash abc123');
    final text = result.lines.map((line) => line.text).join('\n');

    expect(text, contains('SHA-256:'));
    expect(text, isNot(contains('abc123')));
  });

  test('каталог содержит WesiOS, сертификаты, SSH и токены', () {
    expect(ConsoleTemplateLibrary.pinned, isNotEmpty);
    expect(
      ConsoleTemplateLibrary.inCategory(
        ConsoleTemplateCategory.certificates,
      ),
      isNotEmpty,
    );
    expect(
      ConsoleTemplateLibrary.inCategory(ConsoleTemplateCategory.ssh),
      isNotEmpty,
    );
    expect(
      ConsoleTemplateLibrary.inCategory(ConsoleTemplateCategory.tokens),
      everyElement(predicate<ConsoleTemplate>((value) => value.sensitive)),
    );
  });

  test('templates печатает готовые команды', () async {
    final result = await ConsoleCommandService.execute('templates');
    final text = result.lines.map((line) => line.text).join('\n');

    expect(text, contains('tls api.wesi-inc.ru 443'));
    expect(text, contains('ssh-check'));
    expect(text, contains('token inspect <TOKEN>'));
  });

  test('clear возвращает управляющий флаг без вывода', () async {
    final result = await ConsoleCommandService.execute('clear');
    expect(result.clear, isTrue);
    expect(result.lines, isEmpty);
  });

  test('неизвестная команда объясняет, как открыть справку', () async {
    final result = await ConsoleCommandService.execute('abracadabra');
    expect(result.lines.single.kind, ConsoleLineKind.error);
    expect(result.lines.single.text, contains('help'));
  });

  test('автодополнение предлагает команды по префиксу', () {
    expect(ConsoleCommandService.completions('sta'), contains('status'));
    expect(ConsoleCommandService.completions('tl'), contains('tls '));
    expect(
      ConsoleCommandService.completions('ssh'),
      contains('ssh-check '),
    );
  });
}
