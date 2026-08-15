import 'wesi_job_coordinator.dart';
import 'wesi_self_debug_engine.dart';

/// Bridges Stage-9 phases to the Stage-8 durable job timeline.
///
/// The caller still owns terminal success/failure transitions so an observer
/// cannot mark a job successful before artifact delivery has completed.
class WesiSelfDebugJobObserver implements WesiSelfDebugObserver {
  final WesiJobCoordinator coordinator;
  final String jobId;
  double _lastProgress = 0;

  WesiSelfDebugJobObserver({
    required this.coordinator,
    required this.jobId,
  });

  @override
  Future<void> onProgress(WesiSelfDebugProgress progress) async {
    final requested = _progressFor(progress.phase);
    final monotonic = requested < _lastProgress ? _lastProgress : requested;
    _lastProgress = monotonic;
    await coordinator.updateProgress(
      jobId,
      progress: monotonic,
      stage: _stageFor(progress),
    );
  }

  double _progressFor(WesiSelfDebugPhase phase) {
    switch (phase) {
      case WesiSelfDebugPhase.planning:
        return 0.05;
      case WesiSelfDebugPhase.executing:
        return 0.20;
      case WesiSelfDebugPhase.verifying:
        return 0.50;
      case WesiSelfDebugPhase.diagnosing:
        return 0.56;
      case WesiSelfDebugPhase.repairing:
        return 0.62;
      case WesiSelfDebugPhase.validatingArtifacts:
        return 0.82;
      case WesiSelfDebugPhase.delivering:
        return 0.93;
      case WesiSelfDebugPhase.succeeded:
        return 0.99;
      case WesiSelfDebugPhase.blocked:
      case WesiSelfDebugPhase.failed:
        return 0.99;
    }
  }

  String _stageFor(WesiSelfDebugProgress progress) {
    final iteration =
        progress.repairIteration > 0 ? ' #${progress.repairIteration}' : '';
    return '${progress.phase.name}$iteration: ${progress.message}';
  }
}
