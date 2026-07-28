import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../models/transaction_model.dart';

/// Публичный диалог добавления транзакции (доход/расход)
/// Используется из HomeScreen (быстрые кнопки) и TreasuryScreen
class AddTransactionDialog extends StatefulWidget {
  final TransactionType type;
  final String symbol;

  const AddTransactionDialog({
    super.key,
    required this.type,
    required this.symbol,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late String _category;
  bool _isRecurring = false;
  RecurringPeriod? _recurringPeriod;

  List<String> get _categories => WesiLocale.isRussian
      ? [
          'ПО',
          'Маркетинг',
          'Офис',
          'Зарплаты',
          'Фриланс',
          'Инвестиции',
          'Инфраструктура',
          'Другое'
        ]
      : [
          'Software',
          'Marketing',
          'Office',
          'Salaries',
          'Freelance',
          'Investments',
          'Infrastructure',
          'Other'
        ];

  @override
  void initState() {
    super.initState();
    _category = _categories.last;
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final title = isIncome
        ? (WesiLocale.isRussian ? 'Продажа' : 'Sale')
        : (WesiLocale.isRussian ? 'Трата' : 'Expense');

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(labelText: WesiLocale.get('title')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('amount'),
                prefixText: '${widget.symbol} ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: AppTheme.surface,
              decoration:
                  InputDecoration(labelText: WesiLocale.get('category')),
              items: _categories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(
                                color: AppTheme.textPrimary)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? _categories.last),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                  labelText: WesiLocale.get('description_optional')),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                ),
                Expanded(
                  child: HoverButton(
                    onTap: () {
                      final amount = double.tryParse(_amountCtrl.text);
                      if (_titleCtrl.text.isNotEmpty && amount != null) {
                        final rub = CurrencyService.toRub(amount);
                        Navigator.pop(context, {
                          'title': _titleCtrl.text,
                          'amount': rub,
                          'category': _category,
                          'description': _descCtrl.text,
                          'isRecurring': _isRecurring,
                          'recurringPeriod': _recurringPeriod,
                        });
                      }
                    },
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor:
                        isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                    child: Center(
                      child: Text(WesiLocale.get('save'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
