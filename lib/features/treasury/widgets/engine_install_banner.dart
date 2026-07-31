import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../services/engine_install_service.dart';
import '../services/forecast_engine_kind.dart';

/// Баннер на экране прогноза: предлагает докачать Prophet/SARIMAX, если они
/// ещё не установлены. Закрывается крестиком — тогда сам больше не
/// появляется (движки всё равно можно докачать вручную в Настройках), пока
/// пользователь явно не откроет его снова оттуда.
///
/// Windows-only — на других платформах эти движки принципиально недоступны
/// (см. STATUS.md), баннер там просто не рисуется.
class EngineInstallBanner extends StatefulWidget {
  const EngineInstallBanner({super.key});

  @override
  State<EngineInstallBanner> createState() => _EngineInstallBannerState();
}

class _EngineInstallBannerState extends State<EngineInstallBanner> {
  static const _downloadable = [
    ForecastEngineKind.sarimax,
    ForecastEngineKind.prophet,
  ];

  bool _dismissed = EngineInstallService.bannerDismissed;
  Map<ForecastEngineKind, bool> _installed = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    EngineInstallService.progress.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    EngineInstallService.progress.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    final justFinished = EngineInstallService.progress.value.values
        .any((p) => p.stage == InstallStage.done);
    if (justFinished) _refresh();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final result = <ForecastEngineKind, bool>{};
    for (final kind in _downloadable) {
      result[kind] = await EngineInstallService.isInstalled(kind);
    }
    // Манифест нужен, чтобы понять, не устарела ли уже установленная сборка.
    // Fail-soft: нет сети — просто не будет предложений об обновлении.
    await EngineInstallService.fetchManifest();
    if (mounted) setState(() => _installed = result);
  }

  Future<void> _dismiss() async {
    await EngineInstallService.setBannerDismissed(true);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows || _dismissed) return const SizedBox.shrink();

    final missing =
        _downloadable.where((k) => _installed[k] == false).toList();
    // Установленные, но устаревшие — предлагаем обновить тем же баннером.
    final outdated = _downloadable
        .where((k) =>
            _installed[k] == true && EngineInstallService.updateAvailable(k))
        .toList();
    final actionable = [...missing, ...outdated];
    if (actionable.isEmpty) return const SizedBox.shrink();

    // Если ставить нечего и речь только про обновление — меняем текст,
    // чтобы не предлагать «установить» уже установленное.
    final updateOnly = missing.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(updateOnly ? Icons.system_update_alt : Icons.auto_awesome,
                  size: 18, color: AppTheme.accentOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  updateOnly
                      ? 'engine_update_banner_title'.w
                      : 'engine_install_banner_title'.w,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: _dismiss,
                child: const Icon(Icons.close,
                    size: 18, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            updateOnly
                ? 'engine_update_banner_hint'.w
                : 'engine_install_banner_hint'.w,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actionable.map(_downloadButton).toList(),
          ),
        ],
      ),
    );
  }

  Widget _downloadButton(ForecastEngineKind kind) {
    final p = EngineInstallService.progress.value[kind];
    final installing = p != null &&
        (p.stage == InstallStage.downloading ||
            p.stage == InstallStage.extracting);
    final failed = p?.stage == InstallStage.failed;
    final label = WesiLocale.isRussian ? kind.nameRu : kind.nameEn;
    final isUpdate = _installed[kind] == true;
    // Размер из манифеста точнее зашитой оценки — берём его, когда есть.
    final knownSize = EngineInstallService.cachedRelease(kind)?.sizeBytes ??
        EngineInstallService.approxSizeBytes[kind]!;
    final sizeMb = (knownSize / (1024 * 1024)).round();

    if (installing) {
      final pct =
          p.fraction != null ? ' ${(p.fraction! * 100).round()}%' : '';
      final stageLabel = p.stage == InstallStage.extracting
          ? 'engine_stage_extracting'.w
          : 'engine_stage_downloading'.w;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accentOrange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppTheme.accentOrange),
            ),
            const SizedBox(width: 8),
            Text(
              '$label · $stageLabel$pct',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.accentOrange,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => EngineInstallService.install(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: failed
                  ? AppTheme.accentRed.withOpacity(0.5)
                  : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                failed
                    ? Icons.refresh
                    : (isUpdate ? Icons.system_update_alt : Icons.download),
                size: 14,
                color: failed ? AppTheme.accentRed : AppTheme.accentOrange),
            const SizedBox(width: 6),
            Text(
              failed
                  ? '${'engine_retry'.w} $label'
                  : '${isUpdate ? 'engine_update_button'.w : 'engine_download'.w}'
                      ' $label (~$sizeMb ${WesiLocale.isRussian ? 'МБ' : 'MB'})',
              style: TextStyle(
                  fontSize: 12,
                  color: failed ? AppTheme.accentRed : AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
