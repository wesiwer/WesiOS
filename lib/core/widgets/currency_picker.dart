import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';
import '../services/currency_service.dart';
import '../services/exchange_rate_service.dart';
import 'window_controls.dart';

/// Выбор валюты списком: флаг, страна, название и текущий курс к рублю.
///
/// Заменяет перебор по кругу (тап → следующая валюта), при котором нельзя
/// было ни увидеть весь список, ни понять, к какой стране относится код.
class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({super.key});

  /// Возвращает выбранный код валюты или null, если закрыли без выбора.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const CurrencyPicker(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final current = CurrencyService.current;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
              child: Text(
                ru ? 'Валюта' : 'Currency',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                _sourceLabel(ru),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: CurrencyService.codes
                    .map((code) => _row(context, code, code == current, ru))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(bool ru) {
    final src = ExchangeRateService.source;
    final date = ExchangeRateService.rateDateLabel;
    if (src == null) {
      return ru
          ? 'Курсы пока не загружены — показаны резервные значения'
          : 'Rates not loaded yet — showing fallback values';
    }
    final onDate = date == null ? '' : (ru ? ' на $date' : ' as of $date');
    return ru ? 'Источник: $src$onDate' : 'Source: $src$onDate';
  }

  Widget _row(BuildContext context, String code, bool selected, bool ru) {
    final rate = CurrencyService.rateToRub(code);
    final rateLabel = code == 'rub'
        ? (ru ? 'базовая валюта' : 'base currency')
        : '1 ${CurrencyService.symbolOf(code)} = '
            '${rate.toStringAsFixed(rate >= 10 ? 2 : 4)} ₽';

    return InkWell(
      onTap: () => Navigator.pop(context, code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: selected
            ? AppTheme.accentOrange.withOpacity(0.10)
            : Colors.transparent,
        child: Row(
          children: [
            Text(CurrencyService.flag(code),
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        code.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? AppTheme.accentOrange
                              : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          CurrencyService.currencyName(code, russian: ru),
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${CurrencyService.countryName(code, russian: ru)} · $rateLabel',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  size: 18, color: AppTheme.accentOrange),
          ],
        ),
      ),
    );
  }
}
