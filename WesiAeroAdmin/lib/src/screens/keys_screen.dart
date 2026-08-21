import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/admin_theme.dart';
import '../models/admin_models.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class KeysScreen extends StatelessWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final licenses = controller.snapshot?.licenses ?? const <AdminLicense>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Ключи доступа',
                subtitle: '${licenses.length} создано · ключи зашифрованы в базе',
                trailing: FilledButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (_) => const _GenerateKeyDialog(),
                          ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Сгенерировать'),
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              if (licenses.isEmpty)
                const GlassCard(child: Text('Ключей пока нет.'))
              else
                ...licenses.map(
                  (license) => Padding(
                    padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
                    child: _LicenseCard(license: license),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.license});

  final AdminLicense license;

  @override
  Widget build(BuildContext context) {
    final color = license.active ? context.palette.connected : context.palette.danger;
    return GlassCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(license.active ? Icons.key_rounded : Icons.key_off_rounded, color: color),
          ),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(license.maskedKey, style: Theme.of(context).textTheme.titleMedium),
                    Chip(label: Text(license.source == 'admin' ? 'Бесплатный' : 'Оплачен')),
                    Chip(label: Text(license.active ? 'Активен' : 'Недействителен')),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${license.ipMode == 'dedicated' ? 'Индивидуальный' : 'Общий'} IP · '
                  '${license.deviceCount}/${license.deviceLimit} устройств · '
                  'до ${_date(license.expiresAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Скопировать ключ',
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_rounded),
          ),
          if (license.active)
            IconButton(
              tooltip: 'Отозвать',
              onPressed: () => _revoke(context),
              icon: const Icon(Icons.block_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    try {
      final key = await AdminScope.read(context).revealLicenseKey(license.id);
      await Clipboard.setData(ClipboardData(text: key));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ключ скопирован.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AdminScope.read(context).error ?? 'Не удалось получить ключ.')),
        );
      }
    }
  }

  Future<void> _revoke(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отозвать ключ?'),
        content: const Text('Все активные сессии этого ключа будут завершены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отозвать')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AdminScope.read(context).revokeLicense(license.id);
    }
  }
}

class _GenerateKeyDialog extends StatefulWidget {
  const _GenerateKeyDialog();

  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  String? _planId;
  String _ipMode = 'shared';
  int _devices = 1;
  int _duration = 30;
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final plans = AdminScope.read(context).snapshot?.plans ?? const <AdminPlan>[];
    if (_planId == null && plans.isNotEmpty) _planId = plans.first.id;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plans = AdminScope.of(context).snapshot?.plans ?? const <AdminPlan>[];
    return AlertDialog(
      title: const Text('Бесплатный ключ'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _planId,
              decoration: const InputDecoration(labelText: 'Тариф'),
              items: plans
                  .map((plan) => DropdownMenuItem(value: plan.id, child: Text(plan.name)))
                  .toList(growable: false),
              onChanged: (value) => setState(() => _planId = value),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'shared', label: Text('Общий IP')),
                ButtonSegment(value: 'dedicated', label: Text('Индивидуальный')),
              ],
              selected: {_ipMode},
              onSelectionChanged: (value) => setState(() => _ipMode = value.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _devices,
              decoration: const InputDecoration(labelText: 'Устройств'),
              items: [1, 2, 3, 4, 5]
                  .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
                  .toList(growable: false),
              onChanged: (value) => setState(() => _devices = value ?? 1),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: const InputDecoration(labelText: 'Период'),
              items: const {
                7: 'Неделя',
                30: 'Месяц',
                90: '3 месяца',
                180: 'Полгода',
                365: 'Год',
              }
                  .entries
                  .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                  .toList(growable: false),
              onChanged: (value) => setState(() => _duration = value ?? 30),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Заметка'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _generate, child: Text(_busy ? 'Создаём…' : 'Создать')),
      ],
    );
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final key = await AdminScope.read(context).generateLicense(
        planId: _planId,
        ipMode: _ipMode,
        deviceLimit: _devices,
        durationDays: _duration,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (_) => _GeneratedKeyDialog(keyValue: key),
      );
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _GeneratedKeyDialog extends StatelessWidget {
  const _GeneratedKeyDialog({required this.keyValue});

  final String keyValue;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ключ готов'),
        content: SelectableText(keyValue),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: keyValue));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Скопировать'),
          ),
        ],
      );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
