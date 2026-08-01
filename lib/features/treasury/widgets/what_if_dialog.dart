import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../../../core/localization/wesi_locale.dart';
import '../models/transaction_model.dart';
import '../services/forecast_engine.dart';

/// Диалог сценария «Что если?» — виртуальное разовое событие и/или
/// процентная корректировка доходов/расходов. Ничего не пишет в базу:
/// возвращает [WhatIfScenario] через Navigator.pop, экран-вызыватель просто
/// передаёт его в следующий [ForecastEngine.generate].
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
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _includeEvent = false;
  TransactionType _eventType = TransactionType.expense;
  late DateTime _eventDate;
  late double _incomeMult;
  late double _expenseMult;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _eventDate = DateTime(today.year, today.month, today.day)
        .add(Duration(days: (widget.forecastDays / 2).round().clamp(1, widget.forecastDays)));
    _incomeMult = widget.initial.incomeMultiplier;
    _expenseMult = widget.initial.expenseMultiplier;
    if (widget.initial.events.isNotEmpty) {
      final e = widget.initial.events.first;
      _includeEvent = true;
      _titleCtrl.text = e.title;
      _amountCtrl.text = e.amount.toStringAsFixed(0);
      _eventType = e.type;
      _eventDate = DateTime(e.date.year, e.date.month, e.date.day);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: start.add(Duration(days: 1)),
      lastDate: start.add(Duration(days: widget.forecastDays)),
      locale: WesiLocale.isRussian ? Locale('ru') : const Locale('en'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppTheme.accentOrange,
            onPrimary: AppTheme.background,
            surface: AppTheme.surface,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  void _apply() {
    final events = <WhatIfEvent>[];
    if (_includeEvent) {
      final amount = double.tryParse(_amountCtrl.text);
      if (_titleCtrl.text.isNotEmpty && amount != null && amount > 0) {
        events.add(WhatIfEvent(
          title: _titleCtrl.text,
          amount: amount,
          type: _eventType,
          date: _eventDate,
        ));
      }
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
      // Отступ сверху на высоту кастомного title bar — кнопки диалога не
      // должны оказаться под системными кнопками окна.
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'what_if'.w,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              SizedBox(height: 6),
              Text(
                'what_if_hint'.w,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Switch(
                    value: _includeEvent,
                    activeColor: AppTheme.accentOrange,
                    onChanged: (v) => setState(() => _includeEvent = v),
                  ),
                  Expanded(
                    child: Text('what_if_add_event'.w,
                        style: TextStyle(color: AppTheme.textPrimary)),
                  ),
                ],
              ),
              if (_includeEvent) ...[
                SizedBox(height: 8),
                TextField(
                  controller: _titleCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                      labelText: 'what_if_event_title'.w),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'amount'.w,
                          prefixText: '${widget.symbol} ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _typeToggle(),
                  ],
                ),
                SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.glassBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month,
                            size: 18, color: AppTheme.textMuted),
                        SizedBox(width: 10),
                        Text(
                          '${'what_if_event_date'.w}: '
                          '${_eventDate.day.toString().padLeft(2, '0')}.'
                          '${_eventDate.month.toString().padLeft(2, '0')}.'
                          '${_eventDate.year}',
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(height: 24),
              _slider(
                label: 'what_if_income_adjust'.w,
                value: _incomeMult,
                min: 0.5,
                max: 1.5,
                color: AppTheme.accentGreen,
                onChanged: (v) => setState(() => _incomeMult = v),
              ),
              SizedBox(height: 12),
              _slider(
                label: 'what_if_expense_adjust'.w,
                value: _expenseMult,
                min: 0.5,
                max: 2.0,
                color: AppTheme.accentRed,
                onChanged: (v) => setState(() => _expenseMult = v),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed: _reset,
                    child: Text('what_if_reset'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('cancel'.w,
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  SizedBox(width: 8),
                  HoverButton(
                    onTap: _apply,
                    padding: EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accentOrange,
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

  Widget _typeToggle() {
    return ToggleButtons(
      isSelected: [
        _eventType == TransactionType.income,
        _eventType == TransactionType.expense,
      ],
      onPressed: (i) => setState(
          () => _eventType = i == 0 ? TransactionType.income : TransactionType.expense),
      borderRadius: BorderRadius.circular(10),
      selectedColor: Colors.white,
      fillColor: _eventType == TransactionType.income
          ? AppTheme.accentGreen
          : AppTheme.accentRed,
      color: AppTheme.textMuted,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      children: const [
        Icon(Icons.add_circle_outline, size: 18),
        Icon(Icons.remove_circle_outline, size: 18),
      ],
    );
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
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary)),
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
