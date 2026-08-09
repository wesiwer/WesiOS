from pathlib import Path


def patch(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip:', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('ok:', label)

engine = 'lib/features/treasury/services/forecast_engine.dart'

patch(
    engine,
    """    return _ShockPool(
      income: incomeTx.map((e) => e.amount).toList(),
      expense: expenseTx.map((e) => e.amount).toList(),
      incomeProbability:
          spanDays == 0 ? 0 : (incomeTx.length / spanDays).clamp(0.0, 0.12),
      expenseProbability:
          spanDays == 0 ? 0 : (expenseTx.length / spanDays).clamp(0.0, 0.12),
      incomeDays: daySet(incomeTx),
      expenseDays: daySet(expenseTx),
    );
""",
    """    int shockEpisodes(List<TransactionModel> list) {
      final days = daySet(list).toList()..sort();
      if (days.isEmpty) return 0;
      var episodes = 1;
      for (var i = 1; i < days.length; i++) {
        if (days[i] - days[i - 1] > 2) episodes++;
      }
      return episodes;
    }

    final incomeEpisodes = shockEpisodes(incomeTx);
    final expenseEpisodes = shockEpisodes(expenseTx);
    return _ShockPool(
      income: incomeTx.map((e) => e.amount).toList(),
      expense: expenseTx.map((e) => e.amount).toList(),
      incomeProbability: spanDays == 0
          ? 0
          : (incomeEpisodes / spanDays).clamp(0.0, 0.12),
      expenseProbability: spanDays == 0
          ? 0
          : (expenseEpisodes / spanDays).clamp(0.0, 0.12),
      incomeDays: daySet(incomeTx),
      expenseDays: daySet(expenseTx),
    );
""",
    'cluster consecutive shocks into episodes',
)

patch(
    engine,
    "        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;\n",
    "",
    'remove duplicate whole-income suppression',
)

patch(
    engine,
    "      recommendedReserve: max(recommendedReserve, committedNearTerm),\n",
    "      recommendedReserve: recommendedReserve,\n",
    'do not double-count commitments in reserve',
)

patch(
    'lib/features/audio/widgets/horizon_contract_dialog.dart',
    'HorizonContractMemoryService.forLease(lease.id)',
    'HorizonContractMemoryService.byLease(lease.id)',
    'contract memory lookup API',
)

patch(
    'lib/features/treasury/widgets/account_liquidity_dialog.dart',
    """                items: CurrencyService.currencies.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.value.flag} ${e.value.code} · ${e.value.name}'),
                        ))
                    .toList(),
""",
    """                items: CurrencyService.currencies.keys
                    .map((code) => DropdownMenuItem(
                          value: code,
                          child: Text(
                            '${CurrencyService.flag(code)} ${code.toUpperCase()} · ${CurrencyService.currencyName(code, russian: _ru)}',
                          ),
                        ))
                    .toList(),
""",
    'currency metadata API',
)

print('focused Horizon core fix complete')
