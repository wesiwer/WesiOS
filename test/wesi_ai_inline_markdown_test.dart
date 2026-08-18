import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

// Звёздочки не должны доезжать до экрана.
//
// Старый разбор был одним регулярным выражением `\*\*[^*\n]+\*\*`: внутри
// жирного нельзя было ни звёздочки, ни переноса строки. Плюс заголовок
// `### **Итог**` превращался в `****Итог****`. В итоге на экране оставались
// `**` — из пяти обычных случаев корректно отрисовывался один.
String rendered(String source) => WesiAiInlineParser
    .tokens(WesiAiRichParser.displayMarkdown(source))
    .map((token) => token.text)
    .join();

List<WesiAiInlineKind> kinds(String source) => WesiAiInlineParser
    .tokens(WesiAiRichParser.displayMarkdown(source))
    .where((token) => token.kind != WesiAiInlineKind.plain)
    .map((token) => token.kind)
    .toList();

void main() {
  test('заголовок с жирным внутри не оставляет звёздочек', () {
    expect(rendered('### **Итог**'), 'Итог');
    expect(kinds('### **Итог**'), [WesiAiInlineKind.bold]);
  });

  test('заголовок с двоеточием и жирным хвостом читается целиком', () {
    expect(rendered('## Шаг 1: **важно**'), 'Шаг 1: важно');
    expect(rendered('## Шаг 1: **важно**'), isNot(contains('*')));
  });

  test('жирный с курсивом внутри разбирается, а не показывается сырым', () {
    expect(rendered('**Заголовок с *курсивом* внутри**'),
        'Заголовок с курсивом внутри');
  });

  test('жирный переживает перенос строки', () {
    expect(rendered('**Жирный текст,\nразорванный переносом**'),
        'Жирный текст,\nразорванный переносом');
    expect(kinds('**Жирный текст,\nразорванный переносом**'),
        [WesiAiInlineKind.bold]);
  });

  test('обычный жирный по-прежнему работает', () {
    expect(kinds('**Обычный жирный**'), [WesiAiInlineKind.bold]);
    expect(rendered('**Обычный жирный**'), 'Обычный жирный');
  });

  test('тройные звёздочки — жирный курсив', () {
    expect(kinds('***сразу оба***'), [WesiAiInlineKind.boldItalic]);
    expect(rendered('***сразу оба***'), 'сразу оба');
  });

  test('код в обратных кавычках остаётся кодом', () {
    expect(kinds('вызови `flutter test` сейчас'), [WesiAiInlineKind.code]);
    expect(rendered('вызови `flutter test` сейчас'), 'вызови flutter test сейчас');
  });

  test('непарная звёздочка остаётся обычным символом', () {
    expect(rendered('умножение 2 * 3 и ещё **жирный**'),
        'умножение 2 * 3 и ещё жирный');
  });

  test('строка списка не превращает абзац в курсив', () {
    const source = '* первый пункт\n* второй пункт';
    expect(rendered(source), source);
    expect(kinds(source), isEmpty);
  });

  test('оборванный жирный не съедает остаток текста', () {
    expect(rendered('**незакрытый жирный и дальше текст'),
        '**незакрытый жирный и дальше текст');
  });

  test('несколько жирных участков в одной строке', () {
    expect(kinds('**раз** обычный **два**'),
        [WesiAiInlineKind.bold, WesiAiInlineKind.bold]);
    expect(rendered('**раз** обычный **два**'), 'раз обычный два');
  });

  test('пустой заголовок не оставляет пустых звёздочек', () {
    expect(rendered('###   '), isNot(contains('*')));
  });

  test('реальный ответ модели не показывает разметку', () {
    const answer = '''
### **Что делает программа**

Она **генерирует пароль** и проверяет его на *надёжность*.

## Итог: **готово**
''';
    expect(rendered(answer), isNot(contains('**')));
  });
}
