#!/usr/bin/env bash
set -euo pipefail
cp .github/scripts/fix_employee_activation_01916_v2.sh /tmp/fix_employee_activation_01916.sh
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/fix_employee_activation_01916.sh')
s = p.read_text(encoding='utf-8')
s = s.replace('        pubspec.yaml pubspec.lock\n', '        pubspec.yaml\n', 1)
p.write_text(s, encoding='utf-8')
PY
bash /tmp/fix_employee_activation_01916.sh
