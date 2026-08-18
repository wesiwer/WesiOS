import 'package:flutter/material.dart';

import '../models/wesi_ai_activity.dart';

/// Одно реально применённое изменение из длинного прохода Wesi AI.
class WesiAiRunChange {
  final String label;
  final String module;
  final String detail;

  const WesiAiRunChange({
    required this.label,
    required this.module,
    this.detail = '',
  });
}

/// Группа изменений одного продуктового контура.
///
/// После длинного прохода человеку важнее сначала увидеть «GitHub · 2 /
/// Задачи · 3», а уже потом провалиться в конкретные tool-вызовы.
class WesiAiRunGroup {
  final String module;
  final String title;
  final List<WesiAiRunChange> changes;

  const WesiAiRunGroup({
    required this.module,
    required this.title,
    required this.changes,
  });

  int get count => changes.length;
}

/// Человеческие названия модулей. Незнакомый модуль показывается как есть —
/// техническое слово лучше выдуманной расшифровки.
const Map<String, String> _moduleTitles = <String, String>{
  'tasks': 'Задачи',
  'treasury': 'Казна',
  'finance': 'Казна',
  'crm': 'CRM',
  'knowledge': 'База знаний',
  'calendar': 'Календарь',
  'roadmap': 'Дорожная карта',
  'audio': 'Audio Vault',
  'team': 'Команда',
  'media': 'Медиа',
  'github': 'GitHub',
  'git': 'GitHub',
  'deploy': 'Deploy',
  'deployment': 'Deploy',
  'files': 'Файлы',
  'file': 'Файлы',
  'engineering': 'Разработка',
  'code': 'Разработка',
  'projects': 'Проекты',
  'project': 'Проекты',
  'sync': 'Синхронизация',
  'security': 'Безопасность',
  'employees': 'Команда',
  'organization': 'Организация',
};

String moduleTitle(String module) {
  final key = module.trim().toLowerCase();
  if (key.isEmpty) return 'WesiOS';
  return _moduleTitles[key] ?? module;
}

String _moduleKey(String module) {
  final key = module.trim().toLowerCase();
  if (key.isEmpty) return 'wesios';
  if (key == 'finance') return 'treasury';
  if (key == 'git') return 'github';
  if (key == 'deployment') return 'deploy';
  if (key == 'file') return 'files';
  if (key == 'code') return 'engineering';
  if (key == 'project') return 'projects';
  if (key == 'employees') return 'team';
  return key;
}

/// Собирает только применённые изменения. Чтение и неудачная mutation в
/// итог прохода не попадают: итог отвечает на вопрос «что реально поменялось».
List<WesiAiRunChange> runChangesFrom(dynamic activityRaw) {
  final events = WesiAiActivityEvent.listFrom(activityRaw);
  final changes = <WesiAiRunChange>[];
  for (final event in events) {
    if (!event.appliedChange) continue;
    changes.add(WesiAiRunChange(
      label: event.sourceName.isEmpty ? event.label : event.sourceName,
      module: event.module,
      detail: event.detail,
    ));
  }
  return changes;
}

/// Группировка сохраняет порядок первого появления модулей в проходе.
List<WesiAiRunGroup> runGroupsFromChanges(List<WesiAiRunChange> changes) {
  final buckets = <String, List<WesiAiRunChange>>{};
  final originalModule = <String, String>{};
  for (final change in changes) {
    final key = _moduleKey(change.module);
    buckets.putIfAbsent(key, () => <WesiAiRunChange>[]).add(change);
    originalModule.putIfAbsent(key, () => change.module);
  }
  return buckets.entries
      .map((entry) => WesiAiRunGroup(
            module: entry.key,
            title: moduleTitle(originalModule[entry.key] ?? entry.key),
            changes: List<WesiAiRunChange>.unmodifiable(entry.value),
          ))
      .toList(growable: false);
}

String _countLabel(int count) {
  final n10 = count % 10;
  final n100 = count % 100;
  if (n10 == 1 && n100 != 11) return '$count изменение';
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) {
    return '$count изменения';
  }
  return '$count изменений';
}

class WesiAiRunSummaryChip extends StatelessWidget {
  final List<WesiAiRunChange> changes;

  const WesiAiRunSummaryChip({super.key, required this.changes});

  List<WesiAiRunGroup> get _groups => runGroupsFromChanges(changes);

  String get _title {
    final groups = _groups;
    if (groups.length == 1) return 'Изменено · ${groups.first.title}';
    return 'Изменено за проход';
  }

  IconData _groupIcon(String module) => switch (module) {
        'github' => Icons.account_tree_outlined,
        'deploy' => Icons.rocket_launch_outlined,
        'tasks' => Icons.task_alt_outlined,
        'treasury' => Icons.account_balance_wallet_outlined,
        'crm' => Icons.handshake_outlined,
        'knowledge' => Icons.menu_book_outlined,
        'calendar' => Icons.calendar_month_outlined,
        'files' => Icons.folder_outlined,
        'engineering' => Icons.code_outlined,
        'sync' => Icons.sync_outlined,
        'security' => Icons.shield_outlined,
        'team' => Icons.groups_outlined,
        _ => Icons.check_circle_outline,
      };

  void _open(BuildContext context) {
    final groups = _groups;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(
                    'Итог прохода',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Text(
                    '${_countLabel(changes.length)} · ${groups.length} ${groups.length == 1 ? 'модуль' : 'модуля'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final group in groups)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _groupIcon(group.module),
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${group.title} · ${group.count}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                          child: Row(
                            children: [
                              Icon(
                                _groupIcon(group.module),
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  group.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '${group.count}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final change in group.changes)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              Icons.check_circle_outline,
                              size: 19,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(change.label),
                            subtitle: change.detail.isEmpty
                                ? null
                                : Text(
                                    change.detail,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_motion_outlined,
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${changes.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
