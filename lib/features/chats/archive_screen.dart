import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';
import 'data/sticker_packs.dart';
import 'models/chat_message.dart';
import 'services/chat_service.dart';
import 'services/message_store.dart';

/// Архив — то, что человек решил сохранить навсегда.
///
/// Обычная переписка живёт месяц и исчезает. Здесь — обратное правило: не
/// удаляется ничем. Ни чисткой по сроку, ни очисткой чата, ни удалением
/// самого разговора.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ArchiveScreen()),
      );

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  String _search = '';

  bool get _ru => WesiLocale.isRussian;

  List<ChatMessage> get _visible {
    final all = MessageStore.archive();
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((m) {
      final author =
          TeamService.byId(m.authorId)?.displayName.toLowerCase() ?? '';
      return m.body.toLowerCase().contains(q) || author.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessageStore.revision,
      builder: (context, _, __) {
        final items = _visible;
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            WesiTitle(_ru ? 'Архив' : 'Archive', size: 20),
                            Text(
                              _ru
                                  ? 'Сохранено навсегда: ${items.length}'
                                  : 'Kept forever: ${items.length}',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style:
                        TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _ru ? 'Поиск по архиву' : 'Search archive',
                      hintStyle: TextStyle(
                          fontSize: 13, color: AppTheme.textMuted),
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: AppTheme.textMuted),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.surfaceLight.withOpacity(0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: BorderSide(color: AppTheme.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: BorderSide(color: AppTheme.glassBorder),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty ? _empty() : _list(items),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmarks_outlined,
                  size: 40, color: AppTheme.textMuted),
              const SizedBox(height: 14),
              Text(
                _search.isNotEmpty
                    ? (_ru ? 'Ничего не найдено' : 'Nothing found')
                    : (_ru
                        ? 'Архив пуст.\n\nОбычные сообщения живут месяц и '
                            'исчезают. Долгое нажатие на сообщение → «В '
                            'архив», и оно останется навсегда.'
                        : 'Archive is empty.\n\nOrdinary messages live a '
                            'month. Long-press → Archive to keep one '
                            'forever.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _list(List<ChatMessage> items) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final m = items[i];
          final author = TeamService.byId(m.authorId)?.displayName ??
              (m.authorId == ChatService.meId ? (_ru ? 'Вы' : 'You') : '');
          final chat = ChatService.byId(m.chatId);
          final at = m.at.toLocal();
          String two(int v) => v.toString().padLeft(2, '0');

          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmark, size: 11, color: AppTheme.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (author.isNotEmpty) author,
                            if (chat != null) ChatService.titleOf(chat),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted),
                        ),
                      ),
                      Text(
                        '${two(at.day)}.${two(at.month)}.${at.year}',
                        style: TextStyle(
                            fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    m.isSticker ? StickerPacks.resolve(m.body) : m.body,
                    style: TextStyle(
                      fontSize: m.isSticker ? 30 : 13.5,
                      height: 1.4,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await MessageStore.unarchive(m.id);
                          if (mounted) setState(() {});
                        },
                        child: Text(
                          _ru ? 'Убрать из архива' : 'Remove from archive',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}
