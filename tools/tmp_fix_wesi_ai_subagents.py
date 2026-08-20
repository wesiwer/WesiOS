from pathlib import Path

screen = Path('lib/features/ai/ai_assistant_v2_screen.dart')
text = screen.read_text(encoding='utf-8')

import_line = "import 'widgets/wesi_ai_subagents_sheet.dart';\n"
if import_line not in text:
    marker = "import 'widgets/wesi_ai_run_summary_chip.dart';\n"
    if marker not in text:
        raise SystemExit('Wesi AI import marker not found')
    text = text.replace(marker, marker + import_line, 1)

entry = "title: const Text('Субагенты'),"
if entry not in text:
    marker = '''              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Коннекторы'),
'''
    replacement = '''              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('Субагенты'),
                  subtitle: const Text('Каталог, ручной вызов и Dynamic Agents'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => WesiAiSubagentsSheet(controller: controller),
                  ),
                ),
                const Divider(height: 1, indent: 52),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Коннекторы'),
'''
    if marker not in text:
        raise SystemExit('Wesi AI sidebar utilities marker not found')
    text = text.replace(marker, replacement, 1)

screen.write_text(text, encoding='utf-8')
