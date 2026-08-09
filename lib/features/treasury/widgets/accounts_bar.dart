import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../services/account_service.dart';
import 'account_liquidity_dialog.dart';

/// Полоса счетов над балансом: «Все счета» плюс карточка на каждый счёт.
class AccountsBar extends StatefulWidget {
  final List<TransactionModel> transactions;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  const AccountsBar({
    super.key,
    required this.transactions,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  State<AccountsBar> createState() => _AccountsBarState();
}

class _AccountsBarState extends State<AccountsBar> {
  List<AccountSummary> _summaries = [];
  bool _loaded = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
    AccountService.revision.addListener(_load);
  }

  @override
  void didUpdateWidget(covariant AccountsBar old) {
    super.didUpdateWidget(old);
    if (old.transactions.length != widget.transactions.length) _load();
  }

  @override
  void dispose() {
    AccountService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AccountService.summaries(widget.transactions);
    if (!mounted) return;
    setState(() {
      _summaries = s;
      _loaded = true;
    });
  }

  double get _totalBalance =>
      _summaries.fold<double>(0, (s, x) => s + x.balance);

  IconData _icon(AccountKind kind) => switch (kind) {
        AccountKind.main => Icons.account_balance,
        AccountKind.card => Icons.credit_card,
        AccountKind.cash => Icons.payments,
        AccountKind.savings => Icons.savings,
        AccountKind.project => Icons.workspaces_outline,
      };

  String _kindLabel(AccountKind kind) => switch (kind) {
        AccountKind.main => _ru ? 'Основной' : 'Main',
        AccountKind.card => _ru ? 'Карта' : 'Card',
        AccountKind.cash => _ru ? 'Наличные' : 'Cash',
        AccountKind.savings => _ru ? 'Накопления' : 'Savings',
        AccountKind.project => _ru ? 'Проект' : 'Project',
      };

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 96);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _ru ? 'Счета' : 'Accounts',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _createAccount,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.add, size: 15, color: AppTheme.accent),
              label: Text(_ru ? 'Счёт' : 'Account',
                  style: TextStyle(fontSize: 12, color: AppTheme.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _allCard(),
              ..._summaries
                  .where((s) => !s.account.archived || s.operations > 0)
                  .map(_accountCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _allCard() {
    final selected = widget.selectedId == null;
    return _card(
      selected: selected,
      color: AppTheme.accent,
      icon: Icons.dashboard_customize_outlined,
      title: _ru ? 'Все счета' : 'All accounts',
      subtitle: '${_summaries.length} ${_ru ? 'шт.' : 'total'}',
      amount: _totalBalance,
      onTap: () => widget.onSelect(null),
    );
  }

  Widget _accountCard(AccountSummary s) {
    final selected = widget.selectedId == s.account.id;
    return _card(
      selected: selected,
      color: Color(s.account.colorValue),
      icon: _icon(s.account.kind),
      title: s.account.name,
      subtitle: s.account.archived
          ? (_ru ? 'в архиве' : 'archived')
          : _kindLabel(s.account.kind),
      amount: s.balance,
      onTap: () => widget.onSelect(s.account.id),
      onEdit: () => _editAccount(s),
      onRisk: () => AccountLiquidityDialog.show(context, s.account),
    );
  }

  Widget _card({
    required bool selected,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required double amount,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onRisk,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 168,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? color.withOpacity(0.15)
                : AppTheme.surface.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color.withOpacity(0.6) : AppTheme.glassBorder,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? color : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (onRisk != null)
                    GestureDetector(
                      onTap: onRisk,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.shield_outlined,
                            size: 14, color: AppTheme.textMuted),
                      ),
                    ),
                  if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.more_horiz,
                          size: 15, color: AppTheme.textMuted),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                CurrencyService.formatExact(amount, decimals: 0),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createAccount() async {
    final result = await AccountEditorDialog.show(context);
    if (result == null) return;
    await AccountService.create(
      name: result.name,
      kind: result.kind,
      openingBalance: result.openingBalance,
      colorValue: result.colorValue,
    );
    await _load();
  }

  Future<void> _editAccount(AccountSummary s) async {
    final result = await AccountEditorDialog.show(context, initial: s.account);
    if (result == null) return;
    if (result.delete) {
      final ok = await AccountService.delete(
        s.account.id,
        hasOperations: s.operations > 0,
      );
      if (ok && widget.selectedId == s.account.id) widget.onSelect(null);
      await _load();
      return;
    }
    await AccountService.save(s.account.copyWith(
      name: result.name,
      kind: result.kind,
      openingBalance: result.openingBalance,
      colorValue: result.colorValue,
    ));
    await _load();
  }
}

class AccountEditResult {
  final String name;
  final AccountKind kind;
  final double openingBalance;
  final int colorValue;
  final bool delete;

  const AccountEditResult({
    required this.name,
    required this.kind,
    required this.openingBalance,
    required this.colorValue,
    this.delete = false,
  });
}

class AccountEditorDialog extends StatefulWidget {
  final AccountModel? initial;

  const AccountEditorDialog({super.key, this.initial});

  static Future<AccountEditResult?> show(BuildContext context,
      {AccountModel? initial}) {
    return showDialog<AccountEditResult>(
      context: context,
      builder: (_) => AccountEditorDialog(initial: initial),
    );
  }

  @override
  State<AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<AccountEditorDialog> {
  static const List<int> _colors = [
    0xFFF97316,
    0xFF38BDF8,
    0xFF34D399,
    0xFFA78BFA,
    0xFFF472B6,
    0xFFFBBF24,
  ];

  final _nameCtrl = TextEditingController();
  final _openingCtrl = TextEditingController();
  late AccountKind _kind;
  late int _color;

  bool get _ru => WesiLocale.isRussian;
  bool get _isMain => widget.initial?.id == AccountModel.mainId;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _kind = a?.kind ?? AccountKind.project;
    _color = a?.colorValue ?? _colors[1];
    if (a != null) {
      _nameCtrl.text = a.name;
      if (a.openingBalance != 0) {
        _openingCtrl.text = a.openingBalance.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _openingCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      AccountEditResult(
        name: name,
        kind: _kind,
        openingBalance: double.tryParse(_openingCtrl.text.trim()) ?? 0,
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null
                    ? (_ru ? 'Новый счёт' : 'New account')
                    : (_ru ? 'Счёт' : 'Account'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration:
                    InputDecoration(labelText: _ru ? 'Название' : 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _openingCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: _ru ? 'Начальный остаток' : 'Opening balance',
                  helperText: _ru
                      ? 'Сколько уже лежало на счёте до первой операции'
                      : 'What was already there before the first operation',
                  helperStyle:
                      TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 18),
              Text(_ru ? 'Тип' : 'Kind',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AccountKind.values.map((k) {
                  final sel = k == _kind;
                  return GestureDetector(
                    onTap: () => setState(() => _kind = k),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTheme.accent.withOpacity(0.18)
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: sel
                                ? AppTheme.accent.withOpacity(0.6)
                                : AppTheme.glassBorder),
                      ),
                      child: Text(
                        switch (k) {
                          AccountKind.main => _ru ? 'Основной' : 'Main',
                          AccountKind.card => _ru ? 'Карта' : 'Card',
                          AccountKind.cash => _ru ? 'Наличные' : 'Cash',
                          AccountKind.savings => _ru ? 'Накопления' : 'Savings',
                          AccountKind.project => _ru ? 'Проект' : 'Project',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          color: sel ? AppTheme.accent : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Text(_ru ? 'Цвет' : 'Colour',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Row(
                children: _colors.map((c) {
                  final sel = c == _color;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (widget.initial != null && !_isMain)
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        AccountEditResult(
                          name: widget.initial!.name,
                          kind: widget.initial!.kind,
                          openingBalance: widget.initial!.openingBalance,
                          colorValue: widget.initial!.colorValue,
                          delete: true,
                        ),
                      ),
                      child: Text(_ru ? 'Удалить' : 'Delete',
                          style: TextStyle(color: AppTheme.accentRed)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  HoverButton(
                    onTap: _submit,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accent,
                    child: Text(WesiLocale.get('save'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
