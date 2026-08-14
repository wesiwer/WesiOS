import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../ai/media_engines/wesi_media_engine_service.dart';

class WesiMediaEnginesSection extends StatefulWidget {
  const WesiMediaEnginesSection({super.key});

  @override
  State<WesiMediaEnginesSection> createState() => _WesiMediaEnginesSectionState();
}

class _WesiMediaEnginesSectionState extends State<WesiMediaEnginesSection> {
  Map<WesiMediaEngineKind, bool> _installed = const {};

  @override
  void initState() {
    super.initState();
    WesiMediaEngineService.progress.addListener(_changed);
    WesiMediaEngineService.revision.addListener(_changed);
    _refresh();
  }

  @override
  void dispose() {
    WesiMediaEngineService.progress.removeListener(_changed);
    WesiMediaEngineService.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await WesiMediaEngineService.fetchManifest(force: true);
    final next = <WesiMediaEngineKind, bool>{};
    for (final kind in WesiMediaEngineKind.values) {
      next[kind] = await WesiMediaEngineService.isInstalled(kind);
    }
    if (mounted) setState(() => _installed = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Wesi AI поставляется без тяжёлых моделей. Генераторы можно установить отдельно; пакет проверяется SHA-256 перед запуском.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
        for (final kind in WesiMediaEngineKind.values) _tile(kind),
      ],
    );
  }

  Widget _tile(WesiMediaEngineKind kind) {
    final release = WesiMediaEngineService.cachedRelease(kind);
    final progress = WesiMediaEngineService.progress.value[kind];
    final installed = _installed[kind] == true;
    final installing = WesiMediaEngineService.isInstalling(kind);
    final failed = progress?.stage == WesiMediaInstallStage.failed;
    final size = release == null ? null : _formatBytes(release.sizeBytes);

    final title = switch (kind) {
      WesiMediaEngineKind.image => 'Wesi Image Engine',
      WesiMediaEngineKind.music => 'Wesi Music Engine',
      WesiMediaEngineKind.video => 'Wesi Video Engine',
    };

    String subtitle;
    if (release == null) {
      subtitle = 'Пакет ещё не опубликован на сервере';
    } else if (installing) {
      final percent = progress?.fraction == null
          ? ''
          : ' ${(progress!.fraction! * 100).round()}%';
      subtitle = switch (progress?.stage) {
        WesiMediaInstallStage.verifying => 'Проверка SHA-256…',
        WesiMediaInstallStage.extracting => 'Распаковка…',
        _ => 'Загрузка$percent',
      };
    } else if (failed) {
      subtitle = switch (progress?.error) {
        'sha256_mismatch' => 'Проверка целостности не пройдена',
        'size_mismatch' => 'Сервер отдал пакет неправильного размера',
        'launcher_missing' => 'Пакет повреждён: нет runtime launcher',
        'not_published' => 'Пакет ещё не опубликован',
        _ => 'Не удалось установить пакет',
      };
    } else if (installed) {
      subtitle = 'Установлен · ${release.name} ${release.version} · ${release.license}';
    } else {
      final requirements = <String>[
        if (size != null) size,
        if (release.minRamGb > 0) 'RAM ≥ ${release.minRamGb} ГБ',
        if (release.recommendedVramGb > 0) 'GPU VRAM ≈ ${release.recommendedVramGb} ГБ',
        release.license,
      ].join(' · ');
      subtitle = requirements;
    }

    return ListTile(
      leading: Icon(
        installed ? Icons.check_circle : _icon(kind),
        color: installed ? AppTheme.accentGreen : AppTheme.accent,
      ),
      title: Text(title, style: TextStyle(color: AppTheme.textPrimary)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: failed ? AppTheme.accentRed : AppTheme.textMuted,
          fontSize: 13,
        ),
      ),
      trailing: installing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress?.fraction,
                color: AppTheme.accent,
              ),
            )
          : installed
              ? TextButton(
                  onPressed: () async {
                    await WesiMediaEngineService.remove(kind);
                    await _refresh();
                  },
                  child: const Text('Удалить'),
                )
              : TextButton(
                  onPressed: release == null
                      ? _refresh
                      : () async {
                          await WesiMediaEngineService.install(kind);
                          await _refresh();
                        },
                  child: Text(release == null ? 'Проверить' : 'Установить'),
                ),
    );
  }

  static IconData _icon(WesiMediaEngineKind kind) => switch (kind) {
        WesiMediaEngineKind.image => Icons.image_outlined,
        WesiMediaEngineKind.music => Icons.music_note_outlined,
        WesiMediaEngineKind.video => Icons.movie_creation_outlined,
      };

  static String _formatBytes(int value) {
    final gb = value / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} ГБ';
    return '${(value / (1024 * 1024)).round()} МБ';
  }
}
