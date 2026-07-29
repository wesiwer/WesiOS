import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../models/transaction_model.dart';

/// Круговые диаграммы «за счёт чего» — отдельно по доходам и по расходам.
///
/// Отвечает на вопрос, который по плоскому списку операций не читается:
/// какие категории дают основную массу денег и куда они уходят.
class CategoryPieSection extends StatefulWidget {
  final List<TransactionModel> transactions;

  const CategoryPieSection({super.key, required this.transactions});

  @override
  State<CategoryPieSection> createState() => _CategoryPieSectionState();
}

class _CategoryPieSectionState extends State<CategoryPieSection> {
  /// Палитра для секторов. Специально не привязана к зелёному/красному:
  /// внутри одной диаграммы все сектора — это одна сторона (доход или
  /// расход), различать нужно категории между собой.
  static const List<Color> _palette = [
    Color(0xFFF97316),
    Color(0xFF38BDF8),
    Color(0xFFC084FC),
    Color(0xFF2DD4BF),
    Color(0xFFFBBF24),
    Color(0xFF84CC16),
    Color(0xFFFB7185),
    Color(0xFF818CF8),
  ];

  /// Сколько категорий показываем по отдельности; остальные сводятся в
  /// «Другое», иначе на диаграмме появляется десяток нечитаемых полосок.
  static const int _maxSlices = 7;

  int? _touchedIncome;
  int? _touchedExpense;

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final income = _breakdown(TransactionType.income);
    final expense = _breakdown(TransactionType.expense);

    if (income.isEmpty && expense.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // На узком экране (телефон) две диаграммы рядом не помещаются.
        final side = constraints.maxWidth < 620;
        final charts = [
          if (income.isNotEmpty)
            _pieCard(
              title: ru ? 'Откуда доходы' : 'Where income comes from',
              data: income,
              touched: _touchedIncome,
              onTouch: (i) => setState(() => _touchedIncome = i),
              accent: AppTheme.accentGreen,
            ),
          if (expense.isNotEmpty)
            _pieCard(
              title: ru ? 'На что расходы' : 'Where money goes',
              data: expense,
              touched: _touchedExpense,
              onTouch: (i) => setState(() => _touchedExpense = i),
              accent: AppTheme.accentRed,
            ),
        ];

        if (side) {
          return Column(
            children: [
              for (final c in charts) ...[c, const SizedBox(height: 12)],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < charts.length; i++) ...[
              Expanded(child: charts[i]),
              if (i != charts.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  /// Суммы по категориям, отсортированные по убыванию, с хвостом в «Другое».
  List<MapEntry<String, double>> _breakdown(TransactionType type) {
    final sums = <String, double>{};
    for (final tx in widget.transactions) {
      if (tx.type != type) continue;
      final key = (tx.category == null || tx.category!.trim().isEmpty)
          ? (WesiLocale.isRussian ? 'Без категории' : 'Uncategorised')
          : tx.category!;
      sums[key] = (sums[key] ?? 0) + tx.amount;
    }
    final entries = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.length <= _maxSlices) return entries;

    final head = entries.take(_maxSlices).toList();
    final tail = entries.skip(_maxSlices);
    final rest = tail.fold<double>(0, (sum, e) => sum + e.value);
    head.add(MapEntry(WesiLocale.isRussian ? 'Другое' : 'Other', rest));
    return head;
  }

  Widget _pieCard({
    required String title,
    required List<MapEntry<String, double>> data,
    required int? touched,
    required ValueChanged<int?> onTouch,
    required Color accent,
  }) {
    final total = data.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: accent)),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${WesiLocale.isRussian ? 'Всего' : 'Total'}: '
            '${CurrencyService.format(total)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response?.touchedSection == null) {
                      onTouch(null);
                      return;
                    }
                    onTouch(response!.touchedSection!.touchedSectionIndex);
                  },
                ),
                sections: [
                  for (int i = 0; i < data.length; i++)
                    PieChartSectionData(
                      value: data[i].value,
                      color: _palette[i % _palette.length],
                      // Подпись только у выделенного сектора: подписи на всех
                      // сразу на маленькой диаграмме сливаются в кашу.
                      title: touched == i
                          ? '${(data[i].value / total * 100).toStringAsFixed(0)}%'
                          : '',
                      radius: touched == i ? 62 : 54,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(data.length, (i) {
            final share = data[i].value / total * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: _palette[i % _palette.length],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data[i].key,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${share.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    CurrencyService.format(data[i].value),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
