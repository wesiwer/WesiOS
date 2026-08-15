from pathlib import Path


def patch(path: str, replacements: list[tuple[str, str]]) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    changed = False
    for old, new in replacements:
        if old in text:
            text = text.replace(old, new)
            changed = True
    if changed:
        p.write_text(text, encoding='utf-8')


patch(
    'lib/features/ai/models/wesi_ai_activity.dart',
    [
        (
            "final offset = _nonNegativeInt(map['textOffset']).clamp(0, 10000000);",
            "final offset = _nonNegativeInt(map['textOffset']).clamp(0, 10000000).toInt();",
        ),
    ],
)

path = Path('lib/features/ai/widgets/wesi_ai_rich_message.dart')
text = path.read_text(encoding='utf-8')
text = text.replace('.withValues(alpha: 0.12)', '.withOpacity(0.12)')
text = text.replace('.withValues(alpha: 0.62)', '.withOpacity(0.62)')
text = text.replace(
    'final rawOffset = event.textOffset.clamp(0, text.length);',
    'final rawOffset = event.textOffset.clamp(0, text.length).toInt();',
)

old_switch = '''      switch (block.kind) {
        case WesiAiRichBlockKind.code:
          widgets.add(WesiAiCodeBlock(code: block.text, language: block.language));
        case WesiAiRichBlockKind.quote:
          widgets.add(WesiAiQuoteBlock(text: block.text));
        case WesiAiRichBlockKind.draft:
          widgets.add(WesiAiQuoteBlock(text: block.text, label: _draftLabel(block.language)));
        case WesiAiRichBlockKind.text:
          widgets.add(WesiAiFormattedText(text: block.text));
      }'''
new_switch = '''      switch (block.kind) {
        case WesiAiRichBlockKind.code:
          widgets.add(WesiAiCodeBlock(code: block.text, language: block.language));
          break;
        case WesiAiRichBlockKind.quote:
          widgets.add(WesiAiQuoteBlock(text: block.text));
          break;
        case WesiAiRichBlockKind.draft:
          widgets.add(WesiAiQuoteBlock(text: block.text, label: _draftLabel(block.language)));
          break;
        case WesiAiRichBlockKind.text:
          widgets.add(WesiAiFormattedText(text: block.text));
          break;
      }'''
if old_switch in text:
    text = text.replace(old_switch, new_switch, 1)

old_quote = '''    return Row(
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
              SelectableText(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.48)),
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
    );'''
new_quote = '''    return IntrinsicHeight(
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
    );'''
if old_quote in text:
    text = text.replace(old_quote, new_quote, 1)

path.write_text(text, encoding='utf-8')

# After the main generator wires the rich renderer, the old local variable is
# no longer used and would make analyzer output noisy.
message_content = Path('lib/features/ai/widgets/wesi_ai_message_content.dart')
if message_content.exists():
    text = message_content.read_text(encoding='utf-8')
    old = '''    final assistant = message.author == WesiAiMessageAuthor.zane ||
        message.author == WesiAiMessageAuthor.nirvana;

'''
    if "activityRaw: message.metadata['activity']" in text and old in text:
        text = text.replace(old, '', 1)
    message_content.write_text(text, encoding='utf-8')

# WesiAiApi.send gained an optional observable activity callback. Every
# subclass/test double must keep an override-compatible named parameter even
# when that implementation does not consume activity itself.
signature_old = '''    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
'''
signature_new = '''    void Function(String delta)? onDelta,
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
'''
for override_path in (
    'lib/features/ai/wesi_ai_lobby_api.dart',
    'test/wesi_ai_memory_engine_test.dart',
    'test/wesi_ai_queue_hardening_test.dart',
):
    p = Path(override_path)
    override_text = p.read_text(encoding='utf-8')
    override_text = override_text.replace(signature_old, signature_new)
    if override_path.endswith('wesi_ai_lobby_api.dart'):
        override_text = override_text.replace(
            '''        onDelta: onDelta,
        cancellation: cancellation,
''',
            '''        onDelta: onDelta,
        onActivity: onActivity,
        cancellation: cancellation,
''',
        )
    p.write_text(override_text, encoding='utf-8')

# Final assistant messages must retain the same observable activity that was
# visible on the transient streaming message. Otherwise tool/agent history
# disappears after the partial message is replaced or after app restart.
controller = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
text = controller.read_text(encoding='utf-8')
final_metadata_old = '''          'requestId': reply.requestId,
          if (streamVisible) 'transportStreamed': true,
          if (reply.blocks.isNotEmpty)
'''
final_metadata_new = '''          'requestId': reply.requestId,
          if (streamVisible) 'transportStreamed': true,
          if (activity.isNotEmpty)
            'activity': activity
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
          'workStartedAt': workStartedAt.toIso8601String(),
          'workDurationMs':
              DateTime.now().toUtc().difference(workStartedAt).inMilliseconds,
          if (reply.blocks.isNotEmpty)
'''
if final_metadata_old in text:
    text = text.replace(final_metadata_old, final_metadata_new, 1)

close_activity_anchor = '''      final at = DateTime.now();
      final assistant = WesiAiMessage(
'''
close_activity_replacement = '''      final completedAt = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < activity.length; index++) {
        final current = activity[index];
        if ('${current['status'] ?? ''}' != 'start') continue;
        final closed = Map<String, dynamic>.from(current);
        closed['status'] = 'done';
        closed['completedAt'] = completedAt;
        activity[index] = closed;
      }
      final at = DateTime.now();
      final assistant = WesiAiMessage(
'''
if "final completedAt = DateTime.now().toUtc().toIso8601String();" not in text and close_activity_anchor in text:
    text = text.replace(close_activity_anchor, close_activity_replacement, 1)
controller.write_text(text, encoding='utf-8')

# Extend the existing streaming lifecycle regression so it proves activity is
# both visible before the answer and durable after the transient message is
# collapsed into the final assistant message.
queue_test = Path('test/wesi_ai_queue_hardening_test.dart')
text = queue_test.read_text(encoding='utf-8')
if 'void Function(Map<String, dynamic> event)? activityCallback;' not in text:
    text = text.replace(
        '''  void Function(String delta)? onDelta;

  @override
''',
        '''  void Function(String delta)? onDelta;
  void Function(Map<String, dynamic> event)? activityCallback;

  @override
''',
        1,
    )
    text = text.replace(
        '''    this.onDelta = onDelta;
    return reply.future;
''',
        '''    this.onDelta = onDelta;
    activityCallback = onActivity;
    return reply.future;
''',
        1,
    )

stream_test_old = '''    final sending = controller.addUserMessage('stream me');
    await _waitUntil(() => api.onDelta != null);
    api.onDelta!('При');
'''
stream_test_new = '''    final sending = controller.addUserMessage('stream me');
    await _waitUntil(() => api.onDelta != null && api.activityCallback != null);
    api.activityCallback!({
      'type': 'tool',
      'phase': 'start',
      'name': 'github_file_upsert',
    });
    api.activityCallback!({
      'type': 'tool',
      'phase': 'result',
      'name': 'github_file_upsert',
      'additions': 4,
      'deletions': 2,
      'files': ['lib/example.dart'],
    });
    api.onDelta!('При');
'''
if stream_test_old in text:
    text = text.replace(stream_test_old, stream_test_new, 1)

stream_assert_old = '''    expect(messages.last.metadata['transportStreamed'], isTrue);
    expect(store.saved!.messagesFor(conversationId).last.text, 'Привет');
'''
stream_assert_new = '''    expect(messages.last.metadata['transportStreamed'], isTrue);
    final activity = messages.last.metadata['activity'];
    expect(activity, isA<List>());
    final toolEvent = (activity as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .singleWhere((item) => item['sourceName'] == 'github_file_upsert');
    expect(toolEvent['additions'], 4);
    expect(toolEvent['deletions'], 2);
    expect(toolEvent['files'], ['lib/example.dart']);
    expect(toolEvent['status'], 'result');
    final persisted = store.saved!.messagesFor(conversationId).last;
    expect(persisted.text, 'Привет');
    expect(persisted.metadata['activity'], isA<List>());
    expect(persisted.metadata['workStartedAt'], isNotNull);
    expect(persisted.metadata['workDurationMs'], isA<int>());
'''
if stream_assert_old in text:
    text = text.replace(stream_assert_old, stream_assert_new, 1)
queue_test.write_text(text, encoding='utf-8')

print('chat UX postfix applied')
