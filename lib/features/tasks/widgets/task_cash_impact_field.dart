import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/task_cash_impact.dart';

class TaskCashImpactField extends StatefulWidget {
  final TaskCashImpact? initial;
  final ValueChanged<TaskCashImpact?> onChanged;

  const TaskCashImpactField({
    super.key,
    this.initial,
    required this.onChanged,
  });

  @override
  State<TaskCashImpactField> createState() => _TaskCashImpactFieldState();
}

class _TaskCashImpactFieldState extends State<TaskCashImpactField> {
  final _amount = TextEditingController();
  TaskCashDirection? _direction;
  bool _committed = true;
  double _probability = .5;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _direction = value?.direction;
    _committed = value?.committed ?? true;
    _probability = value?.probability ?? .5;
    if (value != null)
      _amount.text =
          value.amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _emit() {
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (_direction == null || amount <= 0) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(TaskCashImpact(
      direction: _direction!,
      amount: amount,
      committed: _committed,
      probability: _committed ? 1 : _probability,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withOpacity(.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 17, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _ru
                      ? 'Денежное влияние для Horizon'
                      : 'Cash impact for Horizon',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
              ),
              if (_direction != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip:
                      _ru ? 'Убрать денежное влияние' : 'Remove cash impact',
                  onPressed: () {
                    setState(() {
                      _direction = null;
                      _amount.clear();
                    });
                    _emit();
                  },
                  icon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
          Text(
            _ru
                ? 'Дата дедлайна задачи становится датой обязательства/ожидаемого поступления. Это не создаёт Treasury-операцию.'
                : 'The task due date becomes the obligation/expected cash date. This does not create a Treasury transaction.',
            style: TextStyle(
                color: AppTheme.textMuted, fontSize: 10.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          SegmentedButton<TaskCashDirection?>(
            segments: [
              ButtonSegment<TaskCashDirection?>(
                value: null,
                label: Text(_ru ? 'Нет' : 'None'),
              ),
              ButtonSegment<TaskCashDirection?>(
                value: TaskCashDirection.income,
                icon: const Icon(Icons.south_west, size: 15),
                label: Text(_ru ? 'Приход' : 'Incoming'),
              ),
              ButtonSegment<TaskCashDirection?>(
                value: TaskCashDirection.expense,
                icon: const Icon(Icons.north_east, size: 15),
                label: Text(_ru ? 'Расход' : 'Outgoing'),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (values) {
              setState(() => _direction = values.first);
              _emit();
            },
          ),
          if (_direction != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _emit(),
              decoration: InputDecoration(
                labelText: _ru
                    ? 'Сумма, ${CurrencyService.symbol}'
                    : 'Amount, ${CurrencyService.symbol}',
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _committed,
              title: Text(_ru
                  ? 'Обязательство / почти точно'
                  : 'Committed / near-certain'),
              subtitle: Text(
                _ru
                    ? 'Выключи для вероятностной надежды: лид, возможный платёж, неподтверждённая покупка.'
                    : 'Turn off for uncertain cash: lead, possible payment or unconfirmed purchase.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
              ),
              onChanged: (value) {
                setState(() => _committed = value);
                _emit();
              },
            ),
            if (!_committed) ...[
              Text(
                _ru
                    ? 'Вероятность: ${(_probability * 100).round()}%'
                    : 'Probability: ${(_probability * 100).round()}%',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              Slider(
                value: _probability,
                min: .05,
                max: .95,
                divisions: 18,
                label: '${(_probability * 100).round()}%',
                onChanged: (value) {
                  setState(() => _probability = value);
                  _emit();
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
