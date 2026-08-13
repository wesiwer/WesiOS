#!/usr/bin/env python3
"""Build the Wesi AI runtime persona bundle from authoritative Persona Bible.

The generated JSON is deployment material and must not be edited by hand.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "server" / "pb_hooks" / ".wesi-ai-personas.json"
SOURCES = {
    "zane": ROOT / "docs" / "wesi_ai" / "personas" / "ZANE_PERSONA.md",
    "nirvana": ROOT / "docs" / "wesi_ai" / "personas" / "NIRVANA_PERSONA.md",
}


def extract_system_prompt(text: str, source: Path) -> str:
    marker = "Канонический системный промпт v2.0"
    pos = text.find(marker)
    if pos < 0:
        raise RuntimeError(f"Missing canonical prompt section in {source}")
    tail = text[pos:]
    match = re.search(r"```text\s*\n(.*?)\n```", tail, flags=re.S)
    if not match:
        raise RuntimeError(f"Missing fenced canonical prompt in {source}")
    prompt = match.group(1).strip()
    if len(prompt) < 200:
        raise RuntimeError(f"Canonical prompt is unexpectedly short in {source}")
    return prompt


def main() -> None:
    personas: dict[str, str] = {}
    for key, path in SOURCES.items():
        personas[key] = extract_system_prompt(path.read_text(encoding="utf-8"), path)

    payload = {
        "schemaVersion": 1,
        "source": "docs/wesi_ai/personas/*_PERSONA.md",
        "personas": personas,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
