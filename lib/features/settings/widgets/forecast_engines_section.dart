import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../treasury/services/engine_install_service.dart';
import '../../treasury/services/forecast_engine_kind.dart';

/// Раздел настроек «Модели прогноза»: статус и (пере)установка Prophet/
/// SARIMAX, плюс тумблер видимости плавающего индикатора загрузки.
/// То же самое, что баннер на экране прогноза, но всегда доступно — баннер
/// можно закрыть, а сюда можно вернуться в любой момент (см. STATUS.md,
/// запрос пользователя: «докачать в настройках приложения»).
class ForecastEnginesSection extends StatefulWidget {
  const ForecastEnginesSection({super.key});

  @override
  State<ForecastEnginesSection> createState() =>
      _ForecastEnginesSectionState();
}

class _ForecastEnginesSectionState extends State<ForecastEnginesSection> {
  static const _engines = [
    ForecastEngineKind.sarimax,
    ForecastEngineKind.prophet,
  ];

  Map<ForecastEngineKind, bool> _installed = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    EngineInstallService.progress.addListener(_onChange);
  }

  @override
  void dispose() {
    EngineInstallService.progress.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final justFinished = EngineInstallService.progress.value.values
        .any((p) => p.stage == InstallStage.done);
    if (justFinished) _refresh();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final result = <ForecastEngineKind, bool>{};
    for (final kind in _engines) {
      result[kind] = await EngineInstallService.isInstalled(kind);
    }
    if (mounted) setState(() => _installed = result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._engines.map(_engineTile),
        if (Platform.isWindows) _overlayToggleTile(),
      ],
    );
  }

  Widget _engineTile(ForecastEngineKind kind) {
    final label = WesiLocale.isRussian ? kind.nameRu : kind.nameEn;
    final sizeMb =
        (EngineInstallService.approxSizeBytes[kind]! / (1024 * 1024)).round();
    final unit = WesiLocale.isRussian ? 'МБ' : 'MB';
    final installed = _installed[kind] == true;
    final p = EngineInstallService.progress.value[kind];
    final installing = p != null &&
        (p.stage == InstallStage.downloading ||
            p.stage == InstallStage.extracting);
    final failed = p?.stage == InstallStage.failed;

    String subtitle;
    if (!Platform.isWindows) {
      subtitle = 'engine_windows_only'.w;
    } else if (installing) {
      final pct = p.fraction != null ? ' ${(p.fraction! * 100).round()}%' : '';
      final stage = p.stage == InstallStage.extracting
          ? 'engine_stage_extracting'.w
          : 'engine_stage_downloading'.w;
      subtitle = '$stage$pct';
    } else if (installed) {
      subtitle = '${'engine_installed'.w} · ~$sizeMb $unit';
    } else if (failed) {
      subtitle = p?.error == 'windows_only'
          ? 'engine_windows_only'.w
          : 'engine_not_installed'.w;
    } else {
      subtitle = '${'engine_not_installed'.w} · ~$sizeMb $unit';
    }

    return ListTile(
      leading: Icon(
        installed ? Icons.check_circle : Icons.cloud_download_outlined,
        color: installed ? AppTheme.accentGreen : AppTheme.accentOrange,
      ),
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: (failed ? AppTheme.accentRed : AppTheme.textMuted)
                  .withOpacity(0.9),
              fontSize: 13)),
      trailing: !Platform.isWindows
          ? null
          : installing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accentOrange),
                )
              : TextButton(
                  onPressed: () => EngineInstallService.install(kind),
                  child: Text(
                    installed
                        ? 'engine_reinstall_button'.w
                        : 'engine_install_button'.w,
                    style: const TextStyle(color: AppTheme.accentOrange),
                  ),
                ),
    );
  }

  Widget _overlayToggleTile() {
    return ListTile(
      leading: const Icon(Icons.picture_in_picture,
          color: AppTheme.accentOrange),
      title: Text('engine_show_download_overlay'.w,
          style: const TextStyle(color: AppTheme.textPrimary)),
      subtitle: Text('engine_show_download_overlay_hint'.w,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      trailing: ValueListenableBuilder<bool>(
        valueListenable: EngineInstallService.overlayHidden,
        builder: (context, hidden, _) => Switch(
          value: !hidden,
          onChanged: (v) => EngineInstallService.overlayHidden.value = !v,
          activeColor: AppTheme.accentOrange,
        ),
      ),
    );
  }
}
