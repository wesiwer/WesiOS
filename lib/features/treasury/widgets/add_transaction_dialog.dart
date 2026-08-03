import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../models/transaction_model.dart';
import '../services/category_service.dart';
import 'category_editor_dialog.dart';

/// Публичный диалог добавления/редактирования транзакции (доход/расход)
/// Используется из HomeScreen (быстрые кнопки), TreasuryScreen и OperationsScreen.
///
/// [initial] != null — режим редактирования: поля предзаполняются,
/// заголовок меняется на «Редактировать операцию».
class AddTransactionDialog extends StatefulWidget {
  final TransactionType type;
  final String symbol;
  final TransactionModel? initial;

  const AddTransactionDialog({
    super.key,
    required this.type,
    required this.symbol,
    this.initial,
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
  DateTime _selectedDate = DateTime.now();

  /// Категории берутся из [CategoryService] — их можно править прямо
  /// отсюда, а не только менять код.
  /// Категории именно этого типа операции — у доходов и расходов
  /// наборы разные.
  List<String> get _categories => CategoryService.forType(widget.type);

  @override
  void initState() {
    super.initState();
    final tx = widget.initial;
    if (tx != null) {
      _titleCtrl.text = tx.title;
      // amount хранится в RUB-эквиваленте — показываем в текущей валюте
      _amountCtrl.text = _trimZeros(CurrencyService.fromRub(tx.amount));
      _descCtrl.text = tx.description ?? '';
      _isRecurring = tx.isRecurring;
      _recurringPeriod = tx.recurringPeriod;
      _selectedDate = tx.date;
      final cat = tx.category;
      _category =
          (cat != null && _categories.contains(cat)) ? cat : _categories.last;
    } else {
      _category = _categories.last;
    }
  }

  static String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.accent,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = DateTime(d.year, d.month, d.day);
    if (picked == today) {
      return WesiLocale.isRussian ? 'Сегодня' : 'Today';
    }
    final diff = picked.difference(today).inDays;
    if (diff == 1) return WesiLocale.isRussian ? 'Завтра' : 'Tomorrow';
    if (diff == -1) return WesiLocale.isRussian ? 'Вчера' : 'Yesterday';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final title = widget.initial != null
        ? WesiLocale.get('edit_operation')
        : isIncome
            ? (WesiLocale.isRussian ? 'Доход' : 'Income')
            : (WesiLocale.isRussian ? 'Трата' : 'Expense');

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // Отступ сверху на высоту кастомного title bar — иначе кнопки диалога
      // оказываются под системными кнопками окна (свернуть/закрыть).
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: Container(
        width: 400,
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(labelText: WesiLocale.get('title')),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('amount'),
                prefixText: '${widget.symbol} ',
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // Категорию могли переименовать/удалить, пока диалог был
                    // открыт в другом месте — тогда value не найдётся в items
                    // и Dropdown упадёт. Подстраховываемся значением из списка.
                    value: _categories.contains(_category)
                        ? _category
                        : _categories.last,
                    dropdownColor: AppTheme.surface,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: WesiLocale.get('category')),
                    items: _categories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppTheme.textPrimary)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _category = v ?? _categories.last),
                  ),
                ),
                IconButton(
                  tooltip: WesiLocale.isRussian
                      ? 'Изменить категории'
                      : 'Edit categories',
                  icon: Icon(Icons.tune,
                      size: 18, color: AppTheme.accent),
                  onPressed: () async {
                    await CategoryEditorDialog.show(context, widget.type);
                    if (!mounted) return;
                    setState(() {
                      if (!_categories.contains(_category)) {
                        _category = _categories.last;
                      }
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                  labelText: WesiLocale.get('description_optional')),
            ),
            SizedBox(height: 12),
            // Выбор даты транзакции
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _formatDate(_selectedDate),
                        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                      ),
                    ),
                    if (_selectedDate.isAfter(DateTime.now().add(const Duration(days: 1))))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          WesiLocale.isRussian ? 'Запланировано' : 'Planned',
                          style: TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: TextStyle(color: AppTheme.textMuted)),
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
                          'date': _selectedDate,
                        });
                      }
                    },
                    padding: EdgeInsets.symmetric(vertical: 14),
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
