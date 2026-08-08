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

# PocketBase JSON fields may reach JSVM as JSONRaw byte arrays (typeof ===
# "object"), as JSONMap-like objects, or as JSON strings depending on the
# schema/runtime path. Normalize all of those into a plain JS object.
keys = [
    "kind", "challengeId", "userId", "employeeId", "login", "email",
    "purpose", "hash", "salt", "attempts", "sentAt", "expiresAt",
    "usedAt", "delivery", "sessionId", "revokedAt", "createdAt",
    "lastSeenAt", "platform", "deviceName", "timezone", "country",
    "userAgent", "fullName", "name", "ownerId",
]
keys_js = ", ".join('"%s"' % k for k in keys)

normalizer = f'''  const normalizeJsonValue = (raw) => {{
    if (!raw) return {{}};

    const parseText = (text) => {{
      try {{
        let parsed = JSON.parse(String(text || ""));
        if (typeof parsed === "string" && parsed.trim()) {{
          try {{ parsed = JSON.parse(parsed); }} catch (_) {{}}
        }}
        return parsed && typeof parsed === "object" ? parsed : {{}};
      }} catch (_) {{ return {{}}; }}
    }};

    if (typeof raw === "string") return parseText(raw);

    if (typeof raw === "object") {{
      // PocketBase JSONMap-like value.
      if (typeof raw.get === "function") {{
        const out = {{}};
        const keys = [{keys_js}];
        let found = false;
        for (const key of keys) {{
          try {{
            const value = raw.get(key);
            if (value !== undefined && value !== null) {{
              out[key] = value;
              found = true;
            }}
          }} catch (_) {{}}
        }}
        if (found) return out;
      }}

      // PocketBase JSONRaw ([]byte) value. JSON fields are documented as raw
      // byte arrays in JSVM exports; decode them before property access.
      if (typeof raw.length === "number" && raw.length >= 0) {{
        try {{
          let text = "";
          for (let i = 0; i < raw.length; i++) {{
            text += String.fromCharCode(Number(raw[i]) & 255);
          }}
          const parsed = parseText(text);
          if (parsed && typeof parsed === "object" && Object.keys(parsed).length) {{
            return parsed;
          }}
        }} catch (_) {{}}
      }}

      // Already a normal plain object.
      if (!Array.isArray(raw)) return raw;
    }}

    return {{}};
  }};'''

old_simple_field = '''  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const raw = record.get(field);
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };'''

old_patched_field = '''  const valueObject = (record, field) => {
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

new_field = normalizer + '''\n  const valueObject = (record, field) => {
    if (!record) return {};
    try { return normalizeJsonValue(record.get(field)); }
    catch (_) { return {}; }
  };'''

old_simple_single = '''  const valueObject = (record) => {
    try {
      const raw = record.get("payload");
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) { return {}; }
  };'''

old_patched_single = '''  const valueObject = (record) => {
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

new_single = normalizer + '''\n  const valueObject = (record) => {
    try { return normalizeJsonValue(record.get("payload")); }
    catch (_) { return {}; }
  };'''

old_session_simple = '''    let payload = {};
    try {
      const raw = record.get("payload");
      payload = raw && typeof raw === "object" ? raw : {};
    } catch (_) {
      payload = {};
    }'''

old_session_patched = '''    let payload = {};
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

session_normalizer = normalizer.replace("  const normalizeJsonValue", "    const normalizeJsonValue")
new_session = session_normalizer + '''\n    let payload = {};
    try { payload = normalizeJsonValue(record.get("payload")); }
    catch (_) { payload = {}; }'''

old_direct_simple = '''  const payload = record.get("payload") || {};'''
old_direct_patched = '''  let payload = {};
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
new_direct = normalizer + '''\n  let payload = {};
  try { payload = normalizeJsonValue(record.get("payload")); }
  catch (_) { payload = {}; }'''

replacements = [
    (old_patched_field, new_field),
    (old_simple_field, new_field),
    (old_patched_single, new_single),
    (old_simple_single, new_single),
    (old_session_patched, new_session),
    (old_session_simple, new_session),
    (old_direct_patched, new_direct),
    (old_direct_simple, new_direct),
]

patched = 0
for old, new in replacements:
    count = text.count(old)
    if count:
        text = text.replace(old, new)
        patched += count
        print(f"Patched {count} matching block(s)")

path.write_text(text)
print(f"JSONRaw payload parser patch complete: {patched} block(s) changed in {path}")
PY

grep -n "JSONRaw\|normalizeJsonValue" "$HOOK" | head -40 || true
