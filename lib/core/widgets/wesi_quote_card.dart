import 'package:flutter/material.dart';
import '../data/wesi_quotes.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';

/// Карточка с фразой дня на главном экране.
///
/// По умолчанию берёт фразу текущего слота ([WesiQuotes.current]) — она
/// стабильна в пределах нескольких часов, поэтому экран не мельтешит. Кнопка
/// «обновить» показывает случайную, если захотелось другую прямо сейчас.
class WesiQuoteCard extends StatefulWidget {
  const WesiQuoteCard({super.key});

  @override
  State<WesiQuoteCard> createState() => _WesiQuoteCardState();
}

class _WesiQuoteCardState extends State<WesiQuoteCard> {
  WesiQuote? _manual; // выбранная вручную, перебивает фразу слота

  @override
  Widget build(BuildContext context) {
    final quote = _manual ?? WesiQuotes.current();
    final text = WesiLocale.isRussian ? quote.ru : quote.en;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentOrange.withOpacity(0.10),
            AppTheme.surface.withOpacity(0.35),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.format_quote,
                size: 18, color: AppTheme.accentOrange.withOpacity(0.8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppTheme.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                // Автор рисуется только если он есть — у народных фраз
                // подпись не нужна вовсе, пустой прочерк выглядел бы багом.
                if (quote.author != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '— ${quote.author}',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: WesiLocale.isRussian ? 'Другая фраза' : 'Another quote',
            icon: Icon(Icons.refresh,
                size: 16, color: AppTheme.textMuted.withOpacity(0.8)),
            onPressed: () => setState(() => _manual = WesiQuotes.random()),
          ),
        ],
      ),
    );
  }
}
