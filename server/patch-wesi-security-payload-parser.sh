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

replacements = []

replacements.append((
'''  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const raw = record.get(field);
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };''',
'''  const valueObject = (record, field) => {
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
))

replacements.append((
'''  const valueObject = (record) => {
    try {
      const raw = record.get("payload");
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };''',
'''  const valueObject = (record) => {
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
))

# Middleware session parser: without this, OTP verification can succeed but
# the very next /bootstrap request is rejected as an invalid WesiOS session.
replacements.append((
'''    let payload = {};
    try {
      const raw = record.get("payload");
      payload = raw && typeof raw === "object" ? raw : {};
    } catch (_) {
      payload = {};
    }''',
'''    let payload = {};
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object") {
        payload = raw;
      } else if (typeof raw === "string" && raw.trim()) {
        try {
          const parsed = JSON.parse(raw);
          payload = parsed && typeof parsed === "object" ? parsed : {};
        } catch (_) {
          payload = {};
        }
      }
    } catch (_) {
      payload = {};
    }'''
))

# A few handlers read the payload directly instead of going through
# valueObject(). Make those tolerant of PocketBase returning a JSON string too.
replacements.append((
'''  const payload = record.get("payload") || {};''',
'''  let payload = {};
  try {
    const rawPayload = record.get("payload");
    if (rawPayload && typeof rawPayload === "object") {
      payload = rawPayload;
    } else if (typeof rawPayload === "string" && rawPayload.trim()) {
      const parsedPayload = JSON.parse(rawPayload);
      payload = parsedPayload && typeof parsedPayload === "object" ? parsedPayload : {};
    }
  } catch (_) {
    payload = {};
  }'''
))

patched = 0
for old, new in replacements:
    count = text.count(old)
    if count:
        text = text.replace(old, new)
        patched += count
        print(f"Patched {count} matching block(s)")

path.write_text(text)
print(f"Payload parser patch complete: {patched} block(s) changed in {path}")
PY

grep -n "JSON.parse(raw)\|JSON.parse(rawPayload)" "$HOOK" | head -20 || true
