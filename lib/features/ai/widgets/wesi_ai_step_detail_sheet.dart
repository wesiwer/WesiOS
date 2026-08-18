import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wesi_ai_activity.dart';

class WesiAiStepDetailSheet extends StatelessWidget {
  final WesiAiActivityEvent event;

  const WesiAiStepDetailSheet({super.key, required this.event});

  static Future<void> open(BuildContext context, WesiAiActivityEvent event) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => WesiAiStepDetailSheet(event: event),
    );
  }

  IconData get _icon => switch (event.kind) {
        WesiAiActivityKind.tool => Icons.terminal_rounded,
        WesiAiActivityKind.agent => Icons.account_tree_outlined,
        WesiAiActivityKind.reasoning => Icons.psychology_alt_outlined,
        WesiAiActivityKind.verification => Icons.fact_check_outlined,
        WesiAiActivityKind.status => Icons.more_horiz_rounded,
      };

  String get _kindLabel => switch (event.kind) {
        WesiAiActivityKind.tool => 'Инструмент',
        WesiAiActivityKind.agent => 'Специалист',
        WesiAiActivityKind.reasoning => 'Ход работы',
        WesiAiActivityKind.verification => 'Проверка',
        WesiAiActivityKind.status => 'Этап',
      };

  String get _statusLabel {
    if (event.succeeded) return 'Успешно';
    return switch (event.status.trim().toLowerCase()) {
      'result' || 'done' || 'complete' || 'completed' => 'Завершено',
      'start' || 'started' || 'running' => 'Выполняется',
      'failed' || 'error' => 'Ошибка',
      final value when value.isNotEmpty => event.status,
      _ => 'Зафиксировано',
    };
  }

  String _durationLabel(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} мс';
    }
    if (duration.inSeconds < 60) {
      final seconds = duration.inMilliseconds / 1000;
      return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} с';
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes мин ${seconds.toString().padLeft(2, '0')} с';
  }

  String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  Future<void> _copyAll(BuildContext context) async {
    final buffer = StringBuffer(event.label);
    if (event.sourceName.isNotEmpty) {
      buffer.writeln('\nИсполнитель: ${event.sourceName}');
    }
    if (event.detail.isNotEmpty) {
      buffer.writeln('\nДетали:\n${event.detail}');
    }
    if (event.files.isNotEmpty) {
      buffer.writeln('\nФайлы:\n${event.files.join('\n')}');
    }
    if (event.input.isNotEmpty) {
      buffer.writeln('\nЗапрос:\n${event.input}');
    }
    if (event.output.isNotEmpty) {
      buffer.writeln('\nОтвет:\n${event.output}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Детали шага скопированы')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = event.duration;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 9),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(_icon, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.sourceName.isEmpty
                              ? _kindLabel
                              : '$_kindLabel · ${event.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Копировать всё',
                    onPressed: () => _copyAll(context),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: event.succeeded
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        label: _statusLabel,
                      ),
                      if (duration != null)
                        _MetaChip(
                          icon: Icons.timer_outlined,
                          label: _durationLabel(duration),
                        ),
                      if (event.module.isNotEmpty)
                        _MetaChip(
                          icon: Icons.widgets_outlined,
                          label: event.module,
                        ),
                      if (event.startedAt != null)
                        _MetaChip(
                          icon: Icons.play_arrow_rounded,
                          label: _clock(event.startedAt!),
                        ),
                      if (event.completedAt != null)
                        _MetaChip(
                          icon: Icons.stop_rounded,
                          label: _clock(event.completedAt!),
                        ),
                    ],
                  ),
                  if (event.detail.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle(title: 'Что происходило'),
                    const SizedBox(height: 7),
                    SelectableText(
                      event.detail,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ],
                  if (event.hasDiff || event.files.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle(title: 'Изменения'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (event.additions > 0)
                          _DiffBadge(
                            text: '+${event.additions}',
                            positive: true,
                          ),
                        if (event.additions > 0 && event.deletions > 0)
                          const SizedBox(width: 7),
                        if (event.deletions > 0)
                          _DiffBadge(
                            text: '-${event.deletions}',
                            positive: false,
                          ),
                      ],
                    ),
                    if (event.files.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.42),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(
                          event.files.take(40).join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (event.input.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _PayloadPanel(
                      title: 'Запрос',
                      body: event.input,
                      icon: Icons.call_made_rounded,
                    ),
                  ],
                  if (event.output.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _PayloadPanel(
                      title: 'Ответ',
                      body: event.output,
                      icon: Icons.call_received_rounded,
                    ),
                  ],
                  if (event.detail.isEmpty &&
                      event.files.isEmpty &&
                      !event.hasIo) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Для этого шага дополнительных технических данных нет.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      );
}

class _DiffBadge extends StatelessWidget {
  final String text;
  final bool positive;

  const _DiffBadge({required this.text, required this.positive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = positive
        ? (theme.brightness == Brightness.dark
            ? Colors.greenAccent.shade400
            : Colors.green.shade700)
        : (theme.brightness == Brightness.dark
            ? Colors.redAccent.shade100
            : Colors.red.shade700);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PayloadPanel extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;

  const _PayloadPanel({
    required this.title,
    required this.body,
    required this.icon,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: body));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title скопирован')),
    );
  }

  Future<void> _openFull(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                IconButton(
                  tooltip: 'Копировать',
                  onPressed: () => _copy(dialogContext),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  body,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 5, 5),
            child: Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Копировать',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Открыть полностью',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openFull(context),
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
