import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/account_model.dart';
import '../services/account_liquidity_service.dart';

/// Migration-free liquidity-location settings for one Treasury account.
class AccountLiquidityDialog extends StatefulWidget {
  final AccountModel account;
  final AccountLiquidityMeta initial;

  const AccountLiquidityDialog({
    super.key,
    required this.account,
    required this.initial,
  });

  static Future<void> show(BuildContext context, AccountModel account) async {
    final meta = await AccountLiquidityService.forAccount(account);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AccountLiquidityDialog(account: account, initial: meta),
    );
  }

  @override
  State<AccountLiquidityDialog> createState() => _AccountLiquidityDialogState();
}

class _AccountLiquidityDialogState extends State<AccountLiquidityDialog> {
  late String _currency;
  late bool _allowNetting;
  late double _haircut;
  late final TextEditingController _minimum;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _currency = widget.initial.currency;
    _allowNetting = widget.initial.allowNetting;
    _haircut = widget.initial.fxHaircut;
    _minimum = TextEditingController(
      text: widget.initial.minimumBalanceRub == 0
          ? ''
          : widget.initial.minimumBalanceRub.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _minimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(_ru
          ? 'Ликвидность · ${widget.account.name}'
          : 'Liquidity · ${widget.account.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ru
                    ? 'Horizon оценивает не только общий баланс, но и риск остаться без денег именно на нужном счёте.'
                    : 'Horizon evaluates not only total cash, but the risk of running out at the location where money is actually needed.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                    labelText:
                        _ru ? 'Валюта ликвидности' : 'Liquidity currency'),
                items: CurrencyService.currencies.keys
                    .map((code) => DropdownMenuItem(
                          value: code,
                          child: Text(
                            '${CurrencyService.flag(code)} ${code.toUpperCase()} · ${CurrencyService.currencyName(code, russian: _ru)}',
                          ),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _currency = value ?? 'rub'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _minimum,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _ru
                      ? 'Неснижаемый остаток, ₽-экв.'
                      : 'Minimum local liquidity, RUB eq.',
                  helperText: _ru
                      ? 'Ниже этой суммы Horizon считает локальный дефицит.'
                      : 'Below this level Horizon flags a local shortfall.',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _allowNetting,
                onChanged: (v) => setState(() => _allowNetting = v),
                title: Text(_ru
                    ? 'Разрешить покрытие с других счетов'
                    : 'Allow netting from other accounts'),
                subtitle: Text(
                  _ru
                      ? 'Если выключено, Horizon не считает деньги в других местах доступными для спасения этого счёта.'
                      : 'When off, Horizon does not treat cash elsewhere as available to rescue this account.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
              if (_allowNetting && _currency != 'rub') ...[
                const SizedBox(height: 8),
                Text(
                  _ru
                      ? 'FX haircut: ${(_haircut * 100).toStringAsFixed(0)}%'
                      : 'FX haircut: ${(_haircut * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                Slider(
                  value: _haircut,
                  min: 0,
                  max: .25,
                  divisions: 25,
                  label: '${(_haircut * 100).round()}%',
                  onChanged: (v) => setState(() => _haircut = v),
                ),
                Text(
                  _ru
                      ? 'Запас на курс, комиссии и задержку конвертации. Чем выше — тем консервативнее неттинг.'
                      : 'Allowance for FX moves, fees and conversion delay. Higher means more conservative netting.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Отмена' : 'Cancel')),
        FilledButton.icon(
          icon: const Icon(Icons.shield_outlined, size: 17),
          label: Text(_ru ? 'Сохранить риск-профиль' : 'Save risk profile'),
          onPressed: _save,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final raw = _minimum.text.trim().replaceAll(',', '.');
    final minimum =
        (double.tryParse(raw) ?? 0).clamp(0, double.infinity).toDouble();
    await AccountLiquidityService.save(AccountLiquidityMeta(
      accountId: widget.account.id,
      currency: _currency,
      minimumBalanceRub: minimum,
      allowNetting: _allowNetting,
      fxHaircut: _currency == 'rub' ? 0 : _haircut,
    ));
    if (mounted) Navigator.pop(context);
  }
}
