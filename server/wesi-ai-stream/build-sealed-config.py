#!/usr/bin/env python3
"""Build Wesi AI relay/stream sealed configuration without needless rotation.

The previous workflow generated a new stream secret on every deploy. A partial
rollout could then restart one side while the other kept the previous secret.
This builder reuses the currently installed Main config whenever possible and
only generates a secret on first installation.
"""

from __future__ import annotations

import base64
import json
import os
import secrets
import sys
from pathlib import Path


def valid_secret(value: object) -> str:
    text = str(value or "").strip()
    return text if len(text) >= 32 else ""


def add(mapping: dict[str, str], key: str, value: str) -> None:
    if value:
        mapping[key] = value


def b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def load_existing(path: Path) -> dict[str, object]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def main() -> None:
    existing_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("existing-wesi-ai-relay.json")
    existing = load_existing(existing_path)

    public_host = os.environ["PUBLIC_HOST"].strip()
    provided_shared = valid_secret(os.environ.get("PROVIDED_SHARED", ""))
    existing_shared = valid_secret(existing.get("sharedSecret"))
    existing_stream = valid_secret(existing.get("streamSecret"))

    shared = provided_shared or existing_shared or secrets.token_hex(32)
    stream = existing_stream or secrets.token_hex(32)

    # GitHub Actions masks any later accidental appearance of these values.
    print(f"::add-mask::{shared}")
    print(f"::add-mask::{stream}")
    print(
        "sealed_source="
        + (
            "github_shared+existing_stream"
            if provided_shared and existing_stream
            else "existing"
            if existing_shared and existing_stream
            else "first_install"
        )
    )

    relay = {
        "WESI_MAIN_SHARED_SECRET_B64": shared,
        "GEMINI_API_KEY_B64": os.environ["GEMINI_KEY"],
    }
    for i in range(2, 6):
        add(relay, f"GEMINI_API_KEY_{i}_B64", os.environ.get(f"GEMINI_KEY_{i}", ""))
    add(relay, "GROQ_API_KEY_B64", os.environ.get("GROQ_KEY", ""))
    add(relay, "MISTRAL_API_KEY_B64", os.environ.get("MISTRAL_KEY", ""))
    add(relay, "OPENROUTER_API_KEY_B64", os.environ.get("OPENROUTER_KEY", ""))
    add(relay, "WESI_ZANE_TTS_VOICE_B64", os.environ.get("ZANE_VOICE", ""))
    add(relay, "WESI_NIRVANA_TTS_VOICE_B64", os.environ.get("NIRVANA_VOICE", ""))
    with open("relay-secrets.b64", "w", encoding="ascii") as handle:
        for key, value in relay.items():
            handle.write(f"{key}={b64(value)}\n")

    main_cfg = {
        "url": "https://" + public_host,
        "sharedSecret": shared,
        "streamSecret": stream,
        "routes": {"fast": "wesi/fast", "pro": "wesi/pro", "maximum": "wesi/ultra"},
    }
    Path("wesi-ai-relay.json").write_text(
        json.dumps(main_cfg, ensure_ascii=False), encoding="utf-8"
    )

    stream_env = {
        "WESI_STREAM_SECRET_B64": stream,
        "WESI_MAIN_SHARED_SECRET_B64": shared,
        "WESI_RELAY_URL_B64": "https://" + public_host,
        "WESI_POCKETBASE_URL_B64": "https://api.wesi-inc.ru",
    }
    with open("stream-secrets.b64", "w", encoding="ascii") as handle:
        for key, value in stream_env.items():
            handle.write(f"{key}={b64(value)}\n")

    configured_gemini = 1 + sum(
        bool(os.environ.get(f"GEMINI_KEY_{i}")) for i in range(2, 6)
    )
    print(f"configured_gemini_slots={configured_gemini}")


if __name__ == "__main__":
    main()
