from pathlib import Path
import subprocess

# Reuse the already reviewed hardening patcher from its immutable commit and
# only repair the generated Dart source assertion that accidentally embedded a
# literal newline inside a single-quoted string.
source = subprocess.check_output(
    ['git', 'show', 'a84c14443f81e98a18ecc558aae70f073c53f76b:tooling/horizon_final_hardening.py'],
    text=True,
)
source = source.replace(
    "    expect(source, isNot(contains('day <= whatIf.incomeDelayDays) {\\n          sampledIncome = 0.0')));",
    "    expect(source, isNot(contains('sampledIncome = 0.0;')));",
)
exec(compile(source, '<horizon-final-hardening>', 'exec'))
