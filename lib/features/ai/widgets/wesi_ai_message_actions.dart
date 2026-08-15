import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wesi_ai_activity.dart';
import '../models/wesi_ai_chat_models.dart';
import 'wesi_ai_rich_message.dart';

class WesiAiMessageActions extends StatelessWidget {
  final WesiAiMessage message;
  final bool saved;
  final Future<void> Function(bool saved) onToggleSaved;
  final Future<void> Function() onBranch;

  const WesiAiMessageActions({
    super.key,
    required this.message,
    required this.saved,
    required this.onToggleSaved,
    required this.onBranch,
  });

  Future<void> _copy(BuildContext context) async {
    final text = WesiAiRichParser.plainText(message.text);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ответ скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activities = WesiAiActivityEvent.listFrom(message.metadata['activity']);
    final additions = WesiAiActivityEvent.totalAdditions(activities);
    final deletions = WesiAiActivityEvent.totalDeletions(activities);
    final hasReview = activities.any((event) => event.kind == WesiAiActivityKind.tool || event.kind == WesiAiActivityKind.agent || event.hasDiff);
    final positive = theme.brightness == Brightness.dark ? Colors.greenAccent.shade400 : Colors.green.shade700;
    final negative = theme.brightness == Brightness.dark ? Colors.redAccent.shade100 : Colors.red.shade700;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Копировать ответ',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_all_outlined, size: 20),
          ),
          IconButton(
            tooltip: saved ? 'Убрать из архива чата' : 'Сохранить в архив чата',
            visualDensity: VisualDensity.compact,
            onPressed: () => onToggleSaved(!saved),
            icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Создать ответвление от этого сообщения',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await onBranch();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Создана отдельная ветка чата')),
              );
            },
            icon: const Icon(Icons.account_tree_outlined, size: 20),
          ),
          if (hasReview)
            InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => WesiAiDiffReviewSheet(
                  message: message,
                  activities: activities,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.difference_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('+$additions', style: theme.textTheme.labelMedium?.copyWith(color: positive, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 5),
                    Text('-$deletions', style: theme.textTheme.labelMedium?.copyWith(color: negative, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WesiAiDiffReviewSheet extends StatelessWidget {
  final WesiAiMessage message;
  final List<WesiAiActivityEvent> activities;

  const WesiAiDiffReviewSheet({
    super.key,
    required this.message,
    required this.activities,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relevant = activities
        .where((event) => event.kind == WesiAiActivityKind.tool || event.kind == WesiAiActivityKind.agent || event.hasDiff)
        .toList(growable: false);
    final additions = WesiAiActivityEvent.totalAdditions(relevant);
    final deletions = WesiAiActivityEvent.totalDeletions(relevant);
    final positive = theme.brightness == Brightness.dark ? Colors.greenAccent.shade400 : Colors.green.shade700;
    final negative = theme.brightness == Brightness.dark ? Colors.redAccent.shade100 : Colors.red.shade700;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Сверка изменений', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('Данные относятся только к этой работе Wesi AI.', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text('+$additions', style: theme.textTheme.titleMedium?.copyWith(color: positive, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('-$deletions', style: theme.textTheme.titleMedium?.copyWith(color: negative, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: relevant.isEmpty
                  ? const Center(child: Text('Инструменты не сообщили diff-данные.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: relevant.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, index) => Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: WesiAiActivityRow(event: relevant[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class WesiAiMessageArchiveSheet extends StatelessWidget {
  final String conversationTitle;
  final List<WesiAiMessage> messages;

  const WesiAiMessageArchiveSheet({
    super.key,
    required this.conversationTitle,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Архив этого чата', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(conversationTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Chip(label: Text('${messages.length}')),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('Сохранённых ответов пока нет.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final preview = WesiAiRichParser.plainText(message.text);
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              preview.isEmpty ? 'Ответ Wesi AI' : preview,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_dateLabel(message.createdAt)),
                            trailing: IconButton(
                              tooltip: 'Копировать',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: preview));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ответ скопирован')),
                                );
                              },
                              icon: const Icon(Icons.copy_all_outlined),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} · ${two(local.hour)}:${two(local.minute)}';
  }
}
