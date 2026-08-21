import 'package:flutter/material.dart';

import '../design/admin_theme.dart';
import '../models/admin_models.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final snapshot = controller.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                title: 'Оплаты',
                subtitle: 'Подтверждение только через webhook или сверку с провайдером.',
              ),
              const SizedBox(height: GatewayTokens.space24),
              _ProviderSettings(
                settings: snapshot.paymentSettings,
                secrets: controller.paymentSecrets,
              ),
              const SizedBox(height: GatewayTokens.space24),
              Text('Операции', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              if (snapshot.payments.isEmpty)
                const GlassCard(child: Text('Платежей пока нет.'))
              else
                ...snapshot.payments.map(
                  (payment) => Padding(
                    padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
                    child: _PaymentCard(payment: payment),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderSettings extends StatelessWidget {
  const _ProviderSettings({required this.settings, required this.secrets});

  final List<AdminPaymentSetting> settings;
  final Map<String, dynamic> secrets;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Способы оплаты', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: GatewayTokens.space8),
          for (var index = 0; index < settings.length; index++) ...[
            _ProviderRow(setting: settings[index], configured: _configured(settings[index].provider)),
            if (index != settings.length - 1) const Divider(height: 24),
          ],
          const SizedBox(height: GatewayTokens.space12),
          Container(
            padding: const EdgeInsets.all(GatewayTokens.space12),
            decoration: BoxDecoration(
              color: context.palette.surfaceRaised.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_rounded, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shop ID, secret key и Crypto Pay token задаются только в окружении сервера. '
                    'Admin API никогда их не возвращает.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _configured(String provider) => switch (provider) {
        'yookassa' => secrets['yookassa'] == true,
        'crypto_pay' => secrets['cryptoPay'] == true,
        _ => secrets['mockAllowed'] == true,
      };
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.setting, required this.configured});

  final AdminPaymentSetting setting;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: context.palette.surfaceRaised,
          child: Icon(_icon(setting.provider)),
        ),
        const SizedBox(width: GatewayTokens.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                setting.publicConfig['label'] as String? ?? _label(setting.provider),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                configured
                    ? (setting.testMode ? 'Секрет задан · тестовый режим' : 'Секрет задан · боевой режим')
                    : 'Серверный секрет не задан',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (setting.provider != 'mock')
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(label: Text(setting.testMode ? 'TEST' : 'LIVE')),
          ),
        Switch(
          value: setting.enabled,
          onChanged: controller.busy
              ? null
              : (value) => controller.updatePaymentSetting(
                    provider: setting.provider,
                    enabled: value,
                    testMode: setting.testMode,
                    label: setting.publicConfig['label'] as String? ?? _label(setting.provider),
                  ),
        ),
        IconButton(
          tooltip: 'Настроить',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _ProviderEditor(setting: setting),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }
}

class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({required this.setting});

  final AdminPaymentSetting setting;

  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  late final TextEditingController _label;
  late bool _enabled;
  late bool _test;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(
      text: widget.setting.publicConfig['label'] as String? ?? _labelFor(widget.setting.provider),
    );
    _enabled = widget.setting.enabled;
    _test = widget.setting.testMode;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_labelFor(widget.setting.provider)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _label, decoration: const InputDecoration(labelText: 'Название в клиенте')),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: const Text('Включить способ оплаты'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.setting.provider != 'mock')
                SwitchListTile(
                  value: _test,
                  onChanged: (value) => setState(() => _test = value),
                  title: const Text('Тестовый режим'),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await AdminScope.read(context).updatePaymentSetting(
                        provider: widget.setting.provider,
                        enabled: _enabled,
                        testMode: _test,
                        label: _label.text.trim(),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('Сохранить'),
          ),
        ],
      );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final AdminPayment payment;

  @override
  Widget build(BuildContext context) {
    final paid = payment.status == 'paid';
    final color = paid ? context.palette.connected : context.palette.warning;
    return GlassCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(paid ? Icons.verified_rounded : Icons.schedule_rounded, color: color),
          ),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_label(payment.provider)} · ${(payment.amountMinor / 100).toStringAsFixed(0)} ₽',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${payment.status.toUpperCase()} · ${payment.durationDays} дней · '
                  '${payment.deviceLimit} устр. · ${_date(payment.createdAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (payment.status == 'pending')
            OutlinedButton.icon(
              onPressed: AdminScope.of(context).busy
                  ? null
                  : () => payment.provider == 'mock'
                      ? AdminScope.read(context).confirmMockPayment(payment.id)
                      : AdminScope.read(context).reconcilePayment(payment.id),
              icon: Icon(payment.provider == 'mock' ? Icons.science_outlined : Icons.sync_rounded),
              label: Text(payment.provider == 'mock' ? 'Подтвердить тест' : 'Сверить'),
            ),
        ],
      ),
    );
  }
}

IconData _icon(String provider) => switch (provider) {
      'yookassa' => Icons.account_balance_rounded,
      'crypto_pay' => Icons.currency_bitcoin_rounded,
      _ => Icons.science_outlined,
    };

String _label(String provider) => _labelFor(provider);

String _labelFor(String provider) => switch (provider) {
      'yookassa' => 'СБП · ЮKassa',
      'crypto_pay' => 'Crypto Pay',
      _ => 'Тестовая оплата',
    };

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
