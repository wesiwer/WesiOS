import 'package:flutter/material.dart';

import '../design/admin_theme.dart';
import '../models/admin_models.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final plans = controller.snapshot?.plans ?? const <AdminPlan>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Тарифы',
                subtitle: 'Базовая цена и доплата за каждое следующее устройство.',
                trailing: FilledButton.icon(
                  onPressed: controller.busy ? null : () => _edit(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новый тариф'),
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
                  child: GlassCard(
                    onTap: () => _edit(context, plan),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: context.palette.connected.withValues(alpha: 0.1),
                          child: Icon(Icons.workspace_premium_outlined, color: context.palette.connected),
                        ),
                        const SizedBox(width: GatewayTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(child: Text(plan.name, style: Theme.of(context).textTheme.titleMedium)),
                                  const SizedBox(width: 8),
                                  Chip(label: Text(plan.enabled ? 'Доступен' : 'Скрыт')),
                                ],
                              ),
                              Text(
                                '${plan.description} · от ${(plan.price('shared', 7, 'base') / 100).toStringAsFixed(0)} ₽',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, [AdminPlan? plan]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PlanEditor(plan: plan),
    );
  }
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({this.plan});

  final AdminPlan? plan;

  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  static const _durations = [7, 30, 90, 180, 365];
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _sortOrder;
  final Map<String, TextEditingController> _prices = {};
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _id = TextEditingController(text: plan?.id ?? '');
    _name = TextEditingController(text: plan?.name ?? '');
    _description = TextEditingController(text: plan?.description ?? '');
    _sortOrder = TextEditingController(text: '${plan?.sortOrder ?? 0}');
    _enabled = plan?.enabled ?? true;
    for (final mode in ['shared', 'dedicated']) {
      for (final duration in _durations) {
        for (final field in ['base', 'extraDevice']) {
          final minor = plan?.price(mode, duration, field) ??
              (mode == 'shared' ? 19900 : 39900);
          _prices['$mode.$duration.$field'] =
              TextEditingController(text: (minor / 100).toStringAsFixed(0));
        }
      }
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _description.dispose();
    _sortOrder.dispose();
    for (final controller in _prices.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'Новый тариф' : 'Настроить тариф'),
      content: SizedBox(
        width: 820,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _text(_id, 'ID', enabled: widget.plan == null)),
                    const SizedBox(width: 12),
                    Expanded(child: _text(_name, 'Название')),
                  ],
                ),
                const SizedBox(height: 12),
                _text(_description, 'Описание', lines: 2),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _text(_sortOrder, 'Порядок', number: true)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        value: _enabled,
                        onChanged: (value) => setState(() => _enabled = value),
                        title: const Text('Показывать клиентам'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Матрица цен, ₽', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _priceTable('shared', 'Общий IP'),
                      const SizedBox(height: 16),
                      _priceTable('dedicated', 'Индивидуальный IP'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Сохраняем…' : 'Сохранить')),
      ],
    );
  }

  Widget _priceTable(String mode, String title) {
    return SizedBox(
      width: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 120, child: Text('Период')),
              const SizedBox(width: 12),
              const SizedBox(width: 280, child: Text('База для 1 устройства')),
              const SizedBox(width: 12),
              const SizedBox(width: 280, child: Text('Доплата за устройство')),
            ],
          ),
          const SizedBox(height: 6),
          for (final duration in _durations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(_durationName(duration))),
                  const SizedBox(width: 12),
                  SizedBox(width: 280, child: _priceField('$mode.$duration.base')),
                  const SizedBox(width: 12),
                  SizedBox(width: 280, child: _priceField('$mode.$duration.extraDevice')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _priceField(String key) => TextFormField(
        controller: _prices[key],
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(suffixText: '₽'),
        validator: (value) {
          final amount = int.tryParse(value ?? '');
          return amount == null || amount < 0 ? 'Введите сумму' : null;
        },
      );

  Widget _text(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool number = false,
    int lines = 1,
  }) =>
      TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: number ? TextInputType.number : null,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        validator: (value) => value == null || value.trim().isEmpty ? 'Обязательное поле' : null,
      );

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _busy = true);
    final pricing = <String, dynamic>{};
    for (final mode in ['shared', 'dedicated']) {
      pricing[mode] = {
        for (final duration in _durations)
          '$duration': {
            'base': int.parse(_prices['$mode.$duration.base']!.text) * 100,
            'extraDevice':
                int.parse(_prices['$mode.$duration.extraDevice']!.text) * 100,
          },
      };
    }
    try {
      await AdminScope.read(context).upsertPlan({
        'id': _id.text.trim(),
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'currency': 'RUB',
        'enabled': _enabled,
        'pricing': pricing,
        'sortOrder': int.tryParse(_sortOrder.text) ?? 0,
      }, id: widget.plan?.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AdminScope.read(context).error ?? 'Не удалось сохранить тариф.')),
        );
      }
    }
  }
}

String _durationName(int days) => switch (days) {
      7 => 'Неделя',
      30 => 'Месяц',
      90 => '3 месяца',
      180 => 'Полгода',
      _ => 'Год',
    };
