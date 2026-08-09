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

forecast = 'lib/features/treasury/forecast_chart_screen.dart'
sandbox_service = 'lib/features/treasury/services/sandbox_service.dart'
scenarios = 'lib/features/treasury/services/horizon_scenarios.dart'
sandbox_screen = 'lib/features/treasury/sandbox_forecast_screen.dart'

# Forecast: smart Combined uses the backtest champion for the selected horizon,
# and the decision layer is visible before the pretty chart.
patch(
    forecast,
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
patch(
    forecast,
    """  final Set<ForecastEngineKind> _unavailableEngines = {};

  /// Цвета движков",
    """  final Set<ForecastEngineKind> _unavailableEngines = {};
  ForecastEngineKind _combinedSelectedKind = ForecastEngineKind.wesiHorizon;
  bool _combinedWasRejected = false;

  /// Цвета движков""",
    'smart Combined state',
)
patch(
    forecast,
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
    'await Combined computation',
)
patch(
    forecast,
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
    'champion-based Combined',
)
patch(
    forecast,
    """          ForecastDiagnostics(forecast: _forecast),
          const SizedBox(height: 12),
          _engineSelector(),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
""",
    'decision panel and Combined truth label',
)

# Sandbox gets the same scenario/risk semantics but NEVER imports real company
# CRM/Tasks/Vault/account context. It stays an isolated financial laboratory.
patch(
    sandbox_service,
    """import 'forecast_engine.dart';
import 'recurring_engine.dart';
""",
    """import 'forecast_engine.dart';
import 'horizon_calibration.dart';
import 'horizon_scenarios.dart';
import 'recurring_engine.dart';
""",
    'Sandbox decision imports',
)
patch(
    sandbox_service,
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
    final package = await HorizonScenarioService.buildDefaultPackage(
      base: base,
      transactions: all,
      currentBalance: balance,
      days: days,
      calibration: calibration,
      annualDiscountRate: annualDiscountRate,
    );
    return active.copyWith(
      scenarioSummaries: package,
      whatIfRiskDelta: whatIf.isEmpty
          ? null
          : HorizonScenarioService.riskDelta(base: base, scenario: active),
      clearWhatIfRiskDelta: whatIf.isEmpty,
    );
""",
    'risk-aware isolated Sandbox forecast',
)

patch(
    scenarios,
    """    List<AccountLiquiditySnapshot> accounts = const [],
    Map<String, double> recurringReliability = const {},
  }) async {
""",
    """    List<AccountLiquiditySnapshot> accounts = const [],
    Map<String, double> recurringReliability = const {},
    double annualDiscountRate = 0.0,
  }) async {
""",
    'scenario package discount argument',
)
patch(
    scenarios,
    """              whatIf: definition.scenario,
              calibration: calibration,
              businessEvents: businessEvents,
""",
    """              whatIf: definition.scenario,
              calibration: calibration,
              annualDiscountRate: annualDiscountRate,
              businessEvents: businessEvents,
""",
    'scenario package preserves DCF',
)

patch(
    sandbox_screen,
    """import 'widgets/forecast_insights.dart';
import 'widgets/what_if_dialog.dart';
""",
    """import 'widgets/forecast_insights.dart';
import 'widgets/horizon_decision_panel.dart';
import 'widgets/what_if_dialog.dart';
""",
    'Sandbox decision panel import',
)
patch(
    sandbox_screen,
    """                          ForecastDiagnostics(forecast: _baseline),
                          const SizedBox(height: 18),
                          _chart(),
""",
    """                          ForecastDiagnostics(forecast: _baseline),
                          const SizedBox(height: 12),
                          HorizonDecisionPanel(forecast: _baseline),
                          const SizedBox(height: 18),
                          _chart(),
""",
    'Sandbox decision panel',
)

print('Decision layer + smart Combined + Sandbox integration complete')
