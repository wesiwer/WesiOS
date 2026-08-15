from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: needle not found')
    return text.replace(old, new, 1)


engine = Path('lib/features/ai/runtime/wesi_self_debug_engine.dart')
text = engine.read_text(encoding='utf-8')
needle = "    var needsRepair = !initial.ok;\n    while (true) {\n"
replacement = r'''    var needsRepair = !initial.ok;
    final recoveredPhase = checkpointTarget?.snapshot?.currentPhase;
    if (!needsRepair &&
        repairIteration > 0 &&
        (recoveredPhase == WesiSelfDebugPhase.diagnosing.name ||
            recoveredPhase == WesiSelfDebugPhase.repairing.name)) {
      final previousVerification = await _runSteps(
        plan.verificationSteps,
        phase: WesiSelfDebugPhase.verifying,
        runtimeContext: runtimeContext,
        evidence: evidence,
        startedAt: startedAt,
        currentToolCalls: toolCalls,
        repairIteration: repairIteration - 1,
      );
      toolCalls = previousVerification.toolCalls;
      if (previousVerification.ok) {
        return _blocked(
          'WSD_CHECKPOINT_INCONSISTENT',
          'Recovered repair phase has no preceding objective failure',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      await checkpointTarget!.updatePosition(
        phase: WesiSelfDebugPhase.diagnosing.name,
        repairIteration: repairIteration,
        toolCalls: toolCalls,
      );
      final resumedProposal = await planner.proposeRepair(
        request: request,
        plan: plan,
        iteration: repairIteration,
        evidence: _boundedEvidence(evidence),
      );
      if (resumedProposal.blocked) {
        return _blocked(
          resumedProposal.blockerCode ?? 'WSD_OBJECTIVE_BLOCKER',
          resumedProposal.blockerMessage ??
              'Planner reported an objective blocker',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      if (resumedProposal.repairSteps.isEmpty ||
          resumedProposal.repairSteps.length > limits.maxRepairStepsPerIteration) {
        return _blocked(
          'WSD_BAD_REPAIR_PLAN',
          'Recovered repair proposal is empty or exceeds the bounded step limit',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      final resumedIds = <String>{};
      for (final step in resumedProposal.repairSteps) {
        if (step.id.trim().isEmpty || !resumedIds.add(step.id)) {
          return _blocked(
            'WSD_BAD_REPAIR_PLAN',
            'Recovered repair proposal contains empty or duplicate step ids',
            repairIteration,
            toolCalls,
            evidence,
          );
        }
        if (WesiLocalCapabilityRegistry.get(step.call.tool) == null) {
          return _blocked(
            'WSD_UNKNOWN_TOOL',
            'Recovered repair proposal contains an unknown local tool',
            repairIteration,
            toolCalls,
            evidence,
          );
        }
      }
      await checkpointTarget.bindRepair(
        iteration: repairIteration,
        fingerprint: _repairFingerprint(resumedProposal.repairSteps),
      );
      final resumedRepair = await _runSteps(
        resumedProposal.repairSteps,
        phase: WesiSelfDebugPhase.repairing,
        runtimeContext: runtimeContext,
        evidence: evidence,
        startedAt: startedAt,
        currentToolCalls: toolCalls,
        repairIteration: repairIteration,
      );
      toolCalls = resumedRepair.toolCalls;
      needsRepair = !resumedRepair.ok;
    }
    while (true) {
'''
text = replace_once(text, needle, replacement, 'resume pending repair')
old = """    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
"""
new = """    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return <String, dynamic>{
        for (final entry in entries) entry.key: _canonicalize(entry.value),
      };
    }
"""
text = replace_once(text, old, new, 'canonical map fingerprint')
engine.write_text(text, encoding='utf-8')

# Add a regression that crashes in a READ repair step and proves the same
# repair iteration is resumed before current-iteration verification.
test = Path('test/wesi_self_debug_durability_test.dart')
test_text = test.read_text(encoding='utf-8')
needle = "    test('restart never repeats an uncertain in-flight WRITE', () async {\n"
addition = r'''    test('restart resumes interrupted READ inside the same repair iteration',
        () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-repair-read-');
      addTearDown(() => root.delete(recursive: true));
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final plan = WesiSelfDebugPlan(
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.fsReadText),
        ],
      );
      final firstPlanner = _RepairPlanner(
        plan: plan,
        repair: WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('diagnostic-read', WesiLocalToolNames.fsReadText),
            _step('repair-write', WesiLocalToolNames.fsWriteText),
          ],
        ),
      );
      final firstExecutor = _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.failure('VERIFY_FAILED', 'needs repair'),
        () async => throw StateError('crash during repair read'),
      ]);
      final first = WesiSelfDebugEngine(
        executor: firstExecutor,
        planner: firstPlanner,
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      await expectLater(
        first.run(
          request: const WesiSelfDebugRequest(
            id: 'repair-read-job',
            goal: 'resume repair',
          ),
          runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
        ),
        throwsA(isA<StateError>()),
      );

      final secondExecutor = _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.success(message: 'diagnostic read'),
        () async => WesiLocalToolResult.success(message: 'repair write'),
        () async => WesiLocalToolResult.success(message: 'verification passed'),
      ]);
      final secondPlanner = _RepairPlanner(
        plan: plan,
        repair: WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('diagnostic-read', WesiLocalToolNames.fsReadText),
            _step('repair-write', WesiLocalToolNames.fsWriteText),
          ],
        ),
      );
      final second = WesiSelfDebugEngine(
        executor: secondExecutor,
        planner: secondPlanner,
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      final result = await second.run(
        request: const WesiSelfDebugRequest(
          id: 'repair-read-job',
          goal: 'resume repair',
        ),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.ok, isTrue);
      expect(secondPlanner.repairCalls, 1);
      expect(secondExecutor.tools, <String>[
        WesiLocalToolNames.fsReadText,
        WesiLocalToolNames.fsWriteText,
        WesiLocalToolNames.fsReadText,
      ]);
    });

'''
test_text = replace_once(test_text, needle, addition + needle, 'repair restart regression')
anchor = "class _SequenceExecutor extends WesiLocalRuntimeExecutor {\n"
helper = r'''class _RepairPlanner implements WesiSelfDebugPlanner {
  final WesiSelfDebugPlan plan;
  final WesiRepairProposal repair;
  int repairCalls = 0;

  _RepairPlanner({required this.plan, required this.repair});

  @override
  Future<WesiSelfDebugPlan> createPlan(WesiSelfDebugRequest request) async => plan;

  @override
  Future<WesiRepairProposal> proposeRepair({
    required WesiSelfDebugRequest request,
    required WesiSelfDebugPlan plan,
    required int iteration,
    required List<WesiDebugEvidence> evidence,
  }) async {
    repairCalls++;
    return repair;
  }
}

'''
test_text = replace_once(test_text, anchor, helper + anchor, 'repair planner helper')
test.write_text(test_text, encoding='utf-8')

print('Stage 9 repair-phase restart fix applied')
