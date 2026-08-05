import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';
import '../data/sticker_packs.dart';
import '../models/chat_attachment.dart';
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

  /// Нажали на вложение.
  final VoidCallback? onOpenAttachment;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onLongPress,
    this.showAuthor = false,
    this.replyTo,
    this.highlight = '',
    this.onReact,
    this.onOpenAttachment,
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
              if (message.attachment case final file?) ...[
                _attachment(context, file),
                const SizedBox(height: 6),
              ],
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

  /// Приложенный файл.
  ///
  /// Картинка показывается сразу, остальное — карточкой с именем и
  /// размером. Показывать имя файла вместо самой картинки значит заставить
  /// человека открывать её, чтобы вспомнить, что он прислал.
  Widget _attachment(BuildContext context, ChatAttachment file) {
    if (file.isImage && file.isHere) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          // Предел по высоте: вертикальная фотография во весь экран
          // выталкивает из ленты всё остальное.
          constraints: const BoxConstraints(maxHeight: 260),
          child: GestureDetector(
            onTap: onOpenAttachment,
            child: Image.file(
              File(file.path),
              fit: BoxFit.cover,
              // Файл мог быть удалён снаружи — каталог чистили, телефон
              // переносили. Пустая рамка честнее, чем красный крест
              // Flutter поверх переписки.
              errorBuilder: (context, _, __) => _fileCard(file, missing: true),
            ),
          ),
        ),
      );
    }
    return _fileCard(file, missing: !file.isHere);
  }

  Widget _fileCard(ChatAttachment file, {bool missing = false}) =>
      GestureDetector(
        onTap: missing ? null : onOpenAttachment,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                missing
                    ? Icons.report_gmailerrorred_outlined
                    : (file.isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined),
                size: 20,
                color: missing ? AppTheme.accentRed : AppTheme.accent,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                    ),
                    Text(
                      missing ? 'файла нет на устройстве' : file.sizeLabel,
                      style: TextStyle(
                          fontSize: 10.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

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
