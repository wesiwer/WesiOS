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

class WesiRuntimePack {
  final WesiRuntimePackId id;
  final String title;
  final String description;
  final List<WesiWorkerCapability> capabilities;
  final bool optional;

  const WesiRuntimePack({
    required this.id,
    required this.title,
    required this.description,
    required this.capabilities,
    this.optional = true,
  });
}

class WesiRuntimeCatalog {
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
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.browser,
      title: 'Browser Pack',
      description: 'Изолированный браузер для поиска, сайтов и UI-тестов.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.web,
        WesiWorkerCapability.browser,
      ],
    ),
    WesiRuntimePack(
      id: WesiRuntimePackId.documents,
      title: 'Documents Pack',
      description: 'Создание и проверка PDF, DOCX, XLSX и других документов.',
      capabilities: <WesiWorkerCapability>[
        WesiWorkerCapability.documents,
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
    ),
  ];
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
