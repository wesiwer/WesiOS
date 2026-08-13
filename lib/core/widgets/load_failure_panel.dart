import 'package:flutter/material.dart';

import '../localization/wesi_locale.dart';
import '../theme/app_theme.dart';

/// Что показать вместо экрана, который не смог загрузиться.
///
/// Появилось из-за поломки, которая повторялась в дюжине экранов: загрузка
/// шла цепочкой `await` без страховки, и одно исключение в середине
/// оставляло `_loading` включённым навсегда. Снаружи это выглядело как
/// вечный спиннер — самое бесполезное из возможных состояний: работать
/// нельзя, причина неизвестна, и даже непонятно, ждать ещё или нет.
///
/// Здесь три обязательные вещи. Сказать, что именно не открылось. Показать
/// саму ошибку — её можно переслать, и по ней сразу видно, дело в правах,
/// в связи или в данных. Дать кнопку повтора: часть сбоев разовые, и
/// перезапускать всё приложение ради них не нужно.
class LoadFailurePanel extends StatelessWidget {
  /// Что именно не загрузилось — «Аналитика», «Мои финансы», «Задачи».
  final String what;

  /// Текст ошибки как есть. Не переводится и не приглаживается: пересланная
  /// строка должна совпадать с тем, что произошло на самом деле.
  final String error;

  final VoidCallback? onRetry;

  const LoadFailurePanel({
    super.key,
    required this.what,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 20, color: AppTheme.accentRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ru ? '$what не загрузились' : '$what failed to load',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ru
                    ? 'Данные на устройстве не тронуты. По тексту ниже видно, '
                        'что именно помешало.'
                    : 'Your data is untouched. The text below shows what '
                        'went wrong.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.background.withOpacity(.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: SelectableText(
                  error,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(ru ? 'Повторить' : 'Retry'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
