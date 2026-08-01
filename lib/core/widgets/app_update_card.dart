import 'package:flutter/material.dart';

import '../localization/wesi_locale.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';
import 'hover_button.dart';

/// Карточка обновления WesiOS.
///
/// Ведёт себя как загрузка моделей прогноза, которую пользователь уже видел:
/// проверка → предложение с версией, размером и changelog → прогресс →
/// установка. Показывается в настройках всегда, на главной — только когда
/// обновление реально есть (см. [AppUpdateBanner]).
class AppUpdateCard extends StatefulWidget {
  /// Компактный режим: без кнопки «Пропустить» — для баннера на главной.
  /// Changelog показывается в обоих режимах, чтобы обновление не ставилось
  /// вслепую.
  final bool compact;

  const AppUpdateCard({super.key, this.compact = false});

  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<AppUpdateCard> {
  bool _checking = false;
  bool _notesExpanded = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await AppUpdateService.check(force: true);
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _install() async {
    await AppUpdateService.downloadAndInstall();
  }

  Future<void> _skip(String version) async {
    await AppUpdateService.skip(version);
    if (mounted) setState(() {});
  }

  String _size(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} ГБ';
    return '${mb.toStringAsFixed(0)} МБ';
  }

  String _speed(double bps) {
    if (bps <= 0) return '';
    final mb = bps / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} МБ/с';
    return '${(bps / 1024).toStringAsFixed(0)} КБ/с';
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    if (!AppUpdateService.isSupported) {
      return _shell(
        child: Text(
          ru
              ? 'Автообновление доступно только в сборках для Windows и Android.'
              : 'Auto-update is available in the Windows and Android builds only.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }

    return ValueListenableBuilder<UpdateProgress>(
      valueListenable: AppUpdateService.progress,
      builder: (context, p, _) {
        return ValueListenableBuilder<AppRelease?>(
          valueListenable: AppUpdateService.latest,
          builder: (context, release, __) => _shell(
            child: _content(ru, p, release),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) => Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );

  Widget _content(bool ru, UpdateProgress p, AppRelease? release) {
    final hasUpdate = AppUpdateService.updateAvailable && release != null;
    final notes = release?.notes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasUpdate ? Icons.system_update : Icons.verified_outlined,
              size: 20,
              color: hasUpdate ? AppTheme.accentOrange : AppTheme.accentGreen,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                hasUpdate
                    ? (ru
                        ? 'Доступна версия ${release.version}'
                        : 'Version ${release.version} is available')
                    : (ru ? 'Обновления WesiOS' : 'WesiOS updates'),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          ru
              ? 'Установлена ${AppUpdateService.currentVersion} (сборка ${AppUpdateService.currentBuild})'
              : 'Installed ${AppUpdateService.currentVersion} (build ${AppUpdateService.currentBuild})',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        // Changelog — показываем всегда, когда есть обновление и notes.
        // И в баннере на главной, и в настройках: обновление не должно
        // ставиться вслепую.
        if (hasUpdate && hasNotes) ...[
          const SizedBox(height: 12),
          _changelogBlock(ru, notes),
        ],
        const SizedBox(height: 14),
        _body(ru, p, release, hasUpdate),
      ],
    );
  }

  Widget _changelogBlock(bool ru, String notes) {
    // В компактном баннере длинный текст сворачиваем, чтобы не занять
    // полэкрана. В настройках показываем полностью.
    final isLong = notes.length > 160 || notes.split('\n').length > 3;
    final showFull = !widget.compact || _notesExpanded || !isLong;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.glassBorder.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ru ? 'Что нового' : "What's new",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentOrange,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: 6),
          Text(
            notes,
            maxLines: showFull ? null : 3,
            overflow: showFull ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          if (widget.compact && isLong) ...[
            SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _notesExpanded = !_notesExpanded),
              child: Text(
                _notesExpanded
                    ? (ru ? 'Свернуть' : 'Show less')
                    : (ru ? 'Подробнее' : 'Show more'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentOrange,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(bool ru, UpdateProgress p, AppRelease? release, bool hasUpdate) {
    switch (p.stage) {
      case UpdateStage.downloading:
        final f = p.fraction;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 6,
                backgroundColor: AppTheme.background,
                valueColor:
                    AlwaysStoppedAnimation(AppTheme.accentOrange),
              ),
            ),
            SizedBox(height: 8),
            Text(
              [
                if (f != null) '${(f * 100).toStringAsFixed(0)}%',
                '${_size(p.bytesDownloaded)}${p.totalBytes != null ? ' / ${_size(p.totalBytes)}' : ''}',
                _speed(p.bytesPerSecond),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        );

      case UpdateStage.installing:
        return Text(
          ru ? 'Запуск установки…' : 'Starting the installer…',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        );

      case UpdateStage.ready:
        return Text(
          ru
              ? 'Установщик запущен. Следуйте подсказкам системы.'
              : 'The installer has started. Follow the system prompts.',
          style: TextStyle(fontSize: 12, color: AppTheme.accentGreen),
        );

      case UpdateStage.failed:
        final permission = p.error?.contains('install_permission_required') == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              permission
                  ? (ru
                      ? 'Нужно разрешить установку из WesiOS — экран настроек уже открыт.'
                      : 'Allow installs from WesiOS — the settings screen is open.')
                  : (ru
                      ? 'Не удалось обновиться: ${p.error}'
                      : 'Update failed: ${p.error}'),
              style: TextStyle(
                fontSize: 12,
                color: permission ? AppTheme.accentOrange : AppTheme.accentRed,
              ),
            ),
            const SizedBox(height: 10),
            _button(
              ru ? 'Повторить' : 'Retry',
              _install,
            ),
          ],
        );

      default:
        if (hasUpdate) {
          return Row(
            children: [
              _button(
                ru
                    ? 'Обновить${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}'
                    : 'Update${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}',
                _install,
              ),
              if (!widget.compact) ...[
                SizedBox(width: 8),
                TextButton(
                  onPressed: () => _skip(release.version),
                  child: Text(
                    ru ? 'Пропустить' : 'Skip',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            _button(
              _checking
                  ? (ru ? 'Проверяем…' : 'Checking…')
                  : (ru ? 'Проверить обновления' : 'Check for updates'),
              _checking ? null : _check,
            ),
          ],
        );
    }
  }

  Widget _button(String label, VoidCallback? onTap) => HoverButton(
        onTap: onTap ?? () {},
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        backgroundColor: onTap == null
            ? AppTheme.surface
            : AppTheme.accentOrange.withOpacity(0.16),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onTap == null ? AppTheme.textMuted : AppTheme.accentOrange,
          ),
        ),
      );
}

/// Полоска на главной — появляется только когда обновление действительно есть.
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppRelease?>(
      valueListenable: AppUpdateService.latest,
      builder: (context, release, _) {
        if (!AppUpdateService.updateAvailable) {
          // Пока идёт закачка, баннер обязан остаться на экране, иначе
          // прогресс исчезнет вместе с ним на середине скачивания.
          if (!AppUpdateService.progress.value.isBusy) {
            return const SizedBox.shrink();
          }
        }
        return const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: AppUpdateCard(compact: true),
        );
      },
    );
  }
}
