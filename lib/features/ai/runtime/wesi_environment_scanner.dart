import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'wesi_runtime_pack_models.dart';

class WesiRuntimeProbeOutcome {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const WesiRuntimeProbeOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });
}

abstract class WesiRuntimeProbeRunner {
  Future<WesiRuntimeProbeOutcome> run({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
  });
}

class WesiIoRuntimeProbeRunner implements WesiRuntimeProbeRunner {
  const WesiIoRuntimeProbeRunner();

  static const int _maxOutputBytes = 128 * 1024;

  @override
  Future<WesiRuntimeProbeOutcome> run({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
  }) async {
    Process? process;
    try {
      final lower = executable.toLowerCase();
      process = await Process.start(
        executable,
        arguments,
        runInShell: Platform.isWindows &&
            (lower.endsWith('.bat') || lower.endsWith('.cmd')),
      );
      final stdoutFuture = _boundedText(process.stdout);
      final stderrFuture = _boundedText(process.stderr);
      final exitFuture = process.exitCode;
      final result = await Future.any<Object?>(<Future<Object?>>[
        exitFuture.then<Object?>((value) => value),
        Future<Object?>.delayed(timeout, () => null),
      ]);
      if (result == null) {
        process.kill();
        final exitCode = await exitFuture;
        return WesiRuntimeProbeOutcome(
          exitCode: exitCode,
          stdout: await stdoutFuture,
          stderr: await stderrFuture,
          timedOut: true,
        );
      }
      return WesiRuntimeProbeOutcome(
        exitCode: result as int,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
        timedOut: false,
      );
    } on ProcessException {
      return const WesiRuntimeProbeOutcome(
        exitCode: -1,
        stdout: '',
        stderr: '',
        timedOut: false,
      );
    } finally {
      if (process != null) {
        try {
          process.kill();
        } catch (_) {}
      }
    }
  }

  static Future<String> _boundedText(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length >= _maxOutputBytes) continue;
      final remaining = _maxOutputBytes - bytes.length;
      bytes.addAll(chunk.length <= remaining ? chunk : chunk.take(remaining));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class WesiEnvironmentScanner {
  final WesiRuntimeProbeRunner runner;
  final WesiRuntimePlatform platform;
  final Map<String, String> environment;

  WesiEnvironmentScanner({
    this.runner = const WesiIoRuntimeProbeRunner(),
    WesiRuntimePlatform? platform,
    Map<String, String>? environment,
  })  : platform = platform ?? WesiRuntimePlatformInfo.current,
        environment = Map<String, String>.unmodifiable(
          environment ?? Platform.environment,
        );

  Future<WesiRuntimeScanSnapshot> scan(
    Iterable<WesiRuntimeDependencySpec> dependencies, {
    Map<String, String> managedExecutablePaths = const <String, String>{},
  }) async {
    final found = <String, WesiRuntimeDetectedDependency>{};
    for (final dependency in dependencies) {
      found[dependency.id] = await scanDependency(
        dependency,
        managedExecutablePath: managedExecutablePaths[dependency.id],
      );
    }
    return WesiRuntimeScanSnapshot(
      platform: platform,
      scannedAt: DateTime.now().toUtc(),
      dependencies: Map<String, WesiRuntimeDetectedDependency>.unmodifiable(found),
    );
  }

  Future<WesiRuntimeDetectedDependency> scanDependency(
    WesiRuntimeDependencySpec dependency, {
    String? managedExecutablePath,
  }) async {
    if (!dependency.supports(platform)) {
      return WesiRuntimeDetectedDependency.missing(dependency.id);
    }

    final managed = managedExecutablePath?.trim();
    if (managed != null && managed.isNotEmpty) {
      final result = await _probeCandidate(
        dependency,
        p.normalize(p.absolute(managed)),
        systemInstallation: false,
      );
      if (result != null) return result;
    }

    if (!dependency.allowSystemReuse) {
      return WesiRuntimeDetectedDependency.missing(dependency.id);
    }

    for (final probe in dependency.probes) {
      for (final executableName in probe.executableNames) {
        final executable = resolveExecutable(executableName);
        if (executable == null) continue;
        final result = await _probeCandidate(
          dependency,
          executable,
          systemInstallation: true,
        );
        if (result != null) return result;
      }
    }
    return WesiRuntimeDetectedDependency.missing(dependency.id);
  }

  Future<WesiRuntimeDetectedDependency?> _probeCandidate(
    WesiRuntimeDependencySpec dependency,
    String executable, {
    required bool systemInstallation,
  }) async {
    if (!File(executable).existsSync()) return null;
    for (final probe in dependency.probes) {
      final candidateNames = probe.executableNames
          .map((name) => p.basename(name).toLowerCase())
          .toSet();
      final executableBase = p.basename(executable).toLowerCase();
      final executableStem = p.basenameWithoutExtension(executable).toLowerCase();
      final nameMatches = candidateNames.isEmpty ||
          candidateNames.contains(executableBase) ||
          candidateNames.contains(executableStem) ||
          candidateNames.any((name) =>
              p.basenameWithoutExtension(name).toLowerCase() == executableStem);
      if (!nameMatches && dependency.probes.length > 1) continue;

      final outcome = await runner.run(
        executable: executable,
        arguments: probe.arguments,
        timeout: probe.timeout,
      );
      if (outcome.timedOut || outcome.exitCode != 0) continue;
      final output = switch (probe.versionStream) {
        WesiRuntimeProbeStream.stdout => outcome.stdout,
        WesiRuntimeProbeStream.stderr => outcome.stderr,
        WesiRuntimeProbeStream.combined => '${outcome.stdout}\n${outcome.stderr}',
      };
      final version = extractVersion(output, probe.versionPattern);
      final compatible = dependency.minimumVersion == null
          ? true
          : version != null &&
              compareVersions(version, dependency.minimumVersion!) >= 0;
      return WesiRuntimeDetectedDependency(
        dependencyId: dependency.id,
        detected: true,
        version: version,
        executablePath: executable,
        compatible: compatible,
        systemInstallation: systemInstallation,
        probeOutput: _safeProbeOutput(output),
      );
    }
    return null;
  }

  String? resolveExecutable(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.contains('\u0000')) return null;
    if (p.isAbsolute(trimmed)) {
      final file = File(p.normalize(trimmed));
      return file.existsSync() ? file.absolute.path : null;
    }
    if (trimmed.contains('/') || trimmed.contains('\\')) return null;

    final pathValue = environment['PATH'] ?? environment['Path'] ?? '';
    if (pathValue.isEmpty) return null;
    final extensions = _candidateExtensions(trimmed);
    for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
      final dir = directory.trim();
      if (dir.isEmpty) continue;
      for (final extension in extensions) {
        final candidate = File(p.join(dir, '$trimmed$extension'));
        if (candidate.existsSync()) return candidate.absolute.path;
      }
    }
    return null;
  }

  List<String> _candidateExtensions(String name) {
    if (!Platform.isWindows && platform != WesiRuntimePlatform.windows) {
      return const <String>[''];
    }
    if (p.extension(name).isNotEmpty) return const <String>[''];
    final raw = environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD';
    final out = raw
        .split(';')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.startsWith('.') && value.length <= 8)
        .toSet()
        .toList(growable: false);
    return <String>['', ...out];
  }

  static String? extractVersion(String output, RegExp? pattern) {
    if (pattern != null) {
      final match = pattern.firstMatch(output);
      if (match != null) {
        if (match.groupCount >= 1 && match.group(1) != null) {
          return match.group(1)!.trim();
        }
        return match.group(0)?.trim();
      }
      return null;
    }
    return RegExp(r'([0-9]+(?:\.[0-9]+){1,3})')
        .firstMatch(output)
        ?.group(1);
  }

  static int compareVersions(String left, String right) {
    final a = _numericVersion(left);
    final b = _numericVersion(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _numericVersion(String value) {
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)*)').firstMatch(value);
    if (match == null) return const <int>[];
    return match
        .group(1)!
        .split('.')
        .take(6)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  static String _safeProbeOutput(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return normalized.length <= 512 ? normalized : normalized.substring(0, 512);
  }
}
