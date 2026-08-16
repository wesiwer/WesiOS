from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"{label}: marker not found")
    return text.replace(old, new, 1)


def replace_after(text: str, marker: str, old: str, new: str, label: str) -> str:
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"{label}: class marker not found")
    prefix = text[:start]
    suffix = text[start:]
    suffix = replace_once(suffix, old, new, label)
    return prefix + suffix


def patch_rich_message() -> None:
    path = Path("lib/features/ai/widgets/wesi_ai_rich_message.dart")
    text = path.read_text(encoding="utf-8")

    old = """  static bool hasClarification(String markdown) {\n"""
    new = """  static String displayMarkdown(String markdown) => markdown.replaceAllMapped(\n        RegExp(r'^\\s{0,3}#{1,6}\\s+(.+)$', multiLine: true),\n        (match) => '**${match.group(1)?.trim() ?? ''}**',\n      );\n\n  static bool hasClarification(String markdown) {\n"""
    text = replace_after(text, "class WesiAiRichParser", old, new, "display markdown headings")

    old = """    return SelectableText.rich(TextSpan(children: _inline(text, base)));\n"""
    new = """    final displayText = WesiAiRichParser.displayMarkdown(text);\n    return SelectableText.rich(\n      TextSpan(children: _inline(displayText, base)),\n    );\n"""
    text = replace_after(text, "class WesiAiFormattedText", old, new, "formatted text display")

    old = """            style: const TextStyle(fontFamily: 'monospace', height: 1.45),\n"""
    new = """            style: const TextStyle(\n              fontFamily: 'monospace',\n              fontSize: 13,\n              height: 1.36,\n            ),\n"""
    text = replace_after(text, "class WesiAiCodeBlock", old, new, "expanded code style")

    old = """    final theme = Theme.of(context);\n    return Container(\n"""
    new = """    final theme = Theme.of(context);\n    final compact = MediaQuery.sizeOf(context).width < 600;\n    return Container(\n"""
    text = replace_after(text, "class WesiAiCodeBlock", old, new, "code compact breakpoint")

    old = """            padding: const EdgeInsets.fromLTRB(14, 8, 7, 7),\n"""
    new = """            padding: EdgeInsets.fromLTRB(\n              compact ? 11 : 14,\n              compact ? 5 : 8,\n              compact ? 4 : 7,\n              compact ? 4 : 7,\n            ),\n"""
    text = replace_after(text, "class WesiAiCodeBlock", old, new, "code header padding")

    old = """            padding: const EdgeInsets.all(14),\n            child: SelectableText(\n              code,\n              style: theme.textTheme.bodyMedium?.copyWith(\n                fontFamily: 'monospace',\n                height: 1.45,\n              ),\n            ),\n"""
    new = """            padding: EdgeInsets.all(compact ? 10 : 13),\n            child: SelectableText(\n              code,\n              style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(\n                fontFamily: 'monospace',\n                fontSize: compact ? 12.25 : 13.25,\n                height: 1.36,\n              ),\n            ),\n"""
    text = replace_after(text, "class WesiAiCodeBlock", old, new, "code body density")

    path.write_text(text, encoding="utf-8")


def patch_markdown_table() -> None:
    path = Path("lib/features/ai/widgets/wesi_ai_visualization.dart")
    text = path.read_text(encoding="utf-8")

    old = """    final theme = Theme.of(context);\n    return Container(\n"""
    new = """    final theme = Theme.of(context);\n    final compact = MediaQuery.sizeOf(context).width < 600;\n    final tableFontSize = compact ? 12.0 : 13.0;\n    return Container(\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table breakpoint")

    old = """            padding: const EdgeInsets.fromLTRB(14, 7, 6, 6),\n"""
    new = """            padding: EdgeInsets.fromLTRB(\n              compact ? 10 : 14,\n              compact ? 4 : 7,\n              compact ? 3 : 6,\n              compact ? 3 : 6,\n            ),\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table header padding")

    old = """                const Expanded(\n                    child: Text('Таблица',\n                        style: TextStyle(fontWeight: FontWeight.w700))),\n"""
    new = """                Expanded(\n                  child: Text(\n                    'Таблица',\n                    style: theme.textTheme.labelLarge?.copyWith(\n                      fontSize: compact ? 13 : 14,\n                      fontWeight: FontWeight.w700,\n                    ),\n                  ),\n                ),\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table title")

    old = """                  DataColumn(\n                      label: Text(header,\n                          style: const TextStyle(fontWeight: FontWeight.w700))),\n"""
    new = """                  DataColumn(\n                    label: Text(\n                      header,\n                      style: TextStyle(\n                        fontSize: tableFontSize,\n                        fontWeight: FontWeight.w700,\n                        height: 1.2,\n                      ),\n                    ),\n                  ),\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table headers")

    old = """                      DataCell(SelectableText(i < row.length ? row[i] : '')),\n"""
    new = """                      DataCell(\n                        SelectableText(\n                          i < row.length ? row[i] : '',\n                          style: TextStyle(\n                            fontSize: tableFontSize,\n                            height: 1.22,\n                          ),\n                        ),\n                      ),\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table cells")

    old = """              headingRowHeight: 44,\n              dataRowMinHeight: 42,\n              dataRowMaxHeight: 72,\n              horizontalMargin: 14,\n              columnSpacing: 24,\n"""
    new = """              headingRowHeight: compact ? 36 : 40,\n              dataRowMinHeight: compact ? 32 : 36,\n              dataRowMaxHeight: compact ? 56 : 64,\n              horizontalMargin: compact ? 9 : 12,\n              columnSpacing: compact ? 16 : 20,\n              dividerThickness: 0.6,\n"""
    text = replace_after(text, "class WesiAiTableBlock", old, new, "markdown table density")

    path.write_text(text, encoding="utf-8")


def patch_structured_table() -> None:
    path = Path("lib/features/ai/widgets/wesi_ai_message_content.dart")
    text = path.read_text(encoding="utf-8")

    old = """    final theme = Theme.of(context);\n    final columns = List<String>.from(data['columns'] as List? ?? const []);\n"""
    new = """    final theme = Theme.of(context);\n    final compact = MediaQuery.sizeOf(context).width < 600;\n    final tableFontSize = compact ? 12.0 : 13.0;\n    final columns = List<String>.from(data['columns'] as List? ?? const []);\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table breakpoint")

    old = """        padding: const EdgeInsets.all(12),\n"""
    new = """        padding: EdgeInsets.all(compact ? 9 : 12),\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table padding")

    old = """                style: theme.textTheme.titleSmall?.copyWith(\n                  fontWeight: FontWeight.w700,\n                ),\n"""
    new = """                style: theme.textTheme.titleSmall?.copyWith(\n                  fontSize: compact ? 13.5 : null,\n                  fontWeight: FontWeight.w700,\n                ),\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table title")

    old = """              child: DataTable(\n                headingRowHeight: 40,\n                dataRowMinHeight: 36,\n                dataRowMaxHeight: 80,\n"""
    new = """              child: DataTable(\n                headingRowHeight: compact ? 35 : 40,\n                dataRowMinHeight: compact ? 31 : 36,\n                dataRowMaxHeight: compact ? 56 : 72,\n                horizontalMargin: compact ? 9 : 12,\n                columnSpacing: compact ? 16 : 20,\n                dividerThickness: 0.6,\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table density")

    old = """                        style: const TextStyle(fontWeight: FontWeight.w700),\n"""
    new = """                        style: TextStyle(\n                          fontSize: tableFontSize,\n                          fontWeight: FontWeight.w700,\n                          height: 1.2,\n                        ),\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table headers")

    old = """                              constraints: const BoxConstraints(maxWidth: 260),\n                              child: Text(i < row.length ? row[i] : ''),\n"""
    new = """                              constraints: BoxConstraints(\n                                maxWidth: compact ? 200 : 260,\n                              ),\n                              child: Text(\n                                i < row.length ? row[i] : '',\n                                style: TextStyle(\n                                  fontSize: tableFontSize,\n                                  height: 1.22,\n                                ),\n                              ),\n"""
    text = replace_after(text, "class _TableBlock", old, new, "structured table cells")

    path.write_text(text, encoding="utf-8")


def patch_tests() -> None:
    path = Path("test/wesi_ai_rich_message_test.dart")
    text = path.read_text(encoding="utf-8")

    marker = """  test('activity model preserves per tool diff and source', () {\n"""
    addition = """  test('display markdown removes raw heading markers', () {\n    const source = '### 🔥 Итог: Когда что использовать?';\n    final display = WesiAiRichParser.displayMarkdown(source);\n    expect(display, '**🔥 Итог: Когда что использовать?**');\n    expect(display, isNot(contains('###')));\n  });\n\n  testWidgets('mobile code and markdown table use compact density',\n      (tester) async {\n    tester.view.physicalSize = const Size(390, 844);\n    tester.view.devicePixelRatio = 1;\n    addTearDown(tester.view.resetPhysicalSize);\n    addTearDown(tester.view.resetDevicePixelRatio);\n\n    await tester.pumpWidget(const MaterialApp(\n      home: Scaffold(\n        body: WesiAiRichMessage(\n          messageId: 'compact',\n          text: '''```dart\nprint(1);\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |''',\n        ),\n      ),\n    ));\n\n    final code = tester.widget<SelectableText>(\n      find.widgetWithText(SelectableText, 'print(1);'),\n    );\n    expect(code.style?.fontSize, 12.25);\n\n    final table = tester.widget<DataTable>(find.byType(DataTable));\n    expect(table.headingRowHeight, 36);\n    expect(table.dataRowMinHeight, 32);\n    expect(table.horizontalMargin, 9);\n    expect(table.columnSpacing, 16);\n  });\n\n"""
    if addition not in text:
        if marker not in text:
            raise RuntimeError("rich message test marker not found")
        text = text.replace(marker, addition + marker, 1)

    path.write_text(text, encoding="utf-8")


def verify() -> None:
    rich = Path("lib/features/ai/widgets/wesi_ai_rich_message.dart").read_text(encoding="utf-8")
    visualization = Path("lib/features/ai/widgets/wesi_ai_visualization.dart").read_text(encoding="utf-8")
    structured = Path("lib/features/ai/widgets/wesi_ai_message_content.dart").read_text(encoding="utf-8")
    tests = Path("test/wesi_ai_rich_message_test.dart").read_text(encoding="utf-8")
    markers = [
        (rich, "fontSize: compact ? 12.25 : 13.25"),
        (rich, "static String displayMarkdown"),
        (visualization, "headingRowHeight: compact ? 36 : 40"),
        (visualization, "fontSize: tableFontSize"),
        (structured, "dataRowMinHeight: compact ? 31 : 36"),
        (structured, "maxWidth: compact ? 200 : 260"),
        (tests, "mobile code and markdown table use compact density"),
    ]
    for source, marker in markers:
        if marker not in source:
            raise RuntimeError(f"verification failed: {marker}")


if __name__ == "__main__":
    patch_rich_message()
    patch_markdown_table()
    patch_structured_table()
    patch_tests()
    verify()
    print("Wesi AI rich content compacted for mobile")
