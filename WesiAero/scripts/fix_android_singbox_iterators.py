#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroSingBoxVpnService.kt"


def main() -> None:
    if not SERVICE.is_file():
        raise SystemExit("AeroSingBoxVpnService.kt is missing; configure sing-box first")

    text = SERVICE.read_text(encoding="utf-8")
    old = '''    internal class StringArray(
        private val iterator: Iterator<String>,
    ) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }
'''
    new = '''    internal class StringArray(source: Iterator<String>) : StringIterator {
        private val values = ArrayList<String>().apply {
            while (source.hasNext()) add(source.next())
        }
        private var index = 0

        override fun len(): Int = values.size
        override fun hasNext(): Boolean = index < values.size
        override fun next(): String {
            if (!hasNext()) throw NoSuchElementException("No more sing-box iterator values")
            return values[index++]
        }
    }
'''

    if new not in text:
        count = text.count(old)
        if count != 1:
            raise SystemExit(f"sing-box StringIterator anchor mismatch: expected 1, found {count}")
        text = text.replace(old, new, 1)

    # Defensive check: a zero length StringIterator makes libbox treat populated
    # Android interface/DNS/package/certificate lists as empty on some paths.
    if re.search(r"override fun len\(\): Int = 0\b", text):
        raise SystemExit("sing-box StringIterator still reports zero length")
    if "override fun len(): Int = values.size" not in text:
        raise SystemExit("sing-box StringIterator length fix was not applied")

    SERVICE.write_text(text, encoding="utf-8")
    print("Fixed sing-box Android StringIterator length/materialization semantics")


if __name__ == "__main__":
    main()
