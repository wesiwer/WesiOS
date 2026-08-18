import 'dart:convert';

/// Risk is derived by the runtime registry, never trusted from model arguments.
enum WesiLocalRisk { read, write, destructive }

enum WesiLocalCapability {
  filesystem,
  terminal,
  git,
  http,
  python,
  node,
  flutter,
  build,
  documents,
  media,
}

enum WesiLocalSandboxProfile {
  /// Direct host execution. Safe only for tools that do not require a sandbox.
  none,

  /// Versioned WesiOS sandbox contract for arbitrary project code/toolchains.
  ///
  /// A trusted Runtime Pack may advertise this profile only when the bound
  /// executable is an OS sandbox wrapper that enforces all of the following:
  /// - filesystem access is limited to the selected workspace;
  /// - `.wesi` internal state and host secrets are inaccessible to child code;
  /// - CPU/RAM/workspace-disk/time quotas are enforceable;
  /// - network is denied by default or routed through an explicit policy;
  /// - no Docker socket, host shell/session credentials or privileged paths.
  ///
  /// The LLM cannot choose or serialize this profile. Stage 7 Environment
  /// Scanner/Runtime Packs are the only intended producer of such bindings.
  workspaceV1,
}

class WesiLocalToolNames {
  WesiLocalToolNames._();

  static const fsList = 'local.fs.list';
  static const fsReadText = 'local.fs.read_text';
  static const fsWriteText = 'local.fs.write_text';
  static const fsDelete = 'local.fs.delete';

  static const terminalRun = 'local.terminal.run';

  static const gitStatus = 'local.git.status';
  static const gitDiff = 'local.git.diff';
  static const gitAdd = 'local.git.add';
  static const gitCommit = 'local.git.commit';

  static const httpGet = 'local.http.get';
  static const httpPost = 'local.http.post';

  static const pythonRun = 'local.python.run';
  static const nodeRun = 'local.node.run';
  static const flutterAnalyze = 'local.flutter.analyze';
  static const flutterTest = 'local.flutter.test';
  static const flutterBuild = 'local.flutter.build';
  static const documentRun = 'local.document.run';
  static const mediaRun = 'local.media.run';
}

class WesiLocalToolMeta {
  final String name;
  final WesiLocalCapability capability;
  final WesiLocalRisk risk;
  final bool requiresSandboxedBinding;

  const WesiLocalToolMeta({
    required this.name,
    required this.capability,
    required this.risk,
    this.requiresSandboxedBinding = false,
  });
}

/// Fail-closed registry for the local worker boundary.
class WesiLocalCapabilityRegistry {
  WesiLocalCapabilityRegistry._();

  static const Map<String, WesiLocalToolMeta> _tools = {
    WesiLocalToolNames.fsList: WesiLocalToolMeta(
      name: WesiLocalToolNames.fsList,
      capability: WesiLocalCapability.filesystem,
      risk: WesiLocalRisk.read,
    ),
    WesiLocalToolNames.fsReadText: WesiLocalToolMeta(
      name: WesiLocalToolNames.fsReadText,
      capability: WesiLocalCapability.filesystem,
      risk: WesiLocalRisk.read,
    ),
    WesiLocalToolNames.fsWriteText: WesiLocalToolMeta(
      name: WesiLocalToolNames.fsWriteText,
      capability: WesiLocalCapability.filesystem,
      risk: WesiLocalRisk.write,
    ),
    WesiLocalToolNames.fsDelete: WesiLocalToolMeta(
      name: WesiLocalToolNames.fsDelete,
      capability: WesiLocalCapability.filesystem,
      risk: WesiLocalRisk.destructive,
    ),
    WesiLocalToolNames.terminalRun: WesiLocalToolMeta(
      name: WesiLocalToolNames.terminalRun,
      capability: WesiLocalCapability.terminal,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.gitStatus: WesiLocalToolMeta(
      name: WesiLocalToolNames.gitStatus,
      capability: WesiLocalCapability.git,
      risk: WesiLocalRisk.read,
    ),
    WesiLocalToolNames.gitDiff: WesiLocalToolMeta(
      name: WesiLocalToolNames.gitDiff,
      capability: WesiLocalCapability.git,
      risk: WesiLocalRisk.read,
    ),
    WesiLocalToolNames.gitAdd: WesiLocalToolMeta(
      name: WesiLocalToolNames.gitAdd,
      capability: WesiLocalCapability.git,
      risk: WesiLocalRisk.write,
    ),
    WesiLocalToolNames.gitCommit: WesiLocalToolMeta(
      name: WesiLocalToolNames.gitCommit,
      capability: WesiLocalCapability.git,
      risk: WesiLocalRisk.write,
    ),
    WesiLocalToolNames.httpGet: WesiLocalToolMeta(
      name: WesiLocalToolNames.httpGet,
      capability: WesiLocalCapability.http,
      risk: WesiLocalRisk.read,
    ),
    WesiLocalToolNames.httpPost: WesiLocalToolMeta(
      name: WesiLocalToolNames.httpPost,
      capability: WesiLocalCapability.http,
      risk: WesiLocalRisk.write,
    ),
    WesiLocalToolNames.pythonRun: WesiLocalToolMeta(
      name: WesiLocalToolNames.pythonRun,
      capability: WesiLocalCapability.python,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.nodeRun: WesiLocalToolMeta(
      name: WesiLocalToolNames.nodeRun,
      capability: WesiLocalCapability.node,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.flutterAnalyze: WesiLocalToolMeta(
      name: WesiLocalToolNames.flutterAnalyze,
      capability: WesiLocalCapability.flutter,
      risk: WesiLocalRisk.read,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.flutterTest: WesiLocalToolMeta(
      name: WesiLocalToolNames.flutterTest,
      capability: WesiLocalCapability.flutter,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.flutterBuild: WesiLocalToolMeta(
      name: WesiLocalToolNames.flutterBuild,
      capability: WesiLocalCapability.build,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.documentRun: WesiLocalToolMeta(
      name: WesiLocalToolNames.documentRun,
      capability: WesiLocalCapability.documents,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
    WesiLocalToolNames.mediaRun: WesiLocalToolMeta(
      name: WesiLocalToolNames.mediaRun,
      capability: WesiLocalCapability.media,
      risk: WesiLocalRisk.write,
      requiresSandboxedBinding: true,
    ),
  };

  static WesiLocalToolMeta? get(String name) => _tools[name];

  static List<WesiLocalToolMeta> get all =>
      List<WesiLocalToolMeta>.unmodifiable(_tools.values);
}

class WesiLocalToolCall {
  final String id;
  final String tool;
  final Map<String, dynamic> arguments;

  const WesiLocalToolCall({
    required this.id,
    required this.tool,
    this.arguments = const <String, dynamic>{},
  });

  int get encodedArgumentBytes => utf8.encode(jsonEncode(arguments)).length;
}

class WesiLocalExecutableBinding {
  /// Logical id exposed to typed tools, for example `git` or `python`.
  final String id;

  /// Host path is runtime-owned configuration and is never supplied by LLM.
  final String executablePath;

  /// For workspaceV1, executablePath is the trusted Wesi sandbox wrapper.
  /// The real detected runtime binary is stored separately and never supplied
  /// by model arguments.
  final String? sandboxTargetPath;

  /// Versioned isolation contract attested by trusted runtime provisioning.
  final WesiLocalSandboxProfile sandboxProfile;

  /// Arbitrary scripts/project code may run only through such a binding.
  final bool allowArbitraryCode;

  const WesiLocalExecutableBinding({
    required this.id,
    required this.executablePath,
    this.sandboxTargetPath,
    this.sandboxProfile = WesiLocalSandboxProfile.none,
    this.allowArbitraryCode = false,
  });

  bool get sandboxed => sandboxProfile != WesiLocalSandboxProfile.none;
}

class WesiLocalRuntimeBindings {
  final Map<String, WesiLocalExecutableBinding> executables;

  /// Environment is produced by the trusted Environment Scanner/Runtime Pack
  /// layer. The executor still filters keys before spawning a process.
  final Map<String, String> environment;

  /// Logical bindings explicitly allowed for `local.terminal.run`.
  final Set<String> terminalAllowlist;

  const WesiLocalRuntimeBindings({
    this.executables = const <String, WesiLocalExecutableBinding>{},
    this.environment = const <String, String>{},
    this.terminalAllowlist = const <String>{},
  });

  WesiLocalExecutableBinding? operator [](String id) => executables[id];
}

class WesiLocalRuntimeLimits {
  final Duration processTimeout;
  final int maxStdoutBytes;
  final int maxStderrBytes;
  final int maxReadBytes;
  final int maxWriteBytes;
  final int maxHttpRequestBytes;
  final int maxHttpResponseBytes;
  final int maxDirectoryEntries;
  final int maxArguments;
  final int maxArgumentLength;

  /// Limits handed to an OS sandbox driver by Stage 7 Runtime Packs. The
  /// Stage 6 executor deliberately does not pretend Dart can enforce host CPU,
  /// RAM or filesystem quotas for arbitrary child processes by itself.
  final int maxMemoryBytes;
  final int maxWorkspaceBytes;
  final int maxCpuPercent;

  const WesiLocalRuntimeLimits({
    this.processTimeout = const Duration(minutes: 3),
    this.maxStdoutBytes = 2 * 1024 * 1024,
    this.maxStderrBytes = 2 * 1024 * 1024,
    this.maxReadBytes = 8 * 1024 * 1024,
    this.maxWriteBytes = 8 * 1024 * 1024,
    this.maxHttpRequestBytes = 2 * 1024 * 1024,
    this.maxHttpResponseBytes = 8 * 1024 * 1024,
    this.maxDirectoryEntries = 2000,
    this.maxArguments = 128,
    this.maxArgumentLength = 4096,
    this.maxMemoryBytes = 1024 * 1024 * 1024,
    this.maxWorkspaceBytes = 4 * 1024 * 1024 * 1024,
    this.maxCpuPercent = 80,
  });
}

class WesiLocalRuntimeContext {
  final String workspaceRoot;
  final WesiLocalRuntimeBindings bindings;
  final WesiLocalRuntimeLimits limits;

  /// Set only by trusted orchestration after explicit user confirmation.
  /// Model arguments are never deserialized into this field.
  final bool destructiveConfirmed;

  /// Trusted policy override for controlled LAN/dev scenarios; never sourced
  /// from a model tool call.
  final bool allowInsecureHttp;

  const WesiLocalRuntimeContext({
    required this.workspaceRoot,
    this.bindings = const WesiLocalRuntimeBindings(),
    this.limits = const WesiLocalRuntimeLimits(),
    this.destructiveConfirmed = false,
    this.allowInsecureHttp = false,
  });

  WesiLocalRuntimeContext copyWith({
    WesiLocalRuntimeBindings? bindings,
    WesiLocalRuntimeLimits? limits,
    bool? destructiveConfirmed,
    bool? allowInsecureHttp,
  }) =>
      WesiLocalRuntimeContext(
        workspaceRoot: workspaceRoot,
        bindings: bindings ?? this.bindings,
        limits: limits ?? this.limits,
        destructiveConfirmed: destructiveConfirmed ?? this.destructiveConfirmed,
        allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
      );
}

class WesiLocalToolResult {
  final bool ok;
  final String code;
  final String message;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final Map<String, dynamic> data;
  final Duration duration;

  const WesiLocalToolResult({
    required this.ok,
    required this.code,
    required this.message,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.data = const <String, dynamic>{},
    this.duration = Duration.zero,
  });

  factory WesiLocalToolResult.success({
    String message = 'OK',
    int? exitCode,
    String? stdout,
    String? stderr,
    Map<String, dynamic> data = const <String, dynamic>{},
    Duration duration = Duration.zero,
  }) =>
      WesiLocalToolResult(
        ok: true,
        code: 'OK',
        message: message,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        data: data,
        duration: duration,
      );

  factory WesiLocalToolResult.failure(
    String code,
    String message, {
    int? exitCode,
    String? stdout,
    String? stderr,
    Map<String, dynamic> data = const <String, dynamic>{},
    Duration duration = Duration.zero,
  }) =>
      WesiLocalToolResult(
        ok: false,
        code: code,
        message: message,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        data: data,
        duration: duration,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'code': code,
        'message': message,
        if (exitCode != null) 'exitCode': exitCode,
        if (stdout != null) 'stdout': stdout,
        if (stderr != null) 'stderr': stderr,
        if (data.isNotEmpty) 'data': data,
        'durationMs': duration.inMilliseconds,
      };
}
