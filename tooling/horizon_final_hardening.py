from pathlib import Path
import subprocess

# Reuse the already reviewed hardening patcher from its immutable commit and
# repair only generated-source issues around the execution harness.
source = subprocess.check_output(
    ['git', 'show', 'a84c14443f81e98a18ecc558aae70f073c53f76b:tooling/horizon_final_hardening.py'],
    text=True,
)
source = source.replace(
    "    expect(source, isNot(contains('day <= whatIf.incomeDelayDays) {\\n          sampledIncome = 0.0')));",
    "    expect(source, isNot(contains('sampledIncome = 0.0;')));",
)
exec(compile(source, '<horizon-final-hardening>', 'exec'))

maintenance = Path('lib/features/treasury/services/horizon_maintenance_automation.dart')
text = maintenance.read_text(encoding='utf-8')
text = text.replace("import 'horizon_calibration.dart';\n", '')
maintenance.write_text(text, encoding='utf-8')
