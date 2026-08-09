from pathlib import Path


def patch(path, old, new, name):
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if new in s:
        print('skip', name)
        return
    if old not in s:
        raise SystemExit('missing: ' + name)
    p.write_text(s.replace(old, new, 1), encoding='utf-8')
    print('ok', name)

service = 'lib/features/treasury/services/sandbox_service.dart'
scenarios = 'lib/features/treasury/services/horizon_scenarios.dart'
screen = 'lib/features/treasury/sandbox_forecast_screen.dart'

patch(
    service,
    "import 'forecast_engine.dart';\nimport 'recurring_engine.dart';\n",
    "import 'forecast_engine.dart';\nimport 'horizon_calibration.dart';\nimport 'horizon_scenarios.dart';\nimport 'recurring_engine.dart';\n",
    'Sandbox imports',
)
patch(
    service,
    '''    return ForecastEngine.generate(
      transactions: all,
      currentBalance: balance,
      whatIf: whatIf,
      annualDiscountRate: annualDiscountRate,
      days: days,
    );
''',
    '''    const calibration = HorizonCalibrationProfile.identity;
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
''',
    'Sandbox risk-aware forecast',
)

patch(
    scenarios,
    '''    List<AccountLiquiditySnapshot> accounts = const [],
    Map<String, double> recurringReliability = const {},
  }) async {
''',
    '''    List<AccountLiquiditySnapshot> accounts = const [],
    Map<String, double> recurringReliability = const {},
    double annualDiscountRate = 0.0,
  }) async {
''',
    'Scenario DCF parameter',
)
patch(
    scenarios,
    '''              whatIf: definition.scenario,
              calibration: calibration,
              businessEvents: businessEvents,
''',
    '''              whatIf: definition.scenario,
              calibration: calibration,
              annualDiscountRate: annualDiscountRate,
              businessEvents: businessEvents,
''',
    'Scenario DCF forwarding',
)

patch(
    screen,
    "import 'widgets/forecast_insights.dart';\nimport 'widgets/what_if_dialog.dart';\n",
    "import 'widgets/forecast_insights.dart';\nimport 'widgets/horizon_decision_panel.dart';\nimport 'widgets/what_if_dialog.dart';\n",
    'Sandbox panel import',
)
patch(
    screen,
    '''                          ForecastDiagnostics(forecast: _baseline),
                          const SizedBox(height: 18),
                          _chart(),
''',
    '''                          ForecastDiagnostics(forecast: _baseline),
                          const SizedBox(height: 12),
                          HorizonDecisionPanel(forecast: _baseline),
                          const SizedBox(height: 18),
                          _chart(),
''',
    'Sandbox panel UI',
)

print('Sandbox decision integration complete')
