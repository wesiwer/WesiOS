from pathlib import Path
import runpy

target = Path('lib/features/treasury/services/forecast_engine.dart')
text = target.read_text(encoding='utf-8')
if ('static const Map<CashRegime, Map<CashRegime, double>> _prior' in text
        and '_semanticStream' in text
        and 'regimeModel.transition' in text):
    print('final Horizon core patch already applied')
else:
    runpy.run_path('tooling/horizon_final_core_patch.py', run_name='__main__')
