from pathlib import Path


def replace(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('patched', label)

engine = 'lib/features/treasury/services/forecast_engine.dart'
panel = 'lib/features/treasury/widgets/horizon_decision_panel.dart'

replace(
    engine,
    '''  final double calibrationCoverage;\n  final CashRegime regime;''',
    '''  final double calibrationCoverage;\n  final int calibrationSamples;\n  final String calibrationSource;\n  final CashRegime regime;''',
    'ForecastResult calibration evidence fields',
)
replace(
    engine,
    '''    this.calibrationCoverage = 0,\n    this.regime = CashRegime.stable,''',
    '''    this.calibrationCoverage = 0,\n    this.calibrationSamples = 0,\n    this.calibrationSource = 'identity',\n    this.regime = CashRegime.stable,''',
    'ForecastResult calibration evidence defaults',
)
replace(
    engine,
    '''        calibrationCoverage: calibrationCoverage,\n        regime: regime,''',
    '''        calibrationCoverage: calibrationCoverage,\n        calibrationSamples: calibrationSamples,\n        calibrationSource: calibrationSource,\n        regime: regime,''',
    'ForecastResult copyWith evidence preservation',
)
replace(
    engine,
    '''      calibrationCoverage: endBucket.coverage,\n      regime: regimeModel.current,''',
    '''      calibrationCoverage: endBucket.coverage,\n      calibrationSamples: endBucket.samples,\n      calibrationSource: calibration.source,\n      regime: regimeModel.current,''',
    'ForecastEngine returns evidence metadata',
)

replace(
    panel,
    '''              Expanded(\n                child: _progress(\n                  _ru ? 'Калибровка P10–P90' : 'P10–P90 coverage',\n                  forecast.calibrationCoverage,\n                  target: .8,\n                ),\n              ),''',
    '''              Expanded(\n                child: _calibrationProgress(),\n              ),''',
    'Decision panel measured calibration widget',
)

progress_anchor = '''  Widget _progress(String label, double value, {double? target}) {\n'''
calibration_method = '''  Widget _calibrationProgress() {\n    final samples = forecast.calibrationSamples;\n    if (samples <= 0) {\n      return Column(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: [\n          Row(\n            children: [\n              Expanded(\n                child: Text(\n                  _ru ? 'Калибровка P10–P90' : 'P10–P90 calibration',\n                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),\n                ),\n              ),\n              Text(\n                _ru ? 'нет оценки · цель 80%' : 'not measured · target 80%',\n                style: TextStyle(\n                  color: Colors.amber,\n                  fontSize: 10.5,\n                  fontWeight: FontWeight.w700,\n                ),\n              ),\n            ],\n          ),\n          const SizedBox(height: 4),\n          ClipRRect(\n            borderRadius: BorderRadius.circular(4),\n            child: LinearProgressIndicator(\n              value: 0,\n              minHeight: 5,\n              backgroundColor: AppTheme.surfaceLight,\n              color: Colors.amber.withOpacity(.55),\n            ),\n          ),\n          const SizedBox(height: 3),\n          Text(\n            _ru\n                ? 'Цель — не измеренный факт. Нужны созревшие backtest/live наблюдения.'\n                : 'The target is not measured evidence. Mature backtest/live observations are required.',\n            maxLines: 2,\n            overflow: TextOverflow.ellipsis,\n            style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5),\n          ),\n        ],\n      );\n    }\n\n    final source = forecast.calibrationSource.startsWith('monthly-learning:backtest+issued')\n        ? (_ru ? 'live + backtest' : 'live + backtest')\n        : forecast.calibrationSource.startsWith('monthly-learning')\n            ? 'backtest'\n            : forecast.calibrationSource;\n    return Column(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n        _progress(\n          _ru ? 'P10–P90 coverage · n=$samples' : 'P10–P90 coverage · n=$samples',\n          forecast.calibrationCoverage,\n          target: .8,\n        ),\n        const SizedBox(height: 3),\n        Text(\n          _ru ? 'Источник: $source' : 'Source: $source',\n          maxLines: 1,\n          overflow: TextOverflow.ellipsis,\n          style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5),\n        ),\n      ],\n    );\n  }\n\n'''
p = Path(panel)
text = p.read_text(encoding='utf-8')
if '_calibrationProgress() {' not in text:
    if progress_anchor not in text:
        raise SystemExit('missing anchor: calibration method insertion')
    text = text.replace(progress_anchor, calibration_method + progress_anchor, 1)
    p.write_text(text, encoding='utf-8')
    print('patched calibration truth UI method')
else:
    print('skip calibration truth UI method')
