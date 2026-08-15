import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'wesi_local_runtime_models.dart';

class WesiSelfDebugStop implements Exception {
  final String code;
  final String message;
  final bool blocked;
  final int repairIteration;
  final int toolCalls;

  const WesiSelfDebugStop(
    this.code,
    this.message, {
    this.blocked = true,
    this.repairIteration = 0,
    this.toolCalls = 0,
  });

  @override
  String toString() => '$code: $message';
}

class WesiSelfDebugPersistedOutcome {
  final String key;
  final bool ok;
  final String code;
  final int? exitCode;
  final String summary;

  const WesiSelfDebugPersistedOutcome({
    required this.key,
    required this.ok,
    required this.code,
    required this.summary,
    this.exitCode,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'ok': ok,
        'code': code,
        if (exitCode != null) 'exitCode': exitCode,
        'summary': summary,
      };

  static WesiSelfDebugPersistedOutcome fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final ok = json['ok'];
    final code = json['code'];
    final exitCode = json['exitCode'];
    final summary = json['summary'];
    if (key is! String ||
        !_validStepKey(key) ||
        ok is! bool ||
        code is! String ||
        code.isEmpty ||
        code.length > 128 ||
        (exitCode != null && exitCode is! int) ||
        summary is! String ||
        summary.length >
            WesiSelfDebugCheckpointManager.maxOutcomeSummaryChars) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Persisted self-debug outcome is invalid',
      );
    }
    return WesiSelfDebugPersistedOutcome(
      key: key,
      ok: ok,
      code: code,
      exitCode: exitCode as int?,
      summary: summary,
    );
  }
}

class WesiSelfDebugCheckpointState {
  static const int schemaVersion = 1;

  final String requestId;
  final String planFingerprint;
  final Map<int, String> repairFingerprints;
  final String? currentPhase;
  final String? currentStepKey;
  final String? currentStepId;
  final int repairIteration;
  final int toolCalls;
  final String? inFlightStepKey;
  final WesiLocalRisk? inFlightRisk;
  final Map<String, WesiSelfDebugPersistedOutcome> outcomes;
  final int revision;
  final DateTime updatedAt;

  const WesiSelfDebugCheckpointState({
    required this.requestId,
    required this.planFingerprint,
    required this.repairFingerprints,
    required this.repairIteration,
    required this.toolCalls,
    required this.outcomes,
    required this.revision,
    required this.updatedAt,
    this.currentPhase,
    this.currentStepKey,
    this.currentStepId,
    this.inFlightStepKey,
    this.inFlightRisk,
  });

  WesiSelfDebugCheckpointState copyWith({
    Map<int, String>? repairFingerprints,
    Object? currentPhase = _unset,
    Object? currentStepKey = _unset,
    Object? currentStepId = _unset,
    int? repairIteration,
    int? toolCalls,
    Object? inFlightStepKey = _unset,
    Object? inFlightRisk = _unset,
    Map<String, WesiSelfDebugPersistedOutcome>? outcomes,
    int? revision,
    DateTime? updatedAt,
  }) =>
      WesiSelfDebugCheckpointState(
        requestId: requestId,
        planFingerprint: planFingerprint,
        repairFingerprints: repairFingerprints ?? this.repairFingerprints,
        currentPhase: identical(currentPhase, _unset)
            ? this.currentPhase
            : currentPhase as String?,
        currentStepKey: identical(currentStepKey, _unset)
            ? this.currentStepKey
            : currentStepKey as String?,
        currentStepId: identical(currentStepId, _unset)
            ? this.currentStepId
            : currentStepId as String?,
        repairIteration: repairIteration ?? this.repairIteration,
        toolCalls: toolCalls ?? this.toolCalls,
        inFlightStepKey: identical(inFlightStepKey, _unset)
            ? this.inFlightStepKey
            : inFlightStepKey as String?,
        inFlightRisk: identical(inFlightRisk, _unset)
            ? this.inFlightRisk
            : inFlightRisk as WesiLocalRisk?,
        outcomes: outcomes ?? this.outcomes,
        revision: revision ?? this.revision,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'requestId': requestId,
        'planFingerprint': planFingerprint,
        'repairFingerprints': <String, String>{
          for (final entry in repairFingerprints.entries)
            entry.key.toString(): entry.value,
        },
        if (currentPhase != null) 'currentPhase': currentPhase,
        if (currentStepKey != null) 'currentStepKey': currentStepKey,
        if (currentStepId != null) 'currentStepId': currentStepId,
        'repairIteration': repairIteration,
        'toolCalls': toolCalls,
        if (inFlightStepKey != null) 'inFlightStepKey': inFlightStepKey,
        if (inFlightRisk != null) 'inFlightRisk': inFlightRisk!.name,
        'outcomes': <String, dynamic>{
          for (final entry in outcomes.entries) entry.key: entry.value.toJson(),
        },
        'revision': revision,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static WesiSelfDebugCheckpointState fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_VERSION',
        'Unsupported self-debug checkpoint schema version',
      );
    }
    final requestId = json['requestId'];
    final planFingerprint = json['planFingerprint'];
    final repairRaw = json['repairFingerprints'];
    final currentPhase = json['currentPhase'];
    final currentStepKey = json['currentStepKey'];
    final currentStepId = json['currentStepId'];
    final repairIteration = json['repairIteration'];
    final toolCalls = json['toolCalls'];
    final inFlightStepKey = json['inFlightStepKey'];
    final inFlightRiskName = json['inFlightRisk'];
    final outcomesRaw = json['outcomes'];
    final revision = json['revision'];
    final updatedAtRaw = json['updatedAt'];

    if (requestId is! String ||
        !_validRequestId(requestId) ||
        planFingerprint is! String ||
        !_validFingerprint(planFingerprint) ||
        repairRaw is! Map ||
        (currentPhase != null &&
            (currentPhase is! String || currentPhase.length > 64)) ||
        (currentStepKey != null &&
            (currentStepKey is! String || !_validStepKey(currentStepKey))) ||
        (currentStepId != null &&
            (currentStepId is! String || currentStepId.length > 128)) ||
        repairIteration is! int ||
        repairIteration < 0 ||
        repairIteration > 100 ||
        toolCalls is! int ||
        toolCalls < 0 ||
        toolCalls > 10000 ||
        (inFlightStepKey != null &&
            (inFlightStepKey is! String || !_validStepKey(inFlightStepKey))) ||
        (inFlightRiskName != null && inFlightRiskName is! String) ||
        outcomesRaw is! Map ||
        revision is! int ||
        revision < 0 ||
        updatedAtRaw is! String) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Persisted self-debug checkpoint is invalid',
      );
    }

    final repair = <int, String>{};
    for (final entry in repairRaw.entries) {
      final iteration = int.tryParse(entry.key.toString());
      final fingerprint = entry.value;
      if (iteration == null ||
          iteration < 1 ||
          iteration > 100 ||
          fingerprint is! String ||
          !_validFingerprint(fingerprint)) {
        throw const WesiSelfDebugStop(
          'WSD_CHECKPOINT_CORRUPT',
          'Persisted repair fingerprint is invalid',
        );
      }
      repair[iteration] = fingerprint;
    }

    if (outcomesRaw.length > WesiSelfDebugCheckpointManager.maxOutcomes) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_LIMIT',
        'Persisted self-debug outcomes exceed the bounded limit',
      );
    }
    final outcomes = <String, WesiSelfDebugPersistedOutcome>{};
    for (final entry in outcomesRaw.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const WesiSelfDebugStop(
          'WSD_CHECKPOINT_CORRUPT',
          'Persisted self-debug outcome map is invalid',
        );
      }
      final outcome = WesiSelfDebugPersistedOutcome.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (outcome.key != entry.key || outcomes.containsKey(entry.key)) {
        throw const WesiSelfDebugStop(
          'WSD_CHECKPOINT_CORRUPT',
          'Persisted self-debug outcome key is inconsistent',
        );
      }
      outcomes[entry.key as String] = outcome;
    }

    WesiLocalRisk? inFlightRisk;
    if (inFlightRiskName != null) {
      try {
        inFlightRisk = WesiLocalRisk.values.byName(inFlightRiskName as String);
      } on ArgumentError {
        throw const WesiSelfDebugStop(
          'WSD_CHECKPOINT_CORRUPT',
          'Persisted in-flight risk is unknown',
        );
      }
    }
    if ((inFlightStepKey == null) != (inFlightRisk == null)) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Persisted in-flight step is incomplete',
      );
    }

    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Persisted checkpoint timestamp is invalid',
      );
    }

    return WesiSelfDebugCheckpointState(
      requestId: requestId,
      planFingerprint: planFingerprint,
      repairFingerprints: Map<int, String>.unmodifiable(repair),
      currentPhase: currentPhase as String?,
      currentStepKey: currentStepKey as String?,
      currentStepId: currentStepId as String?,
      repairIteration: repairIteration,
      toolCalls: toolCalls,
      inFlightStepKey: inFlightStepKey as String?,
      inFlightRisk: inFlightRisk,
      outcomes:
          Map<String, WesiSelfDebugPersistedOutcome>.unmodifiable(outcomes),
      revision: revision,
      updatedAt: updatedAt.toUtc(),
    );
  }
}

abstract class WesiSelfDebugCheckpointJournal {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

class WesiMemorySelfDebugCheckpointJournal
    implements WesiSelfDebugCheckpointJournal {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class WesiFileSelfDebugCheckpointJournal
    implements WesiSelfDebugCheckpointJournal {
  final File file;
  final int maxBytes;

  const WesiFileSelfDebugCheckpointJournal(
    this.file, {
    this.maxBytes = 1024 * 1024,
  });

  File get _previous => File('${file.path}.previous');

  @override
  Future<String?> read() async {
    File? source;
    if (await file.exists()) {
      source = file;
    } else if (await _previous.exists()) {
      source = _previous;
    }
    if (source == null) return null;
    final size = await source.length();
    if (size <= 0 || size > maxBytes) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_LIMIT',
        'Self-debug checkpoint journal size is invalid',
      );
    }
    return utf8.decode(await source.readAsBytes());
  }

  @override
  Future<void> write(String value) async {
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_LIMIT',
        'Self-debug checkpoint exceeds the bounded journal limit',
      );
    }
    await file.parent.create(recursive: true);
    final temp = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await _previous.exists()) await _previous.delete();
      if (await file.exists()) await file.rename(_previous.path);
      await temp.rename(file.path);
      if (await _previous.exists()) await _previous.delete();
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (!await file.exists() && await _previous.exists()) {
        await _previous.rename(file.path);
      }
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_IO',
        'Self-debug checkpoint could not be persisted safely',
      );
    }
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
    if (await _previous.exists()) await _previous.delete();
  }
}

abstract class WesiSelfDebugExecutionControl {
  Future<void> guard(WesiSelfDebugCheckpointManager checkpoint);

  Future<void> waitForWorker(
    WesiSelfDebugCheckpointManager checkpoint, {
    String reason,
  });
}

class WesiSelfDebugCheckpointManager {
  static const int maxOutcomes = 128;
  static const int maxOutcomeSummaryChars = 4096;

  final WesiSelfDebugCheckpointJournal journal;
  WesiSelfDebugCheckpointState? _state;
  bool _loaded = false;

  WesiSelfDebugCheckpointManager({required this.journal});

  WesiSelfDebugCheckpointState? get snapshot => _state;

  WesiSelfDebugPersistedOutcome? outcomeFor(String key) =>
      _state?.outcomes[key];

  Future<void> bindPlan({
    required String requestId,
    required String planFingerprint,
  }) async {
    if (!_validRequestId(requestId) || !_validFingerprint(planFingerprint)) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_BINDING',
        'Self-debug checkpoint binding is invalid',
      );
    }
    if (!_loaded) await _restore();
    final current = _state;
    if (current == null) {
      _state = WesiSelfDebugCheckpointState(
        requestId: requestId,
        planFingerprint: planFingerprint,
        repairFingerprints: const <int, String>{},
        repairIteration: 0,
        toolCalls: 0,
        outcomes: const <String, WesiSelfDebugPersistedOutcome>{},
        revision: 0,
        updatedAt: DateTime.now().toUtc(),
      );
      await _persist();
      return;
    }
    if (current.requestId != requestId ||
        current.planFingerprint != planFingerprint) {
      throw WesiSelfDebugStop(
        'WSD_PLAN_CHANGED_AFTER_RESTART',
        'Recovered self-debug plan does not match the persisted plan fingerprint',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    if (current.inFlightStepKey != null) {
      if (current.inFlightRisk != WesiLocalRisk.read) {
        throw WesiSelfDebugStop(
          'WSD_UNCERTAIN_SIDE_EFFECT',
          'A write/destructive step was in flight during restart and will not be repeated automatically',
          repairIteration: current.repairIteration,
          toolCalls: current.toolCalls,
        );
      }
      _state = current.copyWith(
        inFlightStepKey: null,
        inFlightRisk: null,
        updatedAt: DateTime.now().toUtc(),
      );
      await _persist();
    }
  }

  Future<void> bindRepair({
    required int iteration,
    required String fingerprint,
  }) async {
    final current = _requireState();
    if (iteration < 1 || iteration > 100 || !_validFingerprint(fingerprint)) {
      throw WesiSelfDebugStop(
        'WSD_REPAIR_CHECKPOINT_INVALID',
        'Repair checkpoint binding is invalid',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    final existing = current.repairFingerprints[iteration];
    if (existing != null && existing != fingerprint) {
      throw WesiSelfDebugStop(
        'WSD_REPAIR_PLAN_CHANGED',
        'Recovered repair plan differs from the persisted repair fingerprint',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    if (existing == fingerprint) return;
    final next = <int, String>{
      ...current.repairFingerprints,
      iteration: fingerprint
    };
    _state = current.copyWith(
      repairFingerprints: Map<int, String>.unmodifiable(next),
      repairIteration: iteration,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> updatePosition({
    required String phase,
    required int repairIteration,
    required int toolCalls,
  }) async {
    final current = _requireState();
    if (phase.isEmpty ||
        phase.length > 64 ||
        repairIteration < 0 ||
        toolCalls < 0) {
      throw WesiSelfDebugStop(
        'WSD_CHECKPOINT_POSITION',
        'Self-debug checkpoint position is invalid',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    _state = current.copyWith(
      currentPhase: phase,
      repairIteration: repairIteration,
      toolCalls: toolCalls,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> beforeStep({
    required String key,
    required String stepId,
    required WesiLocalRisk risk,
    required String phase,
    required int repairIteration,
    required int toolCalls,
  }) async {
    final current = _requireState();
    if (!_validStepKey(key) || stepId.isEmpty || stepId.length > 128) {
      throw WesiSelfDebugStop(
        'WSD_CHECKPOINT_STEP',
        'Self-debug step checkpoint is invalid',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    _state = current.copyWith(
      currentPhase: phase,
      currentStepKey: key,
      currentStepId: stepId,
      repairIteration: repairIteration,
      toolCalls: toolCalls,
      inFlightStepKey: key,
      inFlightRisk: risk,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> afterStep({
    required WesiSelfDebugPersistedOutcome outcome,
    required int toolCalls,
  }) async {
    final current = _requireState();
    if (current.inFlightStepKey != outcome.key) {
      throw WesiSelfDebugStop(
        'WSD_CHECKPOINT_STEP_MISMATCH',
        'Completed self-debug step does not match the in-flight checkpoint',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    final outcomes = <String, WesiSelfDebugPersistedOutcome>{
      ...current.outcomes,
      outcome.key: outcome,
    };
    if (outcomes.length > maxOutcomes) {
      throw WesiSelfDebugStop(
        'WSD_CHECKPOINT_LIMIT',
        'Self-debug checkpoint outcome limit reached',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    _state = current.copyWith(
      toolCalls: toolCalls,
      inFlightStepKey: null,
      inFlightRisk: null,
      outcomes:
          Map<String, WesiSelfDebugPersistedOutcome>.unmodifiable(outcomes),
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> clear() async {
    await journal.clear();
    _state = null;
    _loaded = true;
  }

  Future<void> _restore() async {
    _loaded = true;
    final encoded = await journal.read();
    if (encoded == null) return;
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_LIMIT',
        'Self-debug checkpoint exceeds the decode limit',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Self-debug checkpoint JSON is invalid',
      );
    }
    if (decoded is! Map) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_CORRUPT',
        'Self-debug checkpoint root is invalid',
      );
    }
    _state = WesiSelfDebugCheckpointState.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  WesiSelfDebugCheckpointState _requireState() {
    final current = _state;
    if (!_loaded || current == null) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_NOT_BOUND',
        'Self-debug checkpoint must be bound before use',
      );
    }
    return current;
  }

  Future<void> _persist() async {
    final current = _requireState();
    final next = current.copyWith(
      revision: current.revision + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    final encoded = jsonEncode(next.toJson());
    try {
      await journal.write(encoded);
    } on WesiSelfDebugStop {
      rethrow;
    } catch (_) {
      throw WesiSelfDebugStop(
        'WSD_CHECKPOINT_IO',
        'Self-debug checkpoint could not be persisted',
        repairIteration: current.repairIteration,
        toolCalls: current.toolCalls,
      );
    }
    _state = next;
  }
}

bool _validRequestId(String value) =>
    RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value);

bool _validFingerprint(String value) =>
    RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

bool _validStepKey(String value) =>
    RegExp(r'^[A-Za-z0-9._:-]{1,256}$').hasMatch(value);

const Object _unset = Object();
