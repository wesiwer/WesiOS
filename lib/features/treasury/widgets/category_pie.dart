import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/transaction_model.dart';

/// Один сектор диаграммы вместе с тем, из чего он состоит.
class _Slice {
  final String label;
  final double value;
  final List<TransactionModel> items;

  const _Slice(this.label, this.value, this.items);
}

/// Диаграммы по истории операций: доходы, расходы и общее сравнение.
///
/// Три отдельных разреза, а не один: смешивать поступления с тратами в одном
/// круге бессмысленно — доли считались бы от суммы разнородных чисел. Общая
/// диаграмма отвечает на другой вопрос, «сколько пришло против того, сколько
/// ушло», поэтому у неё всего два сектора.
///
/// Диаграммы интерактивные, с детализацией: верхний уровень — категории, тап
/// по сектору разворачивает его в конкретные операции внутри категории.
/// Повторный тап (или кнопка «Категории») возвращает наверх.
class CategoryPieSection extends StatefulWidget {
  final List<TransactionModel> transactions;

  const CategoryPieSection({super.key, required this.transactions});

  @override
  State<CategoryPieSection> createState() => _CategoryPieSectionState();
}

class _CategoryPieSectionState extends State<CategoryPieSection> {
  /// Палитра секторов: достаточно контрастная, чтобы соседние доли не
  /// сливались. Цвет закреплён за позицией, а не за смыслом.
  static const List<Color> _palette = [
    Color(0xFFF97316),
    Color(0xFF38BDF8),
    Color(0xFF34D399),
    Color(0xFFA78BFA),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFF60A5FA),
    Color(0xFF94A3B8),
  ];

  /// Сколько позиций показываем до того, как схлопнуть хвост в «Другое».
  static const int _topN = 7;

  /// Развёрнутая категория для каждой диаграммы (null — верхний уровень).
  String? _drillIncome;
  String? _drillExpense;

  /// Подсвеченный тапом сектор — влияет только на подпись в центре.
  int _touchedIncome = -1;
  int _touchedExpense = -1;
  int _touchedTotal = -1;

  bool get _ru => WesiLocale.isRussian;

  List<TransactionModel> _of(TransactionType type) =>
      widget.transactions.where((t) => t.type == type).toList();

  List<_Slice> _group(
    List<TransactionModel> txs,
    String Function(TransactionModel) keyOf,
    String fallback,
  ) {
    final byKey = <String, List<TransactionModel>>{};
    for (final t in txs) {
      final raw = keyOf(t).trim();
      (byKey[raw.isEmpty ? fallback : raw] ??= []).add(t);
    }

    final slices = byKey.entries
        .map((e) => _Slice(
              e.key,
              e.value.fold<double>(0, (s, t) => s + t.amount),
              e.value,
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (slices.length <= _topN) return slices;

    final head = slices.take(_topN).toList();
    final tail = slices.skip(_topN).toList();
    head.add(_Slice(
      _ru ? 'Другое' : 'Other',
      tail.fold<double>(0, (s, x) => s + x.value),
      tail.expand((x) => x.items).toList(),
    ));
    return head;
  }

  /// Верхний уровень — по категориям.
  List<_Slice> _categorySlices(List<TransactionModel> txs) => _group(
        txs,
        (t) => t.category ?? '',
        _ru ? 'Без категории' : 'Uncategorised',
      );

  /// Второй уровень — операции внутри категории. Одинаковые названия
  /// объединяются: десять одинаковых подписок иначе дали бы десять
  /// неразличимых секторов вместо одного заметного.
  List<_Slice> _detailSlices(List<TransactionModel> items) => _group(
        items,
        (t) => t.title,
        _ru ? 'Без названия' : 'Untitled',
      );

  @override
  Widget build(BuildContext context) {
    final income = _of(TransactionType.income);
    final expense = _of(TransactionType.expense);
    if (income.isEmpty && expense.isEmpty) return SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 620;
        final incomeCard = _pieCard(
          title: _ru ? 'Доходы' : 'Income',
          accent: AppTheme.accentGreen,
          txs: income,
          drill: _drillIncome,
          onDrill: (v) => setState(() {
            _drillIncome = v;
            _touchedIncome = -1;
          }),
          touched: _touchedIncome,
          onTouch: (i) => setState(() => _touchedIncome = i),
        );
        final expenseCard = _pieCard(
          title: _ru ? 'Расходы' : 'Expenses',
          accent: AppTheme.accentRed,
          txs: expense,
          drill: _drillExpense,
          onDrill: (v) => setState(() {
            _drillExpense = v;
            _touchedExpense = -1;
          }),
          touched: _touchedExpense,
          onTouch: (i) => setState(() => _touchedExpense = i),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              incomeCard,
              const SizedBox(height: 14),
              expenseCard,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: incomeCard),
                  const SizedBox(width: 14),
                  Expanded(child: expenseCard),
                ],
              ),
            const SizedBox(height: 14),
            _totalCard(income, expense),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }

  Widget _pieCard({
    required String title,
    required Color accent,
    required List<TransactionModel> txs,
    required String? drill,
    required ValueChanged<String?> onDrill,
    required int touched,
    required ValueChanged<int> onTouch,
  }) {
    if (txs.isEmpty) {
      return _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(title, accent, null, onDrill),
            SizedBox(height: 14),
            Text(
              _ru ? 'Операций пока нет' : 'No operations yet',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    final categories = _categorySlices(txs);
    _Slice? drilled;
    for (final s in categories) {
      if (s.label == drill) drilled = s;
    }
    final slices = drilled == null ? categories : _detailSlices(drilled.items);
    final total = slices.fold<double>(0, (s, x) => s + x.value);

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(title, accent, drilled?.label, onDrill),
          SizedBox(height: 4),
          Text(
            drilled == null
                ? (_ru
                    ? 'Нажмите на сектор, чтобы раскрыть категорию'
                    : 'Tap a slice to break the category down')
                : (_ru
                    ? 'Внутри категории «${drilled.label}»'
                    : 'Inside “${drilled.label}”'),
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 46,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final index =
                            response?.touchedSection?.touchedSectionIndex ?? -1;
                        if (event is FlTapUpEvent && index >= 0) {
                          if (drilled == null) {
                            // Разворачиваем только то, что реально делится:
                            // категория из одной операции внутри выглядела бы
                            // как тот же круг целиком.
                            if (slices[index].items.length > 1) {
                              onDrill(slices[index].label);
                            }
                          } else {
                            onDrill(null);
                          }
                          return;
                        }
                        onTouch(index);
                      },
                    ),
                    sections: List.generate(slices.length, (i) {
                      final s = slices[i];
                      final share = total == 0 ? 0.0 : s.value / total;
                      return PieChartSectionData(
                        value: s.value,
                        color: _palette[i % _palette.length],
                        radius: i == touched ? 32 : 26,
                        // Подпись только у заметных долей: на узких секторах
                        // проценты налезают друг на друга.
                        showTitle: share >= 0.08,
                        title: '${(share * 100).round()}%',
                        titleStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CurrencyService.format(total),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(
                        touched >= 0 && touched < slices.length
                            ? slices[touched].label
                            : '${slices.length} ${_ru ? 'позиций' : 'items'}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(slices.length, (i) {
            final s = slices[i];
            final expandable = drilled == null && s.items.length > 1;
            return _legendRow(
              color: _palette[i % _palette.length],
              label: s.label,
              share: total == 0 ? 0 : s.value / total,
              value: s.value,
              expandable: expandable,
              onTap: expandable ? () => onDrill(s.label) : null,
            );
          }),
        ],
      ),
    );
  }

  /// Общая диаграмма — сравнение «пришло / ушло» и чистый результат.
  Widget _totalCard(
      List<TransactionModel> income, List<TransactionModel> expense) {
    final incomeSum = income.fold<double>(0, (s, t) => s + t.amount);
    final expenseSum = expense.fold<double>(0, (s, t) => s + t.amount);
    final total = incomeSum + expenseSum;
    if (total == 0) return SizedBox.shrink();

    final net = incomeSum - expenseSum;
    final slices = <(String, double, Color)>[
      (_ru ? 'Доходы' : 'Income', incomeSum, AppTheme.accentGreen),
      (_ru ? 'Расходы' : 'Expenses', expenseSum, AppTheme.accentRed),
    ];

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows,
                  size: 17, color: AppTheme.textMuted),
              SizedBox(width: 8),
              Text(
                _ru ? 'Доходы против расходов' : 'Income vs expenses',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 44,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) => setState(() =>
                          _touchedTotal =
                              response?.touchedSection?.touchedSectionIndex ??
                                  -1),
                    ),
                    sections: List.generate(slices.length, (i) {
                      final s = slices[i];
                      final share = s.$2 / total;
                      return PieChartSectionData(
                        value: s.$2,
                        color: s.$3,
                        radius: i == _touchedTotal ? 30 : 24,
                        showTitle: share >= 0.08,
                        title: '${(share * 100).round()}%',
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CurrencyService.format(net),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: net >= 0
                            ? AppTheme.accentGreen
                            : AppTheme.accentRed,
                      ),
                    ),
                    Text(
                      _ru ? 'чистый' : 'net',
                      style: TextStyle(
                          fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < slices.length; i++)
            _legendRow(
              color: slices[i].$3,
              label: slices[i].$1,
              share: slices[i].$2 / total,
              value: slices[i].$2,
            ),
        ],
      ),
    );
  }

  Widget _cardHeader(
    String title,
    Color accent,
    String? drilled,
    ValueChanged<String?> onDrill,
  ) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
        ),
        if (drilled != null)
          TextButton.icon(
            onPressed: () => onDrill(null),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.arrow_back,
                size: 14, color: AppTheme.accentOrange),
            label: Text(
              _ru ? 'Категории' : 'Categories',
              style:
                  TextStyle(fontSize: 11, color: AppTheme.accentOrange),
            ),
          ),
      ],
    );
  }

  Widget _legendRow({
    required Color color,
    required String label,
    required double share,
    required double value,
    bool expandable = false,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          if (expandable) ...[
            Icon(Icons.unfold_more, size: 13, color: AppTheme.textMuted),
            SizedBox(width: 6),
          ],
          Text(
            '${(share * 100).round()}%',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted),
          ),
          SizedBox(width: 10),
          Text(
            CurrencyService.format(value),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }

  Widget _shell({required Widget child}) => Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.32),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );
}
