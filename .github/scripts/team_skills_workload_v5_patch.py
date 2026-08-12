from pathlib import Path


def replace(path, old, new):
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:120]!r}')
    p.write_text(s.replace(old, new, 1), encoding='utf-8')

# TeamService: creation API and persistence.
replace(
    'lib/features/team/services/team_service.dart',
    """    Uint8List? photo,\n    String? login,""",
    """    Uint8List? photo,\n    List<String> skills = const [],\n    double weeklyCapacityPoints = 10,\n    double workloadMinRatio = .65,\n    double workloadMaxRatio = 1.10,\n    String? managerEmployeeId,\n    String workloadAlertTarget = 'manager',\n    String? login,""",
)
replace(
    'lib/features/team/services/team_service.dart',
    """      photo: photo,\n      createdAt: DateTime.now(),""",
    """      photo: photo,\n      skills: skills,\n      weeklyCapacityPoints: weeklyCapacityPoints,\n      workloadMinRatio: workloadMinRatio,\n      workloadMaxRatio: workloadMaxRatio,\n      managerEmployeeId: managerEmployeeId,\n      workloadAlertTarget: workloadAlertTarget,\n      createdAt: DateTime.now(),""",
)

# Wesi AI: explicit skills + per-person recommended capacity.
replace(
    'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
    """import '../../../team/models/employee_model.dart';""",
    """import '../../../team/models/employee_model.dart';\nimport '../../../team/services/team_skill_service.dart';\nimport '../../../team/services/team_workload_service.dart';""",
)
replace(
    'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
    """      final historyFit = WesiAiAdaptivePolicy.historicalRoleFit(\n        employee,\n        template.category,\n        tasks,\n        categoryOfTask,\n      );\n      final roleFit = max(positionFit, historyFit);\n      if (roleFit <= 0) continue;\n\n      final workload = _workload(employee.id, tasks);""",
    """      final historyFit = WesiAiAdaptivePolicy.historicalRoleFit(\n        employee,\n        template.category,\n        tasks,\n        categoryOfTask,\n      );\n      final skillFit = TeamSkillService.fitForTask(\n        employee,\n        roleAliases: template.roleAliases,\n        taskKeywords: template.taskKeywords,\n      );\n      final roleFit = max(max(positionFit, historyFit), skillFit);\n      if (roleFit <= 0) continue;\n\n      final workload = _workload(employee.id, tasks);\n      final recommendedLoad = TeamWorkloadService.calculate(\n        employee,\n        tasks,\n        now: input.now,\n      );""",
)
replace(
    'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
    """      if (workload.openWeight >= 7 || workload.overdue >= 4) continue;\n      if (adaptiveCapacity.fatigueRisk && template.effortPoints >= 2.5) {\n        continue;\n      }""",
    """      if (recommendedLoad.overloaded || workload.overdue >= 4) {\n        if (template.effortPoints >= 1.5) continue;\n      }\n      if (adaptiveCapacity.fatigueRisk && template.effortPoints >= 2.5) {\n        continue;\n      }""",
)
replace(
    'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
    """      final capacity = (1 - workload.openWeight / 7).clamp(0.0, 1.0);\n      final reliability = adaptiveCapacity.reliability;\n      final underloadBoost = adaptiveCapacity.underutilized ? .10 : 0.0;""",
    """      final capacity =\n          (1 - recommendedLoad.ratio).clamp(0.0, 1.0).toDouble();\n      final reliability = adaptiveCapacity.reliability;\n      final underloadBoost = recommendedLoad.underloaded ? .14 : 0.0;""",
)
replace(
    'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
    """      final score = roleFit * .48 +\n          capacity * .28 +""",
    """      final score = roleFit * .48 +\n          skillFit * .10 +\n          capacity * .22 +""",
)

# Employee editor imports and state.
replace(
    'lib/features/team/employee_editor_screen.dart',
    """import 'services/login_pool_service.dart';\nimport 'services/team_service.dart';""",
    """import 'services/login_pool_service.dart';\nimport 'services/team_service.dart';\nimport 'services/team_skill_service.dart';""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """  List<ArticleModel> _articles = const [];\n\n  bool get _ru""",
    """  List<ArticleModel> _articles = const [];\n  final Set<String> _skills = <String>{};\n  double _weeklyCapacity = 10;\n  double _minLoad = .65;\n  double _maxLoad = 1.10;\n  String? _managerId;\n  String _alertTarget = 'manager';\n\n  bool get _ru""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """      _notesCtrl.text = e.notes;\n    }\n    for (final network""",
    """      _notesCtrl.text = e.notes;\n      _skills.addAll(e.skills);\n      _weeklyCapacity = e.weeklyCapacityPoints;\n      _minLoad = e.workloadMinRatio;\n      _maxLoad = e.workloadMaxRatio;\n      _managerId = e.managerEmployeeId;\n      _alertTarget = e.workloadAlertTarget;\n    }\n    TeamSkillService.ensureOpen().then((_) {\n      if (mounted) setState(() {});\n    });\n    for (final network""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """          photo: _photo,\n        );""",
    """          photo: _photo,\n          skills: _skills.toList(),\n          weeklyCapacityPoints: _weeklyCapacity,\n          workloadMinRatio: _minLoad,\n          workloadMaxRatio: _maxLoad,\n          managerEmployeeId: _managerId,\n          workloadAlertTarget: _alertTarget,\n        );""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """          clearPhoto: _photoCleared && _photo == null,\n        );""",
    """          clearPhoto: _photoCleared && _photo == null,\n          skills: _skills.toList(),\n          weeklyCapacityPoints: _weeklyCapacity,\n          workloadMinRatio: _minLoad,\n          workloadMaxRatio: _maxLoad,\n          managerEmployeeId: _managerId,\n          clearManager: _managerId == null,\n          workloadAlertTarget: _alertTarget,\n        );""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """                  _field(_positionCtrl, _ru ? 'Должность' : 'Position'),\n                  const SizedBox(height: 18),\n                  _section(_ru ? 'Связь — видно всем' : 'Contacts — public'),""",
    """                  _field(_positionCtrl, _ru ? 'Должность' : 'Position'),\n                  const SizedBox(height: 18),\n                  _section(_ru ? 'Навыки' : 'Skills'),\n                  _skillsEditor(),\n                  const SizedBox(height: 18),\n                  _section(_ru ? 'Рекомендуемая нагрузка' : 'Recommended workload'),\n                  _workloadEditor(),\n                  const SizedBox(height: 18),\n                  _section(_ru ? 'Связь — видно всем' : 'Contacts — public'),""",
)
replace(
    'lib/features/team/employee_editor_screen.dart',
    """  Widget _loginHint() {""",
    r'''  Future<void> _addSkill() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(_ru ? 'Новый навык' : 'New skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _ru ? 'Например: Саунд-дизайн' : 'For example: Sound design',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_ru ? 'Добавить' : 'Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final saved = await TeamSkillService.add(value);
    if (saved != null && mounted) setState(() => _skills.add(saved));
  }

  Widget _skillsEditor() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? 'Можно выбрать несколько. Wesi AI будет учитывать их при назначении задач.'
                  : 'Select multiple. Wesi AI uses these skills for task assignment.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final skill in TeamSkillService.all)
                  FilterChip(
                    label: Text(skill),
                    selected: _skills.contains(skill),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _skills.add(skill);
                      } else {
                        _skills.remove(skill);
                      }
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(_ru ? 'Новый навык' : 'New skill'),
                  onPressed: _addSkill,
                ),
              ],
            ),
          ],
        ),
      );

  Widget _workloadEditor() {
    final managers = TeamService.all
        .where((e) => e.id != widget.initial?.id)
        .toList();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ru
                ? 'Недельная ёмкость: ${_weeklyCapacity.toStringAsFixed(0)} баллов'
                : 'Weekly capacity: ${_weeklyCapacity.toStringAsFixed(0)} points',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
          ),
          Slider(
            value: _weeklyCapacity.clamp(4, 24),
            min: 4,
            max: 24,
            divisions: 20,
            label: _weeklyCapacity.toStringAsFixed(0),
            onChanged: (v) => setState(() => _weeklyCapacity = v),
          ),
          Text(
            _ru
                ? 'Норма: ${(_minLoad * 100).round()}–${(_maxLoad * 100).round()}% от ёмкости'
                : 'Normal range: ${(_minLoad * 100).round()}–${(_maxLoad * 100).round()}%',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          RangeSlider(
            values: RangeValues(_minLoad.clamp(.35, .95), _maxLoad.clamp(.75, 1.45)),
            min: .35,
            max: 1.45,
            divisions: 22,
            labels: RangeLabels('${(_minLoad * 100).round()}%', '${(_maxLoad * 100).round()}%'),
            onChanged: (values) => setState(() {
              _minLoad = values.start;
              _maxLoad = values.end;
            }),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: managers.any((e) => e.id == _managerId) ? _managerId : null,
            decoration: InputDecoration(labelText: _ru ? 'Руководитель' : 'Manager'),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(_ru ? 'Не выбран' : 'Not selected')),
              for (final manager in managers)
                DropdownMenuItem<String?>(value: manager.id, child: Text(manager.displayName)),
            ],
            onChanged: (value) => setState(() => _managerId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: const {'manager', 'ceo', 'both', 'off'}.contains(_alertTarget)
                ? _alertTarget
                : 'manager',
            decoration: InputDecoration(
              labelText: _ru ? 'Кому сообщать о нагрузке' : 'Workload alerts',
            ),
            items: [
              DropdownMenuItem(value: 'manager', child: Text(_ru ? 'Руководителю' : 'Manager')),
              DropdownMenuItem(value: 'ceo', child: Text(_ru ? 'Только CEO' : 'CEO only')),
              DropdownMenuItem(value: 'both', child: Text(_ru ? 'Руководителю и CEO' : 'Manager and CEO')),
              DropdownMenuItem(value: 'off', child: Text(_ru ? 'Не уведомлять' : 'Off')),
            ],
            onChanged: (value) => setState(() => _alertTarget = value ?? 'manager'),
          ),
        ],
      ),
    );
  }

  Widget _loginHint() {''',
)

# Contacts: manager/CEO notification surface.
replace(
    'lib/features/team/contacts_screen.dart',
    """import '../organizations/widgets/organization_switcher.dart';\nimport 'deleted_employees_screen.dart';""",
    """import '../organizations/widgets/organization_switcher.dart';\nimport '../tasks/services/task_service.dart';\nimport 'deleted_employees_screen.dart';""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """import 'services/team_service.dart';\nimport 'team_stats_screen.dart';""",
    """import 'services/team_service.dart';\nimport 'services/team_workload_service.dart';\nimport 'team_stats_screen.dart';""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """  _ContactSort _sort = _ContactSort.name;\n\n  bool get _ru""",
    """  _ContactSort _sort = _ContactSort.name;\n  List<TeamWorkloadAlert> _workloadAlerts = const [];\n\n  bool get _ru""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """      if (!mounted) return;\n      setState(() {\n        _organizations = organizations;""",
    """      var workloadAlerts = const <TeamWorkloadAlert>[];\n      final viewer = TeamService.current ?? TeamService.owner;\n      if (viewer != null) {\n        try {\n          final taskOrgIds = selected == null ? visibleOrgIds : <String>{selected};\n          final tasks = await TaskService().getForOrganizations(taskOrgIds);\n          workloadAlerts = TeamWorkloadService.alertsForViewer(\n            viewer: viewer,\n            employees: TeamService.all,\n            tasks: tasks,\n          );\n        } catch (_) {}\n      }\n\n      if (!mounted) return;\n      setState(() {\n        _organizations = organizations;""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """        _contextEmployeeIds = contextEmployeeIds;\n        _membersLoading = false;""",
    """        _contextEmployeeIds = contextEmployeeIds;\n        _workloadAlerts = workloadAlerts;\n        _membersLoading = false;""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """            _filters(),\n            Expanded(""",
    """            _filters(),\n            if (_workloadAlerts.isNotEmpty) _workloadAlertsBanner(),\n            Expanded(""",
)
replace(
    'lib/features/team/contacts_screen.dart',
    """  Widget _header(int count) => Padding(""",
    r'''  Widget _workloadAlertsBanner() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: (_workloadAlerts.first.overloaded
                  ? AppTheme.accentRed
                  : AppTheme.accent)
              .withOpacity(.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (_workloadAlerts.first.overloaded
                    ? AppTheme.accentRed
                    : AppTheme.accent)
                .withOpacity(.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _workloadAlerts.first.overloaded
                  ? Icons.warning_amber_rounded
                  : Icons.hourglass_empty_rounded,
              size: 18,
              color: _workloadAlerts.first.overloaded
                  ? AppTheme.accentRed
                  : AppTheme.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru ? 'Уведомления по нагрузке' : 'Workload alerts',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  for (final alert in _workloadAlerts.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        alert.message,
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ),
                  if (_workloadAlerts.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '+${_workloadAlerts.length - 3}',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _header(int count) => Padding(''',
)
