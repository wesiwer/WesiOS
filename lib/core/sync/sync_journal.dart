import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'sync_account_scope.dart';
import 'sync_clock.dart';

class SyncStamp {
  final DateTime updatedAt;
  final bool deleted;

  const SyncStamp(this.updatedAt, {this.deleted = false});

  String encode() =>
      '${updatedAt.toUtc().toIso8601String()}|${deleted ? 1 : 0}';

  static SyncStamp? decode(Object? raw) {
    if (raw is! String) return null;
    final bar = raw.lastIndexOf('|');
    if (bar < 0) return null;
    final at = DateTime.tryParse(raw.substring(0, bar));
    if (at == null) return null;
    return SyncStamp(at, deleted: raw.substring(bar + 1) == '1');
  }

  @override
  String toString() => 'SyncStamp(${encode()})';
}

/// Journal timestamps/tombstones for the current authenticated account.
class SyncJournal {
  static const String baseBoxName = 'wesios_sync_journal';
  static String get boxName => SyncAccountScope.boxName(baseBoxName);

  static Box<dynamic>? _box;
  static String? _openedBoxName;
  static final Map<String, StreamSubscription<BoxEvent>> _watchers = {};

  /// Expected Hive events created by applying remote data.
  ///
  /// box.watch() is asynchronous: applyFields may finish before its event is
  /// delivered. Therefore an expectation must survive the end of a sync run,
  /// otherwise that late event looks like a fresh user edit and receives a new
  /// local timestamp, causing an upload ping-pong back to the server.
  static final Map<String, SyncStamp> _expected = {};
  static final Map<String, DateTime> _expectedAt = {};
  static const Duration _expectationLifetime = Duration(seconds: 5);

  static final ValueNotifier<int> localChanges = ValueNotifier<int>(0);

  static String key(String collection, String id) => '$collection/$id';

  static Future<Box<dynamic>> open() async {
    final currentName = boxName;
    final cached = _box;
    if (cached != null && cached.isOpen && _openedBoxName == currentName) {
      return cached;
    }

    if (cached != null && cached.isOpen && _openedBoxName != currentName) {
      await cached.close();
    }

    final opened = Hive.isBoxOpen(currentName)
        ? Hive.box<dynamic>(currentName)
        : await Hive.openBox<dynamic>(currentName);
    _box = opened;
    _openedBoxName = currentName;
    return opened;
  }

  static Box<dynamic>? get _opened {
    final currentName = boxName;
    final box = _box;
    if (box != null && box.isOpen && _openedBoxName == currentName) return box;
    if (!Hive.isBoxOpen(currentName)) return null;
    _openedBoxName = currentName;
    return _box = Hive.box<dynamic>(currentName);
  }

  static void attach(
    String collection,
    BoxBase<dynamic> box, {
    bool Function(Object? key)? acceptsKey,
    String Function(Object? key)? syncIdForKey,
  }) {
    if (_watchers.containsKey(collection)) return;
    _watchers[collection] = box.watch().listen((event) {
      if (acceptsKey != null && !acceptsKey(event.key)) return;
      final id = syncIdForKey?.call(event.key) ?? '${event.key}';
      if (id.isEmpty) return;

      final k = key(collection, id);
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
    });
  }

  static Future<void> detach() async {
    for (final sub in _watchers.values) {
      await sub.cancel();
    }
    _watchers.clear();
    discardExpectations();
  }

  static void expect(String collection, String id, SyncStamp stamp) {
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

  /// Backwards-compatible end-of-pass hook.
  ///
  /// Fresh expectations are intentionally NOT cleared here. Existing engine
  /// code calls this after a normal run; turning it into TTL pruning fixes the
  /// asynchronous Hive watcher race without swallowing a later real user edit.
  static void clearExpectations() => pruneExpectations();

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

  /// Жёстко выбрасывает все remote expectations.
  ///
  /// Используется только на lifecycle/account boundary. В отличие от
  /// [clearExpectations] здесь нельзя оставлять свежие ожидания на TTL: event
  /// старого аккаунта после logout не должен быть принят новым lifecycle даже
  /// в течение нескольких миллисекунд.
  static void discardExpectations() {
    _expected.clear();
    _expectedAt.clear();
  }

  static SyncStamp? stampOf(String collection, String id) =>
      SyncStamp.decode(_opened?.get(key(collection, id)));

  static Future<void> record(
    String collection,
    String id,
    SyncStamp stamp,
  ) async {
    await _opened?.put(key(collection, id), stamp.encode());
  }

  static Map<String, SyncStamp> forCollection(String collection) {
    final box = _opened;
    if (box == null) return const {};
    final prefix = '$collection/';
    final out = <String, SyncStamp>{};
    for (final k in box.keys) {
      final s = '$k';
      if (!s.startsWith(prefix)) continue;
      final stamp = SyncStamp.decode(box.get(k));
      if (stamp != null) out[s.substring(prefix.length)] = stamp;
    }
    return out;
  }

  static Future<void> seed(
    String collection,
    Iterable<String> ids,
    DateTime at,
  ) async {
    final box = _opened;
    if (box == null) return;
    final stamp = SyncStamp(at).encode();
    final missing = <String, String>{};
    for (final id in ids) {
      final k = key(collection, id);
      if (box.get(k) == null) missing[k] = stamp;
    }
    if (missing.isNotEmpty) await box.putAll(missing);
  }

  static Future<void> pruneTombstones(
    DateTime now, {
    Duration keepFor = const Duration(days: 180),
  }) async {
    final box = _opened;
    if (box == null) return;
    final dead = <dynamic>[];
    for (final k in box.keys) {
      final stamp = SyncStamp.decode(box.get(k));
      if (stamp == null) {
        dead.add(k);
        continue;
      }
      if (stamp.deleted && now.difference(stamp.updatedAt) >= keepFor) {
        dead.add(k);
      }
    }
    if (dead.isNotEmpty) await box.deleteAll(dead);
  }
}
