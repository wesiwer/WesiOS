from pathlib import Path
import re

ROOT = Path('.')


def replace_once(path, old, new, label):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    if new in text:
        print(f'[skip] {label}')
        return
    if old not in text:
        raise SystemExit(f'anchor not found: {label} in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print(f'[ok] {label}')


def regex_once(path, pattern, repl, label):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'regex anchor not found: {label} in {path}')
    p.write_text(updated, encoding='utf-8')
    print(f'[ok] {label}')

# ---- Core mathematical correctness -----------------------------------------
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
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
        // Consecutive exceptional days are one regime episode (for example a
        // lucky sales month), not thirty independent jackpot events forever.
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
    'clustered shock probability',
)
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;
        if (whatIf.incomeMultiplierDays <= 0 ||
""",
    """        if (whatIf.incomeMultiplierDays <= 0 ||
""",
    'remove duplicate global main-source suppression',
)
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """      recommendedReserve: max(recommendedReserve, committedNearTerm),
""",
    """      recommendedReserve: recommendedReserve,
""",
    'reserve is not committed cash twice',
)

# ---- Compile fixes in newly added product widgets --------------------------
replace_once(
    'lib/features/audio/widgets/horizon_contract_dialog.dart',
    "HorizonContractMemoryService.forLease(lease.id)",
    "HorizonContractMemoryService.byLease(lease.id)",
    'contract memory API name',
)
replace_once(
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
                            '${CurrencyService.flag(code)} ${code.toUpperCase()} · '
                            '${CurrencyService.currencyName(code, russian: _ru)}',
                          ),
                        ))
                    .toList(),
""",
    'liquidity currency dropdown',
)

# ---- Tasks -> company cash --------------------------------------------------
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """import '../services/task_assignment.dart';
import '../task_labels.dart';
import 'assignee_field.dart';
""",
    """import '../services/task_assignment.dart';
import '../services/task_cash_impact.dart';
import '../task_labels.dart';
import 'assignee_field.dart';
import 'task_cash_impact_field.dart';
""",
    'task cash editor imports',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """  DateTime? _dueDate;
  late List<SubTask> _subtasks;
""",
    """  DateTime? _dueDate;
  TaskCashImpact? _cashImpact;
  bool _cashNeedsDueDate = false;
  late List<SubTask> _subtasks;
""",
    'task cash editor state',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """    _dueDate = t?.dueDate;
    _subtasks = List<SubTask>.from(t?.subtasks ?? const []);
""",
    """    _dueDate = t?.dueDate;
    _cashImpact = TaskCashImpact.fromTags(t?.tags ?? const []);
    _subtasks = List<SubTask>.from(t?.subtasks ?? const []);
""",
    'load task cash tag',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """    final base = widget.initial;
    final task = base == null
""",
    """    final base = widget.initial;
    if (_cashImpact != null && _dueDate == null) {
      setState(() => _cashNeedsDueDate = true);
      return;
    }
    final existingTags = base?.tags ?? const <String>[];
    final nextTags = _cashImpact == null
        ? TaskCashImpact.clearFrom(existingTags)
        : _cashImpact!.applyTo(existingTags);
    final task = base == null
""",
    'validate task cash due date',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """            assignee: TaskAssignment.coerce(_assignee),
            subtasks: _subtasks,
          )
""",
    """            assignee: TaskAssignment.coerce(_assignee),
            subtasks: _subtasks,
            tags: nextTags,
          )
""",
    'new task cash tags',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """            clearAssignee: TaskAssignment.coerce(_assignee) == null,
            subtasks: _subtasks,
          );
""",
    """            clearAssignee: TaskAssignment.coerce(_assignee) == null,
            subtasks: _subtasks,
            tags: nextTags,
          );
""",
    'edited task cash tags',
)
replace_once(
    'lib/features/tasks/widgets/task_editor_dialog.dart',
    """              SizedBox(height: 18),
              Text(ru ? 'Чек-лист' : 'Checklist',
""",
    """              const SizedBox(height: 12),
              TaskCashImpactField(
                key: ValueKey('${widget.initial?.id ?? 'new'}-cash'),
                initial: _cashImpact,
                onChanged: (value) => setState(() {
                  _cashImpact = value;
                  if (value == null || _dueDate != null) {
                    _cashNeedsDueDate = false;
                  }
                }),
              ),
              if (_cashNeedsDueDate) ...[
                const SizedBox(height: 6),
                Text(
                  ru
                      ? 'Для денежного обязательства укажи срок задачи — это дата движения денег.'
                      : 'Set a due date for cash impact — it is the cash movement date.',
                  style: TextStyle(color: AppTheme.accentRed, fontSize: 11),
                ),
              ],
              SizedBox(height: 18),
              Text(ru ? 'Чек-лист' : 'Checklist',
""",
    'task cash impact UI',
)

replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
""",
    """import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_cash_impact.dart';
import '../../tasks/services/task_service.dart';
""",
    'business context task parser import',
)
replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """        final parsed = _cashFromTags(task.tags);
        if (parsed == null) continue;
""",
    """        final parsed = TaskCashImpact.fromTags(task.tags);
        if (parsed == null) continue;
""",
    'use shared task cash parser',
)
replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """                'Просрочено денежное обязательство «${task.title}» (${parsed.amount.toStringAsFixed(0)} ₽).',
            textEn:
                'Overdue cash obligation “${task.title}” (${parsed.amount.toStringAsFixed(0)} RUB).',
            amount: parsed.amount.abs(),
""",
    """                'Просрочено денежное обязательство «${task.title}» (${parsed.signedAmount.abs().toStringAsFixed(0)} ₽).',
            textEn:
                'Overdue cash obligation “${task.title}” (${parsed.signedAmount.abs().toStringAsFixed(0)} RUB).',
            amount: parsed.signedAmount.abs(),
""",
    'task warning amount',
)
replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """          amount: parsed.amount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
""",
    """          amount: parsed.signedAmount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
""",
    'task event signed amount',
)
regex_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    r"\n  static \(\{double amount, double probability, bool committed\}\)\? _cashFromTags\(.*?\n  \}\n\n  static void _addConcentrationWarnings",
    "\n  static void _addConcentrationWarnings",
    'remove duplicate task tag parser',
)

# ---- Audio Vault contract memory -------------------------------------------
replace_once(
    'lib/features/audio/services/audio_vault_service.dart',
    """import '../../team/services/team_service.dart';
import '../models/audio_vault_models.dart';
""",
    """import '../../team/services/team_service.dart';
import '../../treasury/services/horizon_contract_memory.dart';
import '../models/audio_vault_models.dart';
""",
    'audio contract memory import',
)
replace_once(
    'lib/features/audio/services/audio_vault_service.dart',
    """  static Future<BeatEntry> clearLease(BeatEntry beat) async {
    final taskId = beat.lease?.reminderTaskId;
""",
    """  static Future<BeatEntry> clearLease(BeatEntry beat) async {
    final leaseId = beat.lease?.id;
    if (leaseId != null && leaseId.isNotEmpty) {
      await HorizonContractMemoryService.removeLease(leaseId);
    }
    final taskId = beat.lease?.reminderTaskId;
""",
    'clear contract memory with lease',
)
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    """import 'widgets/audio_visualizer.dart';
import 'widgets/lease_countdown.dart';
""",
    """import 'widgets/audio_visualizer.dart';
import 'widgets/horizon_contract_dialog.dart';
import 'widgets/lease_countdown.dart';
""",
    'audio horizon dialog import',
)
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    """              Row(children: [
                OutlinedButton.icon(
                    onPressed: () => _editLease(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Продлить / изменить')),
                const SizedBox(width: 8),
                TextButton.icon(
""",
    """              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () => _editLease(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Продлить / изменить')),
                OutlinedButton.icon(
                    onPressed: () => HorizonContractDialog.show(context, b),
                    icon: const Icon(Icons.query_stats),
                    label: const Text('Horizon: ожидания денег')),
                TextButton.icon(
""",
    'audio contract memory button',
)
replace_once(
    'lib/features/audio/audio_vault_v2_screen.dart',
    """                  label: const Text('Закрыть аренду'),
                ),
              ]),
""",
    """                  label: const Text('Закрыть аренду'),
                ),
              ]),
""",
    'audio lease wrap close',
)

# ---- Account liquidity UI --------------------------------------------------
replace_once(
    'lib/features/treasury/widgets/accounts_bar.dart',
    """import '../services/account_service.dart';
""",
    """import '../services/account_service.dart';
import 'account_liquidity_dialog.dart';
""",
    'accounts liquidity dialog import',
)
replace_once(
    'lib/features/treasury/widgets/accounts_bar.dart',
    """      onTap: () => widget.onSelect(s.account.id),
      onEdit: () => _editAccount(s),
    );
""",
    """      onTap: () => widget.onSelect(s.account.id),
      onEdit: () => _editAccount(s),
      onRisk: () => AccountLiquidityDialog.show(context, s.account),
    );
""",
    'account card risk action',
)
replace_once(
    'lib/features/treasury/widgets/accounts_bar.dart',
    """    VoidCallback? onEdit,
  }) {
""",
    """    VoidCallback? onEdit,
    VoidCallback? onRisk,
  }) {
""",
    'account card risk callback',
)
replace_once(
    'lib/features/treasury/widgets/accounts_bar.dart',
    """                  if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.more_horiz,
                          size: 15, color: AppTheme.textMuted),
                    ),
""",
    """                  if (onRisk != null)
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
""",
    'account card risk icon',
)

# ---- Forecast decision UI + champion Combined ------------------------------
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    """import 'services/multi_engine_forecast.dart';
import 'models/transaction_model.dart';
import 'widgets/forecast_insights.dart';
""",
    """import 'services/multi_engine_forecast.dart';
import 'services/horizon_engine_competition.dart';
import 'models/transaction_model.dart';
import 'widgets/forecast_insights.dart';
import 'widgets/horizon_decision_panel.dart';
""",
    'forecast decision imports',
)
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    """  final Set<ForecastEngineKind> _unavailableEngines = {};

  /// Цвета движков",
    """  final Set<ForecastEngineKind> _unavailableEngines = {};
  ForecastEngineKind _combinedSelectedKind = ForecastEngineKind.wesiHorizon;
  bool _combinedWasRejected = false;

  /// Цвета движков""",
    'smart Combined UI state',
)
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    """    if (kind == ForecastEngineKind.combined) {
      setState(_recomputeCombined);
      return;
    }
""",
    """    if (kind == ForecastEngineKind.combined) {
      await _recomputeCombined();
      return;
    }
""",
    'await smart Combined',
)
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    """    setState(() {
      _loadingEngines.remove(kind);
      _engineCache[kind] = result;
      if (result == null) {
        _unavailableEngines.add(kind);
      } else {
        _unavailableEngines.remove(kind);
      }
      _recomputeCombined();
    });
  }

  void _recomputeCombined() {
    _engineCache[ForecastEngineKind.combined] = combineForecastResults([
      _engineCache[ForecastEngineKind.wesiHorizon],
      _engineCache[ForecastEngineKind.prophet],
      _engineCache[ForecastEngineKind.sarimax],
    ]);
  }
""",
    """    setState(() {
      _loadingEngines.remove(kind);
      _engineCache[kind] = result;
      if (result == null) {
        _unavailableEngines.add(kind);
      } else {
        _unavailableEngines.remove(kind);
      }
    });
    if (_activeEngines.contains(ForecastEngineKind.combined)) {
      await _recomputeCombined();
    }
  }

  Future<void> _recomputeCombined() async {
    final smart = await HorizonEngineCompetitionService.smartCombined(
      horizon: _forecastDays,
      live: {
        ForecastEngineKind.wesiHorizon:
            _engineCache[ForecastEngineKind.wesiHorizon],
        ForecastEngineKind.prophet: _engineCache[ForecastEngineKind.prophet],
        ForecastEngineKind.sarimax: _engineCache[ForecastEngineKind.sarimax],
      },
    );
    if (!mounted) return;
    setState(() {
      _engineCache[ForecastEngineKind.combined] = smart.result;
      _combinedSelectedKind = smart.selectedKind;
      _combinedWasRejected = smart.combinedWasRejected;
    });
  }
""",
    'smart Combined computation',
)
replace_once(
    'lib/features/treasury/forecast_chart_screen.dart',
    """          ForecastDiagnostics(forecast: _forecast),
          const SizedBox(height: 12),
          _engineSelector(),
""",
    """          ForecastDiagnostics(forecast: _forecast),
          const SizedBox(height: 12),
          HorizonDecisionPanel(forecast: _forecast),
          const SizedBox(height: 12),
          _engineSelector(),
          if (_activeEngines.contains(ForecastEngineKind.combined)) ...[
            const SizedBox(height: 6),
            Text(
              WesiLocale.isRussian
                  ? 'Combined: ${_combinedSelectedKind.nameRu}${_combinedWasRejected ? ' — простое усреднение отклонено backtest' : ''}'
                  : 'Combined: ${_combinedSelectedKind.nameEn}${_combinedWasRejected ? ' — equal averaging rejected by backtest' : ''}',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            ),
          ],
""",
    'decision panel and Combined truth note',
)

# ---- Sandbox decision layer without leaking real Treasury context -----------
replace_once(
    'lib/features/treasury/services/sandbox_service.dart',
    """import 'forecast_engine.dart';
import 'recurring_engine.dart';
""",
    """import 'forecast_engine.dart';
import 'horizon_calibration.dart';
import 'horizon_scenarios.dart';
import 'recurring_engine.dart';
""",
    'sandbox Horizon decision imports',
)
replace_once(
    'lib/features/treasury/services/sandbox_service.dart',
    """    return ForecastEngine.generate(
      transactions: all,
      currentBalance: balance,
      whatIf: whatIf,
      annualDiscountRate: annualDiscountRate,
      days: days,
    );
""",
    """    const calibration = HorizonCalibrationProfile.identity;
    final base = ForecastEngine.generate(
      transactions: all,
      currentBalance: balance,
      annualDiscountRate: annualDiscountRate,
      days: days,
      calibration: calibration,
    );
    final active = whatIf.isEmpty
        ? base
        : ForecastEngine.generate(
            transactions: all,
            currentBalance: balance,
            whatIf: whatIf,
            annualDiscountRate: annualDiscountRate,
            days: days,
            calibration: calibration,
          );
    final scenarios = await HorizonScenarioService.buildDefaultPackage(
      base: base,
      transactions: all,
      currentBalance: balance,
      days: days,
      calibration: calibration,
      annualDiscountRate: annualDiscountRate,
    );
    return active.copyWith(
      scenarioSummaries: scenarios,
      whatIfRiskDelta: whatIf.isEmpty
          ? null
          : HorizonScenarioService.riskDelta(base: base, scenario: active),
      clearWhatIfRiskDelta: whatIf.isEmpty,
    );
""",
    'sandbox risk-aware scenario package',
)
replace_once(
    'lib/features/treasury/services/horizon_scenarios.dart',
    """    Map<String, double> recurringReliability = const {},
  }) async {
""",
    """    Map<String, double> recurringReliability = const {},
    double annualDiscountRate = 0.0,
  }) async {
""",
    'scenario package discount parameter',
)
replace_once(
    'lib/features/treasury/services/horizon_scenarios.dart',
    """              calibration: calibration,
              businessEvents: businessEvents,
""",
    """              calibration: calibration,
              annualDiscountRate: annualDiscountRate,
              businessEvents: businessEvents,
""",
    'scenario package honors DCF',
)
replace_once(
    'lib/features/treasury/sandbox_forecast_screen.dart',
    """import 'widgets/forecast_insights.dart';
import 'widgets/what_if_dialog.dart';
""",
    """import 'widgets/forecast_insights.dart';
import 'widgets/horizon_decision_panel.dart';
import 'widgets/what_if_dialog.dart';
""",
    'sandbox decision panel import',
)
# Insert after diagnostics wherever it currently appears.
replace_once(
    'lib/features/treasury/sandbox_forecast_screen.dart',
    """                    ForecastDiagnostics(forecast: _baseline),
""",
    """                    ForecastDiagnostics(forecast: _baseline),
                    const SizedBox(height: 12),
                    HorizonDecisionPanel(forecast: _baseline),
""",
    'sandbox decision panel',
)

print('Horizon integration patch complete')
