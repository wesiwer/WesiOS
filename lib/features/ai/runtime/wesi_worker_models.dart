enum WesiWorkerPlatform { android, ios, windows, linux, macos, unknown }

enum WesiWorkerCapability {
  chat,
  files,
  terminal,
  git,
  web,
  browser,
  documents,
  archives,
  python,
  node,
  flutter,
  androidBuild,
  windowsBuild,
  ffmpeg,
  imageGeneration,
  musicGeneration,
  videoGeneration,
}

enum WesiRuntimePackId { core, developer, browser, documents, media }

enum WesiWorkerStatus { offline, online, busy, paused }

enum WesiRuntimeDependencyKind {
  executable,
  sdk,
  workload,
  bundledTool,
  model,
}

enum WesiRuntimeDependencyAction {
  reuse,
  install,
  upgrade,
  unsupported,
}

class WesiRuntimeDependency {
  final String id;
  final String title;
  final WesiRuntimeDependencyKind kind;
  final String? minimumVersion;
  final List<String> detectionCommands;
  final bool allowSystemInstallation;
  final bool optional;
  final List<WesiWorkerPlatform> platforms;
  final String installHint;

  const WesiRuntimeDependency({
    required this.id,
    required this.title,
    required this.kind,
    required this.detectionCommands,
    required this.platforms,
    required this.installHint,
    this.minimumVersion,
    this.allowSystemInstallation = true,
    this.optional = false,
  });

  bool supportsPlatform(WesiWorkerPlatform platform) =>
      platforms.isEmpty || platforms.contains(platform);
}

class WesiRuntimeDependencyState {
  final String dependencyId;
  final bool detected;
  final String? version;
  final String? path;
  final bool compatible;

  const WesiRuntimeDependencyState({
    required this.dependencyId,
    required this.detected,
    required this.compatible,
    this.version,
    this.path,
  });
}

class WesiRuntimeDependencyPlanItem {
  final WesiRuntimeDependency dependency;
  final WesiRuntimeDependencyAction action;
  final WesiRuntimeDependencyState? detected;
  final String reason;

  const WesiRuntimeDependencyPlanItem({
    required this.dependency,
    required this.action,
    required this.reason,
    this.detected,
  });
}

class WesiRuntimePack {
  final WesiRuntimePackId id;
  final String title;
  final String description;
  final List<WesiWorkerCapability> capabilities;
  final List<WesiRuntimeDependency> dependencies;
  final bool optional;

  const WesiRuntimePack({
    required this.id,
    required this.title,
    required this.description,
    required this.capabilities,
    this.dependencies = const <WesiRuntimeDependency>[],
    this.optional = true,
  });
}

class WesiRuntimeCatalog {
  static const desktopPlatforms = <WesiWorkerPlatform>[
    WesiWorkerPlatform.windows,
    WesiWorkerPlatform.linux,
    WesiWorkerPlatform.macos,
  ];

  static const packs = <WesiRuntimePack>[
    WesiRuntimePack(
      id: WesiRuntimePackId.core,
      title: 'Wesi Agent Runtime',
      description: 'Файлы, безопасный локальный executor, Git и базовые инструменты.',
      optional: false,
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.files,
        WesiWorkerCapability.git,
        WesiWorkerCapability.archives,
      ],
      dependencies: <WesiRuntimeDependency>[
        WesiRuntimeDependency(
          id: 'git',
          title: 'Git',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '2.40',
          detectionCommands: <String>['git --version'],
          platforms: desktopPlatforms,
          installHint: 'Install Git using the platform package manager or the Wesi managed package.',
        ),
        WesiRuntimeDependency(
          id: '7zip',
          title: '7-Zip / archive tools',
          kind: WesiRuntimeDependencyKind.executable,
          detectionCommands: <String>['7z --help', '7zz --help'],
          platforms: desktopPlatforms,
          installHint: 'Install the Wesi managed archive tools bundle.',
        ),
      ],
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.developer,
      title: 'Developer Pack',
      description: 'Terminal, Python, Node, Flutter и сборочные инструменты.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.terminal,
        WesiWorkerCapability.python,
        WesiWorkerCapability.node,
        WesiWorkerCapability.flutter,
        WesiWorkerCapability.androidBuild,
        WesiWorkerCapability.windowsBuild,
      ],
      dependencies: <WesiRuntimeDependency>[
        WesiRuntimeDependency(
          id: 'python',
          title: 'Python',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '3.11',
          detectionCommands: <String>['python --version', 'python3 --version'],
          platforms: desktopPlatforms,
          installHint: 'Install a Wesi managed Python runtime if a compatible system Python is unavailable.',
        ),
        WesiRuntimeDependency(
          id: 'node',
          title: 'Node.js',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '20',
          detectionCommands: <String>['node --version'],
          platforms: desktopPlatforms,
          installHint: 'Install the Wesi managed Node.js LTS runtime.',
        ),
        WesiRuntimeDependency(
          id: 'jdk',
          title: 'Java JDK',
          kind: WesiRuntimeDependencyKind.sdk,
          minimumVersion: '17',
          detectionCommands: <String>['java -version', 'javac -version'],
          platforms: desktopPlatforms,
          installHint: 'Install the Wesi managed JDK required by Android/Gradle builds.',
        ),
        WesiRuntimeDependency(
          id: 'flutter',
          title: 'Flutter SDK',
          kind: WesiRuntimeDependencyKind.sdk,
          minimumVersion: '3.24',
          detectionCommands: <String>['flutter --version'],
          platforms: desktopPlatforms,
          installHint: 'Install Flutter SDK into the Wesi runtime directory when no compatible system SDK exists.',
        ),
        WesiRuntimeDependency(
          id: 'android-sdk',
          title: 'Android SDK / command-line tools',
          kind: WesiRuntimeDependencyKind.sdk,
          detectionCommands: <String>['adb --version', 'sdkmanager --version'],
          platforms: desktopPlatforms,
          installHint: 'Install Android command-line tools, platform-tools and the required SDK platforms.',
        ),
        WesiRuntimeDependency(
          id: 'cmake',
          title: 'CMake',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '3.22',
          detectionCommands: <String>['cmake --version'],
          platforms: desktopPlatforms,
          installHint: 'Install CMake only when native desktop/Android builds require it.',
        ),
        WesiRuntimeDependency(
          id: 'vs-build-tools',
          title: 'Visual Studio Build Tools C++ workload',
          kind: WesiRuntimeDependencyKind.workload,
          detectionCommands: <String>['vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64'],
          platforms: <WesiWorkerPlatform>[WesiWorkerPlatform.windows],
          installHint: 'Install Visual Studio Build Tools with Desktop development with C++; the full Visual Studio IDE is not required.',
        ),
      ],
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.browser,
      title: 'Browser Pack',
      description: 'Изолированный браузер для поиска, сайтов и UI-тестов.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.web,
        WesiWorkerCapability.browser,
      ],
      dependencies: <WesiRuntimeDependency>[
        WesiRuntimeDependency(
          id: 'chromium-runtime',
          title: 'Managed Chromium',
          kind: WesiRuntimeDependencyKind.bundledTool,
          detectionCommands: <String>['chromium --version', 'chrome --version'],
          allowSystemInstallation: false,
          platforms: desktopPlatforms,
          installHint: 'Install the sandboxed Wesi Chromium runtime.',
        ),
      ],
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.documents,
      title: 'Documents Pack',
      description: 'Создание и проверка PDF, DOCX, XLSX и других документов.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.documents,
      ],
      dependencies: <WesiRuntimeDependency>[
        WesiRuntimeDependency(
          id: 'document-toolchain',
          title: 'Wesi Document Toolchain',
          kind: WesiRuntimeDependencyKind.bundledTool,
          detectionCommands: <String>[],
          allowSystemInstallation: false,
          platforms: desktopPlatforms,
          installHint: 'Install the Wesi managed PDF/DOCX/XLSX document toolchain.',
        ),
      ],
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.media,
      title: 'Media Pack',
      description: 'FFmpeg и локальные Image/Music/Video Engines.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.ffmpeg,
        WesiWorkerCapability.imageGeneration,
        WesiWorkerCapability.musicGeneration,
        WesiWorkerCapability.videoGeneration,
      ],
      dependencies: <WesiRuntimeDependency>[
        WesiRuntimeDependency(
          id: 'ffmpeg',
          title: 'FFmpeg',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '6',
          detectionCommands: <String>['ffmpeg -version'],
          platforms: desktopPlatforms,
          installHint: 'Reuse a compatible FFmpeg or install the Wesi managed media toolchain.',
        ),
      ],
    ),
  ];

  static List<WesiRuntimeDependencyPlanItem> planDependencies({
    required WesiRuntimePack pack,
    required WesiWorkerPlatform platform,
    required Map<String, WesiRuntimeDependencyState> detected,
  }) {
    return pack.dependencies.map((dependency) {
      if (!dependency.supportsPlatform(platform)) {
        return WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.unsupported,
          reason: 'Dependency is not supported on ${platform.name}.',
        );
      }
      final state = detected[dependency.id];
      if (state == null || !state.detected) {
        return WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.install,
          detected: state,
          reason: 'Dependency is missing.',
        );
      }
      if (!state.compatible) {
        return WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.upgrade,
          detected: state,
          reason: 'Installed version is incompatible with this runtime pack.',
        );
      }
      return WesiRuntimeDependencyPlanItem(
        dependency: dependency,
        action: WesiRuntimeDependencyAction.reuse,
        detected: state,
        reason: 'Compatible installation is already available.',
      );
    }).toList(growable: false);
  }
}

class WesiWorkerProfile {
  final String id;
  final String name;
  final WesiWorkerPlatform platform;
  final WesiWorkerStatus status;
  final int cpuCores;
  final int ramMb;
  final int? gpuVramMb;
  final String? gpuName;
  final int? freeDiskMb;
  final List<WesiWorkerCapability> capabilities;
  final List<WesiRuntimePackId> installedPacks;
  final DateTime? lastSeenAt;
  final bool localDevice;

  const WesiWorkerProfile({
    required this.id,
    required this.name,
    required this.platform,
    required this.status,
    required this.cpuCores,
    required this.ramMb,
    required this.capabilities,
    required this.installedPacks,
    this.gpuVramMb,
    this.gpuName,
    this.freeDiskMb,
    this.lastSeenAt,
    this.localDevice = false,
  });

  bool supportsAll(Iterable<WesiWorkerCapability> required) =>
      required.every(capabilities.contains);

  bool get online => status == WesiWorkerStatus.online || status == WesiWorkerStatus.busy;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'platform': platform.name,
        'status': status.name,
        'cpuCores': cpuCores,
        'ramMb': ramMb,
        'gpuVramMb': gpuVramMb,
        'gpuName': gpuName,
        'freeDiskMb': freeDiskMb,
        'capabilities': capabilities.map((e) => e.name).toList(growable: false),
        'installedPacks': installedPacks.map((e) => e.name).toList(growable: false),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'localDevice': localDevice,
      };

  factory WesiWorkerProfile.fromJson(Map<String, dynamic> json) => WesiWorkerProfile(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Wesi Worker'}',
        platform: WesiWorkerPlatform.values.byName('${json['platform'] ?? 'unknown'}'),
        status: WesiWorkerStatus.values.byName('${json['status'] ?? 'offline'}'),
        cpuCores: (json['cpuCores'] as num?)?.toInt() ?? 0,
        ramMb: (json['ramMb'] as num?)?.toInt() ?? 0,
        gpuVramMb: (json['gpuVramMb'] as num?)?.toInt(),
        gpuName: json['gpuName'] as String?,
        freeDiskMb: (json['freeDiskMb'] as num?)?.toInt(),
        capabilities: (json['capabilities'] as List? ?? const <dynamic>[])
            .map((e) => WesiWorkerCapability.values.byName('$e'))
            .toList(growable: false),
        installedPacks: (json['installedPacks'] as List? ?? const <dynamic>[])
            .map((e) => WesiRuntimePackId.values.byName('$e'))
            .toList(growable: false),
        lastSeenAt: json['lastSeenAt'] == null ? null : DateTime.tryParse('${json['lastSeenAt']}'),
        localDevice: json['localDevice'] == true,
      );
}
