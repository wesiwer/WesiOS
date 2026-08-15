from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label} needle not found')
    return text.replace(old, new, 1)


models = Path('lib/features/ai/runtime/wesi_resource_scheduler_models.dart')
text = models.read_text(encoding='utf-8')
text = replace_once(
    text,
    "      (totalGpuVramMb == 0 || freeGpuVramMb <= totalGpuVramMb) &&\n",
    "      freeGpuVramMb <= totalGpuVramMb &&\n",
    'GPU snapshot guard',
)
models.write_text(text, encoding='utf-8')

scheduler_test = Path('test/wesi_resource_scheduler_test.dart')
test_text = scheduler_test.read_text(encoding='utf-8')
needle = "    test('corrupt resource telemetry is rejected before routing', () {\n      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(\n        WesiLocalToolNames.pythonRun,\n      );\n      final result = scheduler.select(\n        job: requirements,\n        workers: <WesiWorkerResourceProfile>[\n          _worker(totalRamMb: 4096, availableRamMb: 8192),\n        ],\n      );\n      expect(result.ok, isFalse);\n      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);\n    });\n\n"
addition = needle + "    test('GPU telemetry cannot report free VRAM when total VRAM is zero', () {\n      final requirements = WesiTrustedWorkloadRegistry.gpuMediaRequirements(\n        minFreeGpuVramMb: 1024,\n      );\n      final result = scheduler.select(\n        job: requirements,\n        workers: <WesiWorkerResourceProfile>[\n          _worker(totalGpuVramMb: 0, freeGpuVramMb: 4096),\n        ],\n      );\n      expect(result.ok, isFalse);\n      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);\n    });\n\n"
test_text = replace_once(test_text, needle, addition, 'Scheduler regression insertion')
scheduler_test.write_text(test_text, encoding='utf-8')

queue = Path('lib/features/ai/runtime/wesi_job_queue.dart')
queue_text = queue.read_text(encoding='utf-8')
queue_text = replace_once(
    queue_text,
    "        if (job.checkpoint == null) {\n          throw const WesiJobQueueException(\n            'WJQ_CHECKPOINT_REQUIRED',\n            'A checkpoint is required before pausing this job',\n          );\n        }\n",
    "        if (!_checkpointMatchesCurrentState(job)) {\n          throw const WesiJobQueueException(\n            'WJQ_CHECKPOINT_REQUIRED',\n            'A current checkpoint is required before pausing this job',\n          );\n        }\n",
    'Pause checkpoint freshness',
)
queue_text = replace_once(
    queue_text,
    "        if (job.requirements.checkpointable &&\n            (job.state == WesiScheduledJobState.running ||\n                job.state == WesiScheduledJobState.pauseRequested) &&\n            job.checkpoint == null) {\n          throw const WesiJobQueueException(\n            'WJQ_CHECKPOINT_REQUIRED',\n            'Checkpointable running work must checkpoint before losing its worker',\n          );\n        }\n",
    "        if (job.requirements.checkpointable &&\n            (job.state == WesiScheduledJobState.running ||\n                job.state == WesiScheduledJobState.pauseRequested) &&\n            !_checkpointMatchesCurrentState(job)) {\n          throw const WesiJobQueueException(\n            'WJQ_CHECKPOINT_REQUIRED',\n            'Checkpointable running work must save a current checkpoint before losing its worker',\n          );\n        }\n",
    'Worker-loss checkpoint freshness',
)
restore_needle = "  if (state == WesiScheduledJobState.running &&\n      (workerId == null || startedAt == null)) {\n    throw const WesiJobQueueException(\n      'WJQ_CORRUPT_JOURNAL',\n      'Running job is missing its worker/start metadata',\n    );\n  }\n  final terminal = state == WesiScheduledJobState.cancelled ||\n"
restore_replacement = "  final active = state == WesiScheduledJobState.running ||\n      state == WesiScheduledJobState.pauseRequested ||\n      state == WesiScheduledJobState.cancelling;\n  if (active && (workerId == null || startedAt == null)) {\n    throw const WesiJobQueueException(\n      'WJQ_CORRUPT_JOURNAL',\n      'Active job is missing its worker/start metadata',\n    );\n  }\n  final workerMustBeReleased = state == WesiScheduledJobState.queued ||\n      state == WesiScheduledJobState.paused ||\n      state == WesiScheduledJobState.waitingForWorker ||\n      state == WesiScheduledJobState.blocked ||\n      state == WesiScheduledJobState.cancelled ||\n      state == WesiScheduledJobState.succeeded ||\n      state == WesiScheduledJobState.failed;\n  if (workerMustBeReleased && workerId != null) {\n    throw const WesiJobQueueException(\n      'WJQ_CORRUPT_JOURNAL',\n      'Persisted job retains a worker outside active execution',\n    );\n  }\n  final checkpointIsCurrent = checkpoint != null &&\n      checkpoint.progress == progress &&\n      checkpoint.stage == currentStage;\n  if (state == WesiScheduledJobState.paused &&\n      (!requirements.checkpointable || !checkpointIsCurrent)) {\n    throw const WesiJobQueueException(\n      'WJQ_CORRUPT_JOURNAL',\n      'Paused job is missing its current checkpoint',\n    );\n  }\n  if (state == WesiScheduledJobState.waitingForWorker &&\n      requirements.checkpointable &&\n      startedAt != null &&\n      !checkpointIsCurrent) {\n    throw const WesiJobQueueException(\n      'WJQ_CORRUPT_JOURNAL',\n      'Checkpointable waiting job is missing its current checkpoint',\n    );\n  }\n  final terminal = state == WesiScheduledJobState.cancelled ||\n"
queue_text = replace_once(queue_text, restore_needle, restore_replacement, 'Restore state invariants')
helper_needle = "void _validateRequirements(WesiJobRequirements value) {\n"
helper = "bool _checkpointMatchesCurrentState(WesiScheduledJob job) {\n  final checkpoint = job.checkpoint;\n  return checkpoint != null &&\n      checkpoint.progress == job.progress &&\n      checkpoint.stage == job.currentStage;\n}\n\n"
queue_text = replace_once(queue_text, helper_needle, helper + helper_needle, 'Checkpoint helper insertion')
queue.write_text(queue_text, encoding='utf-8')

queue_test = Path('test/wesi_job_queue_test.dart')
queue_test_text = queue_test.read_text(encoding='utf-8')
worker_loss_needle = "    test('checkpointed worker loss becomes waiting_for_worker and is resumable',\n        () async {\n"
worker_loss_test = "    test('stale checkpoint cannot be used for worker-loss resume', () async {\n      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());\n      await queue.restore();\n      await queue.enqueue(id: 'job', requirements: _checkpointable());\n      await queue.markRunning('job', workerId: 'desktop');\n      await queue.checkpoint(\n        'job',\n        checkpoint: WesiJobCheckpointRef(\n          checkpointId: 'cp-old',\n          version: 1,\n          stage: 'compile',\n          progress: 0.4,\n          createdAt: DateTime.utc(2026, 8, 15),\n        ),\n      );\n      await queue.updateProgress('job', progress: 0.7, stage: 'tests');\n\n      await expectLater(\n        queue.waitForWorker('job'),\n        throwsA(\n          isA<WesiJobQueueException>().having(\n            (error) => error.code,\n            'code',\n            'WJQ_CHECKPOINT_REQUIRED',\n          ),\n        ),\n      );\n      expect(queue.get('job')!.state, WesiScheduledJobState.running);\n\n      await queue.checkpoint(\n        'job',\n        checkpoint: WesiJobCheckpointRef(\n          checkpointId: 'cp-current',\n          version: 1,\n          stage: 'tests',\n          progress: 0.7,\n          createdAt: DateTime.utc(2026, 8, 15, 0, 1),\n        ),\n      );\n      final waiting = await queue.waitForWorker('job');\n      expect(waiting.state, WesiScheduledJobState.waitingForWorker);\n      expect(waiting.checkpoint!.checkpointId, 'cp-current');\n    });\n\n"
queue_test_text = replace_once(
    queue_test_text,
    worker_loss_needle,
    worker_loss_test + worker_loss_needle,
    'Stale checkpoint regression insertion',
)
restore_test_needle = "    test('oversized journal fails before JSON parsing', () async {\n"
restore_test = "    test('restore rejects paused state with a stale checkpoint', () async {\n      final journal = WesiMemoryJobJournal();\n      final queue = WesiDurableJobQueue(journal: journal);\n      await queue.restore();\n      await queue.enqueue(id: 'job', requirements: _checkpointable());\n      await queue.markRunning('job', workerId: 'desktop');\n      await queue.requestPause('job');\n      await queue.checkpoint(\n        'job',\n        checkpoint: WesiJobCheckpointRef(\n          checkpointId: 'cp-restore',\n          version: 1,\n          stage: 'tests',\n          progress: 0.5,\n          createdAt: DateTime.utc(2026, 8, 15),\n        ),\n      );\n      await queue.markPaused('job');\n      journal.value = journal.value!.replaceFirst(\n        '\"stage\":\"tests\",\"progress\":0.5,\"createdAt\"',\n        '\"stage\":\"compile\",\"progress\":0.5,\"createdAt\"',\n      );\n\n      final restored = WesiDurableJobQueue(journal: journal);\n      await expectLater(\n        restored.restore(),\n        throwsA(\n          isA<WesiJobQueueException>().having(\n            (error) => error.code,\n            'code',\n            'WJQ_CORRUPT_JOURNAL',\n          ),\n        ),\n      );\n    });\n\n"
queue_test_text = replace_once(
    queue_test_text,
    restore_test_needle,
    restore_test + restore_test_needle,
    'Restore checkpoint regression insertion',
)
queue_test.write_text(queue_test_text, encoding='utf-8')

print('Stage 8 GPU telemetry and checkpoint fail-closed hardening applied')
