from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'missing replacement anchor: {label}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


queue = ROOT / 'lib/features/ai/runtime/wesi_job_queue.dart'
text = queue.read_text(encoding='utf-8')
if "import 'wesi_resource_scheduler.dart';" not in text:
    text = text.replace(
        "import 'wesi_local_runtime_models.dart';\n",
        "import 'wesi_local_runtime_models.dart';\nimport 'wesi_resource_scheduler.dart';\n",
        1,
    )
queue.write_text(text, encoding='utf-8')

replace_once(
    queue,
    """        final raw = await journal.read();\n        _jobs.clear();\n        if (raw == null || raw.trim().isEmpty) {\n          _initialized = true;\n          return;\n        }\n""",
    """        final raw = await journal.read();\n        if (raw == null || raw.trim().isEmpty) {\n          _jobs.clear();\n          _initialized = true;\n          return;\n        }\n""",
    'restore clear timing',
)
replace_once(
    queue,
    """        final rawJobs = root['jobs'];\n        if (rawJobs is! List || rawJobs.length > maxJobs) {\n          throw const WesiJobQueueException(\n            'WJQ_CORRUPT_JOURNAL',\n            'Job journal contains an invalid job collection',\n          );\n        }\n        for (final rawJob in rawJobs) {\n""",
    """        final rawJobs = root['jobs'];\n        if (rawJobs is! List || rawJobs.length > maxJobs) {\n          throw const WesiJobQueueException(\n            'WJQ_CORRUPT_JOURNAL',\n            'Job journal contains an invalid job collection',\n          );\n        }\n        final restoredJobs = <String, WesiScheduledJob>{};\n        for (final rawJob in rawJobs) {\n""",
    'restore staging map',
)
replace_once(
    queue,
    """          if (_jobs.containsKey(job.id)) {\n            throw const WesiJobQueueException(\n              'WJQ_CORRUPT_JOURNAL',\n              'Job journal contains duplicate job ids',\n            );\n          }\n          _jobs[job.id] = job;\n        }\n        _initialized = true;\n""",
    """          if (restoredJobs.containsKey(job.id)) {\n            throw const WesiJobQueueException(\n              'WJQ_CORRUPT_JOURNAL',\n              'Job journal contains duplicate job ids',\n            );\n          }\n          restoredJobs[job.id] = job;\n        }\n        _jobs\n          ..clear()\n          ..addAll(restoredJobs);\n        _initialized = true;\n""",
    'restore atomic in-memory publish',
)
replace_once(
    queue,
    """        _jobs[id] = job;\n        await _persist();\n        return job;\n""",
    """        return _insert(job);\n""",
    'enqueue persistence rollback',
)
replace_once(
    queue,
    """  Future<WesiScheduledJob> _replace(WesiScheduledJob job) async {\n    _jobs[job.id] = job;\n    await _persist();\n    return job;\n  }\n\n  Future<void> _persist() async {\n""",
    """  Future<WesiScheduledJob> _insert(WesiScheduledJob job) async {\n    _jobs[job.id] = job;\n    try {\n      await _persist();\n      return job;\n    } catch (_) {\n      _jobs.remove(job.id);\n      rethrow;\n    }\n  }\n\n  Future<WesiScheduledJob> _replace(WesiScheduledJob job) async {\n    final previous = _jobs[job.id];\n    _jobs[job.id] = job;\n    try {\n      await _persist();\n      return job;\n    } catch (_) {\n      if (previous == null) {\n        _jobs.remove(job.id);\n      } else {\n        _jobs[job.id] = previous;\n      }\n      rethrow;\n    }\n  }\n\n  Future<void> _persist() async {\n""",
    'mutation persistence rollback',
)
replace_once(
    queue,
    """void _validateRequirements(WesiJobRequirements value) {\n  if (value.toolName.trim().isEmpty ||\n      value.toolName.length > 160 ||\n      value.allowedPlatforms.isEmpty ||\n      value.minCpuCores < 0 ||\n      value.maxCpuLoadPercent <= 0 ||\n      value.maxCpuLoadPercent > 100 ||\n      value.minAvailableRamMb < 0 ||\n      value.minFreeGpuVramMb < 0 ||\n      value.minFreeDiskMb < 0 ||\n      value.estimatedDurationSeconds < 0) {\n    throw const WesiJobQueueException(\n      'WJQ_BAD_REQUIREMENTS',\n      'Job requirements are invalid',\n    );\n  }\n}\n""",
    """void _validateRequirements(WesiJobRequirements value) {\n  if (value.toolName.trim().isEmpty ||\n      value.toolName.length > 160 ||\n      value.allowedPlatforms.isEmpty ||\n      value.minCpuCores < 0 ||\n      value.maxCpuLoadPercent <= 0 ||\n      value.maxCpuLoadPercent > 100 ||\n      value.minAvailableRamMb < 0 ||\n      value.minFreeGpuVramMb < 0 ||\n      value.minFreeDiskMb < 0 ||\n      value.estimatedDurationSeconds < 0) {\n    throw const WesiJobQueueException(\n      'WJQ_BAD_REQUIREMENTS',\n      'Job requirements are invalid',\n    );\n  }\n\n  late final WesiTrustedWorkloadDescriptor trusted;\n  try {\n    trusted = WesiTrustedWorkloadRegistry.require(value.toolName);\n  } on WesiSchedulerPolicyException {\n    throw const WesiJobQueueException(\n      'WJQ_BAD_REQUIREMENTS',\n      'Persisted workload is not present in the trusted registry',\n    );\n  }\n\n  const desktop = <WesiWorkerPlatform>{\n    WesiWorkerPlatform.windows,\n    WesiWorkerPlatform.linux,\n    WesiWorkerPlatform.macos,\n  };\n  final weakened =\n      value.level.index < trusted.level.index ||\n      !value.requiredCapabilities.containsAll(trusted.requiredCapabilities) ||\n      !value.requiredPacks.containsAll(trusted.requiredPacks) ||\n      !value.allowedPlatforms.every(desktop.contains) ||\n      value.minCpuCores < trusted.minCpuCores ||\n      value.maxCpuLoadPercent > trusted.maxCpuLoadPercent ||\n      value.minAvailableRamMb < trusted.minAvailableRamMb ||\n      value.minFreeGpuVramMb < trusted.minFreeGpuVramMb ||\n      value.minFreeDiskMb < trusted.minFreeDiskMb ||\n      (value.level.index >= WesiWorkloadLevel.l3.index &&\n          value.foregroundPolicy != WesiForegroundPolicy.foregroundRequired) ||\n      (trusted.foregroundPolicy == WesiForegroundPolicy.foregroundRequired &&\n          value.foregroundPolicy != WesiForegroundPolicy.foregroundRequired) ||\n      value.checkpointable != trusted.checkpointable ||\n      (value.remoteAllowed && !trusted.remoteAllowed) ||\n      (value.allowControlPlane && !trusted.allowControlPlane);\n  if (weakened) {\n    throw const WesiJobQueueException(\n      'WJQ_BAD_REQUIREMENTS',\n      'Persisted workload requirements weaken trusted scheduling policy',\n    );\n  }\n}\n""",
    'trusted persisted requirements',
)

# The trusted builder must not let a caller route Stage-6 Local Runtime onto a
# non-desktop platform by widening allowedPlatforms.
scheduler = ROOT / 'lib/features/ai/runtime/wesi_resource_scheduler.dart'
replace_once(
    scheduler,
    """    final platforms = allowedPlatforms ?? _desktop;\n    if (platforms.isEmpty) {\n      throw const WesiSchedulerPolicyException(\n        'WS_INVALID_REQUIREMENTS',\n        'At least one trusted target platform is required',\n      );\n    }\n""",
    """    final platforms = allowedPlatforms ?? _desktop;\n    if (platforms.isEmpty || !platforms.every(_desktop.contains)) {\n      throw const WesiSchedulerPolicyException(\n        'WS_INVALID_REQUIREMENTS',\n        'Local Runtime workloads require a trusted desktop target platform',\n      );\n    }\n""",
    'desktop-only Local Runtime routing',
)

# Add regressions for journal policy tampering and write-failure rollback.
test = ROOT / 'test/wesi_job_queue_test.dart'
test_text = test.read_text(encoding='utf-8')
helper_anchor = "WesiJobRequirements _nonCheckpointable() =>\n    WesiTrustedWorkloadRegistry.requirementsFor(WesiLocalToolNames.gitStatus);\n\n"
helper = """class _FailingJobJournal implements WesiJobJournal {\n  String? value;\n  bool failWrites = false;\n\n  @override\n  Future<String?> read() async => value;\n\n  @override\n  Future<void> write(String value) async {\n    if (failWrites) throw StateError('simulated disk failure');\n    this.value = value;\n  }\n}\n\n"""
if helper not in test_text:
    if helper_anchor not in test_text:
        raise SystemExit('missing job queue test helper anchor')
    test_text = test_text.replace(helper_anchor, helper_anchor + helper, 1)

insert_anchor = "    test('oversized journal fails before JSON parsing', () async {\n"
regressions = r'''    test('persisted requirements cannot downgrade the trusted workload policy', () async {
      final journal = WesiMemoryJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(
        id: 'build',
        requirements: WesiTrustedWorkloadRegistry.requirementsFor(
          WesiLocalToolNames.flutterBuild,
        ),
      );
      journal.value = journal.value!
          .replaceFirst('"level":"l4"', '"level":"l1"')
          .replaceFirst('"foregroundPolicy":"foregroundRequired"',
              '"foregroundPolicy":"backgroundAllowed"');

      final restored = WesiDurableJobQueue(journal: journal);
      await expectLater(
        restored.restore(),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_BAD_REQUIREMENTS',
          ),
        ),
      );
    });

    test('journal write failure rolls back in-memory mutation', () async {
      final journal = _FailingJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _nonCheckpointable());
      journal.failWrites = true;

      await expectLater(
        queue.requestCancel('job'),
        throwsA(isA<StateError>()),
      );
      expect(queue.get('job')!.state, WesiScheduledJobState.queued);

      await expectLater(
        queue.enqueue(id: 'new-job', requirements: _nonCheckpointable()),
        throwsA(isA<StateError>()),
      );
      expect(queue.get('new-job'), isNull);
    });

    test('failed restore does not destroy the previous in-memory snapshot', () async {
      final journal = WesiMemoryJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _nonCheckpointable());
      journal.value = journal.value!.replaceFirst(
        '"requiredPacks":["core"]',
        '"requiredPacks":[]',
      );

      await expectLater(
        queue.restore(),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_BAD_REQUIREMENTS',
          ),
        ),
      );
      expect(queue.get('job')!.state, WesiScheduledJobState.queued);
    });

'''
if regressions not in test_text:
    if insert_anchor not in test_text:
        raise SystemExit('missing job queue test insertion anchor')
    test_text = test_text.replace(insert_anchor, regressions + insert_anchor, 1)
test.write_text(test_text, encoding='utf-8')

scheduler_test = ROOT / 'test/wesi_resource_scheduler_test.dart'
scheduler_test_text = scheduler_test.read_text(encoding='utf-8')
anchor = "    test('model-style negative resource relaxation is rejected', () {\n"
platform_test = r'''    test('Local Runtime target platforms cannot be widened to Android', () {
      expect(
        () => WesiTrustedWorkloadRegistry.requirementsFor(
          WesiLocalToolNames.pythonRun,
          allowedPlatforms: const <WesiWorkerPlatform>{WesiWorkerPlatform.android},
        ),
        throwsA(
          isA<WesiSchedulerPolicyException>().having(
            (error) => error.code,
            'code',
            'WS_INVALID_REQUIREMENTS',
          ),
        ),
      );
    });

'''
if platform_test not in scheduler_test_text:
    if anchor not in scheduler_test_text:
        raise SystemExit('missing scheduler test insertion anchor')
    scheduler_test_text = scheduler_test_text.replace(anchor, platform_test + anchor, 1)
scheduler_test.write_text(scheduler_test_text, encoding='utf-8')

print('Stage 8 journal trust hardening applied')
