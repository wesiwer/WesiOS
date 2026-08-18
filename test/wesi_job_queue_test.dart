import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_job_queue.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';

WesiJobRequirements _checkpointable() =>
    WesiTrustedWorkloadRegistry.requirementsFor(WesiLocalToolNames.pythonRun);

WesiJobRequirements _nonCheckpointable() =>
    WesiTrustedWorkloadRegistry.requirementsFor(WesiLocalToolNames.gitStatus);

class _FailingJobJournal implements WesiJobJournal {
  String? value;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('simulated disk failure');
    this.value = value;
  }
}

void main() {
  group('Durable job queue', () {
    test('must be restored before use', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      expect(
        () => queue.jobs,
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_NOT_RESTORED',
          ),
        ),
      );
    });

    test('priority is deterministic and FIFO within a priority', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(
        id: 'normal-first',
        requirements: _nonCheckpointable(),
        now: DateTime.utc(2026, 8, 15, 10),
      );
      await queue.enqueue(
        id: 'urgent-later',
        requirements: _nonCheckpointable(),
        priority: WesiJobPriority.urgent,
        now: DateTime.utc(2026, 8, 15, 10, 1),
      );
      await queue.enqueue(
        id: 'urgent-last',
        requirements: _nonCheckpointable(),
        priority: WesiJobPriority.urgent,
        now: DateTime.utc(2026, 8, 15, 10, 2),
      );

      expect(queue.nextQueued!.id, 'urgent-later');
      await queue.requestCancel('urgent-later');
      expect(queue.nextQueued!.id, 'urgent-last');
    });

    test('invalid lifecycle transitions fail closed', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());

      await expectLater(
        queue.succeed('job'),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_BAD_STATE',
          ),
        ),
      );
      expect(queue.get('job')!.state, WesiScheduledJobState.queued);
    });

    test('checkpoint pause and resume survive restart', () async {
      final journal = WesiMemoryJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(
        id: 'build-loop',
        requirements: _checkpointable(),
        now: DateTime.utc(2026, 8, 15, 11),
      );
      await queue.markRunning(
        'build-loop',
        workerId: 'desktop-a',
        now: DateTime.utc(2026, 8, 15, 11, 1),
      );
      await queue.updateProgress(
        'build-loop',
        progress: 0.25,
        stage: 'analyze',
        now: DateTime.utc(2026, 8, 15, 11, 2),
      );
      await queue.requestPause(
        'build-loop',
        now: DateTime.utc(2026, 8, 15, 11, 3),
      );
      await queue.checkpoint(
        'build-loop',
        checkpoint: WesiJobCheckpointRef(
          checkpointId: 'cp-1',
          version: 1,
          stage: 'tests',
          progress: 0.5,
          createdAt: DateTime.utc(2026, 8, 15, 11, 4),
        ),
      );
      await queue.markPaused('build-loop');

      final restored = WesiDurableJobQueue(journal: journal);
      await restored.restore();
      final paused = restored.get('build-loop')!;
      expect(paused.state, WesiScheduledJobState.paused);
      expect(paused.checkpoint!.checkpointId, 'cp-1');
      expect(paused.progress, 0.5);
      expect(paused.workerId, isNull);

      final resumed = await restored.resume('build-loop');
      expect(resumed.state, WesiScheduledJobState.queued);
      expect(resumed.checkpoint!.stage, 'tests');
    });

    test('worker loss requires a checkpoint when the running job supports it',
        () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      await queue.markRunning('job', workerId: 'desktop');

      await expectLater(
        queue.waitForWorker('job'),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_CHECKPOINT_REQUIRED',
          ),
        ),
      );
      expect(queue.get('job')!.state, WesiScheduledJobState.running);
    });

    test('stale checkpoint cannot be used for worker-loss resume', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      await queue.markRunning('job', workerId: 'desktop');
      await queue.checkpoint(
        'job',
        checkpoint: WesiJobCheckpointRef(
          checkpointId: 'cp-old',
          version: 1,
          stage: 'compile',
          progress: 0.4,
          createdAt: DateTime.utc(2026, 8, 15),
        ),
      );
      await queue.updateProgress('job', progress: 0.7, stage: 'tests');

      await expectLater(
        queue.waitForWorker('job'),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_CHECKPOINT_REQUIRED',
          ),
        ),
      );
      expect(queue.get('job')!.state, WesiScheduledJobState.running);

      await queue.checkpoint(
        'job',
        checkpoint: WesiJobCheckpointRef(
          checkpointId: 'cp-current',
          version: 1,
          stage: 'tests',
          progress: 0.7,
          createdAt: DateTime.utc(2026, 8, 15, 0, 1),
        ),
      );
      final waiting = await queue.waitForWorker('job');
      expect(waiting.state, WesiScheduledJobState.waitingForWorker);
      expect(waiting.checkpoint!.checkpointId, 'cp-current');
    });

    test('checkpointed worker loss becomes waiting_for_worker and is resumable',
        () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      await queue.markRunning('job', workerId: 'desktop');
      await queue.checkpoint(
        'job',
        checkpoint: WesiJobCheckpointRef(
          checkpointId: 'cp-worker-loss',
          version: 1,
          stage: 'compile',
          progress: 0.4,
          createdAt: DateTime.utc(2026, 8, 15),
        ),
      );
      final waiting = await queue.waitForWorker(
        'job',
        reason: 'desktop heartbeat expired',
      );
      expect(waiting.state, WesiScheduledJobState.waitingForWorker);
      expect(waiting.workerId, isNull);
      expect(waiting.checkpoint!.stage, 'compile');

      final resumed = await queue.resume('job');
      expect(resumed.state, WesiScheduledJobState.queued);
      expect(resumed.progress, 0.4);
    });

    test('non-checkpointable workload cannot pretend to pause safely',
        () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'git-status', requirements: _nonCheckpointable());
      await queue.markRunning('git-status', workerId: 'desktop');

      await expectLater(
        queue.requestPause('git-status'),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_NOT_CHECKPOINTABLE',
          ),
        ),
      );
    });

    test('progress cannot move backwards', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      await queue.markRunning('job', workerId: 'desktop');
      await queue.updateProgress('job', progress: 0.7, stage: 'tests');

      await expectLater(
        queue.updateProgress('job', progress: 0.6, stage: 'tests'),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_BAD_PROGRESS',
          ),
        ),
      );
    });

    test('queued cancellation is immediate, running cancellation is two-phase',
        () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'queued', requirements: _nonCheckpointable());
      final queued = await queue.requestCancel('queued');
      expect(queued.state, WesiScheduledJobState.cancelled);
      expect(queued.finishedAt, isNotNull);

      await queue.enqueue(id: 'running', requirements: _checkpointable());
      await queue.markRunning('running', workerId: 'desktop');
      final cancelling = await queue.requestCancel('running');
      expect(cancelling.state, WesiScheduledJobState.cancelling);
      final cancelled = await queue.markCancelled('running');
      expect(cancelled.state, WesiScheduledJobState.cancelled);
    });

    test('terminal jobs cannot be resumed', () async {
      final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
      await queue.restore();
      await queue.enqueue(id: 'done', requirements: _nonCheckpointable());
      await queue.markRunning('done', workerId: 'desktop');
      await queue.succeed('done');

      await expectLater(
        queue.resume('done'),
        throwsA(isA<WesiJobQueueException>()),
      );
    });

    test('unknown persisted capability is rejected instead of dropped',
        () async {
      final journal = WesiMemoryJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      journal.value =
          journal.value!.replaceFirst('"python"', '"futureCapability"');

      final restored = WesiDurableJobQueue(journal: journal);
      await expectLater(
        restored.restore(),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_CORRUPT_JOURNAL',
          ),
        ),
      );
    });

    test('persisted requirements cannot downgrade the trusted workload policy',
        () async {
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

    test('failed restore does not destroy the previous in-memory snapshot',
        () async {
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

    test('restore rejects paused state with a stale checkpoint', () async {
      final journal = WesiMemoryJobJournal();
      final queue = WesiDurableJobQueue(journal: journal);
      await queue.restore();
      await queue.enqueue(id: 'job', requirements: _checkpointable());
      await queue.markRunning('job', workerId: 'desktop');
      await queue.requestPause('job');
      await queue.checkpoint(
        'job',
        checkpoint: WesiJobCheckpointRef(
          checkpointId: 'cp-restore',
          version: 1,
          stage: 'tests',
          progress: 0.5,
          createdAt: DateTime.utc(2026, 8, 15),
        ),
      );
      await queue.markPaused('job');
      journal.value = journal.value!.replaceFirst(
        '"stage":"tests","progress":0.5,"createdAt"',
        '"stage":"compile","progress":0.5,"createdAt"',
      );

      final restored = WesiDurableJobQueue(journal: journal);
      await expectLater(
        restored.restore(),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_CORRUPT_JOURNAL',
          ),
        ),
      );
    });

    test('oversized journal fails before JSON parsing', () async {
      final journal = WesiMemoryJobJournal(
        List<String>.filled(WesiDurableJobQueue.maxJournalBytes + 1, 'x')
            .join(),
      );
      final queue = WesiDurableJobQueue(journal: journal);
      await expectLater(
        queue.restore(),
        throwsA(
          isA<WesiJobQueueException>().having(
            (error) => error.code,
            'code',
            'WJQ_JOURNAL_TOO_LARGE',
          ),
        ),
      );
    });

    test('file journal recovers an interrupted previous-file swap', () async {
      final root = await Directory.systemTemp.createTemp('wesi-job-journal-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/jobs.json');
      final backup = File('${file.path}.previous');
      await backup.writeAsString('recovered');

      final journal = WesiFileJobJournal(file);
      expect(await journal.read(), 'recovered');
      expect(await file.exists(), isTrue);
      expect(await backup.exists(), isFalse);
    });
  });
}
