import 'package:flutter/material.dart';

import '../models/wesi_ai_activity.dart';

/// Итог прохода: что ассистент реально изменил в WesiOS.
///
/// В длинном проходе шагов бывает два десятка, и прокручивать ход мыслей,
/// чтобы понять, что именно поменялось, — работа. Плашка отвечает на этот
/// вопрос сразу: сколько изменений и каких. Чтения в счёт не идут: важно не
/// то, сколько раз ассистент что-то посмотрел, а что он тронул.
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

/// Русские названия модулей. Незнакомый модуль показывается как есть — лучше
/// техническое слово, чем выдуманное.
const Map<String, String> _moduleTitles = <String, String>{
  'tasks': 'Задачи',
  'treasury': 'Казна',
  'crm': 'CRM',
  'knowledge': 'База знаний',
  'calendar': 'Календарь',
  'roadmap': 'Дорожная карта',
  'audio': 'Audio Vault',
  'team': 'Команда',
  'media': 'Медиа',
};

String moduleTitle(String module) {
  final key = module.trim().toLowerCase();
  if (key.isEmpty) return 'WesiOS';
  return _moduleTitles[key] ?? module;
}

/// Собирает изменения из журнала работы сообщения.
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

class WesiAiRunSummaryChip extends StatelessWidget {
  final List<WesiAiRunChange> changes;

  const WesiAiRunSummaryChip({super.key, required this.changes});

  String get _title {
    final modules = <String>{};
    for (final change in changes) {
      modules.add(moduleTitle(change.module));
    }
    if (modules.length == 1) return 'Изменено · ${modules.first}';
    return 'Изменения за проход';
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    'Что изменил проход',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: changes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, index) {
                      final change = changes[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(change.label),
                        subtitle: Text(
                          change.detail.isEmpty
                              ? moduleTitle(change.module)
                              : '${moduleTitle(change.module)} · ${change.detail}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
