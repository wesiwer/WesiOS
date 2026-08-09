import 'package:flutter/material.dart';

import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../treasury/services/horizon_contract_memory.dart';
import '../models/audio_vault_models.dart';

/// Domain memory for beat/service contracts. It is intentionally separate from
/// the visible lease object: changing forecast assumptions never rewrites the
/// legal/business record in Audio Vault.
class HorizonContractDialog extends StatefulWidget {
  final BeatEntry beat;
  final BeatLease lease;
  final HorizonContractMemory initial;

  const HorizonContractDialog({
    super.key,
    required this.beat,
    required this.lease,
    required this.initial,
  });

  static Future<void> show(BuildContext context, BeatEntry beat) async {
    final lease = beat.lease;
    if (lease == null) return;
    final existing = await HorizonContractMemoryService.forLease(lease.id);
    final fallbackAmount = lease.amount *
        CurrencyService.rateToRub(lease.currency.toLowerCase());
    final initial = existing ??
        HorizonContractMemory(
          beatId: beat.id,
          leaseId: lease.id,
          renewalProbability: .35,
          renewalAmountRub: fallbackAmount,
          royaltyProbability: .5,
          updatedAt: DateTime.now(),
        );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => HorizonContractDialog(
        beat: beat,
        lease: lease,
        initial: initial,
      ),
    );
  }

  @override
  State<HorizonContractDialog> createState() => _HorizonContractDialogState();
}

class _HorizonContractDialogState extends State<HorizonContractDialog> {
  late double _renewalProbability;
  late double _royaltyProbability;
  late DateTime? _royaltyDate;
  late final TextEditingController _renewalAmount;
  late final TextEditingController _royaltyAmount;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _renewalProbability = initial.renewalProbability;
    _royaltyProbability = initial.royaltyProbability;
    _royaltyDate = initial.royaltyDueAt;
    _renewalAmount = TextEditingController(
      text: initial.renewalAmountRub <= 0
          ? ''
          : initial.renewalAmountRub.toStringAsFixed(0),
    );
    _royaltyAmount = TextEditingController(
      text: initial.expectedRoyaltyRub <= 0
          ? ''
          : initial.expectedRoyaltyRub.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _renewalAmount.dispose();
    _royaltyAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Horizon · ${widget.beat.title}'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Контрактная память не меняет договор. Она говорит Horizon, какие деньги ожидаются после окончания аренды и насколько им можно доверять.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              _section('Продление аренды', Icons.autorenew),
              const SizedBox(height: 8),
              TextField(
                controller: _renewalAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Ожидаемая сумма продления, ₽'),
              ),
              const SizedBox(height: 8),
              _probability(
                label: 'Вероятность продления',
                value: _renewalProbability,
                onChanged: (v) => setState(() => _renewalProbability = v),
              ),
              const SizedBox(height: 18),
              _section('Роялти / отложенное поступление', Icons.payments_outlined),
              const SizedBox(height: 8),
              TextField(
                controller: _royaltyAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Ожидаемое роялти, ₽'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ожидаемая дата роялти'),
                subtitle: Text(_royaltyDate == null ? 'Не указана' : _date(_royaltyDate!)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_royaltyDate != null)
                      IconButton(
                        tooltip: 'Снять дату',
                        onPressed: () => setState(() => _royaltyDate = null),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    IconButton(
                      onPressed: _pickRoyaltyDate,
                      icon: const Icon(Icons.calendar_month),
                    ),
                  ],
                ),
              ),
              if (_royaltyDate != null || _royaltyAmount.text.trim().isNotEmpty)
                _probability(
                  label: 'Вероятность роялти',
                  value: _royaltyProbability,
                  onChanged: (v) => setState(() => _royaltyProbability = v),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accent.withOpacity(.2)),
                ),
                child: Text(
                  'Если ничего не настраивать, Wesi Horizon использует консервативное допущение: 35% вероятности продления на сумму текущей сделки.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: const Text('Сохранить ожидания'),
        ),
      ],
    );
  }

  Widget _section(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ],
      );

  Widget _probability({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${(value * 100).round()}%',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5)),
          Slider(
            value: value.clamp(.05, .95).toDouble(),
            min: .05,
            max: .95,
            divisions: 18,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      );

  Future<void> _pickRoyaltyDate() async {
    final initial = _royaltyDate ?? widget.lease.endsAt.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _royaltyDate = picked);
  }

  Future<void> _save() async {
    final renewal = double.tryParse(_renewalAmount.text.trim().replaceAll(',', '.')) ?? 0;
    final royalty = double.tryParse(_royaltyAmount.text.trim().replaceAll(',', '.')) ?? 0;
    await HorizonContractMemoryService.save(HorizonContractMemory(
      beatId: widget.beat.id,
      leaseId: widget.lease.id,
      renewalProbability: _renewalProbability,
      renewalAmountRub: renewal.clamp(0, double.infinity).toDouble(),
      expectedRoyaltyRub: royalty.clamp(0, double.infinity).toDouble(),
      royaltyDueAt: royalty > 0 ? _royaltyDate : null,
      royaltyProbability: _royaltyProbability,
      updatedAt: DateTime.now(),
    ));
    if (mounted) Navigator.pop(context);
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}