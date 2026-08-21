#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AMBIENT = ROOT / "lib/src/widgets/ambient_background.dart"


def main() -> None:
    text = AMBIENT.read_text(encoding="utf-8")
    old = "  final ValueListenable<double> phase;"
    new = "  final ValueNotifier<double> phase;"
    if new not in text:
        if text.count(old) != 1:
            raise SystemExit(
                f"ambient perf compatibility patch expected one anchor, found {text.count(old)}"
            )
        text = text.replace(old, new, 1)
        AMBIENT.write_text(text, encoding="utf-8")
    print("Applied Flutter 3.47 ambient notifier compatibility patch")


if __name__ == "__main__":
    main()
