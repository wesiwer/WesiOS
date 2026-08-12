from pathlib import Path

p = Path('lib/features/tasks/tasks_screen.dart')
s = p.read_text(encoding='utf-8')
start = s.index('  Widget _filters(bool ru) {')
end = s.index('  Widget _chip({', start)
replacement = '''  Widget _filters(bool ru) {
    final search = SizedBox(
      height: 38,
      child: TextField(
        style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 17, color: AppTheme.textMuted),
          hintText: ru ? 'Поиск по задачам' : 'Search tasks',
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.surface.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );

    final overdue = _chip(
      label: ru ? 'Просроченные' : 'Overdue',
      selected: _onlyOverdue,
      color: AppTheme.accentRed,
      onTap: () => setState(() => _onlyOverdue = !_onlyOverdue),
    );

    final priority = PopupMenuButton<TaskPriority?>(
      color: AppTheme.surface,
      tooltip: ru ? 'Приоритет' : 'Priority',
      onSelected: (v) => setState(() => _priorityFilter = v),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Text(
            ru ? 'Любой приоритет' : 'Any priority',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
        ),
        ...TaskPriority.values.map(
          (p) => PopupMenuItem(
            value: p,
            child: Text(
              TaskLabels.priority(p, ru),
              style: TextStyle(color: TaskLabels.priorityColor(p)),
            ),
          ),
        ),
      ],
      child: _chip(
        label: _priorityFilter == null
            ? (ru ? 'Приоритет' : 'Priority')
            : TaskLabels.priority(_priorityFilter!, ru),
        selected: _priorityFilter != null,
        color: _priorityFilter == null
            ? AppTheme.accent
            : TaskLabels.priorityColor(_priorityFilter!),
        onTap: null,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    overdue,
                    const SizedBox(width: 8),
                    priority,
                  ],
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            overdue,
            const SizedBox(width: 8),
            priority,
          ],
        );
      },
    );
  }

'''
p.write_text(s[:start] + replacement + s[end:], encoding='utf-8')
print('mobile task filters patched')
