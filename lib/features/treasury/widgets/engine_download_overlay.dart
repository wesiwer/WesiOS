import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../services/engine_install_service.dart';
import '../services/forecast_engine_kind.dart';

/// Плавающее окошко прогресса загрузки движков прогноза — поверх ЛЮБОГО
/// экрана приложения (тот же принцип, что у CalculatorOverlay в app.dart:
/// живёт в глобальном Overlay, а не привязано к конкретной вкладке).
///
/// Автоматически появляется, когда идёт хотя бы одна закачка, и исчезает,
/// когда все завершились. Можно свернуть кнопкой — тогда прогресс всё
/// равно продолжается в фоне, просто без мини-окна; вернуть его можно из
/// Настроек (EngineInstallService.overlayHidden).
class EngineDownloadOverlay extends StatefulWidget {
  const EngineDownloadOverlay({super.key});

  @override
  State<EngineDownloadOverlay> createState() => _EngineDownloadOverlayState();
}

class _EngineDownloadOverlayState extends State<EngineDownloadOverlay> {
  @override
  void initState() {
    super.initState();
    EngineInstallService.progress.addListener(_onChange);
    EngineInstallService.overlayHidden.addListener(_onChange);
  }

  @override
  void dispose() {
    EngineInstallService.progress.removeListener(_onChange);
    EngineInstallService.overlayHidden.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (EngineInstallService.overlayHidden.value) return const SizedBox.shrink();

    final active = EngineInstallService.progress.value.entries
        .where((e) =>
            e.value.stage == InstallStage.downloading ||
            e.value.stage == InstallStage.extracting)
        .toList();
    if (active.isEmpty) return SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.downloading,
                      size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'engine_downloading_title'.w,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => EngineInstallService.overlayHidden.value = true,
                    child: Icon(Icons.remove,
                        size: 16, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...active.map((e) => _row(e.key, e.value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ForecastEngineKind kind, EngineInstallProgress p) {
    final label = WesiLocale.isRussian ? kind.nameRu : kind.nameEn;
    final pct = p.fraction != null ? '${(p.fraction! * 100).round()}%' : '';
    final stageLabel = p.stage == InstallStage.extracting
        ? 'engine_stage_extracting'.w
        : 'engine_stage_downloading'.w;
    final speedMb = p.bytesPerSecond / (1024 * 1024);
    final speedUnit = WesiLocale.isRussian ? 'МБ/с' : 'MB/s';

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$label — $stageLabel',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                pct,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent),
              ),
            ],
          ),
          SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p.fraction,
              minHeight: 4,
              backgroundColor: AppTheme.surfaceLight,
              valueColor: AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          if (p.stage == InstallStage.downloading) ...[
            SizedBox(height: 2),
            Text(
              '${speedMb.toStringAsFixed(1)} $speedUnit',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
