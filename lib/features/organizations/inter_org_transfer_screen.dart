import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../team/services/team_service.dart';
import '../treasury/models/account_model.dart';
import '../treasury/services/account_service.dart';
import 'models/inter_org_transfer_model.dart';
import 'models/organization_model.dart';
import 'services/inter_org_transfer_service.dart';
import 'services/organization_access_service.dart';
import 'services/organization_service.dart';

class InterOrgTransferScreen extends StatefulWidget {
  const InterOrgTransferScreen({super.key});

  @override
  State<InterOrgTransferScreen> createState() => _InterOrgTransferScreenState();
}

class _InterOrgTransferScreenState extends State<InterOrgTransferScreen> {
  List<OrganizationModel> _orgs = const [];
  List<AccountModel> _fromAccounts = const [];
  List<AccountModel> _toAccounts = const [];
  String? _fromOrg;
  String? _toOrg;
  String? _fromAccount;
  String? _toAccount;
  InterOrgTransferType _type = InterOrgTransferType.investment;
  final _amount = TextEditingController();
  final _fromBase = TextEditingController();
  final _toBase = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _fromBase.dispose();
    _toBase.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await OrganizationService.all();
    final allowed = TeamService.current == null
        ? all.map((e) => e.id).toSet()
        : await OrganizationAccessService.visibleOrganizationIds();
    final orgs = all.where((o) => allowed.contains(o.id)).toList();
    if (!mounted) return;
    setState(() {
      _orgs = orgs;
      _fromOrg ??= orgs.isNotEmpty ? orgs.first.id : null;
      _toOrg ??= orgs.length > 1 ? orgs[1].id : null;
    });
    await _reloadAccounts();
  }

  Future<void> _reloadAccounts() async {
    final from = _fromOrg == null
        ? <AccountModel>[]
        : await AccountService.forOrganization(_fromOrg!, includeArchived: false);
    final to = _toOrg == null
        ? <AccountModel>[]
        : await AccountService.forOrganization(_toOrg!, includeArchived: false);
    if (!mounted) return;
    setState(() {
      _fromAccounts = from;
      _toAccounts = to;
      if (!from.any((a) => a.id == _fromAccount)) {
        _fromAccount = from.isEmpty ? null : from.first.id;
      }
      if (!to.any((a) => a.id == _toAccount)) {
        _toAccount = to.isEmpty ? null : to.first.id;
      }
    });
  }

  OrganizationModel? _org(String? id) =>
      _orgs.where((o) => o.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final from = _org(_fromOrg);
    final to = _org(_toOrg);
    final crossCurrency = from != null && to != null && from.baseCurrency != to.baseCurrency;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Межорганизационный перевод'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Перевод всегда создаёт две связанные проводки. Деньги не переносятся скрытым изменением баланса.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          _orgPicker('Откуда', _fromOrg, (v) async {
            setState(() => _fromOrg = v);
            if (_toOrg == v) {
              _toOrg = _orgs.where((o) => o.id != v).firstOrNull?.id;
            }
            await _reloadAccounts();
          }),
          const SizedBox(height: 10),
          _accountPicker('Счёт списания', _fromAccount, _fromAccounts,
              (v) => setState(() => _fromAccount = v)),
          const SizedBox(height: 18),
          _orgPicker('Куда', _toOrg, (v) async {
            setState(() => _toOrg = v);
            if (_fromOrg == v) {
              _fromOrg = _orgs.where((o) => o.id != v).firstOrNull?.id;
            }
            await _reloadAccounts();
          }),
          const SizedBox(height: 10),
          _accountPicker('Счёт зачисления', _toAccount, _toAccounts,
              (v) => setState(() => _toAccount = v)),
          const SizedBox(height: 18),
          DropdownButtonFormField<InterOrgTransferType>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Тип'),
            items: const [
              DropdownMenuItem(value: InterOrgTransferType.investment, child: Text('Инвестиция')),
              DropdownMenuItem(value: InterOrgTransferType.profitShare, child: Text('Доля прибыли')),
              DropdownMenuItem(value: InterOrgTransferType.funding, child: Text('Финансирование')),
              DropdownMenuItem(value: InterOrgTransferType.internalTransfer, child: Text('Внутренний перевод')),
              DropdownMenuItem(value: InterOrgTransferType.other, child: Text('Прочее')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Сумма ${from?.baseCurrency ?? ''}'),
            onChanged: (v) {
              if (_fromBase.text.isEmpty) _fromBase.text = v;
              if (_toBase.text.isEmpty) _toBase.text = v;
            },
          ),
          if (crossCurrency) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _fromBase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'В базе ${from!.name} (${from.baseCurrency})'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toBase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'В базе ${to!.name} (${to.baseCurrency})'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Комментарий'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_horiz_rounded),
            label: const Text('Провести перевод'),
          ),
        ],
      ),
    );
  }

  Widget _orgPicker(String label, String? value, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final org in _orgs)
            DropdownMenuItem(value: org.id, child: Text(org.name)),
        ],
        onChanged: onChanged,
      );

  Widget _accountPicker(
    String label,
    String? value,
    List<AccountModel> accounts,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final account in accounts)
            DropdownMenuItem(value: account.id, child: Text(account.name)),
        ],
        onChanged: onChanged,
      );

  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    final amount = _number(_amount.text);
    if (_fromOrg == null || _toOrg == null || _fromAccount == null || _toAccount == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заполни организации, счета и корректную сумму.')));
      return;
    }
    if (_fromOrg == _toOrg) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Для перевода нужны две разные организации.')));
      return;
    }
    final from = _org(_fromOrg)!;
    final to = _org(_toOrg)!;
    final fromBase = _number(_fromBase.text) ?? amount;
    final toBase = _number(_toBase.text) ?? amount;
    setState(() => _busy = true);
    try {
      await InterOrgTransferService.execute(
        fromOrganizationId: _fromOrg!,
        toOrganizationId: _toOrg!,
        fromAccountId: _fromAccount!,
        toAccountId: _toAccount!,
        amount: amount,
        currency: from.baseCurrency,
        amountInFromOrgBase: fromBase,
        amountInToOrgBase: toBase,
        type: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Перевод ${from.name} → ${to.name} проведён в обеих организациях.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
