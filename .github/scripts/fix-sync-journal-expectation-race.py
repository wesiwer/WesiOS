from pathlib import Path

root = Path('.')

p = root / 'lib/core/sync/sync_journal.dart'
s = p.read_text(encoding='utf-8')

anchor = '''  static final Map<String, SyncStamp> _expected = {};

  /// Счётчик **своих** правок'''
replacement = '''  static final Map<String, SyncStamp> _expected = {};
  static final Map<String, DateTime> _expectedAt = {};

  /// Hive box events are asynchronous. A remote apply may finish before the
  /// watcher consumes its event, so an expectation must survive the end of a
  /// sync pass. It is deliberately short-lived: if an event never arrives, a
  /// real user edit later must never be mistaken for that old remote apply.
  static const Duration _expectationLifetime = Duration(seconds: 5);

  /// Счётчик **своих** правок'''
if anchor not in s:
    raise SystemExit('expected map anchor not found')
s = s.replace(anchor, replacement, 1)

anchor = '''      final k = key(collection, id);
      final expected = _expected.remove(k);
      _opened?.put(
        k,
        (expected ?? SyncStamp(SyncClock.now(), deleted: event.deleted))
            .encode(),
      );
      if (expected == null) localChanges.value++;
'''
replacement = '''      final k = key(collection, id);
      final expectedStamp = _expected.remove(k);
      final expectedAt = _expectedAt.remove(k);
      final now = DateTime.now();
      final age = expectedAt == null ? null : now.difference(expectedAt);
      final expected = expectedStamp != null &&
              age != null &&
              !age.isNegative &&
              age <= _expectationLifetime
          ? expectedStamp
          : null;
      _opened?.put(
        k,
        (expected ?? SyncStamp(SyncClock.now(), deleted: event.deleted))
            .encode(),
      );
      if (expected == null) localChanges.value++;
'''
if anchor not in s:
    raise SystemExit('watcher expectation anchor not found')
s = s.replace(anchor, replacement, 1)

anchor = '''    _watchers.clear();
    _expected.clear();
  }

  /// Предупредить журнал'''
replacement = '''    _watchers.clear();
    _expected.clear();
    _expectedAt.clear();
  }

  /// Предупредить журнал'''
if anchor not in s:
    raise SystemExit('detach anchor not found')
s = s.replace(anchor, replacement, 1)

anchor = '''  static void expect(String collection, String id, SyncStamp stamp) {
    _expected[key(collection, id)] = stamp;
  }

  static void forget(String collection, String id) =>
      _expected.remove(key(collection, id));

  static void clearExpectations() => _expected.clear();
'''
replacement = '''  static void expect(String collection, String id, SyncStamp stamp) {
    pruneExpectations();
    final k = key(collection, id);
    _expected[k] = stamp;
    _expectedAt[k] = DateTime.now();
  }

  static void forget(String collection, String id) {
    final k = key(collection, id);
    _expected.remove(k);
    _expectedAt.remove(k);
  }

  static void clearExpectations() {
    _expected.clear();
    _expectedAt.clear();
  }

  static void pruneExpectations() {
    if (_expectedAt.isEmpty) return;
    final now = DateTime.now();
    final expired = <String>[];
    for (final entry in _expectedAt.entries) {
      final age = now.difference(entry.value);
      if (age.isNegative || age > _expectationLifetime) expired.add(entry.key);
    }
    for (final k in expired) {
      _expected.remove(k);
      _expectedAt.remove(k);
    }
  }
'''
if anchor not in s:
    raise SystemExit('expect/forget anchor not found')
s = s.replace(anchor, replacement, 1)
p.write_text(s, encoding='utf-8')

p = root / 'lib/core/sync/sync_engine.dart'
s = p.read_text(encoding='utf-8')
anchor = '''      await SyncJournal.pruneTombstones(at);
      SyncJournal.clearExpectations();
'''
replacement = '''      await SyncJournal.pruneTombstones(at);
      // Do not clear fresh remote expectations here. Hive box.watch() events
      // are asynchronous and may be delivered just after this run returns.
      // Expired expectations are harmlessly pruned by wall-clock TTL instead.
      SyncJournal.pruneExpectations();
'''
if anchor not in s:
    raise SystemExit('engine clear expectations anchor not found')
s = s.replace(anchor, replacement, 1)
p.write_text(s, encoding='utf-8')

p = root / 'test/sync_receive_regression_test.dart'
s = p.read_text(encoding='utf-8')
old = '''  test('fresh interactive login starts receive polling for every employee', () {
    final source =
        File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(source, contains('await SyncEngine.runOnLaunch();'));
    expect(source, contains('SyncAuto.start();'));
    expect(source, isNot(contains('if (employee.isOwner) {')));
  });

  test('initial remote watermark is never accepted from stale lastReport', () {
    final source = File('lib/core/sync/sync_auto.dart').readAsStringSync();
    expect(source, isNot(contains('SyncEngine.lastReport.value?.ok == true')));
    expect(
      source,
      contains(
        'if (_remoteRevision == null) {\\n        final report = await _runAuto();',
      ),
    );
  });
'''
new = '''  test('fresh interactive login serializes rebind, pull and receive polling', () {
    final source =
        File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(
      source,
      contains('await SyncFeatureExtensions.rebindCurrentAccountAndSync();'),
    );
    expect(source, isNot(contains('await SyncEngine.runOnLaunch();')));
    expect(source, isNot(contains('if (employee.isOwner) {')));
  });

  test('remote watermark is accepted only after the matching pull succeeds', () {
    final source = File('lib/core/sync/sync_auto.dart').readAsStringSync();
    expect(source, isNot(contains('SyncEngine.lastReport.value?.ok == true')));
    expect(source, contains('final observedRevision = result.value!;'));
    expect(source, contains('final report = await _runAuto();'));
    expect(source, contains('_acceptObservedRevision(observedRevision);'));
    final observed = source.indexOf('final observedRevision = result.value!;');
    final run = source.indexOf('final report = await _runAuto();', observed);
    final accepted = source.indexOf(
      '_acceptObservedRevision(observedRevision);',
      run,
    );
    expect(observed, greaterThanOrEqualTo(0));
    expect(run, greaterThan(observed));
    expect(accepted, greaterThan(run));
  });
'''
if old not in s:
    raise SystemExit('receive regression source assertions anchor not found')
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')

# Static contract catches accidental return to end-of-pass global clearing.
t = root / 'test/sync_journal_expectation_race_test.dart'
t.write_text('''import 'dart:io';\n\nimport 'package:flutter_test/flutter_test.dart';\n\nvoid main() {\n  test('remote expectations survive run completion but expire for real edits', () {\n    final journal = File('lib/core/sync/sync_journal.dart').readAsStringSync();\n    final engine = File('lib/core/sync/sync_engine.dart').readAsStringSync();\n    expect(journal, contains('_expectationLifetime = Duration(seconds: 5)'));\n    expect(journal, contains('age <= _expectationLifetime'));\n    expect(journal, contains('static void pruneExpectations()'));\n    expect(engine, contains('SyncJournal.pruneExpectations();'));\n    expect(engine, isNot(contains('SyncJournal.clearExpectations();')));\n  });\n}\n''', encoding='utf-8')

for rel in [
    'lib/core/sync/sync_journal.dart',
    'lib/core/sync/sync_engine.dart',
    'test/sync_receive_regression_test.dart',
    'test/sync_journal_expectation_race_test.dart',
]:
    path = root / rel
    path.write_text('\n'.join(line.rstrip() for line in path.read_text(encoding='utf-8').splitlines()) + '\n', encoding='utf-8')

print('SYNC_JOURNAL_EXPECTATION_RACE_PATCH_READY')
