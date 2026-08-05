import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';
import '../data/sticker_packs.dart';
import '../models/chat_message.dart';

/// Сообщение в ленте.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool showAuthor;
  final ChatMessage? replyTo;
  final VoidCallback onLongPress;

  /// Что подсветить в тексте — то, что человек ищет. Пусто — не подсвечивать.
  final String highlight;

  /// Нажали на отклик — поставить или снять такой же.
  final void Function(String emoji)? onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onLongPress,
    this.showAuthor = false,
    this.replyTo,
    this.highlight = '',
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ),
      );
    }

    // Стикер — без «пузыря»: рамка вокруг крупного символа выглядит как
    // ошибка вёрстки, а не как стикер.
    if (message.isSticker) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(StickerPacks.resolve(message.body),
                    style: const TextStyle(fontSize: 46)),
                _meta(ru),
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            // Не во всю ширину: сообщение, дотянутое до края, читается
            // хуже и не даёт понять, чьё оно, без разглядывания.
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine
                ? AppTheme.accent.withOpacity(0.16)
                : AppTheme.surface.withOpacity(0.55),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: Border.all(
              color: mine
                  ? AppTheme.accent.withOpacity(0.35)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor) ...[
                Text(
                  TeamService.byId(message.authorId)?.displayName ?? '',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent),
                ),
                const SizedBox(height: 3),
              ],
              if (replyTo != null) _quoted(replyTo!),
              _body(),
              if (message.reactions.isNotEmpty) _reactions(),
              const SizedBox(height: 3),
              _meta(ru),
            ],
          ),
        ),
      ),
    );
  }

  /// Текст сообщения; найденное — подсвечено.
  ///
  /// Подсветка делается разбором строки, а не подстановкой разметки: в
  /// переписке встречается что угодно, и текст, случайно похожий на разметку,
  /// не должен превращаться в неё.
  Widget _body() {
    final base = TextStyle(
        fontSize: 14, height: 1.35, color: AppTheme.textPrimary);
    final needle = highlight.trim().toLowerCase();
    if (needle.isEmpty) return Text(message.body, style: base);

    final hay = message.body.toLowerCase();
    final spans = <TextSpan>[];
    var from = 0;
    while (true) {
      final hit = hay.indexOf(needle, from);
      if (hit < 0) break;
      if (hit > from) {
        spans.add(TextSpan(text: message.body.substring(from, hit)));
      }
      spans.add(TextSpan(
        text: message.body.substring(hit, hit + needle.length),
        style: TextStyle(
          backgroundColor: AppTheme.accent.withOpacity(0.28),
          fontWeight: FontWeight.w700,
        ),
      ));
      from = hit + needle.length;
    }
    if (spans.isEmpty) return Text(message.body, style: base);
    if (from < message.body.length) {
      spans.add(TextSpan(text: message.body.substring(from)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Отклики под сообщением.
  ///
  /// Показываем символ и число, а не список имён: в группе из десяти
  /// человек имена заняли бы больше места, чем само сообщение. Кто именно
  /// откликнулся — видно долгим нажатием, там же, где остальные действия.
  Widget _reactions() {
    final counts = message.reactionCounts;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final e in counts.entries)
            GestureDetector(
              onTap: onReact == null ? null : () => onReact!(e.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Text(
                  e.value > 1 ? '${e.key} ${e.value}' : e.key,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quoted(ChatMessage source) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.accent.withOpacity(0.6), width: 2),
          ),
        ),
        child: Text(
          source.isSticker
              ? StickerPacks.resolve(source.body)
              : source.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
      );

  Widget _meta(bool ru) {
    final at = message.at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        // Архивное помечается видимо: иначе человек не отличит сообщение,
        // которое исчезнет через месяц, от сохранённого навсегда — а это
        // ровно та разница, ради которой архив и сделан.
        if (message.archived) ...[
          Icon(Icons.bookmark, size: 10, color: AppTheme.accent),
          const SizedBox(width: 4),
        ],
        // Правку видно. Иначе поправленное сообщение — это возможность
        // переписать сказанное задним числом так, что собеседник не отличит
        // его от исходного.
        if (message.edited) ...[
          Text(
            ru ? 'изменено' : 'edited',
            style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          '${two(at.hour)}:${two(at.minute)}',
          style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
        ),
        if (mine) ...[
          // У `local` значка нет намеренно: сообщению некуда идти, и
          // сообщать о его пути нечего. Пустое место честнее часиков,
          // которые обещают отправку и висят вечно.
          if (_stateIcon() case final icon?) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 11, color: _stateColor()),
          ],
        ],
      ],
    );
  }

  IconData? _stateIcon() => switch (message.state) {
        DeliveryState.local => null,
        DeliveryState.pending => Icons.schedule,
        DeliveryState.sent => Icons.check,
        DeliveryState.delivered => Icons.done_all,
        DeliveryState.read => Icons.done_all,
        DeliveryState.failed => Icons.error_outline,
      };

  Color _stateColor() => switch (message.state) {
        DeliveryState.read => AppTheme.accent,
        DeliveryState.failed => AppTheme.accentRed,
        _ => AppTheme.textMuted,
      };
}
