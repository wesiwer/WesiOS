from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    source = p.read_text(encoding="utf-8")
    if old not in source:
        raise SystemExit(f"pattern not found in {path}: {old[:120]!r}")
    p.write_text(source.replace(old, new, 1), encoding="utf-8")


# Keep the existing equal-timestamp policy. Raw server fields can normalize
# during model decode/encode, so comparing them directly would re-apply the
# same remote row on every pass and can create an echo loop.
replace(
    "lib/core/sync/sync_merge.dart",
    """class SyncMerge {
  static bool _sameValue(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameValue(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameValue(a[i], b[i])) return false;
      }
      return true;
    }
    return false;
  }

  /// Побеждает более поздняя правка — **по записи**, а не по всему документу.
""",
    """class SyncMerge {
  /// Побеждает более поздняя правка — **по записи**, а не по всему документу.
""",
)

replace(
    "lib/core/sync/sync_merge.dart",
    """        // Ровно одинаковое время — не «одно и то же». При delete/live
        // споре удаление побеждает, чтобы стёртая запись не воскресла.
        // Если обе копии живы, но поля различаются, серверная копия является
        // детерминированным tie-breaker. Важно не только положить её в merged,
        // но и реально применить локально — раньше этот шаг отсутствовал и
        // устройство могло навсегда остаться с другой версией данных.
        if (l.deleted || r.deleted) {
          merged[id] = l.deleted ? l : r;
          if (l.deleted && !r.deleted) toUpload.add(l);
          if (r.deleted && !l.deleted) toApplyLocally.add(r);
        } else {
          merged[id] = r;
          if (!_sameValue(l.fields, r.fields)) {
            toApplyLocally.add(r);
          }
        }
""",
    """        // Ровно одинаковое время — не «одно и то же». Часы двух устройств
        // расходятся, и совпадение до миллисекунды скорее случайность.
        // При споре выбираем удаление: воскресить стёртое хуже, чем
        // потерять правку, сделанную в ту же миллисекунду на другом
        // устройстве. Первое — потеря доверия к удалению, второе —
        // крайне редкий случай, который человек переделает.
        merged[id] = l.deleted ? l : r;
        if (l.deleted && !r.deleted) toUpload.add(l);
        if (r.deleted && !l.deleted) toApplyLocally.add(r);
""",
)

# The old engine test intentionally checked that an unknown future-version row
# is not marked as consumed. It must now also require the overall pass to stay
# incomplete so SyncAuto cannot advance its receive watermark.
replace(
    "test/sync_engine_test.dart",
    """      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isTrue);
      expect(txBox().get('future'), isNull);
""",
    """      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isFalse);
      expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');
      expect(txBox().get('future'), isNull);
""",
)

# Drop the experimental equal-timestamp regression from the new receive suite;
# the existing sync_merge_test keeps the established no-loop contract covered.
p = Path("test/sync_receive_regression_test.dart")
source = p.read_text(encoding="utf-8")
start = source.index("  test('equal timestamp divergent live rows apply the server copy'")
end = source.index("  test('fresh interactive login starts receive polling for every employee'", start)
source = source[:start] + source[end:]
source = source.replace("import 'package:wesios/core/sync/sync_merge.dart';\n", "")
p.write_text(source, encoding="utf-8")
