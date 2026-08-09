from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str, label: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f'{label}: anchor not found in {path}')
    write(path, text.replace(old, new, 1))


# Shared employee picker: an employee from WesiOS or an optional free-form value.
write('lib/features/team/widgets/employee_or_custom_field.dart', r'''import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/employee_model.dart';
import '../services/team_service.dart';

class EmployeeOrCustomField extends StatefulWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowCustom;
  final bool allowEmpty;
  final bool storeEmployeeId;
  final String? customLabel;

  const EmployeeOrCustomField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowCustom = true,
    this.allowEmpty = true,
    this.storeEmployeeId = false,
    this.customLabel,
  });

  @override
  State<EmployeeOrCustomField> createState() => _EmployeeOrCustomFieldState();
}

class _EmployeeOrCustomFieldState extends State<EmployeeOrCustomField> {
  static const _none = '__wesios_none__';
  static const _custom = '__wesios_custom__';

  late final TextEditingController _customController;
  String? _employeeId;
  bool _customMode = false;

  @override
  void initState() {
    super.initState();
    _syncFromValue();
    _customController = TextEditingController(
      text: _customMode ? (widget.value ?? '') : '',
    );
  }

  @override
  void didUpdateWidget(covariant EmployeeOrCustomField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final oldCustom = _customMode;
    _syncFromValue();
    if (_customMode && (!oldCustom || _customController.text != widget.value)) {
      _customController.text = widget.value ?? '';
    }
  }

  void _syncFromValue() {
    final value = widget.value?.trim() ?? '';
    _employeeId = _matchEmployee(value)?.id;
    _customMode = value.isNotEmpty && _employeeId == null && widget.allowCustom;
  }

  EmployeeModel? _matchEmployee(String value) {
    if (value.isEmpty) return null;
    for (final employee in TeamService.all) {
      if (employee.id == value ||
          employee.displayName.toLowerCase() == value.toLowerCase()) {
        return employee;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = TeamService.all;
    final selected = _customMode
        ? _custom
        : _employeeId ?? (widget.allowEmpty ? _none : null);

    if (people.isEmpty && widget.allowCustom) {
      return _customInput(alwaysVisible: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selected,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          decoration: InputDecoration(labelText: widget.label),
          items: [
            if (widget.allowEmpty)
              const DropdownMenuItem<String>(
                value: _none,
                child: Text('—'),
              ),
            for (final employee in people)
              DropdownMenuItem<String>(
                value: employee.id,
                child: Text(
                  employee.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (widget.allowCustom)
              DropdownMenuItem<String>(
                value: _custom,
                child: Text(widget.customLabel ?? 'Другой…'),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == _none) {
              setState(() {
                _employeeId = null;
                _customMode = false;
                _customController.clear();
              });
              widget.onChanged(null);
              return;
            }
            if (value == _custom) {
              setState(() {
                _employeeId = null;
                _customMode = true;
              });
              widget.onChanged(_customController.text.trim());
              return;
            }
            final employee = TeamService.byId(value);
            if (employee == null) return;
            setState(() {
              _employeeId = employee.id;
              _customMode = false;
              _customController.clear();
            });
            widget.onChanged(
              widget.storeEmployeeId ? employee.id : employee.displayName,
            );
          },
        ),
        if (_customMode) ...[
          const SizedBox(height: 8),
          _customInput(),
        ],
      ],
    );
  }

  Widget _customInput({bool alwaysVisible = false}) => TextField(
        controller: _customController,
        autofocus: !alwaysVisible,
        decoration: InputDecoration(
          labelText: widget.customLabel ?? 'Другой ответственный',
        ),
        onChanged: (value) => widget.onChanged(
          value.trim().isEmpty ? null : value.trim(),
        ),
      );
}
''')

# Home: WesiOS name stays visible, exact balance, separate clock/calendar taps.
replace_once(
    'lib/features/home/home_screen.dart',
    '''                                  WesiWordmark(\n                                    size: compactHeader ? 24 : 26,\n                                    showText: !compactHeader,\n                                    markFirst: true,\n                                  ),\n''',
    '''                                  FittedBox(\n                                    fit: BoxFit.scaleDown,\n                                    alignment: Alignment.centerLeft,\n                                    child: WesiWordmark(\n                                      size: compactHeader ? 21 : 26,\n                                      showText: true,\n                                      markFirst: true,\n                                    ),\n                                  ),\n''',
    'home wordmark',
)
replace_once(
    'lib/features/home/home_screen.dart',
    '''                    Tooltip(\n                      message: WesiLocale.isRussian\n                          ? 'Открыть центр времени · долгий тап — стиль часов'\n                          : 'Open Time Center · long-press for clock style',\n                      child: GestureDetector(\n                        behavior: HitTestBehavior.opaque,\n                        onTap: () => Navigator.pushNamed(context, '/time'),\n                        onLongPress: () {\n                          final next =\n                              WesiClock.savedStyle == ClockStyle.digital\n                                  ? ClockStyle.analog\n                                  : ClockStyle.digital;\n                          WesiClock.setStyle(next);\n                          setState(() {});\n                        },\n                        child: const SizedBox(\n                          key: ValueKey('home_clock_panel'),\n                          width: double.infinity,\n                          child: WesiClock(),\n                        ),\n                      ),\n                    ),\n''',
    '''                    Tooltip(\n                      message: WesiLocale.isRussian\n                          ? 'Часы открывают центр времени, календарь — календарь'\n                          : 'Clock opens Time Center, calendar opens Calendar',\n                      child: SizedBox(\n                        key: const ValueKey('home_clock_panel'),\n                        width: double.infinity,\n                        child: WesiClock(\n                          onClockTap: () =>\n                              Navigator.pushNamed(context, '/time'),\n                          onClockLongPress: () {\n                            final next =\n                                WesiClock.savedStyle == ClockStyle.digital\n                                    ? ClockStyle.analog\n                                    : ClockStyle.digital;\n                            WesiClock.setStyle(next);\n                            setState(() {});\n                          },\n                          onCalendarTap: () =>\n                              Navigator.pushNamed(context, '/calendar'),\n                        ),\n                      ),\n                    ),\n''',
    'home clock split tap',
)
replace_once(
    'lib/features/home/home_screen.dart',
    '                        CurrencyService.format(_balance),\n',
    '                        CurrencyService.formatExactSmart(_balance),\n',
    'home exact balance',
)

# Exact sum without k/M, trimming meaningless zeros.
replace_once(
    'lib/core/services/currency_service.dart',
    '''  /// Конвертирует и возвращает голое число в текущей валюте — для графиков,\n  /// где подпись оси строится отдельно.\n  static double display(double rubValue) => fromRub(rubValue);\n''',
    '''  /// Точная сумма без k/M, но без бессмысленных хвостов `.00`.\n  static String formatExactSmart(double rubValue, {int maxDecimals = 2}) {\n    if (privacyMode.value) return '$symbol$_masked';\n    final v = fromRub(rubValue);\n    final sign = v < 0 ? '-' : '';\n    var amount = v.abs().toStringAsFixed(maxDecimals);\n    if (amount.contains('.')) {\n      amount = amount.replaceFirst(RegExp(r'0+$'), '');\n      amount = amount.replaceFirst(RegExp(r'\\.$'), '');\n    }\n    return '$sign$symbol$amount';\n  }\n\n  /// Конвертирует и возвращает голое число в текущей валюте — для графиков,\n  /// где подпись оси строится отдельно.\n  static double display(double rubValue) => fromRub(rubValue);\n''',
    'currency exact smart',
)

# More: Calendar ready + proper mobile status-bar inset.
replace_once(
    'lib/features/home/more_tab.dart',
    '''            subtitle: ru\n                ? 'Сетка месяца работает, события — впереди'\n                : 'Month grid works, events are next',\n            stage: ModuleStage.partial,\n''',
    '''            subtitle: ru\n                ? 'События, задачи, финансы и напоминания на временной шкале'\n                : 'Events, tasks, finance and reminders on one timeline',\n            stage: ModuleStage.ready,\n''',
    'calendar readiness',
)
replace_once(
    'lib/features/home/more_tab.dart',
    '        padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 16, 16, 32),\n',
    '''        padding: EdgeInsets.fromLTRB(\n          16,\n          MediaQuery.paddingOf(context).top + kTitleBarInset + 16,\n          16,\n          32,\n        ),\n''',
    'more status bar inset',
)

# WesiClock independent click targets.
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    '''class WesiClock extends StatefulWidget {\n  final bool showSeconds;\n  final ClockStyle? forceStyle;\n\n  const WesiClock({\n    super.key,\n    this.showSeconds = true,\n    this.forceStyle,\n  });\n''',
    '''class WesiClock extends StatefulWidget {\n  final bool showSeconds;\n  final ClockStyle? forceStyle;\n  final VoidCallback? onClockTap;\n  final VoidCallback? onClockLongPress;\n  final VoidCallback? onCalendarTap;\n\n  const WesiClock({\n    super.key,\n    this.showSeconds = true,\n    this.forceStyle,\n    this.onClockTap,\n    this.onClockLongPress,\n    this.onCalendarTap,\n  });\n''',
    'clock callbacks',
)
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    '''          SizedBox(\n            width: clockWidth,\n            child: FittedBox(\n              fit: BoxFit.scaleDown,\n              alignment: Alignment.centerLeft,\n              child: SizedBox(width: clockWidth, child: info),\n            ),\n          ),\n          SizedBox(width: gap),\n          _MiniMonthCalendar(\n            now: _now,\n            width: calendarWidth,\n            large: large,\n          ),\n''',
    '''          GestureDetector(\n            behavior: HitTestBehavior.opaque,\n            onTap: widget.onClockTap,\n            onLongPress: widget.onClockLongPress,\n            child: SizedBox(\n              width: clockWidth,\n              child: FittedBox(\n                fit: BoxFit.scaleDown,\n                alignment: Alignment.centerLeft,\n                child: SizedBox(width: clockWidth, child: info),\n              ),\n            ),\n          ),\n          SizedBox(width: gap),\n          GestureDetector(\n            behavior: HitTestBehavior.opaque,\n            onTap: widget.onCalendarTap,\n            child: _MiniMonthCalendar(\n              now: _now,\n              width: calendarWidth,\n              large: large,\n            ),\n          ),\n''',
    'clock hit targets',
)

# Task assignee becomes employee list + custom value while permissions still lock normal employees.
assignee = read('lib/features/tasks/widgets/assignee_field.dart')
if "import '../../team/widgets/employee_or_custom_field.dart';" not in assignee:
    assignee = assignee.replace(
        "import '../../team/models/employee_model.dart';\n",
        "import '../../team/models/employee_model.dart';\nimport '../../team/widgets/employee_or_custom_field.dart';\n",
        1,
    )
start_marker = "    return Column(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n        _label(ru ? 'Исполнитель' : 'Assignee'),"
start = assignee.find(start_marker, assignee.find('if (!canAssign)'))
end_marker = "    );\n  }\n\n  /// Исполнитель из старой записи"
end = assignee.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('assignee dropdown block anchor not found')
assignee = assignee[:start] + '''    return EmployeeOrCustomField(\n      label: ru ? 'Исполнитель' : 'Assignee',\n      value: value,\n      storeEmployeeId: true,\n      allowCustom: true,\n      allowEmpty: true,\n      customLabel: ru ? 'Другой исполнитель' : 'Other assignee',\n      onChanged: onChanged,\n    );\n  }\n\n''' + assignee[end + len("    );\n  }\n\n"):]
write('lib/features/tasks/widgets/assignee_field.dart', assignee)
replace_once(
    'lib/features/tasks/services/task_assignment.dart',
    '''  static String? coerce(String? requested) {\n    if (canAssignToOthers) return requested;\n    final me = currentId;\n''',
    '''  static String? coerce(String? requested) {\n    if (canAssignToOthers) {\n      final value = requested?.trim();\n      return value == null || value.isEmpty ? null : value;\n    }\n    final me = currentId;\n''',
    'task custom assignee',
)

# Roadmap: employees in owners/assignees + timeline zoom.
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    "import '../tasks/services/task_service.dart';\n",
    "import '../tasks/services/task_service.dart';\nimport '../team/widgets/employee_or_custom_field.dart';\n",
    'roadmap picker import',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '''  String? _projectId;\n  bool _showArchived = false;\n''',
    '''  String? _projectId;\n  bool _showArchived = false;\n  double _timelineZoom = 1.0;\n''',
    'roadmap zoom state',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '''            _legend(AppTheme.accentGreen, _ru ? 'Готово' : 'Done'),\n            const SizedBox(width: 10),\n            _legend(AppTheme.accentRed, _ru ? 'Риск' : 'Risk'),\n          ],\n        ),\n        const SizedBox(height: 10),\n        _TimelineBoard(\n          project: project,\n          items: items,\n          russian: _ru,\n          onTap: (item) => _editItem(item, data),\n        ),\n''',
    '''            _legend(AppTheme.accentGreen, _ru ? 'Готово' : 'Done'),\n            const SizedBox(width: 10),\n            _legend(AppTheme.accentRed, _ru ? 'Риск' : 'Risk'),\n          ],\n        ),\n        const SizedBox(height: 8),\n        Row(\n          children: [\n            Icon(Icons.zoom_out, size: 17, color: AppTheme.textMuted),\n            Expanded(\n              child: Slider(\n                value: _timelineZoom,\n                min: 0.6,\n                max: 2.4,\n                divisions: 9,\n                label: '${(_timelineZoom * 100).round()}%',\n                onChanged: (value) => setState(() => _timelineZoom = value),\n              ),\n            ),\n            Text(\n              '${(_timelineZoom * 100).round()}%',\n              style: TextStyle(\n                fontSize: 10.5,\n                fontWeight: FontWeight.w700,\n                color: AppTheme.textSecondary,\n              ),\n            ),\n            const SizedBox(width: 4),\n            Icon(Icons.zoom_in, size: 17, color: AppTheme.textMuted),\n          ],\n        ),\n        const SizedBox(height: 6),\n        _TimelineBoard(\n          project: project,\n          items: items,\n          russian: _ru,\n          zoom: _timelineZoom,\n          onTap: (item) => _editItem(item, data),\n        ),\n''',
    'roadmap zoom controls',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '''  final bool russian;\n  final ValueChanged<RoadmapItem> onTap;\n\n  const _TimelineBoard({\n    required this.project,\n    required this.items,\n    required this.russian,\n    required this.onTap,\n  });\n''',
    '''  final bool russian;\n  final double zoom;\n  final ValueChanged<RoadmapItem> onTap;\n\n  const _TimelineBoard({\n    required this.project,\n    required this.items,\n    required this.russian,\n    required this.zoom,\n    required this.onTap,\n  });\n''',
    'roadmap zoom property',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '    final dayWidth = days <= 45 ? 25.0 : days <= 120 ? 16.0 : 10.0;\n',
    '    final baseDayWidth = days <= 45 ? 25.0 : days <= 120 ? 16.0 : 10.0;\n    final dayWidth = (baseDayWidth * zoom).clamp(5.0, 48.0);\n',
    'roadmap zoom width',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '''            _roadField(_owner, _ru ? 'Владелец проекта' : 'Project owner'),\n            _roadField(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n''',
    '''            EmployeeOrCustomField(\n              label: _ru ? 'Владелец проекта' : 'Project owner',\n              value: _owner.text,\n              storeEmployeeId: false,\n              allowCustom: true,\n              customLabel: _ru ? 'Другой владелец' : 'Other owner',\n              onChanged: (value) => _owner.text = value ?? '',\n            ),\n            const SizedBox(height: 10),\n            _roadField(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n''',
    'roadmap project owner',
)
replace_once(
    'lib/features/roadmap/roadmap_screen.dart',
    '''            _roadField(_assignee, _ru ? 'Ответственный' : 'Assignee'),\n            Row(\n''',
    '''            EmployeeOrCustomField(\n              label: _ru ? 'Ответственный' : 'Assignee',\n              value: _assignee.text,\n              storeEmployeeId: false,\n              allowCustom: true,\n              customLabel: _ru ? 'Другой ответственный' : 'Other assignee',\n              onChanged: (value) => _assignee.text = value ?? '',\n            ),\n            const SizedBox(height: 10),\n            Row(\n''',
    'roadmap item assignee',
)

# CRM responsible picker.
replace_once(
    'lib/features/crm/crm_screen.dart',
    "import '../../core/widgets/window_controls.dart';\n",
    "import '../../core/widgets/window_controls.dart';\nimport '../team/widgets/employee_or_custom_field.dart';\n",
    'crm picker import',
)
replace_once(
    'lib/features/crm/crm_screen.dart',
    '''            _field(_address, _ru ? 'Адрес' : 'Address'),\n            _field(_owner, _ru ? 'Ответственный' : 'Owner'),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n''',
    '''            _field(_address, _ru ? 'Адрес' : 'Address'),\n            EmployeeOrCustomField(\n              label: _ru ? 'Ответственный' : 'Owner',\n              value: _owner.text,\n              storeEmployeeId: false,\n              allowCustom: true,\n              customLabel: _ru ? 'Другой ответственный' : 'Other owner',\n              onChanged: (value) => _owner.text = value ?? '',\n            ),\n            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n''',
    'crm owner picker',
)

# Audio Vault uses the same employee selector for responsible/author.
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    "import '../team/services/team_service.dart';\n",
    "import '../team/services/team_service.dart';\nimport '../team/widgets/employee_or_custom_field.dart';\n",
    'audio picker import',
)
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    '''  Widget build(BuildContext context) {\n    final employees = TeamService.all;\n    return AlertDialog(\n''',
    '''  Widget build(BuildContext context) {\n    return AlertDialog(\n''',
    'audio employee local list',
)
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    '''            DropdownButtonFormField<String>(\n              value: authorId,\n              dropdownColor: AppTheme.surface,\n              decoration: const InputDecoration(labelText: 'Автор / сотрудник'),\n              items: employees\n                  .map((e) =>\n                      DropdownMenuItem(value: e.id, child: Text(e.displayName)))\n                  .toList(),\n              onChanged: (v) => setState(() => authorId = v),\n            ),\n''',
    '''            EmployeeOrCustomField(\n              label: 'Ответственный / автор',\n              value: authorId,\n              storeEmployeeId: true,\n              allowCustom: false,\n              allowEmpty: false,\n              onChanged: (value) => setState(() => authorId = value),\n            ),\n''',
    'audio author picker',
)

# Launcher icon follows theme and light alias has a genuinely different resource.
replace_once(
    'lib/main.dart',
    '''  ThemeNotifier.load();\n  AppIconService.load();\n''',
    '''  ThemeNotifier.load();\n  ThemeNotifier.instance.addListener(AppIconService.apply);\n  AppIconService.load();\n''',
    'theme icon listener',
)
replace_once(
    'android/app/src/main/AndroidManifest.xml',
    '''        <activity-alias\n            android:name=".IconLight"\n            android:enabled="false"\n            android:exported="true"\n            android:icon="@mipmap/launcher_icon"\n            android:roundIcon="@mipmap/launcher_icon"\n''',
    '''        <activity-alias\n            android:name=".IconLight"\n            android:enabled="false"\n            android:exported="true"\n            android:icon="@drawable/launcher_icon_light"\n            android:roundIcon="@drawable/launcher_icon_light"\n''',
    'light icon alias',
)
write('android/app/src/main/res/drawable/launcher_icon_light.xml', r'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#F8F9FC" android:pathData="M0,0h108v108h-108z" />
    <path android:fillColor="#334155" android:pathData="M20,31 L30,31 L38,65 L49,43 L58,43 L68,65 L76,31 L86,31 L75,77 L65,77 L53.5,54 L42,77 L32,77 Z" />
    <path android:fillColor="#3B82F6" android:pathData="M75,28 L84,28 L76,62 L68,62 Z" />
</vector>
''')

# Transaction date + exact time.
replace_once(
    'lib/features/treasury/widgets/add_transaction_dialog.dart',
    '''    if (picked != null) {\n      setState(() => _selectedDate = picked);\n    }\n  }\n\n  String _formatDate(DateTime d) {\n''',
    '''    if (picked != null) {\n      setState(() {\n        _selectedDate = DateTime(\n          picked.year,\n          picked.month,\n          picked.day,\n          _selectedDate.hour,\n          _selectedDate.minute,\n          _selectedDate.second,\n        );\n      });\n    }\n  }\n\n  Future<void> _pickTime() async {\n    final picked = await showTimePicker(\n      context: context,\n      initialTime: TimeOfDay.fromDateTime(_selectedDate),\n    );\n    if (picked == null) return;\n    setState(() {\n      _selectedDate = DateTime(\n        _selectedDate.year,\n        _selectedDate.month,\n        _selectedDate.day,\n        picked.hour,\n        picked.minute,\n      );\n    });\n  }\n\n  String _formatTime(DateTime d) =>\n      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';\n\n  String _formatDate(DateTime d) {\n''',
    'transaction time picker',
)
old_date_ui = '''            // Выбор даты транзакции\n            GestureDetector(\n              onTap: _pickDate,\n              child: Container(\n                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),\n                decoration: BoxDecoration(\n                  color: AppTheme.surface.withOpacity(0.3),\n                  borderRadius: BorderRadius.circular(12),\n                  border: Border.all(color: AppTheme.glassBorder),\n                ),\n                child: Row(\n                  children: [\n                    Icon(Icons.calendar_today, size: 18, color: AppTheme.accent),\n                    const SizedBox(width: 10),\n                    Expanded(\n                      child: Text(\n                        _formatDate(_selectedDate),\n                        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),\n                      ),\n                    ),\n                    if (_selectedDate.isAfter(DateTime.now().add(const Duration(days: 1))))\n                      Container(\n                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),\n                        decoration: BoxDecoration(\n                          color: AppTheme.accent.withOpacity(0.15),\n                          borderRadius: BorderRadius.circular(6),\n                        ),\n                        child: Text(\n                          WesiLocale.isRussian ? 'Запланировано' : 'Planned',\n                          style: TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.w600),\n                        ),\n                      ),\n                  ],\n                ),\n              ),\n            ),\n'''
new_date_ui = '''            // Дата и точное время операции редактируются независимо.\n            Row(\n              children: [\n                Expanded(\n                  child: GestureDetector(\n                    onTap: _pickDate,\n                    child: Container(\n                      padding: const EdgeInsets.symmetric(\n                          horizontal: 12, vertical: 14),\n                      decoration: BoxDecoration(\n                        color: AppTheme.surface.withOpacity(0.3),\n                        borderRadius: BorderRadius.circular(12),\n                        border: Border.all(color: AppTheme.glassBorder),\n                      ),\n                      child: Row(\n                        children: [\n                          Icon(Icons.calendar_today,\n                              size: 18, color: AppTheme.accent),\n                          const SizedBox(width: 9),\n                          Expanded(\n                            child: Text(\n                              _formatDate(_selectedDate),\n                              maxLines: 1,\n                              overflow: TextOverflow.ellipsis,\n                              style: TextStyle(\n                                  fontSize: 13, color: AppTheme.textPrimary),\n                            ),\n                          ),\n                        ],\n                      ),\n                    ),\n                  ),\n                ),\n                const SizedBox(width: 8),\n                SizedBox(\n                  width: 112,\n                  child: GestureDetector(\n                    onTap: _pickTime,\n                    child: Container(\n                      padding: const EdgeInsets.symmetric(\n                          horizontal: 12, vertical: 14),\n                      decoration: BoxDecoration(\n                        color: AppTheme.surface.withOpacity(0.3),\n                        borderRadius: BorderRadius.circular(12),\n                        border: Border.all(color: AppTheme.glassBorder),\n                      ),\n                      child: Row(\n                        children: [\n                          Icon(Icons.schedule, size: 18, color: AppTheme.accent),\n                          const SizedBox(width: 8),\n                          Text(\n                            _formatTime(_selectedDate),\n                            style: TextStyle(\n                                fontSize: 13, color: AppTheme.textPrimary),\n                          ),\n                        ],\n                      ),\n                    ),\n                  ),\n                ),\n              ],\n            ),\n'''
replace_once('lib/features/treasury/widgets/add_transaction_dialog.dart', old_date_ui, new_date_ui, 'transaction date/time UI')

# Operations: visual day sections, show exact time, no rounded amounts.
replace_once(
    'lib/features/treasury/operations_screen.dart',
    '''                      const SizedBox(height: 20),\n                      ..._filtered.map(_txItem),\n''',
    '''                      const SizedBox(height: 20),\n                      ..._transactionRows(),\n''',
    'operations grouped rows',
)
replace_once(
    'lib/features/treasury/operations_screen.dart',
    '  Widget _txItem(TransactionModel tx) {\n',
    '''  List<Widget> _transactionRows() {\n    if (_filtered.isEmpty) return const [];\n    if (_sortBy != 'date') return _filtered.map(_txItem).toList();\n\n    final rows = <Widget>[];\n    DateTime? previousDay;\n    for (final tx in _filtered) {\n      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);\n      if (previousDay != day) {\n        rows.add(_dateHeader(day));\n        previousDay = day;\n      }\n      rows.add(_txItem(tx));\n    }\n    return rows;\n  }\n\n  Widget _dateHeader(DateTime day) {\n    final now = DateTime.now();\n    final today = DateTime(now.year, now.month, now.day);\n    final yesterday = today.subtract(const Duration(days: 1));\n    final label = day == today\n        ? (WesiLocale.isRussian ? 'Сегодня' : 'Today')\n        : day == yesterday\n            ? (WesiLocale.isRussian ? 'Вчера' : 'Yesterday')\n            : _formatDate(day);\n    return Padding(\n      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),\n      child: Row(\n        children: [\n          Text(\n            label,\n            style: TextStyle(\n              fontSize: 12,\n              fontWeight: FontWeight.w800,\n              color: AppTheme.textSecondary,\n            ),\n          ),\n          const SizedBox(width: 10),\n          Expanded(child: Divider(color: AppTheme.glassBorder)),\n        ],\n      ),\n    );\n  }\n\n  Widget _txItem(TransactionModel tx) {\n''',
    'operations group helper',
)
replace_once(
    'lib/features/treasury/operations_screen.dart',
    "    final isIncome = tx.type == TransactionType.income;\n    final sym = CurrencyService.symbol;\n",
    "    final isIncome = tx.type == TransactionType.income;\n",
    'operations remove sym',
)
replace_once(
    'lib/features/treasury/operations_screen.dart',
    "                    '${tx.category ?? WesiLocale.get('uncategorized')} · ${_formatDate(tx.date)}',\n",
    "                    '${tx.category ?? WesiLocale.get('uncategorized')} · ${_formatDate(tx.date)} · ${_formatTime(tx.date)}',\n",
    'operations time',
)
replace_once(
    'lib/features/treasury/operations_screen.dart',
    "              '${isIncome ? '+' : '-'}$sym${CurrencyService.fromRub(tx.amount).toStringAsFixed(0)}',\n",
    "              '${isIncome ? '+' : '-'}${CurrencyService.formatExactSmart(tx.amount)}',\n",
    'operations exact amount',
)
replace_once(
    'lib/features/treasury/operations_screen.dart',
    '''  String _formatDate(DateTime d) {\n    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';\n  }\n}\n''',
    '''  String _formatDate(DateTime d) {\n    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';\n  }\n\n  String _formatTime(DateTime d) =>\n      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';\n}\n''',
    'operations time formatter',
)

# Time Center: smoother boundary updates, stopwatch only whole seconds.
replace_once(
    'lib/features/time_center/time_center_screen.dart',
    '    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {\n',
    '    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {\n',
    'time center ticker',
)
replace_once(
    'lib/features/time_center/time_center_screen.dart',
    '''  String _formatStopwatchMs(int ms) {\n    final safe = ms < 0 ? 0 : ms;\n    final hours = safe ~/ 3600000;\n    final minutes = (safe ~/ 60000) % 60;\n    final seconds = (safe ~/ 1000) % 60;\n    final hundredths = (safe ~/ 10) % 100;\n    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';\n  }\n''',
    '''  String _formatStopwatchMs(int ms) {\n    final safe = ms < 0 ? 0 : ms;\n    final totalSeconds = safe ~/ 1000;\n    final hours = totalSeconds ~/ 3600;\n    final minutes = (totalSeconds ~/ 60) % 60;\n    final seconds = totalSeconds % 60;\n    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';\n  }\n''',
    'stopwatch seconds only',
)

# Short forecast visually stretches: 7-day future gets ~7-day history, not fixed 30d history.
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    '    final historyWindowDays = _forecastDays.clamp(30, 90);\n',
    '''    // Keep short horizons readable: a 7-day forecast gets about 7 days\n    // of history instead of being squeezed by a fixed 30-day history window.\n    final historyWindowDays = _forecastDays.clamp(7, 90);\n''',
    'forecast short horizon',
)

# What-If: recurring virtual operations.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    '''class WhatIfEvent {\n  final String title;\n  final double amount;\n  final TransactionType type;\n  final DateTime date;\n\n  const WhatIfEvent({\n    required this.title,\n    required this.amount,\n    required this.type,\n    required this.date,\n  });\n}\n''',
    '''class WhatIfEvent {\n  final String title;\n  final double amount;\n  final TransactionType type;\n  final DateTime date;\n  final RecurringPeriod? recurringPeriod;\n\n  const WhatIfEvent({\n    required this.title,\n    required this.amount,\n    required this.type,\n    required this.date,\n    this.recurringPeriod,\n  });\n\n  bool get isRecurring => recurringPeriod != null;\n}\n''',
    'what-if recurring model',
)
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    '''    // Виртуальные события «Что если?» — по смещению в днях.\n    final whatIfByOffset = <int, double>{};\n    for (final e in whatIf.events) {\n      final day = DateTime(e.date.year, e.date.month, e.date.day);\n      final offset = day.difference(todayOnly).inDays;\n      if (offset < 1 || offset > days) continue;\n      final net = e.type == TransactionType.income ? e.amount : -e.amount;\n      whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;\n    }\n''',
    '''    // Виртуальные операции «Что если?»: разовые и регулярные.\n    final whatIfByOffset = <int, double>{};\n    final whatIfHorizon = todayOnly.add(Duration(days: days));\n    for (final e in whatIf.events) {\n      final net = e.type == TransactionType.income ? e.amount : -e.amount;\n      final start = DateTime(e.date.year, e.date.month, e.date.day);\n      final period = e.recurringPeriod;\n      if (period == null) {\n        final offset = start.difference(todayOnly).inDays;\n        if (offset < 1 || offset > days) continue;\n        whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;\n        continue;\n      }\n\n      var occurrence = start.isAfter(todayOnly)\n          ? start\n          : RecurringEngine.nextOccurrenceAfter(start, period, todayOnly);\n      var guard = 0;\n      while (!occurrence.isAfter(whatIfHorizon) && guard < 10000) {\n        final offset = occurrence.difference(todayOnly).inDays;\n        if (offset >= 1 && offset <= days) {\n          whatIfByOffset[offset] = (whatIfByOffset[offset] ?? 0) + net;\n        }\n        occurrence = RecurringEngine.advance(occurrence, period);\n        guard++;\n      }\n    }\n''',
    'what-if recurring engine',
)

# What-If dialog now supports any number of one-time/recurring virtual operations.
write('lib/features/treasury/widgets/what_if_dialog.dart', r'''import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/transaction_model.dart';
import '../services/forecast_engine.dart';

class WhatIfDialog extends StatefulWidget {
  final WhatIfScenario initial;
  final int forecastDays;
  final String symbol;

  const WhatIfDialog({
    super.key,
    required this.initial,
    required this.forecastDays,
    required this.symbol,
  });

  @override
  State<WhatIfDialog> createState() => _WhatIfDialogState();
}

class _WhatIfDialogState extends State<WhatIfDialog> {
  late double _incomeMult;
  late double _expenseMult;
  final List<_VirtualOperationDraft> _operations = [];

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _incomeMult = widget.initial.incomeMultiplier;
    _expenseMult = widget.initial.expenseMultiplier;
    for (final event in widget.initial.events) {
      _operations.add(_VirtualOperationDraft.fromEvent(event));
    }
  }

  @override
  void dispose() {
    for (final operation in _operations) {
      operation.dispose();
    }
    super.dispose();
  }

  void _addOperation() {
    final now = DateTime.now();
    setState(() {
      _operations.add(
        _VirtualOperationDraft(
          date: DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 1)),
        ),
      );
    });
  }

  void _removeOperation(int index) {
    final value = _operations.removeAt(index);
    value.dispose();
    setState(() {});
  }

  void _apply() {
    final events = <WhatIfEvent>[];
    for (final operation in _operations) {
      final amount = double.tryParse(
        operation.amount.text.trim().replaceAll(',', '.'),
      );
      final title = operation.title.text.trim();
      if (title.isEmpty || amount == null || amount <= 0) continue;
      events.add(
        WhatIfEvent(
          title: title,
          amount: amount,
          type: operation.type,
          date: operation.date,
          recurringPeriod: operation.recurringPeriod,
        ),
      );
    }
    Navigator.pop(
      context,
      WhatIfScenario(
        events: events,
        incomeMultiplier: _incomeMult,
        expenseMultiplier: _expenseMult,
      ),
    );
  }

  void _reset() => Navigator.pop(context, WhatIfScenario.none);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.fromLTRB(20, kTitleBarHeight + 20, 20, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'what_if'.w,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _ru
                    ? 'Добавьте виртуальные доходы и траты: один раз или по расписанию. Реальные операции не изменятся.'
                    : 'Add virtual income and expenses once or on a schedule. Real operations stay untouched.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _ru ? 'Виртуальные операции' : 'Virtual operations',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addOperation,
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(_ru ? 'Добавить' : 'Add'),
                  ),
                ],
              ),
              if (_operations.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Text(
                    _ru
                        ? 'Например: инвестиции +10 000 ₽ каждый месяц, аренда −50 000 ₽ ежемесячно или разовая покупка.'
                        : 'For example: +10,000 monthly investment, −50,000 monthly rent, or a one-time purchase.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppTheme.textMuted,
                    ),
                  ),
                )
              else
                for (var i = 0; i < _operations.length; i++) ...[
                  _operationCard(i, _operations[i]),
                  if (i + 1 < _operations.length)
                    const SizedBox(height: 10),
                ],
              const SizedBox(height: 22),
              _slider(
                label: 'what_if_income_adjust'.w,
                value: _incomeMult,
                min: 0.5,
                max: 1.5,
                color: AppTheme.accentGreen,
                onChanged: (v) => setState(() => _incomeMult = v),
              ),
              const SizedBox(height: 12),
              _slider(
                label: 'what_if_expense_adjust'.w,
                value: _expenseMult,
                min: 0.5,
                max: 2.0,
                color: AppTheme.accentRed,
                onChanged: (v) => setState(() => _expenseMult = v),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: _reset,
                    child: Text('what_if_reset'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('cancel'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  HoverButton(
                    onTap: _apply,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accent,
                    child: Text('what_if_apply'.w,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _operationCard(int index, _VirtualOperationDraft operation) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: operation.title,
                  decoration: InputDecoration(
                    labelText: _ru ? 'Название' : 'Title',
                    hintText: _ru ? 'Инвестиции' : 'Investment',
                  ),
                ),
              ),
              IconButton(
                tooltip: _ru ? 'Удалить' : 'Delete',
                onPressed: () => _removeOperation(index),
                icon: Icon(Icons.delete_outline, color: AppTheme.accentRed),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: operation.amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'amount'.w,
                    prefixText: '${widget.symbol} ',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ToggleButtons(
                isSelected: [
                  operation.type == TransactionType.income,
                  operation.type == TransactionType.expense,
                ],
                onPressed: (value) => setState(() {
                  operation.type = value == 0
                      ? TransactionType.income
                      : TransactionType.expense;
                }),
                borderRadius: BorderRadius.circular(10),
                selectedColor: Colors.white,
                fillColor: operation.type == TransactionType.income
                    ? AppTheme.accentGreen
                    : AppTheme.accentRed,
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                children: const [
                  Icon(Icons.add_circle_outline, size: 18),
                  Icon(Icons.remove_circle_outline, size: 18),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickOperationDate(operation),
                  icon: const Icon(Icons.calendar_month, size: 17),
                  label: Text(
                    '${operation.date.day.toString().padLeft(2, '0')}.'
                    '${operation.date.month.toString().padLeft(2, '0')}.'
                    '${operation.date.year}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<RecurringPeriod?>(
                  value: operation.recurringPeriod,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: _ru ? 'Повтор' : 'Repeat'),
                  items: [
                    DropdownMenuItem<RecurringPeriod?>(
                      value: null,
                      child: Text(_ru ? 'Один раз' : 'Once'),
                    ),
                    for (final period in RecurringPeriod.values)
                      DropdownMenuItem<RecurringPeriod?>(
                        value: period,
                        child: Text(_periodLabel(period)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => operation.recurringPeriod = value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickOperationDate(_VirtualOperationDraft operation) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(Duration(days: widget.forecastDays));
    var initial = operation.date;
    if (initial.isBefore(start)) initial = start;
    if (initial.isAfter(end)) initial = end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: end,
      locale: _ru ? const Locale('ru') : const Locale('en'),
    );
    if (picked != null) setState(() => operation.date = picked);
  }

  String _periodLabel(RecurringPeriod value) {
    if (_ru) {
      return switch (value) {
        RecurringPeriod.daily => 'Каждый день',
        RecurringPeriod.weekly => 'Каждую неделю',
        RecurringPeriod.monthly => 'Каждый месяц',
        RecurringPeriod.yearly => 'Каждый год',
      };
    }
    return switch (value) {
      RecurringPeriod.daily => 'Daily',
      RecurringPeriod.weekly => 'Weekly',
      RecurringPeriod.monthly => 'Monthly',
      RecurringPeriod.yearly => 'Yearly',
    };
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final pct = ((value - 1.0) * 100).round();
    final pctLabel = pct == 0 ? '0%' : (pct > 0 ? '+$pct%' : '$pct%');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
            Text(pctLabel,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: AppTheme.glassBorder,
            overlayColor: color.withOpacity(0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _VirtualOperationDraft {
  final TextEditingController title;
  final TextEditingController amount;
  TransactionType type;
  DateTime date;
  RecurringPeriod? recurringPeriod;

  _VirtualOperationDraft({
    String title = '',
    String amount = '',
    this.type = TransactionType.expense,
    required this.date,
    this.recurringPeriod,
  })  : title = TextEditingController(text: title),
        amount = TextEditingController(text: amount);

  factory _VirtualOperationDraft.fromEvent(WhatIfEvent event) =>
      _VirtualOperationDraft(
        title: event.title,
        amount: event.amount.toStringAsFixed(event.amount % 1 == 0 ? 0 : 2),
        type: event.type,
        date: event.date,
        recurringPeriod: event.recurringPeriod,
      );

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}
''')

# Preset JSON keeps recurrence backward-compatible.
replace_once(
    'lib/features/treasury/services/what_if_store.dart',
    "      parts.add('${e.title}: $sign$symbol${e.amount.toStringAsFixed(0)}');\n",
    "      final repeat = e.recurringPeriod == null\n          ? ''\n          : ' (${_periodLabel(e.recurringPeriod!, ru)})';\n      parts.add('${e.title}: $sign$symbol${e.amount.toStringAsFixed(0)}$repeat');\n",
    'what-if summary recurrence',
)
replace_once(
    'lib/features/treasury/services/what_if_store.dart',
    "                  'dayOffset': _offsetOf(e.date),\n",
    "                  'dayOffset': _offsetOf(e.date),\n                  'recurringPeriod': e.recurringPeriod?.name,\n",
    'what-if serialize recurrence',
)
replace_once(
    'lib/features/treasury/services/what_if_store.dart',
    "          date: today.add(Duration(days: offset)),\n        ));\n",
    "          date: today.add(Duration(days: offset)),\n          recurringPeriod: _recurringPeriod(e['recurringPeriod']),\n        ));\n",
    'what-if deserialize recurrence',
)
replace_once(
    'lib/features/treasury/services/what_if_store.dart',
    '  static WhatIfPreset? fromJson(Map<String, dynamic> json) {\n',
    '''  static String _periodLabel(RecurringPeriod value, bool ru) {\n    if (ru) {\n      return switch (value) {\n        RecurringPeriod.daily => 'ежедневно',\n        RecurringPeriod.weekly => 'еженедельно',\n        RecurringPeriod.monthly => 'ежемесячно',\n        RecurringPeriod.yearly => 'ежегодно',\n      };\n    }\n    return switch (value) {\n      RecurringPeriod.daily => 'daily',\n      RecurringPeriod.weekly => 'weekly',\n      RecurringPeriod.monthly => 'monthly',\n      RecurringPeriod.yearly => 'yearly',\n    };\n  }\n\n  static RecurringPeriod? _recurringPeriod(dynamic raw) {\n    if (raw is! String || raw.isEmpty) return null;\n    for (final value in RecurringPeriod.values) {\n      if (value.name == raw) return value;\n    }\n    return null;\n  }\n\n  static WhatIfPreset? fromJson(Map<String, dynamic> json) {\n''',
    'what-if recurrence helpers',
)

# Version bump.
replace_once('pubspec.yaml', 'version: 0.19.17+65\n', 'version: 0.19.18+66\n', 'pubspec version')
replace_once('lib/core/constants/app_version.dart', "  static const String number = '0.19.17';\n", "  static const String number = '0.19.18';\n", 'version number')
replace_once('lib/core/constants/app_version.dart', '  static const int build = 65;\n', '  static const int build = 66;\n', 'build number')

# Regression checks for the whole mobile pass.
write('test/mobile_ux_01918_test.dart', r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/what_if_store.dart';

void main() {
  test('home keeps WesiOS name and exact balance', () {
    final source = File('lib/features/home/home_screen.dart').readAsStringSync();
    expect(source, contains('showText: true'));
    expect(source, contains('CurrencyService.formatExactSmart(_balance)'));
    expect(source, contains('onCalendarTap:'));
  });

  test('more tab marks calendar ready and respects system inset', () {
    final source = File('lib/features/home/more_tab.dart').readAsStringSync();
    expect(source, contains('MediaQuery.paddingOf(context).top'));
    final start = source.indexOf("route: '/calendar'");
    expect(start, greaterThanOrEqualTo(0));
    expect(source.substring(start, (start + 620).clamp(0, source.length)),
        contains('stage: ModuleStage.ready'));
  });

  test('transaction editor has both date and time picker', () {
    final source = File('lib/features/treasury/widgets/add_transaction_dialog.dart')
        .readAsStringSync();
    expect(source, contains('showDatePicker'));
    expect(source, contains('showTimePicker'));
    expect(source, contains('_formatTime(_selectedDate)'));
  });

  test('operations have date sections and visible operation time', () {
    final source =
        File('lib/features/treasury/operations_screen.dart').readAsStringSync();
    expect(source, contains('List<Widget> _transactionRows()'));
    expect(source, contains('Widget _dateHeader(DateTime day)'));
    expect(source, contains('_formatTime(tx.date)'));
  });

  test('theme applies launcher icon and light alias is distinct', () {
    final main = File('lib/main.dart').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(main,
        contains('ThemeNotifier.instance.addListener(AppIconService.apply)'));
    expect(manifest, contains('@drawable/launcher_icon_light'));
  });

  test('roadmap exposes zoom and team picker', () {
    final source =
        File('lib/features/roadmap/roadmap_screen.dart').readAsStringSync();
    expect(source, contains('double _timelineZoom = 1.0'));
    expect(source, contains('final double zoom;'));
    expect(source, contains('EmployeeOrCustomField('));
  });

  test('short forecast no longer forces 30 days of history', () {
    final source = File('lib/features/treasury/forecast_chart_screen.dart')
        .readAsStringSync();
    expect(source, contains('_forecastDays.clamp(7, 90)'));
  });

  test('recurring what-if survives preset JSON roundtrip', () {
    final preset = WhatIfPreset(
      id: 'recurring',
      name: 'Monthly investment',
      createdAt: DateTime.now(),
      scenario: WhatIfScenario(
        events: [
          WhatIfEvent(
            title: 'Investment',
            amount: 10000,
            type: TransactionType.income,
            date: DateTime.now().add(const Duration(days: 1)),
            recurringPeriod: RecurringPeriod.monthly,
          ),
        ],
      ),
    );
    final decoded = WhatIfPreset.fromJson(preset.toJson());
    expect(decoded, isNotNull);
    expect(decoded!.scenario.events.first.recurringPeriod,
        RecurringPeriod.monthly);
  });

  test('stopwatch source no longer formats hundredths', () {
    final source = File('lib/features/time_center/time_center_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('String _formatStopwatchMs');
    expect(start, greaterThanOrEqualTo(0));
    final window = source.substring(start, (start + 700).clamp(0, source.length));
    expect(window, isNot(contains('hundredths')));
  });
}
''')
