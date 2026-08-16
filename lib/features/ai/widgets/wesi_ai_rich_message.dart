import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wesi_ai_activity.dart';
import 'wesi_ai_visualization.dart';

enum WesiAiRichBlockKind {
  text,
  code,
  quote,
  draft,
  clarification,
  table,
  chart,
}

class WesiAiRichBlock {
  final WesiAiRichBlockKind kind;
  final String text;
  final String language;

  const WesiAiRichBlock(this.kind, this.text, {this.language = ''});
}

class WesiAiRichParser {
  const WesiAiRichParser._();

  static List<WesiAiRichBlock> parse(String input) {
    if (input.isEmpty) return const <WesiAiRichBlock>[];
    final lines = input.replaceAll('\r\n', '\n').split('\n');
    final blocks = <WesiAiRichBlock>[];
    final text = <String>[];

    void flushText() {
      if (text.isEmpty) return;
      final value = text.join('\n').trimRight();
      text.clear();
      if (value.trim().isNotEmpty) {
        blocks.add(WesiAiRichBlock(WesiAiRichBlockKind.text, value));
      }
    }

    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.trimLeft().startsWith('```')) {
        flushText();
        final marker = line.trimLeft();
        final language = marker.length > 3 ? marker.substring(3).trim() : '';
        final body = <String>[];
        index++;
        while (index < lines.length &&
            !lines[index].trimLeft().startsWith('```')) {
          body.add(lines[index]);
          index++;
        }
        if (index < lines.length) index++;
        final lower = language.toLowerCase();
        final draft = const <String>{
          'text',
          'message',
          'email',
          'draft',
          'quote',
          'letter',
        }.contains(lower);
        final kind = lower == 'question'
            ? WesiAiRichBlockKind.clarification
            : const <String>{
                'chart',
                'wesi-chart',
                'wesi_chart',
              }.contains(lower)
                ? WesiAiRichBlockKind.chart
                : draft
                    ? WesiAiRichBlockKind.draft
                    : WesiAiRichBlockKind.code;
        blocks.add(WesiAiRichBlock(kind, body.join('\n'), language: language));
        continue;
      }
      if (line.contains('|') && index + 1 < lines.length) {
        final tableLines = <String>[line, lines[index + 1]];
        var scan = index + 2;
        while (scan < lines.length && lines[scan].contains('|')) {
          tableLines.add(lines[scan]);
          scan++;
        }
        final parsedTable = WesiAiTableData.tryParseMarkdown(tableLines);
        if (parsedTable != null) {
          flushText();
          blocks.add(
            WesiAiRichBlock(
              WesiAiRichBlockKind.table,
              tableLines.take(2 + parsedTable.rows.length).join('\n'),
            ),
          );
          index += 2 + parsedTable.rows.length;
          continue;
        }
      }
      if (line.trimLeft().startsWith('>')) {
        flushText();
        final quote = <String>[];
        while (
            index < lines.length && lines[index].trimLeft().startsWith('>')) {
          final raw = lines[index].trimLeft().substring(1);
          quote.add(raw.startsWith(' ') ? raw.substring(1) : raw);
          index++;
        }
        blocks.add(
          WesiAiRichBlock(
            WesiAiRichBlockKind.quote,
            quote.join('\n').trimRight(),
          ),
        );
        continue;
      }
      text.add(line);
      index++;
    }
    flushText();
    return blocks;
  }

  static String displayMarkdown(String markdown) => markdown.replaceAllMapped(
        RegExp(r'^\s{0,3}#{1,6}\s+(.+)$', multiLine: true),
        (match) => '**${match.group(1)?.trim() ?? ''}**',
      );

  static bool hasClarification(String markdown) {
    for (final block in parse(markdown)) {
      if (block.kind == WesiAiRichBlockKind.clarification &&
          WesiAiClarification.tryParse(block.text) != null) {
        return true;
      }
    }
    return false;
  }

  static String plainText(String markdown) {
    return markdown
        .replaceAll(RegExp(r'```[^\n]*\n?'), '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'^>\s?', multiLine: true), '')
        .replaceAllMapped(
          RegExp(r'\*\*(.+?)\*\*', dotAll: true),
          (m) => m.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m.group(1) ?? '')
        .trim();
  }
}

class WesiAiClarification {
  final String prompt;
  final List<String> options;
  final bool allowOther;

  const WesiAiClarification({
    required this.prompt,
    required this.options,
    required this.allowOther,
  });

  static WesiAiClarification? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final prompt = '${decoded['prompt'] ?? ''}'.trim();
      final rawOptions = decoded['options'];
      if (prompt.isEmpty || prompt.length > 1200 || rawOptions is! List)
        return null;
      final options = rawOptions
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty && item.length <= 240)
          .toSet()
          .take(5)
          .toList(growable: false);
      if (options.length < 2) return null;
      return WesiAiClarification(
        prompt: prompt,
        options: options,
        allowOther: decoded['allowOther'] != false,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef WesiAiQuickReply = Future<void> Function(String answer);

class WesiAiRichMessage extends StatelessWidget {
  final String messageId;
  final String text;
  final dynamic activityRaw;
  final bool streaming;
  final bool showWorkLog;
  final bool expandWorkLog;
  final int workDurationMs;
  final WesiAiQuickReply? onQuickReply;

  const WesiAiRichMessage({
    super.key,
    required this.messageId,
    required this.text,
    this.activityRaw,
    this.streaming = false,
    this.showWorkLog = false,
    this.expandWorkLog = false,
    this.workDurationMs = 0,
    this.onQuickReply,
  });

  @override
  Widget build(BuildContext context) {
    final activities = WesiAiActivityEvent.listFrom(activityRaw);
    final work = activities
        .where(
          (event) =>
              event.kind != WesiAiActivityKind.tool &&
              event.kind != WesiAiActivityKind.agent,
        )
        .toList(growable: false);
    final inline = activities
        .where(
          (event) =>
              event.kind == WesiAiActivityKind.tool ||
              event.kind == WesiAiActivityKind.agent,
        )
        .toList(growable: false);

    final children = <Widget>[];
    if (showWorkLog && (work.isNotEmpty || streaming)) {
      children.add(
        WesiAiWorkLog(
          key: ValueKey('work_$messageId'),
          events: work,
          streaming: streaming,
          initiallyExpanded: expandWorkLog,
          durationMs: workDurationMs,
        ),
      );
      if (text.isNotEmpty || inline.isNotEmpty)
        children.add(const SizedBox(height: 8));
    }

    if (inline.isEmpty) {
      children.addAll(_renderBlocks(context, text));
    } else {
      var cursor = 0;
      for (final event in inline) {
        final rawOffset = event.textOffset.clamp(0, text.length).toInt();
        final offset = rawOffset < cursor ? cursor : rawOffset;
        if (offset > cursor) {
          children.addAll(
            _renderBlocks(context, text.substring(cursor, offset)),
          );
        }
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: WesiAiActivityRow(event: event),
          ),
        );
        cursor = offset;
      }
      if (cursor < text.length) {
        children.addAll(_renderBlocks(context, text.substring(cursor)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<Widget> _renderBlocks(BuildContext context, String value) {
    final blocks = WesiAiRichParser.parse(value);
    final widgets = <Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      if (index > 0) widgets.add(const SizedBox(height: 9));
      final block = blocks[index];
      switch (block.kind) {
        case WesiAiRichBlockKind.code:
          widgets.add(
            WesiAiCodeBlock(code: block.text, language: block.language),
          );
          break;
        case WesiAiRichBlockKind.quote:
          widgets.add(WesiAiQuoteBlock(text: block.text));
          break;
        case WesiAiRichBlockKind.draft:
          widgets.add(
            WesiAiQuoteBlock(
              text: block.text,
              label: _draftLabel(block.language),
            ),
          );
          break;
        case WesiAiRichBlockKind.text:
          widgets.add(WesiAiFormattedText(text: block.text));
          break;
        case WesiAiRichBlockKind.clarification:
          final question = WesiAiClarification.tryParse(block.text);
          if (question == null) {
            widgets.add(
              WesiAiCodeBlock(code: block.text, language: block.language),
            );
          } else {
            widgets.add(
              WesiAiClarificationBlock(
                question: question,
                onAnswer: onQuickReply,
              ),
            );
          }
          break;
        case WesiAiRichBlockKind.table:
          final table = WesiAiTableData.tryParseMarkdown(
            block.text.split('\n'),
          );
          if (table == null) {
            widgets.add(WesiAiFormattedText(text: block.text));
          } else {
            widgets.add(WesiAiTableBlock(table: table));
          }
          break;
        case WesiAiRichBlockKind.chart:
          final chart = WesiAiChartSpec.tryParse(block.text);
          if (chart == null) {
            widgets.add(
              WesiAiCodeBlock(code: block.text, language: block.language),
            );
          } else {
            widgets.add(WesiAiChartBlock(spec: chart));
          }
          break;
      }
    }
    return widgets;
  }

  String _draftLabel(String language) => switch (language.toLowerCase()) {
        'email' => 'Готовое письмо',
        'message' => 'Готовое сообщение',
        'letter' => 'Готовый текст',
        'draft' => 'Черновик',
        _ => 'Текст для копирования',
      };
}

class WesiAiClarificationBlock extends StatelessWidget {
  final WesiAiClarification question;
  final WesiAiQuickReply? onAnswer;

  const WesiAiClarificationBlock({
    super.key,
    required this.question,
    this.onAnswer,
  });

  Future<void> _customAnswer(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(question.prompt),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Свой ответ'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Ответить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await onAnswer?.call(value.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.prompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in question.options)
                ActionChip(
                  label: Text(option),
                  onPressed: onAnswer == null ? null : () => onAnswer!(option),
                ),
              if (question.allowOther)
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Свой ответ'),
                  onPressed:
                      onAnswer == null ? null : () => _customAnswer(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class WesiAiFormattedText extends StatelessWidget {
  final String text;

  const WesiAiFormattedText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(height: 1.48) ??
        const TextStyle(height: 1.48);
    final displayText = WesiAiRichParser.displayMarkdown(text);
    return SelectableText.rich(
      TextSpan(children: _inline(displayText, base)),
    );
  }

  List<InlineSpan> _inline(String source, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*[^*\n]+\*\*|`[^`\n]+`|(?<!\*)\*[^*\n]+\*(?!\*))',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: source.substring(cursor, match.start), style: base),
        );
      }
      final token = match.group(0) ?? '';
      if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.grey.withOpacity(0.12),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < source.length)
      spans.add(TextSpan(text: source.substring(cursor), style: base));
    return spans;
  }
}

class WesiAiCodeBlock extends StatelessWidget {
  final String code;
  final String language;

  const WesiAiCodeBlock({super.key, required this.code, this.language = ''});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Код скопирован')));
  }

  Future<void> _expand(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(language.isEmpty ? 'Код' : language),
              actions: [
                IconButton(
                  tooltip: 'Копировать',
                  onPressed: () => _copy(dialogContext),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.36,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.62),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 11 : 14,
              compact ? 5 : 8,
              compact ? 4 : 7,
              compact ? 4 : 7,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'Code' : language,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Копировать код',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_all_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Открыть',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _expand(context),
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(compact ? 10 : 13),
            child: SelectableText(
              code,
              style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                fontFamily: 'monospace',
                fontSize: compact ? 12.25 : 13.25,
                height: 1.36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WesiAiQuoteBlock extends StatelessWidget {
  final String text;
  final String label;

  const WesiAiQuoteBlock({super.key, required this.text, this.label = ''});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Текст скопирован')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(label, style: theme.textTheme.labelMedium),
                  ),
                SelectableText(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.48),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Копировать',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_all_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class WesiAiWorkLog extends StatefulWidget {
  final List<WesiAiActivityEvent> events;
  final bool streaming;
  final bool initiallyExpanded;
  final int durationMs;

  const WesiAiWorkLog({
    super.key,
    required this.events,
    required this.streaming,
    required this.initiallyExpanded,
    required this.durationMs,
  });

  @override
  State<WesiAiWorkLog> createState() => _WesiAiWorkLogState();
}

class _WesiAiWorkLogState extends State<WesiAiWorkLog> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.streaming || widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant WesiAiWorkLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.streaming && widget.streaming) _expanded = true;
    if (oldWidget.streaming && !widget.streaming && !widget.initiallyExpanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds =
        widget.durationMs <= 0 ? null : (widget.durationMs / 1000).ceil();
    final title = widget.streaming
        ? 'Ход работы…'
        : seconds == null
            ? 'Ход работы'
            : 'Ход работы · ${seconds}с';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.streaming) ...[
                      const SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.events.isEmpty)
                      Text(
                        'Подготавливаю контекст и следующий шаг…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    for (final event in widget.events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: WesiAiActivityRow(event: event, compact: true),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WesiAiActivityRow extends StatefulWidget {
  final WesiAiActivityEvent event;
  final bool compact;

  const WesiAiActivityRow({
    super.key,
    required this.event,
    this.compact = false,
  });

  @override
  State<WesiAiActivityRow> createState() => _WesiAiActivityRowState();
}

class _WesiAiActivityRowState extends State<WesiAiActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = widget.event;
    final inlineReadDetail = event.kind == WesiAiActivityKind.tool &&
        event.detail.isNotEmpty &&
        !event.hasDiff &&
        event.files.isEmpty;
    final hasDetails = (!inlineReadDetail && event.detail.isNotEmpty) ||
        event.files.isNotEmpty;
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
      onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 0 : 8,
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
                    maxLines: widget.compact ? 2 : 1,
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
                    _expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 18,
                  ),
                ],
              ],
            ),
            if (inlineReadDetail)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 5),
                child: Text(
                  event.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_expanded) ...[
              if (event.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 5),
                  child: Text(event.detail, style: theme.textTheme.bodySmall),
                ),
              if (event.files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final file in event.files.take(12))
                        Text(
                          file,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
