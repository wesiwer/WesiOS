from pathlib import Path


def patch(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip:', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('ok:', label)

editor = 'lib/features/tasks/widgets/task_editor_dialog.dart'
context = 'lib/features/treasury/services/horizon_business_context.dart'

patch(
    editor,
    """import '../services/task_assignment.dart';
import '../task_labels.dart';
import 'assignee_field.dart';
""",
    """import '../services/task_assignment.dart';
import '../services/task_cash_impact.dart';
import '../task_labels.dart';
import 'assignee_field.dart';
import 'task_cash_impact_field.dart';
""",
    'task editor imports',
)
patch(
    editor,
    """  DateTime? _dueDate;
  late List<SubTask> _subtasks;
""",
    """  DateTime? _dueDate;
  TaskCashImpact? _cashImpact;
  bool _cashNeedsDueDate = false;
  late List<SubTask> _subtasks;
""",
    'task editor state',
)
patch(
    editor,
    """    _priority = t?.priority ?? TaskPriority.normal;
    _dueDate = t?.dueDate;
    _subtasks = List<SubTask>.from(t?.subtasks ?? const []);
""",
    """    _priority = t?.priority ?? TaskPriority.normal;
    _dueDate = t?.dueDate;
    _cashImpact = TaskCashImpact.fromTags(t?.tags ?? const []);
    _subtasks = List<SubTask>.from(t?.subtasks ?? const []);
""",
    'load existing cash impact',
)
patch(
    editor,
    """    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final base = widget.initial;
    final task = base == null
""",
    """    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final base = widget.initial;
    if (_cashImpact != null && _dueDate == null) {
      setState(() => _cashNeedsDueDate = true);
      return;
    }
    final existingTags = base?.tags ?? const <String>[];
    final nextTags = _cashImpact == null
        ? TaskCashImpact.clearFrom(existingTags)
        : _cashImpact!.applyTo(existingTags);
    final task = base == null
""",
    'validate task cash and preserve tags',
)
patch(
    editor,
    """            assignee: TaskAssignment.coerce(_assignee),
            subtasks: _subtasks,
          )
""",
    """            assignee: TaskAssignment.coerce(_assignee),
            subtasks: _subtasks,
            tags: nextTags,
          )
""",
    'new task cash tags',
)
patch(
    editor,
    """            clearAssignee: TaskAssignment.coerce(_assignee) == null,
            subtasks: _subtasks,
          );
""",
    """            clearAssignee: TaskAssignment.coerce(_assignee) == null,
            subtasks: _subtasks,
            tags: nextTags,
          );
""",
    'edited task cash tags',
)
patch(
    editor,
    """              SizedBox(height: 18),
              Text(ru ? 'Чек-лист' : 'Checklist',
""",
    """              const SizedBox(height: 12),
              TaskCashImpactField(
                key: ValueKey('${widget.initial?.id ?? 'new'}-cash'),
                initial: _cashImpact,
                onChanged: (value) => setState(() {
                  _cashImpact = value;
                  if (value == null || _dueDate != null) {
                    _cashNeedsDueDate = false;
                  }
                }),
              ),
              if (_cashNeedsDueDate) ...[
                const SizedBox(height: 6),
                Text(
                  ru
                      ? 'Для денежного влияния укажи срок задачи — это дата движения денег.'
                      : 'Set a due date for cash impact — it is the cash movement date.',
                  style: TextStyle(color: AppTheme.accentRed, fontSize: 11),
                ),
              ],
              SizedBox(height: 18),
              Text(ru ? 'Чек-лист' : 'Checklist',
""",
    'task cash impact field',
)

patch(
    context,
    """import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
""",
    """import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_cash_impact.dart';
import '../../tasks/services/task_service.dart';
""",
    'shared task cash parser import',
)
patch(
    context,
    """        final parsed = _cashFromTags(task.tags);
        if (parsed == null) continue;
""",
    """        final parsed = TaskCashImpact.fromTags(task.tags);
        if (parsed == null) continue;
""",
    'business context uses shared parser',
)
patch(
    context,
    """                'Просрочено денежное обязательство «${task.title}» (${parsed.amount.toStringAsFixed(0)} ₽).',
            textEn:
                'Overdue cash obligation “${task.title}” (${parsed.amount.toStringAsFixed(0)} RUB).',
            amount: parsed.amount.abs(),
""",
    """                'Просрочено денежное обязательство «${task.title}» (${parsed.signedAmount.abs().toStringAsFixed(0)} ₽).',
            textEn:
                'Overdue cash obligation “${task.title}” (${parsed.signedAmount.abs().toStringAsFixed(0)} RUB).',
            amount: parsed.signedAmount.abs(),
""",
    'overdue task signed amount',
)
patch(
    context,
    """          amount: parsed.amount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
""",
    """          amount: parsed.signedAmount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
""",
    'task cash event signed amount',
)

p = Path(context)
text = p.read_text(encoding='utf-8')
start = text.find("  static ({double amount, double probability, bool committed})? _cashFromTags(")
end = text.find("  static void _addConcentrationWarnings(", start)
if start >= 0 and end > start:
    text = text[:start] + text[end:]
    p.write_text(text, encoding='utf-8')
    print('ok: removed duplicate cash parser')
elif start < 0:
    print('skip: duplicate cash parser already removed')
else:
    raise SystemExit('could not remove duplicate cash parser')

print('Tasks -> Horizon integration complete')
