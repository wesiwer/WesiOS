from pathlib import Path

p = Path('lib/features/treasury/forecast_chart_screen.dart')
s = p.read_text(encoding='utf-8')


def one(old, new, name):
    global s
    if new in s:
        print('skip', name)
        return
    if old not in s:
        raise SystemExit('missing: ' + name)
    s = s.replace(old, new, 1)
    print('ok', name)

one(
    "import 'services/multi_engine_forecast.dart';\nimport 'models/transaction_model.dart';\nimport 'widgets/forecast_insights.dart';\n",
    "import 'services/multi_engine_forecast.dart';\nimport 'services/horizon_engine_competition.dart';\nimport 'models/transaction_model.dart';\nimport 'widgets/forecast_insights.dart';\nimport 'widgets/horizon_decision_panel.dart';\n",
    'imports',
)

one(
    "  final Set<ForecastEngineKind> _unavailableEngines = {};\n",
    "  final Set<ForecastEngineKind> _unavailableEngines = {};\n  ForecastEngineKind _combinedSelectedKind = ForecastEngineKind.wesiHorizon;\n  bool _combinedWasRejected = false;\n",
    'state',
)

one(
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
    'combined await',
)

start_marker = "    setState(() {\n      _loadingEngines.remove(kind);"
end_marker = "\n  Future<void> _cycleCurrency() async {"
start = s.find(start_marker)
end = s.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('missing engine completion block')
replacement = '''    setState(() {
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
      live: <ForecastEngineKind, ForecastResult?>{
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
'''
s = s[:start] + replacement + s[end:]
print('ok smart combined block')

one(
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
    'decision UI',
)

p.write_text(s, encoding='utf-8')
print('Forecast decision UI patch complete')
