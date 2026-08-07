from pathlib import Path

service = Path('lib/features/sysadmin/console/console_command_service.dart')
text = service.read_text(encoding='utf-8')
old1 = "RegExp(r'(?i)(bearer\\s+)[A-Za-z0-9._~+/=-]+'),"
new1 = "RegExp(r'(bearer\\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),"
old2 = "RegExp(r'(?i)((?:api[_-]?key|access[_-]?token)=)[^\\s&]+'),"
new2 = "RegExp(\n          r'((?:api[_-]?key|access[_-]?token)=)[^\\s&]+',\n          caseSensitive: false,\n        ),"
if old1 not in text or old2 not in text:
    raise SystemExit('console regex anchors not found')
text = text.replace(old1, new1, 1).replace(old2, new2, 1)
service.write_text(text, encoding='utf-8')

templates = Path('lib/features/sysadmin/console/console_templates.dart')
text = templates.read_text(encoding='utf-8')
text = text.replace(
    "descriptionRu: 'Проверить все серверы, API и портал сотрудников.',",
    "descriptionRu: 'Проверить состояние ранее выбранного сервера.',",
    1,
).replace(
    "descriptionEn: 'Probe every server, API endpoint, and employee portal.',",
    "descriptionEn: 'Probe the previously selected server.',",
    1,
)
templates.write_text(text, encoding='utf-8')

test = Path('test/sysadmin_console_test.dart')
text = test.read_text(encoding='utf-8')
anchor = "  test('echo учитывает кавычки и сохраняет историю', () async {\n"
addition = """  test('обычная команда безопасно печатается в prompt', () {\n    expect(ConsoleCommandService.displayCommand('status'), 'status');\n    expect(\n      ConsoleCommandService.displayCommand('http https://example.com?api_key=secret'),\n      contains('••••••••'),\n    );\n  });\n\n"""
if addition not in text:
    if anchor not in text:
        raise SystemExit('test anchor not found')
    text = text.replace(anchor, addition + anchor, 1)
test.write_text(text, encoding='utf-8')
print('console runtime regex hotfix applied')
