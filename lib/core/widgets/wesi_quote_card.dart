import 'package:flutter/material.dart';

import '../data/wesi_quotes.dart';
import '../localization/wesi_locale.dart';
import '../services/quote_mind_charge_service.dart';
import '../theme/app_theme.dart';

/// Карточка с фразой дня на главном экране.
///
/// Карточка сама слушает тему и язык. Раньше она надеялась, что родитель
/// когда-нибудь перестроится, поэтому после смены темы могла оставаться со
/// старыми цветами до перехода на другую вкладку.
class WesiQuoteCard extends StatefulWidget {
  const WesiQuoteCard({super.key});

  @override
  State<WesiQuoteCard> createState() => _WesiQuoteCardState();
}

class _WesiQuoteCardState extends State<WesiQuoteCard> {
  WesiQuote? _manual;

  Future<void> _refresh() async {
    setState(() => _manual = WesiQuotes.random());
    await QuoteMindChargeService.registerRead();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: WesiLocale.localeNotifier,
          builder: (context, _, __) {
            final quote = _manual ?? WesiQuotes.current();
            final text = WesiLocale.isRussian ? quote.ru : quote.en;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic,
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.glassBorder),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accent.withOpacity(0.10),
                    AppTheme.surface.withOpacity(0.35),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.format_quote,
                      size: 18,
                      color: AppTheme.accent.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.08),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(
                            text,
                            key: ValueKey('${WesiLocale.current}:$text'),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: AppTheme.textPrimary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        if (quote.author != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '— ${quote.author}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: WesiLocale.isRussian
                        ? 'Другая фраза'
                        : 'Another quote',
                    icon: Icon(
                      Icons.refresh,
                      size: 16,
                      color: AppTheme.textMuted.withOpacity(0.8),
                    ),
                    onPressed: _refresh,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
