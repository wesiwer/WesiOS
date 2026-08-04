import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';
import 'models/chat_message.dart';
import 'models/chat_thread.dart';
import 'services/chat_service.dart';
import 'services/message_store.dart';
import 'services/topic_privacy.dart';
import 'widgets/message_bubble.dart';
import 'widgets/sticker_sheet.dart';
import 'widgets/topic_divider.dart';
import 'widgets/topic_question_card.dart';

/// Переписка.
///
/// **Блоки тем — не украшение, а главная особенность.** Разговор режется на
/// осознанные части, и там, где программа не уверена, она спрашивает
/// человека прямо в ленте, а не молча делает по-своему.
class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  static Future<void> open(BuildContext context, String chatId) =>
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  ChatMessage? _replyTo;

  bool get _ru => WesiLocale.isRussian;

  ChatThread? get _chat => ChatService.byId(widget.chatId);

  @override
  void initState() {
    super.initState();
    ChatService.markOpened(widget.chatId);
    // Чистка при входе, а не по таймеру: сообщение с вышедшим сроком не
    // должно дождаться, пока кто-то вспомнит про уборку.
    MessageStore.sweep();
  }

  @override
  void dispose() {
    // Отметку ставим и на выходе: человек мог читать долго, и всё, что
    // пришло за это время, он уже видел.
    ChatService.markOpened(widget.chatId);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send({String? sticker}) async {
    final chat = _chat;
    if (chat == null) return;
    final text = sticker ?? _input.text;
    if (text.trim().isEmpty) return;

    await MessageStore.send(
      chatId: chat.id,
      authorId: ChatService.meId,
      body: text,
      kind: sticker == null ? MessageKind.text : MessageKind.sticker,
      replyTo: _replyTo?.id,
    );
    if (!mounted) return;
    setState(() {
      _input.clear();
      _replyTo = null;
    });
    _toBottom();
  }

  void _toBottom() {
    // Кадром позже: список ещё не перестроился, и прокручивать пока некуда.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _stickers() async {
    final picked = await StickerSheet.show(context);
    if (picked != null) await _send(sticker: picked);
  }

  void _actions(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageActions(
        message: m,
        onReply: () => setState(() => _replyTo = m),
        onChanged: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessageStore.revision,
      builder: (context, _, __) {
        final chat = _chat;
        if (chat == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Text(_ru ? 'Разговор удалён' : 'Chat removed',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
          );
        }
        final messages = MessageStore.of(chat.id);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              children: [
                _header(chat),
                Expanded(
                  child: messages.isEmpty
                      ? _empty()
                      : _list(chat, messages),
                ),
                if (_replyTo != null) _replyBar(),
                _composer(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(ChatThread chat) {
    final other = chat.otherThan(ChatService.meId);
    final person = other == null ? null : TeamService.byId(other);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          8, kTitleBarInset + 10, kHasCustomTitleBar ? 148 : 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          if (person != null)
            WesiAvatar(size: 34, index: person.avatarIndex, photo: person.photo)
          else
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Icon(Icons.groups_outlined,
                  size: 17, color: AppTheme.textMuted),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ChatService.titleOf(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 1),
                // Кто читает переписку — прямо в шапке, а не в настройках.
                // Человек должен видеть это, когда пишет, а не когда ищет.
                Text(
                  TopicPrivacy.describe(chat.kind, russian: _ru),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _ru
                ? 'Сообщений пока нет.\n\nОбычные сообщения хранятся месяц. '
                    'Всё, что должно остаться навсегда, — долгим нажатием '
                    'в архив.'
                : 'No messages yet.\n\nOrdinary messages are kept for a '
                    'month. Long-press to archive what must survive.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
          ),
        ),
      );

  Widget _list(ChatThread chat, List<ChatMessage> messages) {
    // Блоки тем считаются из самой переписки. Заголовок вставляется перед
    // первым сообщением каждого блока, а спорные места превращаются в
    // карточку с вопросом.
    final blocks = TopicDivider.planFor(messages);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final mine = m.authorId == ChatService.meId;
        final divider = blocks.headerAt(i);
        final question = blocks.questionAt(i);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (divider != null) TopicDivider(title: divider),
            if (question != null)
              TopicQuestionCard(
                question: question,
                onSplit: () => _splitAt(messages, question.index),
                onKeep: () => setState(() => blocks.dismiss(question.index)),
              ),
            MessageBubble(
              message: m,
              mine: mine,
              showAuthor: chat.isGroup && !mine,
              replyTo: m.replyTo == null
                  ? null
                  : MessageStore.byId(m.replyTo!),
              onLongPress: () => _actions(m),
            ),
          ],
        );
      },
    );
  }

  Future<void> _splitAt(List<ChatMessage> messages, int index) async {
    // Разделение — это метка темы на сообщениях после границы, а не
    // удаление и не перенос. Ничего не теряется, и решение обратимо.
    final topicId = 't${DateTime.now().microsecondsSinceEpoch}';
    await MessageStore.assignTopic(
      [for (var i = index; i < messages.length; i++) messages[i].id],
      topicId,
    );
    if (mounted) setState(() {});
  }

  Widget _replyBar() => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          border: Border(top: BorderSide(color: AppTheme.glassBorder)),
        ),
        child: Row(
          children: [
            Container(width: 2.5, height: 30, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru ? 'Ответ' : 'Reply',
                    style: TextStyle(fontSize: 10, color: AppTheme.accent),
                  ),
                  Text(
                    _replyTo!.isSticker ? '🖼' : _replyTo!.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 17, color: AppTheme.textMuted),
              onPressed: () => setState(() => _replyTo = null),
            ),
          ],
        ),
      );

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.35),
        border: Border(top: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: _ru ? 'Стикеры' : 'Stickers',
            icon: Icon(Icons.emoji_emotions_outlined,
                size: 22, color: AppTheme.textMuted),
            onPressed: _stickers,
          ),
          Expanded(
            child: ConstrainedBox(
              // Растёт до пяти строк и дальше прокручивается: без предела
              // длинное сообщение выдавило бы переписку с экрана целиком.
              constraints: const BoxConstraints(maxHeight: 116),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: _ru ? 'Сообщение' : 'Message',
                  hintStyle:
                      TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppTheme.surfaceLight.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.glassBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _input.text.trim().isEmpty ? null : _send,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _input.text.trim().isEmpty
                    ? AppTheme.surface
                    : AppTheme.accent.withOpacity(0.2),
                border: Border.all(
                  color: _input.text.trim().isEmpty
                      ? AppTheme.glassBorder
                      : AppTheme.accent.withOpacity(0.6),
                ),
              ),
              child: Icon(
                Icons.arrow_upward,
                size: 19,
                color: _input.text.trim().isEmpty
                    ? AppTheme.textMuted
                    : AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Что можно сделать с сообщением.
class _MessageActions extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onReply;
  final VoidCallback onChanged;

  const _MessageActions({
    required this.message,
    required this.onReply,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            context,
            Icons.reply,
            ru ? 'Ответить' : 'Reply',
            () {
              Navigator.pop(context);
              onReply();
            },
          ),
          if (!message.isSticker)
            _row(
              context,
              Icons.copy_all_outlined,
              ru ? 'Скопировать' : 'Copy',
              () {
                Clipboard.setData(ClipboardData(text: message.body));
                Navigator.pop(context);
              },
            ),
          if (message.archived)
            _row(
              context,
              Icons.unarchive_outlined,
              ru ? 'Убрать из архива' : 'Remove from archive',
              () async {
                await MessageStore.unarchive(message.id);
                if (context.mounted) Navigator.pop(context);
                onChanged();
              },
              hint: ru
                  ? 'Снова начнёт храниться месяц'
                  : 'Will be kept for a month again',
            )
          else
            _row(
              context,
              Icons.archive_outlined,
              ru ? 'В архив' : 'Archive',
              () async {
                await MessageStore.archiveMessage(message.id);
                if (context.mounted) Navigator.pop(context);
                onChanged();
              },
              hint: ru
                  ? 'Останется навсегда, даже когда чат очистится'
                  : 'Kept forever, even when the chat is cleared',
            ),
          _row(
            context,
            Icons.delete_outline,
            ru ? 'Удалить' : 'Delete',
            () async {
              final removed = await MessageStore.remove(message.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (!removed) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ru
                      ? 'Архивное сообщение не удаляется — сначала уберите '
                          'его из архива'
                      : 'Archived messages cannot be deleted'),
                  backgroundColor: AppTheme.surface,
                ));
              }
              onChanged();
            },
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? hint,
    bool danger = false,
  }) {
    final color = danger ? AppTheme.accentRed : AppTheme.textPrimary;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 19, color: color),
      title: Text(label, style: TextStyle(fontSize: 13.5, color: color)),
      subtitle: hint == null
          ? null
          : Text(hint,
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
      onTap: onTap,
    );
  }
}
