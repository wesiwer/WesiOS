import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/models/employee_model.dart';
import '../team/services/team_service.dart';
import 'archive_screen.dart';
import 'chat_screen.dart';
import 'models/chat_policy.dart';
import 'models/chat_thread.dart';
import 'services/chat_service.dart';
import 'services/message_store.dart';
import 'services/topic_privacy.dart';

/// Чаты.
///
/// Папки не косметические: рабочий и личный разговор различаются тем, кто их
/// может прочитать, и это написано под каждой папкой открытым текстом. Тихое
/// разделение — не приватность, а её видимость.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  int _folder = 0;

  bool get _ru => WesiLocale.isRussian;

  List<String> get _folders => _ru
      ? const ['Все', 'Рабочие', 'Личные', 'Люди']
      : const ['All', 'Work', 'Personal', 'People'];

  ChatKind? get _kind => switch (_folder) {
        1 => ChatKind.work,
        2 => ChatKind.personal,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    // Уборка при входе: сообщение с вышедшим сроком не должно ждать, пока
    // кто-то вспомнит про чистку.
    MessageStore.sweep();
  }

  Future<void> _openWith(EmployeeModel person, ChatKind kind) async {
    final chat = await ChatService.direct(person.id, kind: kind);
    if (!mounted) return;
    await ChatScreen.open(context, chat.id);
    if (mounted) setState(() {});
  }

  Future<void> _pickPersonFor(ChatKind kind) async {
    final people = TeamService.all
        .where((e) => e.id != ChatService.meId)
        .toList();
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_ru
            ? 'Сначала заведите людей в контактах'
            : 'Add people in contacts first'),
        backgroundColor: AppTheme.surface,
      ));
      return;
    }
    final picked = await showModalBottomSheet<EmployeeModel>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PersonPicker(people: people, kind: kind),
    );
    if (picked != null) await _openWith(picked, kind);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatService.revision,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: MessageStore.revision,
        builder: (context, __, ___) => _build(context),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final showPeople = _folder == 3;
    final chats = showPeople ? const <ChatThread>[] : ChatService.all(kind: _kind);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  for (var i = 0; i < _folders.length; i++) ...[
                    _folderChip(i),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (_kind != null) _privacyLine(),
            Expanded(
              child: showPeople
                  ? _people()
                  : chats.isEmpty
                      ? _emptyChats()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          itemCount: chats.length,
                          itemBuilder: (context, i) => _chatRow(chats[i]),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: showPeople
          ? null
          : FloatingActionButton(
              onPressed: () => _pickPersonFor(_kind ?? ChatKind.work),
              backgroundColor: AppTheme.accent,
              child: const Icon(Icons.edit_outlined, color: Colors.white),
            ),
    );
  }

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(
            8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 12, 0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(child: WesiTitle(_ru ? 'Чаты' : 'Chats', size: 22)),
            IconButton(
              tooltip: _ru ? 'Архив' : 'Archive',
              icon: Icon(Icons.bookmarks_outlined,
                  size: 20, color: AppTheme.textMuted),
              onPressed: () => ArchiveScreen.open(context),
            ),
          ],
        ),
      );

  Widget _folderChip(int i) {
    final on = i == _folder;
    return GestureDetector(
      onTap: () => setState(() => _folder = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? AppTheme.accent.withOpacity(0.16)
              : AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? AppTheme.accent.withOpacity(0.5) : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          _folders[i],
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            color: on ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _privacyLine() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
        child: Row(
          children: [
            Icon(
              _kind == ChatKind.work
                  ? Icons.badge_outlined
                  : Icons.lock_outline,
              size: 13,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                TopicPrivacy.describe(_kind!, russian: _ru),
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      );

  Widget _emptyChats() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 40, color: AppTheme.textMuted),
              const SizedBox(height: 14),
              Text(
                _ru
                    ? 'Разговоров пока нет.\nНачните с вкладки «Люди» или '
                        'кнопкой внизу.'
                    : 'No conversations yet.\nStart from the People tab.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _people() {
    final people =
        TeamService.all.where((e) => e.id != ChatService.meId).toList();
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _ru
                ? 'В составе пока никого нет.\nЗаведите людей в контактах.'
                : 'No people yet. Add them in contacts.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      itemCount: people.length,
      itemBuilder: (context, i) {
        final e = people[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                WesiAvatar(size: 36, index: e.avatarIndex, photo: e.photo),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.displayName,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      if (e.position.isNotEmpty)
                        Text(e.position,
                            style: TextStyle(
                                fontSize: 10.5, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                // Два входа, а не один: с кем-то говорят по работе, с
                // кем-то лично, и правила чтения у них разные.
                _startButton(_ru ? 'Рабочий' : 'Work', Icons.badge_outlined,
                    () => _openWith(e, ChatKind.work)),
                const SizedBox(width: 6),
                _startButton(_ru ? 'Личный' : 'Personal', Icons.lock_outline,
                    () => _openWith(e, ChatKind.personal)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _startButton(String label, IconData icon, VoidCallback onTap) =>
      Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Icon(icon, size: 15, color: AppTheme.accent),
          ),
        ),
      );

  Widget _chatRow(ChatThread chat) {
    final other = chat.otherThan(ChatService.meId);
    final person = other == null ? null : TeamService.byId(other);
    final unread = ChatService.unreadOf(chat);
    final preview = ChatService.previewOf(chat);
    final last = MessageStore.lastOf(chat.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () async {
          await ChatScreen.open(context, chat.id);
          if (mounted) setState(() {});
        },
        onLongPress: () => _chatActions(chat),
        onSecondaryTap: () => _chatActions(chat),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chat.pinned
                  ? AppTheme.accent.withOpacity(0.3)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Row(
            children: [
              if (person != null)
                WesiAvatar(
                    size: 38, index: person.avatarIndex, photo: person.photo)
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceLight,
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Icon(Icons.groups_outlined,
                      size: 18, color: AppTheme.textMuted),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.pinned) ...[
                          Icon(Icons.push_pin,
                              size: 11, color: AppTheme.accent),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            ChatService.titleOf(chat),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          chat.kind == ChatKind.work
                              ? Icons.badge_outlined
                              : Icons.lock_outline,
                          size: 11,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.isEmpty
                          ? (_ru ? 'Ни одного сообщения' : 'No messages')
                          : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (last != null)
                    Text(
                      _time(last.at),
                      style: TextStyle(
                          fontSize: 9.5, color: AppTheme.textMuted),
                    ),
                  if (unread > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$unread',
                          style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _time(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? '${two(local.hour)}:${two(local.minute)}'
        : '${two(local.day)}.${two(local.month)}';
  }

  void _chatActions(ChatThread chat) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(
                  chat.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                  size: 19,
                  color: AppTheme.textPrimary),
              title: Text(
                chat.pinned
                    ? (_ru ? 'Открепить' : 'Unpin')
                    : (_ru ? 'Закрепить' : 'Pin'),
                style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary),
              ),
              onTap: () async {
                await ChatService.togglePinned(chat.id);
                if (mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline,
                  size: 19, color: AppTheme.accentRed),
              title: Text(_ru ? 'Удалить разговор' : 'Delete chat',
                  style: TextStyle(
                      fontSize: 13.5, color: AppTheme.accentRed)),
              subtitle: Text(
                _ru
                    ? 'Архивные сообщения останутся'
                    : 'Archived messages will remain',
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
              onTap: () async {
                await ChatService.remove(chat.id);
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор человека для нового разговора.
class _PersonPicker extends StatelessWidget {
  final List<EmployeeModel> people;
  final ChatKind kind;

  const _PersonPicker({required this.people, required this.kind});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind == ChatKind.work
                ? (ru ? 'Рабочий разговор с кем' : 'Work chat with')
                : (ru ? 'Личный разговор с кем' : 'Personal chat with'),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            TopicPrivacy.describe(kind, russian: ru),
            style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, i) {
                final e = people[i];
                return ListTile(
                  dense: true,
                  leading: WesiAvatar(
                      size: 30, index: e.avatarIndex, photo: e.photo),
                  title: Text(e.displayName,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textPrimary)),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
