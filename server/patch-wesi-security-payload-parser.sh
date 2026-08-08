#!/usr/bin/env bash
set -euo pipefail

HOOK="${1:-/opt/pocketbase/pb_hooks/wesi_security.pb.js}"
if [[ ! -f "$HOOK" ]]; then
  echo "ERROR: hook not found: $HOOK" >&2
  exit 1
fi

cp -a "$HOOK" "${HOOK}.bak.$(date +%Y%m%d%H%M%S)"

python3 - "$HOOK" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const raw = record.get(field);
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };'''
new = '''  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const raw = record.get(field);
      if (raw && typeof raw === "object") return raw;
      if (typeof raw === "string" && raw.trim()) {
        try {
          const parsed = JSON.parse(raw);
          return parsed && typeof parsed === "object" ? parsed : {};
        } catch (_) {}
      }
      return {};
    } catch (_) { return {}; }
  };'''
count = text.count(old)
if count == 0:
    print("No matching valueObject(record, field) blocks found; hook may already be patched.")
else:
    text = text.replace(old, new)
    path.write_text(text)
    print(f"Patched {count} valueObject(record, field) block(s) in {path}")
PY

# Also patch the single-argument helper variant used by some newer hooks.
python3 - "$HOOK" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''  const valueObject = (record) => {
    try {
      const raw = record.get("payload");
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };'''
new = '''  const valueObject = (record) => {
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object") return raw;
      if (typeof raw === "string" && raw.trim()) {
        try {
          const parsed = JSON.parse(raw);
          return parsed && typeof parsed === "object" ? parsed : {};
        } catch (_) {}
      }
      return {};
    } catch (_) { return {}; }
  };'''
count = text.count(old)
if count:
    text = text.replace(old, new)
    path.write_text(text)
    print(f"Patched {count} valueObject(record) block(s) in {path}")
PY

echo "Payload parser patch complete."
