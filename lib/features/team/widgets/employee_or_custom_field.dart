import 'package:flutter/material.dart';

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
