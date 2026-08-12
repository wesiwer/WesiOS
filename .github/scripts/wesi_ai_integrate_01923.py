from pathlib import Path

p = Path('lib/features/tasks/tasks_screen.dart')
s = p.read_text(encoding='utf-8')
imp = "import 'widgets/task_editor_dialog.dart';\n"
if "ai/widgets/wesi_ai_suggestions_panel.dart" not in s:
    if imp not in s:
        raise SystemExit('TasksScreen import anchor not found')
    s = s.replace(imp, imp + "import 'ai/widgets/wesi_ai_suggestions_panel.dart';\n")
old = """              _filters(ru),
              const SizedBox(height: 14),
              Expanded(child: _board(ru)),"""
new = """              _filters(ru),
              const SizedBox(height: 10),
              WesiAiSuggestionsPanel(onTaskCreated: _load),
              const SizedBox(height: 10),
              Expanded(child: _board(ru)),"""
if 'WesiAiSuggestionsPanel(onTaskCreated:' not in s:
    if old not in s:
        raise SystemExit('TasksScreen panel anchor not found')
    s = s.replace(old, new)
p.write_text(s, encoding='utf-8')

p = Path('lib/features/tasks/ai/services/wesi_ai_task_engine.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    """    if (input.organizationId == 'org_wesi_beats' &&
        template.organizationHints == WesiAiTaskCatalog.musicHints) {
      return true;
    }""",
    """    if (input.organizationId == 'org_wesi_beats' &&
        template.organizationHints
            .any(WesiAiTaskCatalog.musicHints.contains)) {
      return true;
    }""",
)
s = s.replace(
    "TaskPriority.values[index.clamp(0, TaskPriority.values.length - 1)];",
    "TaskPriority.values[index.clamp(0, TaskPriority.values.length - 1).toInt()];",
)
s = s.replace(
    "AiForecastImpact\n        .values[index.clamp(0, AiForecastImpact.values.length - 1)];",
    "AiForecastImpact.values[\n        index.clamp(0, AiForecastImpact.values.length - 1).toInt()];",
)
p.write_text(s, encoding='utf-8')

p = Path('lib/features/tasks/ai/services/wesi_ai_task_service.dart')
s = p.read_text(encoding='utf-8')
s = s.replace("import '../../../organizations/models/organization_model.dart';\n", '')
p.write_text(s, encoding='utf-8')
print('Wesi AI integrated into TasksScreen')
