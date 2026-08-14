import 'wesi_worker_models.dart';

enum WesiJobClass { light, cpu, build, browser, gpu }

enum WesiExecutionPreference { automatic, localOnly, remotePreferred, remoteOnly }

class WesiJobRequirements {
  final WesiJobClass jobClass;
  final List<WesiWorkerCapability> capabilities;
  final int minRamMb;
  final int minGpuVramMb;
  final WesiExecutionPreference preference;

  const WesiJobRequirements({
    required this.jobClass,
    required this.capabilities,
    this.minRamMb = 0,
    this.minGpuVramMb = 0,
    this.preference = WesiExecutionPreference.automatic,
  });
}

class WesiWorkerSelection {
  final WesiWorkerProfile? worker;
  final String? blocker;
  final bool requiresRemoteOnlineWarning;

  const WesiWorkerSelection._({
    required this.worker,
    this.blocker,
    this.requiresRemoteOnlineWarning = false,
  });

  const WesiWorkerSelection.ok(WesiWorkerProfile worker)
      : this._(worker: worker);

  const WesiWorkerSelection.blocked(String blocker, {bool remoteWarning = false})
      : this._(
          worker: null,
          blocker: blocker,
          requiresRemoteOnlineWarning: remoteWarning,
        );

  bool get ok => worker != null;
}

class WesiWorkerScheduler {
  const WesiWorkerScheduler();

  WesiWorkerSelection select({
    required WesiJobRequirements job,
    required List<WesiWorkerProfile> workers,
  }) {
    final candidates = workers.where((worker) {
      if (!worker.online) return false;
      if (!worker.supportsAll(job.capabilities)) return false;
      if (worker.ramMb < job.minRamMb) return false;
      if ((worker.gpuVramMb ?? 0) < job.minGpuVramMb) return false;
      if (job.jobClass == WesiJobClass.build &&
          worker.platform != WesiWorkerPlatform.windows &&
          worker.platform != WesiWorkerPlatform.linux &&
          worker.platform != WesiWorkerPlatform.macos) {
        return false;
      }
      return true;
    }).toList(growable: false);

    if (job.preference == WesiExecutionPreference.localOnly) {
      for (final worker in candidates) {
        if (worker.localDevice) return WesiWorkerSelection.ok(worker);
      }
      return const WesiWorkerSelection.blocked(
        'На этом устройстве нет подходящего локального runtime или ресурсов.',
      );
    }

    if (job.preference == WesiExecutionPreference.remoteOnly) {
      final remotes = candidates.where((worker) => !worker.localDevice).toList(growable: false);
      if (remotes.isEmpty) {
        return const WesiWorkerSelection.blocked(
          'Нет доступного удалённого Wesi Worker. Откройте WesiOS на привязанном компьютере и оставьте приложение запущенным.',
          remoteWarning: true,
        );
      }
      return WesiWorkerSelection.ok(_best(remotes, job));
    }

    if (job.preference == WesiExecutionPreference.remotePreferred) {
      final remotes = candidates.where((worker) => !worker.localDevice).toList(growable: false);
      if (remotes.isNotEmpty) return WesiWorkerSelection.ok(_best(remotes, job));
    }

    if (candidates.isEmpty) {
      final hasRemote = workers.any((worker) => !worker.localDevice);
      return WesiWorkerSelection.blocked(
        hasRemote
            ? 'Подходящий Wesi Worker сейчас офлайн или не имеет нужного Runtime Pack. Откройте WesiOS на компьютере и проверьте установленные дополнения.'
            : 'Для этой задачи нужен Wesi Worker на компьютере с подходящими Runtime Packs.',
        remoteWarning: hasRemote,
      );
    }

    return WesiWorkerSelection.ok(_best(candidates, job));
  }

  WesiWorkerProfile _best(List<WesiWorkerProfile> workers, WesiJobRequirements job) {
    final sorted = <WesiWorkerProfile>[...workers]
      ..sort((a, b) => _score(b, job).compareTo(_score(a, job)));
    return sorted.first;
  }

  int _score(WesiWorkerProfile worker, WesiJobRequirements job) {
    var score = 0;
    if (worker.localDevice) score += 10;
    score += worker.cpuCores * 4;
    score += worker.ramMb ~/ 1024;
    score += (worker.gpuVramMb ?? 0) ~/ 512;
    if (worker.status == WesiWorkerStatus.online) score += 8;
    if (job.jobClass == WesiJobClass.gpu && (worker.gpuVramMb ?? 0) > 0) score += 40;
    if (job.jobClass == WesiJobClass.build && worker.platform == WesiWorkerPlatform.windows) score += 12;
    return score;
  }
}
