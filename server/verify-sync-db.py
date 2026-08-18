#!/usr/bin/env python3
"""Verify the physical SQLite invariants required by WesiOS sync."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-sync-db.py /path/to/data.db", file=sys.stderr)
        return 64

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"PocketBase DB not found: {path}", file=sys.stderr)
        return 2

    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error as exc:
        print(f"cannot open PocketBase DB: {exc}", file=sys.stderr)
        return 2

    try:
        table = db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='wesios_records'"
        ).fetchone()
        if table is None:
            print("wesios_records table is missing", file=sys.stderr)
            return 2

        indexes = db.execute("PRAGMA index_list('wesios_records')").fetchall()
        matches = [row for row in indexes if row[1] == "idx_wesios_rid"]
        if not matches or int(matches[0][2]) != 1:
            print("idx_wesios_rid is missing or not UNIQUE", file=sys.stderr)
            return 2

        columns = [
            row[2]
            for row in db.execute("PRAGMA index_info('idx_wesios_rid')").fetchall()
        ]
        if columns != ["owner", "coll", "rid"]:
            print(
                f"idx_wesios_rid has wrong columns: {columns}",
                file=sys.stderr,
            )
            return 2

        duplicate_groups = db.execute(
            "SELECT COUNT(*) FROM ("
            "SELECT owner, coll, rid FROM wesios_records "
            "GROUP BY owner, coll, rid HAVING COUNT(*) > 1)"
        ).fetchone()[0]
        if duplicate_groups:
            print(
                f"duplicate sync identities remain: {duplicate_groups}",
                file=sys.stderr,
            )
            return 2

        print("Sync DB invariant OK: UNIQUE(owner, coll, rid), duplicates=0")
        return 0
    except sqlite3.Error as exc:
        print(f"sync DB verification failed: {exc}", file=sys.stderr)
        return 2
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
