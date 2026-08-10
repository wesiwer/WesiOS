from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'missing marker {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new, 1))


path = 'lib/features/crm/crm_screen.dart'
wrong = """            const SizedBox(height: 10),\n            EmployeeOrCustomField(\n              label: _ru ? 'Ответственный сотрудник' : 'Responsible employee',\n              value: _responsibleEmployeeId,\n              storeEmployeeId: true,\n              allowCustom: false,\n              onChanged: (value) =>\n                  setState(() => _responsibleEmployeeId = value),\n            ),\n            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n            DropdownButtonFormField<CrmClientStatus>(\n"""
right = """            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n            DropdownButtonFormField<CrmClientStatus>(\n"""
once(path, wrong, right)

deal_marker = """            _datePicker(\n              context,\n              label: _ru ? 'Плановая дата закрытия' : 'Expected close date',\n              value: _expectedClose,\n              onChanged: (value) => setState(() => _expectedClose = value),\n            ),\n            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n"""
deal_replacement = """            _datePicker(\n              context,\n              label: _ru ? 'Плановая дата закрытия' : 'Expected close date',\n              value: _expectedClose,\n              onChanged: (value) => setState(() => _expectedClose = value),\n            ),\n            const SizedBox(height: 10),\n            EmployeeOrCustomField(\n              label: _ru ? 'Ответственный сотрудник' : 'Responsible employee',\n              value: _responsibleEmployeeId,\n              storeEmployeeId: true,\n              allowCustom: false,\n              onChanged: (value) =>\n                  setState(() => _responsibleEmployeeId = value),\n            ),\n            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n"""
once(path, deal_marker, deal_replacement)

path = 'lib/features/team/contacts_screen.dart'
once(
    path,
    "import 'models/employee_model.dart';\n",
    "import 'models/employee_model.dart';\nimport 'models/team_permissions.dart';\n",
)
