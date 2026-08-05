import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wesi_avatar.dart';
import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';
import '../models/chat_thread.dart';
import '../services/chat_service.dart';
import '../services/message_store.dart';

/// Что можно настроить у разговора: срок хранения, а у группы ещё название и
/// состав.
///
/// Всё это лежит в одном месте намеренно. Срок хранения — не косметика: от
/// него зависит, что человек найдёт через полгода и чего не найдёт. Прятать
/// такое в общие настройки, где оно действует сразу на всё, — значит сделать
/// решение либо слишком крупным, либо незаметным.
class ChatSettingsSheet extends StatefulWidget {
  final String chatId;

  const ChatSettingsSheet({super.key, required this.chatId});

  /// `true` — человек вышел из группы, и разговора у него больше нет.
  ///
  /// Возвращается наружу, а не решается здесь: закрывать за собой лист умеет
  /// и этот виджет, а вот надо ли закрывать ещё и экран под ним — зависит от
  /// того, откуда его открыли. Из переписки — надо, из списка разговоров —
  /// нет, иначе закрылся бы сам список.
  static Future<bool?> show(BuildContext context, String chatId) =>
      showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ChatSettingsSheet(chatId: chatId),
      );

  @override
  State<ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<ChatSettingsSheet> {
  bool get _ru => WesiLocale.isRussian;

  ChatThread? get _chat => ChatService.byId(widget.chatId);

  Future<void> _setLifetime(int? days) async {
    final extended = await ChatService.setLifetime(widget.chatId, days);
    if (!mounted) return;
    setState(() {});
    if (extended > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_ru
            ? 'Срок продлён и уже написанному: $extended сообщений'
            : 'Existing messages extended: $extended'),
        backgroundColor: AppTheme.surface,
      ));
    }
  }

  Future<void> _rename() async {
    final chat = _chat;
    if (chat == null) return;
    final controller = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.glassBorder),
        ),
        title: Text(_ru ? 'Название группы' : 'Group name',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Отмена' : 'Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_ru ? 'Сохранить' : 'Save',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) return;
    await ChatService.rename(widget.chatId, title);
    if (mounted) setState(() {});
  }

  Future<void> _editMembers() async {
    final chat = _chat;
    if (chat == null) return;
    final picked = await ChatMemberPicker.show(
      context,
      selected: chat.participantIds,
    );
    if (picked == null || !mounted) return;
    await ChatService.setMembers(widget.chatId, picked);
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    await ChatService.leave(widget.chatId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) return const SizedBox.shrink();
    final me = ChatService.meId;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              ChatService.titleOf(chat),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            _sectionTitle(_ru ? 'Сколько хранить' : 'How long to keep'),
            const SizedBox(height: 6),
            Text(
              _ru
                  ? 'Продление действует и на уже написанное. Укорачивание — '
                      'только на новое: настройка не стирает переписку задним '
                      'числом. Чтобы что-то осталось навсегда, отправьте его '
                      'в архив.'
                  : 'Extending also applies to existing messages. Shortening '
                      'applies to new ones only. Use the archive to keep '
                      'something forever.',
              style: TextStyle(
                  fontSize: 10.5, height: 1.45, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in ChatService.lifetimeChoices)
                  _lifetimeChip(days, chat.lifetimeDays),
              ],
            ),
            if (chat.isGroup) ...[
              const SizedBox(height: 20),
              _sectionTitle(_ru ? 'Группа' : 'Group'),
              const SizedBox(height: 8),
              _action(Icons.drive_file_rename_outline,
                  _ru ? 'Переименовать' : 'Rename', _rename),
              _action(
                Icons.group_add_outlined,
                _ru ? 'Состав' : 'Members',
                _editMembers,
                hint: _ru
                    ? '${chat.participantIds.length} участников'
                    : '${chat.participantIds.length} members',
              ),
              const SizedBox(height: 8),
              for (final id in chat.participantIds) _member(id, me),
              const SizedBox(height: 6),
              _action(
                Icons.logout,
                _ru ? 'Выйти из группы' : 'Leave group',
                _leave,
                danger: true,
                hint: _ru
                    ? 'Переписка сотрется, кроме отправленной в архив'
                    : 'Messages are removed except archived ones',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: AppTheme.textMuted,
        ),
      );

  Widget _lifetimeChip(int? days, int? current) {
    final on = days == current;
    final label = days == null
        ? (_ru
            ? 'Как везде · ${MessageStore.defaultLifetime.inDays} дн.'
            : 'Default · ${MessageStore.defaultLifetime.inDays}d')
        : (_ru ? '$days дн.' : '${days}d');
    return GestureDetector(
      onTap: () => _setLifetime(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            color: on ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _member(String id, String me) {
    final person = TeamService.byId(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          WesiAvatar(
              size: 26,
              index: person?.avatarIndex ?? 0,
              photo: person?.photo),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              person?.displayName ?? (_ru ? 'Неизвестный' : 'Unknown'),
              style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
            ),
          ),
          if (id == me)
            Text(_ru ? 'вы' : 'you',
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? hint,
    bool danger = false,
  }) {
    final color = danger ? AppTheme.accentRed : AppTheme.textPrimary;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: color),
      title: Text(label, style: TextStyle(fontSize: 13, color: color)),
      subtitle: hint == null
          ? null
          : Text(hint,
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      onTap: onTap,
    );
  }
}

/// Выбор нескольких человек — для состава группы.
///
/// Себя из списка нет: из группы, которую ведёшь, выходят отдельным решением,
/// а не снятой галочкой рядом со своим именем.
class ChatMemberPicker extends StatefulWidget {
  final List<String> selected;

  const ChatMemberPicker({super.key, required this.selected});

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> selected,
  }) =>
      showModalBottomSheet<List<String>>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ChatMemberPicker(selected: selected),
      );

  @override
  State<ChatMemberPicker> createState() => _ChatMemberPickerState();
}

class _ChatMemberPickerState extends State<ChatMemberPicker> {
  late final Set<String> _chosen = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final me = ChatService.meId;
    final people = [
      for (final e in TeamService.all)
        if (e.id != me) e,
    ];

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ru ? 'Кто в группе' : 'Group members',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                ru
                    ? 'В составе пока никого нет. Заведите людей в контактах.'
                    : 'No people yet. Add them in contacts.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: people.length,
                itemBuilder: (context, i) => _row(people[i]),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ru ? 'Отмена' : 'Cancel',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _chosen.toList()),
                child: Text(ru ? 'Готово' : 'Done',
                    style: TextStyle(color: AppTheme.accent)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(EmployeeModel e) {
    final on = _chosen.contains(e.id);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: WesiAvatar(size: 30, index: e.avatarIndex, photo: e.photo),
      title: Text(e.displayName,
          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
      subtitle: e.position.isEmpty
          ? null
          : Text(e.position,
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      trailing: Icon(
        on ? Icons.check_circle : Icons.circle_outlined,
        size: 20,
        color: on ? AppTheme.accent : AppTheme.textMuted,
      ),
      onTap: () => setState(
          () => on ? _chosen.remove(e.id) : _chosen.add(e.id)),
    );
  }
}
