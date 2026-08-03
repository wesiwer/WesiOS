import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/wesi_locale.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';
import 'hover_button.dart';
import 'window_controls.dart';

/// Стилизованное окно ошибки обновления WesiOS.
///
/// Показывается поверх UI через [UpdateErrorHost] (overlay в MaterialApp),
/// когда [AppUpdateService.pendingError] не null — и при ошибках скачивания
/// в текущей сессии, и после падения Windows-bat (маркер + рестарт).
class UpdateErrorDialog extends StatelessWidget {
  final UpdateError error;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  const UpdateErrorDialog({
    super.key,
    required this.error,
    required this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final title = error.title(ru);
    final message = error.message(ru);
    final help = error.help(ru);

    return Material(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            margin: EdgeInsets.fromLTRB(24, kTitleBarHeight + 24, 24, 24),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.error_outline,
                          color: AppTheme.accentRed, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.background.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppTheme.glassBorder.withOpacity(0.7)),
                            ),
                            child: Text(
                              ru
                                  ? 'Код ошибки ${error.code}'
                                  : 'Error code ${error.code}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: AppTheme.accentRed,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onDismiss,
                      icon: Icon(Icons.close,
                          size: 18, color: AppTheme.textMuted),
                      splashRadius: 18,
                      tooltip: ru ? 'Закрыть' : 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (error.detail != null && error.detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.glassBorder.withOpacity(0.6)),
                    ),
                    child: SelectableText(
                      error.detail!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppTheme.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                if (help != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          help,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (error.logPath != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    ru
                        ? 'Лог: ${error.logPath}'
                        : 'Log: ${error.logPath}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (error.logPath != null)
                      TextButton(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: error.logPath!));
                        },
                        child: Text(
                          ru ? 'Копировать путь лога' : 'Copy log path',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ),
                    const Spacer(),
                    if (onRetry != null) ...[
                      HoverButton(
                        onTap: onRetry!,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        backgroundColor: AppTheme.accent.withOpacity(0.16),
                        child: Text(
                          ru ? 'Повторить' : 'Retry',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    HoverButton(
                      onTap: onDismiss,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      backgroundColor: AppTheme.surfaceLight,
                      child: Text(
                        ru ? 'Понятно' : 'OK',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay-хост: слушает [AppUpdateService.pendingError] и рисует диалог.
class UpdateErrorHost extends StatelessWidget {
  const UpdateErrorHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateError?>(
      valueListenable: AppUpdateService.pendingError,
      builder: (context, err, _) {
        if (err == null) return const SizedBox.shrink();
        return UpdateErrorDialog(
          error: err,
          onDismiss: () => AppUpdateService.clearPendingError(),
          onRetry: AppUpdateService.updateAvailable
              ? () {
                  AppUpdateService.clearPendingError();
                  AppUpdateService.downloadAndInstall();
                }
              : null,
        );
      },
    );
  }
}
