import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/sysadmin/console/console_command_service.dart';

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
    expect(text, contains('Ctrl+L'));
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
  });
}
