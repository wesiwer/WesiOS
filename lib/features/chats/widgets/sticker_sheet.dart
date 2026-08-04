import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../data/sticker_packs.dart';

/// Выбор стикера.
///
/// Возвращает **идентификатор** вида `work:3`, а не сам символ. Разница
/// важная: когда символы заменятся на рисованные стикеры, уже отправленные
/// сообщения покажутся новой картинкой, а не останутся текстом.
class StickerSheet extends StatefulWidget {
  const StickerSheet({super.key});

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const StickerSheet(),
      );

  @override
  State<StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<StickerSheet> {
  int _pack = 0;

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final pack = StickerPacks.all[_pack];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
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
          Row(
            children: [
              for (var i = 0; i < StickerPacks.all.length; i++) ...[
                GestureDetector(
                  onTap: () => setState(() => _pack = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: i == _pack
                          ? AppTheme.accent.withOpacity(0.16)
                          : AppTheme.surface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: i == _pack
                            ? AppTheme.accent.withOpacity(0.5)
                            : AppTheme.glassBorder,
                      ),
                    ),
                    child: Text(
                      ru
                          ? StickerPacks.all[i].titleRu
                          : StickerPacks.all[i].titleEn,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            i == _pack ? FontWeight.w700 : FontWeight.w400,
                        color: i == _pack
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: pack.items.length,
            itemBuilder: (context, i) => GestureDetector(
              onTap: () =>
                  Navigator.pop(context, StickerPacks.idOf(pack.id, i)),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(pack.items[i],
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
