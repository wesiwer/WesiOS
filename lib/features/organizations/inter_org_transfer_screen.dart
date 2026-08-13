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
  List<InterOrgTransferModel> _history = const [];
  String? _fromOrg;
  String? _toOrg;
  String? _fromAccount;
  String? _toAccount;
  InterOrgTransferType _type = InterOrgTransferType.investment;
  DateTime _date = DateTime.now();
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
    final history = await InterOrgTransferService.allVisible();
    if (!mounted) return;
    setState(() {
      _orgs = orgs;
      _history = history;
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

  String _orgName(String id) => _org(id)?.name ?? id;

  String _typeName(InterOrgTransferType type) => switch (type) {
        InterOrgTransferType.investment => 'Инвестиция',
        InterOrgTransferType.profitShare => 'Доля прибыли',
        InterOrgTransferType.funding => 'Финансирование',
        InterOrgTransferType.internalTransfer => 'Внутренний перевод',
        InterOrgTransferType.other => 'Прочее',
      };

  String _dateText(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final from = _org(_fromOrg);
    final to = _org(_toOrg);
    final crossCurrency =
        from != null && to != null && from.baseCurrency != to.baseCurrency;
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
            'Перевод хранится как единый журнал и две связанные проводки. При сбое WesiOS автоматически восстанавливает согласованное состояние.',
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
            items: [
              for (final type in InterOrgTransferType.values)
                DropdownMenuItem(value: type, child: Text(_typeName(type))),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                InputDecoration(labelText: 'Сумма ${from?.baseCurrency ?? ''}'),
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
              decoration: InputDecoration(
                  labelText: 'В базе ${from.name} (${from.baseCurrency})'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toBase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'В базе ${to.name} (${to.baseCurrency})'),
            ),
          ],
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Дата и время'),
            subtitle: Text(_dateText(_date)),
            trailing: const Icon(Icons.event_outlined),
            onTap: _pickDateTime,
          ),
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_horiz_rounded),
            label: const Text('Проверить и провести'),
          ),
          const SizedBox(height: 30),
          Text('История переводов',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (_history.isEmpty)
            Text('Переводов в доступном контуре пока нет.',
                style: TextStyle(color: AppTheme.textSecondary))
          else
            for (final transfer in _history) _historyCard(transfer),
        ],
      ),
    );
  }

  Widget _historyCard(InterOrgTransferModel t) => Card(
        child: ListTile(
          title: Text('${_orgName(t.fromOrganizationId)} → ${_orgName(t.toOrganizationId)}'),
          subtitle: Text(
            '${_typeName(t.type)} • ${_dateText(t.date)}\n'
            'Автор: ${t.createdBy}${t.note == null ? '' : '\n${t.note}'}',
          ),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${t.amount.toStringAsFixed(2)} ${t.currency}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (t.cancelled)
                Text('Отменён', style: TextStyle(color: AppTheme.accentRed))
              else
                TextButton(
                  onPressed: _busy ? null : () => _cancel(t),
                  child: const Text('Отменить'),
                ),
            ],
          ),
        ),
      );

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
  ) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final account in accounts)
            DropdownMenuItem(
              value: account.id,
              child: Text('${account.name} • ${account.currency}'),
            ),
        ],
        onChanged: onChanged,
      );

  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null) return;
    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<bool> _confirm({
    required OrganizationModel from,
    required OrganizationModel to,
    required double amount,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение перевода'),
        content: Text(
          '${from.name} → ${to.name}\n'
          '${_typeName(_type)}\n'
          '${amount.toStringAsFixed(2)} ${from.baseCurrency}\n'
          '${_dateText(_date)}'
          '${_note.text.trim().isEmpty ? '' : '\n\n${_note.text.trim()}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Провести'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submit() async {
    final amount = _number(_amount.text);
    if (_fromOrg == null ||
        _toOrg == null ||
        _fromAccount == null ||
        _toAccount == null ||
        amount == null ||
        amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Заполни организации, счета и корректную сумму.')));
      return;
    }
    if (_fromOrg == _toOrg) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Для перевода нужны две разные организации.')));
      return;
    }
    final from = _org(_fromOrg)!;
    final to = _org(_toOrg)!;
    if (!await _confirm(from: from, to: to, amount: amount)) return;
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
        date: _date,
      );
      if (!mounted) return;
      _amount.clear();
      _fromBase.clear();
      _toBase.clear();
      _note.clear();
      _date = DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Перевод ${from.name} → ${to.name} проведён в обеих организациях.')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(InterOrgTransferModel transfer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить перевод?'),
        content: Text(
            '${_orgName(transfer.fromOrganizationId)} → ${_orgName(transfer.toOrganizationId)}\n'
            '${transfer.amount.toStringAsFixed(2)} ${transfer.currency}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить обе проводки'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await InterOrgTransferService.cancel(transfer.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
