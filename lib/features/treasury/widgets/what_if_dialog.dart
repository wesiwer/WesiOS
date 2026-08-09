import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/transaction_model.dart';
import '../services/forecast_engine.dart';

class WhatIfDialog extends StatefulWidget {
  final WhatIfScenario initial;
  final int forecastDays;
  final String symbol;

  const WhatIfDialog({
    super.key,
    required this.initial,
    required this.forecastDays,
    required this.symbol,
  });

  @override
  State<WhatIfDialog> createState() => _WhatIfDialogState();
}

class _WhatIfDialogState extends State<WhatIfDialog> {
  late double _incomeMult;
  late double _expenseMult;
  final List<_VirtualOperationDraft> _operations = [];

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _incomeMult = widget.initial.incomeMultiplier;
    _expenseMult = widget.initial.expenseMultiplier;
    for (final event in widget.initial.events) {
      _operations.add(_VirtualOperationDraft.fromEvent(event));
    }
  }

  @override
  void dispose() {
    for (final operation in _operations) {
      operation.dispose();
    }
    super.dispose();
  }

  void _addOperation() {
    final now = DateTime.now();
    setState(() {
      _operations.add(
        _VirtualOperationDraft(
          date: DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 1)),
        ),
      );
    });
  }

  void _removeOperation(int index) {
    final value = _operations.removeAt(index);
    value.dispose();
    setState(() {});
  }

  void _apply() {
    final events = <WhatIfEvent>[];
    for (final operation in _operations) {
      final amount = double.tryParse(
        operation.amount.text.trim().replaceAll(',', '.'),
      );
      final title = operation.title.text.trim();
      if (title.isEmpty || amount == null || amount <= 0) continue;
      events.add(
        WhatIfEvent(
          title: title,
          amount: amount,
          type: operation.type,
          date: operation.date,
          recurringPeriod: operation.recurringPeriod,
        ),
      );
    }
    Navigator.pop(
      context,
      WhatIfScenario(
        events: events,
        incomeMultiplier: _incomeMult,
        expenseMultiplier: _expenseMult,
      ),
    );
  }

  void _reset() => Navigator.pop(context, WhatIfScenario.none);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(20, kTitleBarHeight + 20, 20, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'what_if'.w,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _ru
                    ? 'Добавьте виртуальные доходы и траты: один раз или по расписанию. Реальные операции не изменятся.'
                    : 'Add virtual income and expenses once or on a schedule. Real operations stay untouched.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _ru ? 'Виртуальные операции' : 'Virtual operations',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addOperation,
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(_ru ? 'Добавить' : 'Add'),
                  ),
                ],
              ),
              if (_operations.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Text(
                    _ru
                        ? 'Например: инвестиции +10 000 ₽ каждый месяц, аренда −50 000 ₽ ежемесячно или разовая покупка.'
                        : 'For example: +10,000 monthly investment, −50,000 monthly rent, or a one-time purchase.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppTheme.textMuted,
                    ),
                  ),
                )
              else
                for (var i = 0; i < _operations.length; i++) ...[
                  _operationCard(i, _operations[i]),
                  if (i + 1 < _operations.length) const SizedBox(height: 10),
                ],
              const SizedBox(height: 22),
              _slider(
                label: 'what_if_income_adjust'.w,
                value: _incomeMult,
                min: 0.5,
                max: 1.5,
                color: AppTheme.accentGreen,
                onChanged: (v) => setState(() => _incomeMult = v),
              ),
              const SizedBox(height: 12),
              _slider(
                label: 'what_if_expense_adjust'.w,
                value: _expenseMult,
                min: 0.5,
                max: 2.0,
                color: AppTheme.accentRed,
                onChanged: (v) => setState(() => _expenseMult = v),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: _reset,
                    child: Text('what_if_reset'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('cancel'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  HoverButton(
                    onTap: _apply,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accent,
                    child: Text('what_if_apply'.w,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _operationCard(int index, _VirtualOperationDraft operation) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: operation.title,
                  decoration: InputDecoration(
                    labelText: _ru ? 'Название' : 'Title',
                    hintText: _ru ? 'Инвестиции' : 'Investment',
                  ),
                ),
              ),
              IconButton(
                tooltip: _ru ? 'Удалить' : 'Delete',
                onPressed: () => _removeOperation(index),
                icon: Icon(Icons.delete_outline, color: AppTheme.accentRed),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: operation.amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'amount'.w,
                    prefixText: '${widget.symbol} ',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ToggleButtons(
                isSelected: [
                  operation.type == TransactionType.income,
                  operation.type == TransactionType.expense,
                ],
                onPressed: (value) => setState(() {
                  operation.type = value == 0
                      ? TransactionType.income
                      : TransactionType.expense;
                }),
                borderRadius: BorderRadius.circular(10),
                selectedColor: Colors.white,
                fillColor: operation.type == TransactionType.income
                    ? AppTheme.accentGreen
                    : AppTheme.accentRed,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                children: const [
                  Icon(Icons.add_circle_outline, size: 18),
                  Icon(Icons.remove_circle_outline, size: 18),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickOperationDate(operation),
                  icon: const Icon(Icons.calendar_month, size: 17),
                  label: Text(
                    '${operation.date.day.toString().padLeft(2, '0')}.'
                    '${operation.date.month.toString().padLeft(2, '0')}.'
                    '${operation.date.year}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<RecurringPeriod?>(
                  value: operation.recurringPeriod,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: _ru ? 'Повтор' : 'Repeat'),
                  items: [
                    DropdownMenuItem<RecurringPeriod?>(
                      value: null,
                      child: Text(_ru ? 'Один раз' : 'Once'),
                    ),
                    for (final period in RecurringPeriod.values)
                      DropdownMenuItem<RecurringPeriod?>(
                        value: period,
                        child: Text(_periodLabel(period)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => operation.recurringPeriod = value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickOperationDate(_VirtualOperationDraft operation) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(Duration(days: widget.forecastDays));
    var initial = operation.date;
    if (initial.isBefore(start)) initial = start;
    if (initial.isAfter(end)) initial = end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: end,
      locale: _ru ? const Locale('ru') : const Locale('en'),
    );
    if (picked != null) setState(() => operation.date = picked);
  }

  String _periodLabel(RecurringPeriod value) {
    if (_ru) {
      return switch (value) {
        RecurringPeriod.daily => 'Каждый день',
        RecurringPeriod.weekly => 'Каждую неделю',
        RecurringPeriod.monthly => 'Каждый месяц',
        RecurringPeriod.yearly => 'Каждый год',
      };
    }
    return switch (value) {
      RecurringPeriod.daily => 'Daily',
      RecurringPeriod.weekly => 'Weekly',
      RecurringPeriod.monthly => 'Monthly',
      RecurringPeriod.yearly => 'Yearly',
    };
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final pct = ((value - 1.0) * 100).round();
    final pctLabel = pct == 0 ? '0%' : (pct > 0 ? '+$pct%' : '$pct%');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
            Text(pctLabel,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: AppTheme.glassBorder,
            overlayColor: color.withOpacity(0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _VirtualOperationDraft {
  final TextEditingController title;
  final TextEditingController amount;
  TransactionType type;
  DateTime date;
  RecurringPeriod? recurringPeriod;

  _VirtualOperationDraft({
    String title = '',
    String amount = '',
    this.type = TransactionType.expense,
    required this.date,
    this.recurringPeriod,
  })  : title = TextEditingController(text: title),
        amount = TextEditingController(text: amount);

  factory _VirtualOperationDraft.fromEvent(WhatIfEvent event) =>
      _VirtualOperationDraft(
        title: event.title,
        amount: event.amount.toStringAsFixed(event.amount % 1 == 0 ? 0 : 2),
        type: event.type,
        date: event.date,
        recurringPeriod: event.recurringPeriod,
      );

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}
