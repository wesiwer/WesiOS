from pathlib import Path

RICH = Path('lib/features/ai/widgets/wesi_ai_rich_message.dart')
DETAIL = Path('lib/features/ai/widgets/wesi_ai_step_detail_sheet.dart')
TEST = Path('test/wesi_ai_step_detail_sheet_test.dart')

source = RICH.read_text(encoding='utf-8')
import_anchor = "import '../models/wesi_ai_activity.dart';\n"
detail_import = "import 'wesi_ai_step_detail_sheet.dart';\n"
if detail_import not in source:
    if source.count(import_anchor) != 1:
        raise SystemExit('activity import anchor mismatch')
    source = source.replace(import_anchor, import_anchor + detail_import, 1)

marker = 'class WesiAiActivityRow extends StatefulWidget {'
if source.count(marker) != 1:
    raise SystemExit('activity row marker mismatch')
start = source.index(marker)
replacement = r'''class WesiAiActivityRow extends StatelessWidget {
  final WesiAiActivityEvent event;
  final bool compact;

  const WesiAiActivityRow({
    super.key,
    required this.event,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inlineReadDetail = (event.kind == WesiAiActivityKind.tool ||
            event.kind == WesiAiActivityKind.agent) &&
        event.detail.isNotEmpty &&
        !event.hasDiff &&
        event.files.isEmpty;
    final hasDetails = event.detail.isNotEmpty ||
        event.files.isNotEmpty ||
        event.hasIo ||
        event.sourceName.isNotEmpty ||
        event.status.isNotEmpty ||
        event.duration != null ||
        event.hasDiff;
    final icon = switch (event.kind) {
      WesiAiActivityKind.tool => Icons.build_outlined,
      WesiAiActivityKind.agent => Icons.account_tree_outlined,
      WesiAiActivityKind.reasoning => Icons.psychology_alt_outlined,
      WesiAiActivityKind.verification => Icons.fact_check_outlined,
      WesiAiActivityKind.status => Icons.more_horiz_rounded,
    };
    final positive = theme.brightness == Brightness.dark
        ? Colors.greenAccent.shade400
        : Colors.green.shade700;
    final negative = theme.brightness == Brightness.dark
        ? Colors.redAccent.shade100
        : Colors.red.shade700;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: hasDetails ? () => WesiAiStepDetailSheet.open(context, event) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : 8,
          vertical: 5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    event.label,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (event.hasDiff) ...[
                  Text(
                    '+${event.additions}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: positive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '-${event.deletions}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: negative,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (hasDetails) ...[
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (inlineReadDetail)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 5),
                child: Text(
                  event.detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
'''
RICH.write_text(source[:start] + replacement, encoding='utf-8')

DETAIL.write_text(r'''import 'package:flutter/material.dart';
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

  String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
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
''', encoding='utf-8')

TEST.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  testWidgets('activity row opens full technical drilldown', (tester) async {
    final start = DateTime(2026, 8, 19, 8, 0, 0);
    final event = WesiAiActivityEvent(
      id: 'step-1',
      kind: WesiAiActivityKind.tool,
      label: 'Инструмент · github_write',
      detail: 'Обновляет два файла и проверяет результат.',
      status: 'result',
      sourceName: 'github_write',
      startedAt: start,
      completedAt: start.add(const Duration(seconds: 3)),
      additions: 12,
      deletions: 4,
      files: const ['lib/a.dart', 'test/a_test.dart'],
      input: '{"branch":"main","path":"lib/a.dart"}',
      output: '{"ok":true,"sha":"abc123"}',
      mutation: true,
      succeeded: true,
      module: 'github',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: WesiAiActivityRow(event: event)),
        ),
      ),
    );

    await tester.tap(find.text('Инструмент · github_write'));
    await tester.pumpAndSettle();

    expect(find.text('Успешно'), findsOneWidget);
    expect(find.text('3.0 с'), findsOneWidget);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('Что происходило'), findsOneWidget);
    expect(find.text('Изменения'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('-4'), findsOneWidget);
    expect(find.text('Запрос'), findsOneWidget);
    expect(find.text('Ответ'), findsOneWidget);
    expect(find.textContaining('branch'), findsOneWidget);
    expect(find.textContaining('abc123'), findsOneWidget);
  });

  testWidgets('compact agent row keeps summary visible and opens sheet',
      (tester) async {
    const event = WesiAiActivityEvent(
      id: 'agent-1',
      kind: WesiAiActivityKind.agent,
      label: 'Зову специалиста · Security Reviewer',
      detail: 'Проверить права доступа и регрессии.',
      sourceName: 'Security Reviewer',
      status: 'start',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WesiAiActivityRow(event: event, compact: true),
        ),
      ),
    );

    expect(find.text('Проверить права доступа и регрессии.'), findsOneWidget);
    await tester.tap(find.text('Зову специалиста · Security Reviewer'));
    await tester.pumpAndSettle();
    expect(find.text('Выполняется'), findsOneWidget);
    expect(find.textContaining('Security Reviewer'), findsWidgets);
  });
}
''', encoding='utf-8')
