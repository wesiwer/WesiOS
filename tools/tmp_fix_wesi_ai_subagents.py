from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: marker not found')
    return text.replace(old, new, 1)


orchestrator = Path('server/wesi-ai-stream/dynamic_subagent_orchestrator.mjs')
text = orchestrator.read_text(encoding='utf-8')

old_parse = '''function parseObject(value) {
  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}
'''
new_parse = '''function parseJsonObjectText(text) {
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function extractBalancedJsonObject(value) {
  const text = String(value || '');
  for (let start = text.indexOf('{'); start >= 0; start = text.indexOf('{', start + 1)) {
    let depth = 0;
    let quoted = false;
    let escaped = false;
    for (let index = start; index < text.length; index += 1) {
      const char = text[index];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\\\') {
          escaped = true;
        } else if (char === '"') {
          quoted = false;
        }
        continue;
      }
      if (char === '"') {
        quoted = true;
        continue;
      }
      if (char === '{') depth += 1;
      if (char !== '}') continue;
      depth -= 1;
      if (depth !== 0) continue;
      const parsed = parseJsonObjectText(text.slice(start, index + 1));
      if (parsed) return parsed;
      break;
    }
  }
  return null;
}

function parseObject(value) {
  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));
  return parseJsonObjectText(text) || extractBalancedJsonObject(text);
}
'''
text = replace_once(text, old_parse, new_parse, 'parseObject')

reasoning_marker = '''function reasoningEvent(label, detail) {
  return {type: 'activity', kind: 'reasoning', phase: 'done', label, detail};
}
'''
reasoning_replacement = '''function reasoningEvent(label, detail) {
  return {type: 'activity', kind: 'reasoning', phase: 'done', label, detail};
}

const BASELINE_SUBAGENT_ROLES = Object.freeze([
  'Coding / Flutter Agent',
  'QA Agent',
  'Build Agent',
  'Research Agent',
  'Documents Agent',
  'Media Agent',
  'Review Agent',
  'Security Reviewer',
]);

function parseManualSubagentRequest(value) {
  const text = String(value || '').trim();
  const match = text.match(/^Позови\\s+(?:субагента|сабагента)\\s+[«"]([^»"]+)[»"]\\s+и\\s+поручи\\s+ему\\s*:\\s*([\\s\\S]+)$/iu);
  if (!match) return null;
  const role = match[1].trim().slice(0, 120);
  const task = match[2].trim().slice(0, 5000);
  return role && task ? {role, task} : null;
}
'''
text = replace_once(text, reasoning_marker, reasoning_replacement, 'manual request helper')

planner_line = "        'Каждому специалисту дай узкую роль и независимую задачу. requestedCapabilities могут содержать только разрешённые read-only tools. ' +\n"
planner_with_catalog = planner_line + "        `Базовый каталог специалистов: ${BASELINE_SUBAGENT_ROLES.join('; ')}. Предпочитай подходящую роль из каталога, а если ни одна не подходит — создай узкую динамическую роль под задачу. ` +\n"
text = replace_once(text, planner_line, planner_with_catalog, 'planner catalog')

old_run = '''  let planRaw = '';
  planRaw = await invokeModel({actor: 'lead', phase: 'subagent-plan', input: plannerInput(prepared, policy)});
  const specs = sanitizePlan(planRaw, prepared, policy, workspace);
'''
new_run = '''  const manualRequest = parseManualSubagentRequest(prepared.message);
  let planRaw = '';
  if (manualRequest) {
    planRaw = JSON.stringify({
      subagents: [{
        role: manualRequest.role,
        task: manualRequest.task,
        requestedCapabilities: Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames : [],
      }],
    });
  } else {
    planRaw = await invokeModel({actor: 'lead', phase: 'subagent-plan', input: plannerInput(prepared, policy)});
  }
  const specs = sanitizePlan(planRaw, prepared, policy, workspace);
'''
text = replace_once(text, old_run, new_run, 'manual planner bypass')
orchestrator.write_text(text, encoding='utf-8')

test_file = Path('server/wesi-ai-stream/dynamic_subagent_orchestrator.test.mjs')
tests = test_file.read_text(encoding='utf-8')
if 'manual named subagent bypasses planner' in tests:
    raise SystemExit('orchestrator tests already patched')
tests = tests.rstrip() + r'''

test('provider prose around planner and specialist JSON is accepted', async () => {
  const p = prepared();
  p.subagents.maxToolTurns = 0;
  const result = await runDynamicSubagents({
    prepared: p,
    invokeModel: async ({phase}) => {
      if (phase === 'subagent-plan') {
        return 'План готов:\n```json\n{"subagents":[{"role":"QA Agent","task":"Проверь сборку"}]}\n```\nПродолжаю.';
      }
      return '<analysis>provider prelude</analysis>\nРезультат:\n{"summary":"checked","findings":[],"risks":[],"recommendation":"ok"}\nГотово.';
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(result.ok, true);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].spec.role, 'QA Agent');
  assert.equal(result.results[0].result.summary, 'checked');
});

test('manual named subagent bypasses planner and runs requested role', async () => {
  const p = prepared({message: 'Позови субагента «Security Reviewer» и поручи ему: Проверь авторизацию'});
  p.subagents.maxToolTurns = 0;
  let plannerCalls = 0;
  const events = [];
  const result = await runDynamicSubagents({
    prepared: p,
    emit: (event) => events.push(event),
    invokeModel: async ({phase, spec}) => {
      if (phase === 'subagent-plan') {
        plannerCalls += 1;
        throw new Error('planner must be bypassed');
      }
      assert.equal(spec.role, 'Security Reviewer');
      assert.equal(spec.task, 'Проверь авторизацию');
      return JSON.stringify({summary: 'security checked', findings: [], risks: [], recommendation: 'ok'});
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(plannerCalls, 0);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].spec.role, 'Security Reviewer');
  assert.ok(events.some((event) => event.event === 'planned' && event.name === 'Security Reviewer'));
});
''' + '\n'
test_file.write_text(tests, encoding='utf-8')

sheet = Path('lib/features/ai/widgets/wesi_ai_subagents_sheet.dart')
sheet.write_text(r'''import 'package:flutter/material.dart';

import '../models/wesi_ai_chat_models.dart';
import '../wesi_ai_managed_controller.dart';

class WesiAiSubagentsSheet extends StatefulWidget {
  final WesiAiManagedChatController controller;

  const WesiAiSubagentsSheet({
    super.key,
    required this.controller,
  });

  @override
  State<WesiAiSubagentsSheet> createState() => _WesiAiSubagentsSheetState();
}

class _WesiAiSubagentsSheetState extends State<WesiAiSubagentsSheet> {
  static const _agents = <_SubagentDefinition>[
    _SubagentDefinition(
      name: 'Coding / Flutter Agent',
      description: 'Код, Flutter, архитектура и точечная реализация.',
      icon: Icons.code_rounded,
    ),
    _SubagentDefinition(
      name: 'QA Agent',
      description: 'Тесты, регрессии, edge cases и воспроизведение ошибок.',
      icon: Icons.fact_check_outlined,
    ),
    _SubagentDefinition(
      name: 'Build Agent',
      description: 'CI/CD, сборки, зависимости и релизные проблемы.',
      icon: Icons.build_circle_outlined,
    ),
    _SubagentDefinition(
      name: 'Research Agent',
      description: 'Исследование вариантов, документации и фактов.',
      icon: Icons.manage_search_rounded,
    ),
    _SubagentDefinition(
      name: 'Documents Agent',
      description: 'Документы, спецификации, отчёты и структурирование.',
      icon: Icons.description_outlined,
    ),
    _SubagentDefinition(
      name: 'Media Agent',
      description: 'Медиа-задачи, ассеты и анализ материалов.',
      icon: Icons.perm_media_outlined,
    ),
    _SubagentDefinition(
      name: 'Review Agent',
      description: 'Независимая проверка решения и поиск слабых мест.',
      icon: Icons.rate_review_outlined,
    ),
    _SubagentDefinition(
      name: 'Security Reviewer',
      description: 'Авторизация, секреты, права и security-регрессии.',
      icon: Icons.security_outlined,
    ),
  ];

  WesiAiManagedChatController get controller => widget.controller;

  bool get _tierSupportsSubagents => controller.state.tier != WesiAiTier.fast;

  bool get _directPersonaSelected {
    final persona = controller.state.activeConversation?.persona;
    return persona == WesiAiPersona.zane || persona == WesiAiPersona.nirvana;
  }

  String? get _unavailableReason {
    if (!_tierSupportsSubagents) {
      return 'Субагенты доступны в Pro и Maximum. Переключите уровень в верхней панели.';
    }
    if (controller.state.activeConversation == null) {
      return 'Сначала откройте чат с Зейном или Нирваной.';
    }
    if (!_directPersonaSelected) {
      return 'Для ручного вызова откройте прямой чат с Зейном или Нирваной. В Lobby ведущая персона выбирается автоматически.';
    }
    return null;
  }

  Future<void> _invoke(_SubagentDefinition agent) async {
    if (_unavailableReason != null) return;
    final taskController = TextEditingController();
    final task = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Задача для ${agent.name}'),
        content: TextField(
          controller: taskController,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Что именно нужно проверить или сделать?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = taskController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Позвать'),
          ),
        ],
      ),
    );
    taskController.dispose();
    if (task == null || !mounted) return;

    final result = await controller.submitUserMessage(
      'Позови субагента «${agent.name}» и поручи ему: $task',
      thinkingMode: true,
    );
    if (!mounted) return;
    if (result == WesiAiMessageSubmitResult.accepted) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_submitError(result))),
    );
  }

  String _submitError(WesiAiMessageSubmitResult result) => switch (result) {
        WesiAiMessageSubmitResult.queueFull => 'Очередь Wesi AI заполнена.',
        WesiAiMessageSubmitResult.invalidAttachments => 'Некорректные вложения.',
        WesiAiMessageSubmitResult.persistenceFailed => 'Не удалось сохранить задачу в очередь.',
        WesiAiMessageSubmitResult.unavailable => 'Сейчас субагент недоступен.',
        WesiAiMessageSubmitResult.accepted => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = _unavailableReason;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Субагенты',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Выберите специалиста вручную. В Pro и Maximum Wesi AI также может создавать узких Dynamic Sub-Agents автоматически.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(reason),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _agents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final agent = _agents[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(agent.icon)),
                      title: Text(agent.name),
                      subtitle: Text(agent.description),
                      trailing: FilledButton.tonal(
                        onPressed: reason == null ? () => _invoke(agent) : null,
                        child: const Text('Позвать'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubagentDefinition {
  final String name;
  final String description;
  final IconData icon;

  const _SubagentDefinition({
    required this.name,
    required this.description,
    required this.icon,
  });
}
''', encoding='utf-8')

screen = Path('lib/features/ai/ai_assistant_v2_screen.dart')
ui = screen.read_text(encoding='utf-8')
import_marker = "import 'widgets/wesi_ai_run_summary_chip.dart';\n"
ui = replace_once(
    ui,
    import_marker,
    import_marker + "import 'widgets/wesi_ai_subagents_sheet.dart';\n",
    'subagents sheet import',
)

tile_marker = '''              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Коннекторы'),
'''
tile_replacement = '''              children: [
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
ui = replace_once(ui, tile_marker, tile_replacement, 'sidebar subagents entry')
screen.write_text(ui, encoding='utf-8')
