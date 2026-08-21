import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/gateway_theme.dart';
import '../models/commerce_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/wesi_aero_wordmark.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return AmbientBackground(
      reducedMotion: controller.reducedMotion,
      child: SafeArea(
        child: Column(
          children: [
            _Header(embedded: embedded),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  GatewayTokens.space16,
                  GatewayTokens.space16,
                  GatewayTokens.space16,
                  GatewayTokens.space32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 820;
                        final builder = _PlanBuilder(
                          onPay: () => _choosePayment(context),
                        );
                        const aside = _SubscriptionAside();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (controller.license != null) ...[
                              const _ActiveLicenseCard(),
                              const SizedBox(height: GatewayTokens.space16),
                            ],
                            if (controller.catalog?.demo == true) ...[
                              const _DemoBanner(),
                              const SizedBox(height: GatewayTokens.space16),
                            ],
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: builder),
                                  const SizedBox(width: GatewayTokens.space16),
                                  const Expanded(flex: 3, child: aside),
                                ],
                              )
                            else ...[
                              builder,
                              const SizedBox(height: GatewayTokens.space16),
                              aside,
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choosePayment(BuildContext context) async {
    final controller = GatewayScope.read(context);
    final methods = controller.paymentMethods;
    if (methods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Способы оплаты пока не настроены.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<AeroPaymentProvider>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PaymentMethodSheet(methods: methods),
    );
    if (selected == null || !context.mounted) return;
    try {
      final order = await controller.startCheckout(selected);
      final checkoutUrl = order.checkoutUrl;
      if (checkoutUrl != null) {
        final uri = Uri.tryParse(checkoutUrl);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PaymentProgressDialog(),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.commerceError ?? 'Не удалось создать заказ.')),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: GatewayTokens.space16),
      decoration: BoxDecoration(
        color: context.palette.background.withValues(alpha: 0.76),
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          if (embedded) ...[
            IconButton(
              tooltip: 'Назад',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: GatewayTokens.space4),
          ],
          const WesiAeroWordmark(),
          const Spacer(),
          IconButton(
            tooltip: 'Сменить тему',
            onPressed: controller.toggleTheme,
            icon: Icon(
              controller.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanBuilder extends StatelessWidget {
  const _PlanBuilder({required this.onPay});

  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final palette = context.palette;
    final plan = controller.selectedPlan;
    return GlassCard(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Настройте свой Aero', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: GatewayTokens.space8),
          Text(
            'Цена пересчитывается сервером после каждого изменения.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: GatewayTokens.space24),
          if ((controller.catalog?.plans.length ?? 0) > 1) ...[
            DropdownButtonFormField<TariffPlan>(
              initialValue: plan,
              decoration: const InputDecoration(labelText: 'Тариф'),
              items: controller.catalog!.plans
                  .map((item) => DropdownMenuItem(value: item, child: Text(item.name)))
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) controller.setPlan(value);
              },
            ),
            const SizedBox(height: GatewayTokens.space20),
          ],
          const _Label('Тип IP'),
          const SizedBox(height: GatewayTokens.space8),
          SegmentedButton<AeroIpMode>(
            segments: AeroIpMode.values
                .map(
                  (mode) => ButtonSegment(
                    value: mode,
                    label: Text(mode.title),
                    icon: Icon(
                      mode == AeroIpMode.shared
                          ? Icons.hub_outlined
                          : Icons.person_pin_circle_outlined,
                    ),
                  ),
                )
                .toList(growable: false),
            selected: {controller.selectedIpMode},
            onSelectionChanged: (value) => controller.setIpMode(value.first),
          ),
          const SizedBox(height: GatewayTokens.space20),
          const _Label('Количество устройств'),
          const SizedBox(height: GatewayTokens.space8),
          Wrap(
            spacing: GatewayTokens.space8,
            runSpacing: GatewayTokens.space8,
            children: [
              for (var count = 1; count <= 5; count++)
                ChoiceChip(
                  label: Text('$count'),
                  selected: controller.selectedDeviceLimit == count,
                  onSelected: (_) => controller.setDeviceLimit(count),
                ),
            ],
          ),
          const SizedBox(height: GatewayTokens.space20),
          const _Label('Период'),
          const SizedBox(height: GatewayTokens.space8),
          Wrap(
            spacing: GatewayTokens.space8,
            runSpacing: GatewayTokens.space8,
            children: const [7, 30, 90, 180, 365].map((days) {
              return _DurationChip(days: days);
            }).toList(growable: false),
          ),
          const SizedBox(height: GatewayTokens.space24),
          AnimatedContainer(
            duration: GatewayTokens.expressive,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(GatewayTokens.space16),
            decoration: BoxDecoration(
              color: palette.connected.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(GatewayTokens.radiusLarge),
              border: Border.all(color: palette.connected.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Итого', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: GatewayTokens.normal,
                        child: Text(
                          controller.quote?.displayAmount ?? '—',
                          key: ValueKey(controller.quote?.amountMinor),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: palette.connected,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: controller.checkoutBusy || plan == null ? null : onPay,
                  icon: controller.checkoutBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_rounded),
                  label: const Text('Оплатить'),
                ),
              ],
            ),
          ),
          if (controller.commerceError != null) ...[
            const SizedBox(height: GatewayTokens.space12),
            Text(
              controller.commerceError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.danger,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return ChoiceChip(
      label: Text(switch (days) {
        7 => 'Неделя',
        30 => 'Месяц',
        90 => '3 месяца',
        180 => 'Полгода',
        _ => 'Год',
      }),
      selected: controller.selectedDurationDays == days,
      onSelected: (_) => controller.setDurationDays(days),
    );
  }
}

class _SubscriptionAside extends StatelessWidget {
  const _SubscriptionAside();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.key_rounded, color: context.palette.connected, size: 30),
          const SizedBox(height: GatewayTokens.space16),
          Text('Уже есть ключ?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: GatewayTokens.space8),
          Text(
            'Вставьте ключ Wesi Aero. Сервер проверит срок и привяжет это устройство.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: GatewayTokens.space16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _KeyDialog(),
              ),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Вставить ключ'),
            ),
          ),
          const SizedBox(height: GatewayTokens.space24),
          const Divider(),
          const SizedBox(height: GatewayTokens.space16),
          const _Benefit(Icons.devices_rounded, 'Лимит устройств контролирует сервер'),
          const _Benefit(Icons.event_available_rounded, 'Срок истекает автоматически'),
          const _Benefit(Icons.sync_rounded, 'Серверы обновляются без переустановки'),
          const _Benefit(Icons.lock_rounded, 'Команды дополнительно шифруются'),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: context.palette.connected),
          const SizedBox(width: GatewayTokens.space8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ActiveLicenseCard extends StatelessWidget {
  const _ActiveLicenseCard();

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final license = controller.license!;
    return GlassCard(
      color: context.palette.connected.withValues(alpha: 0.07),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: context.palette.connected, size: 30),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Тариф активен', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${license.deviceCount}/${license.deviceLimit} устройств · до '
                  '${_date(license.expiresAt)} · ${license.ipMode.title}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          TextButton(onPressed: controller.removeLicense, child: const Text('Сменить ключ')),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      color: context.palette.warning.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.science_outlined, color: context.palette.warning),
          const SizedBox(width: GatewayTokens.space12),
          const Expanded(
            child: Text(
              'Тестовый режим: СБП и крипта симулируются. Боевые списания отключены.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({required this.methods});

  final List<AeroPaymentMethod> methods;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(GatewayTokens.space8),
      padding: const EdgeInsets.all(GatewayTokens.space16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(GatewayTokens.radiusHero),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Способ оплаты', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: GatewayTokens.space12),
          for (final method in methods)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: context.palette.surfaceRaised,
                child: Icon(
                  method.provider == AeroPaymentProvider.yookassa
                      ? Icons.account_balance_rounded
                      : method.provider == AeroPaymentProvider.cryptoPay
                          ? Icons.currency_bitcoin_rounded
                          : Icons.science_outlined,
                ),
              ),
              title: Text(method.label),
              subtitle: method.testMode ? const Text('Тестовый режим') : null,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, method.provider),
            ),
        ],
      ),
    );
  }
}

class _KeyDialog extends StatefulWidget {
  const _KeyDialog();

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Активировать ключ'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Ключ Wesi Aero',
            hintText: 'WA1-…',
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _activate,
          child: Text(_busy ? 'Проверяем…' : 'Активировать'),
        ),
      ],
    );
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await GatewayScope.read(context).redeemLicenseKey(_controller.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = GatewayScope.read(context).commerceError;
        });
      }
    }
  }
}

class _PaymentProgressDialog extends StatefulWidget {
  const _PaymentProgressDialog();

  @override
  State<_PaymentProgressDialog> createState() => _PaymentProgressDialogState();
}

class _PaymentProgressDialogState extends State<_PaymentProgressDialog> {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    final paid = await GatewayScope.read(context).refreshCheckout();
    _checking = false;
    if (paid && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return AlertDialog(
      title: const Text('Ожидаем подтверждение'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: GatewayTokens.space8),
            const CircularProgressIndicator(),
            const SizedBox(height: GatewayTokens.space24),
            Text(
              controller.isCommerceDemo
                  ? 'Тестовый платёж подтверждается автоматически.'
                  : 'После подтверждения провайдером ключ прикрепится автоматически.',
              textAlign: TextAlign.center,
            ),
            if (controller.commerceError != null) ...[
              const SizedBox(height: GatewayTokens.space12),
              Text(
                controller.commerceError!,
                style: TextStyle(color: context.palette.danger),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Проверить позже'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
