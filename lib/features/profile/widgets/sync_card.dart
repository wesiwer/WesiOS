import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/sync/sync_auto.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/sync_screen.dart';

/// Синхронизация в профиле.
///
/// **Почему здесь, а не только в настройках.** Синхронизация — это ответ на
/// вопрос «а мои данные точно не пропадут». Такой вопрос задают, глядя на
/// свой профиль, а не листая настройки; и ответ на него должен быть виден
/// сразу, без нажатий.
///
/// Карточка показывает **состояние**, а не кнопку. Кнопка осталась, но
/// нажимать её больше не обязательно: обмен уходит сам через пару секунд
/// после правки ([SyncAuto]). Поэтому главная строка здесь — не «нажми», а
/// «всё уехало» либо «ждёт отправки».
class ProfileSyncCard extends StatelessWidget {
  const ProfileSyncCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    return ValueListenableBuilder<int>(
      valueListenable: SyncEndpoint.revision,
      builder: (context, _, __) => ValueListenableBuilder<bool>(
        valueListenable: SyncEngine.busy,
        builder: (context, busy, __) => ValueListenableBuilder<bool>(
          valueListenable: SyncAuto.pending,
          builder: (context, pending, __) => ValueListenableBuilder<SyncReport?>(
            valueListenable: SyncEngine.lastReport,
            builder: (context, report, __) =>
                _card(context, ru, busy, pending, report),
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    bool ru,
    bool busy,
    bool pending,
    SyncReport? report,
  ) {
    final connected = SyncEndpoint.isConnected;
    final on = SyncEndpoint.enabled;

    final (icon, color, headline, detail) = _state(
      ru: ru,
      connected: connected,
      on: on,
      busy: busy,
      pending: pending,
      report: report,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => SyncScreen.open(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent)
                      : Icon(icon, size: 21, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                            fontSize: 11, height: 1.35,
                            color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка осталась, но она теперь про «прямо сейчас», а не
                // про «иначе не уедет».
                if (connected && on && !busy)
                  IconButton(
                    tooltip: ru ? 'Отправить сейчас' : 'Sync now',
                    icon: Icon(Icons.sync,
                        size: 19, color: AppTheme.textMuted),
                    onPressed: SyncAuto.now,
                  ),
                Icon(Icons.chevron_right,
                    size: 18, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Что показать. Порядок проверок — от «совсем не работает» к мелочам:
  /// человеку сначала надо знать, работает ли это вообще.
  (IconData, Color, String, String) _state({
    required bool ru,
    required bool connected,
    required bool on,
    required bool busy,
    required bool pending,
    required SyncReport? report,
  }) {
    if (!connected) {
      return (
        Icons.cloud_off_outlined,
        AppTheme.textMuted,
        ru ? 'Вход на сервер не выполнен' : 'Not signed in',
        ru
            ? 'Данные лежат только на этом устройстве. Нажмите и войдите — адрес сервера уже известен.'
            : 'Data stays on this device only. Tap and sign in — the server address is already known.',
      );
    }
    if (!on) {
      return (
        Icons.pause_circle_outline,
        AppTheme.textMuted,
        ru ? 'Синхронизация выключена' : 'Sync is off',
        ru
            ? 'Вход есть, но обмен не идёт. Нажмите, чтобы включить.'
            : 'Signed in, but nothing is exchanged. Tap to turn it on.',
      );
    }
    if (busy) {
      return (
        Icons.sync,
        AppTheme.accent,
        ru ? 'Обмен идёт' : 'Syncing',
        ru ? 'Секунду' : 'One moment',
      );
    }
    if (pending) {
      return (
        Icons.cloud_upload_outlined,
        AppTheme.accent,
        ru ? 'Ждёт отправки' : 'Waiting to send',
        ru
            ? 'Уедет само через пару секунд. Если связи нет — при первой возможности.'
            : 'Will go on its own shortly, or as soon as there is a connection.',
      );
    }

    final failure = report?.firstFailure;
    if (failure != null) {
      return (
        Icons.error_outline,
        AppTheme.accentRed,
        ru ? 'Не удалось' : 'Failed',
        failure.describe(russian: ru),
      );
    }

    final at = SyncEndpoint.lastRun;
    return (
      Icons.cloud_done_outlined,
      AppTheme.accent,
      ru ? 'Всё уехало' : 'Everything is synced',
      at == null
          ? (ru ? 'Первый обмен ещё не проходил' : 'No exchange yet')
          : (ru ? 'Последний обмен: ${_when(at, ru)}' : 'Last sync: ${_when(at, ru)}'),
    );
  }

  /// «Только что» вместо точного времени в первые минуты: человеку важно
  /// «свежее или нет», а не секунда.
  static String _when(DateTime at, bool ru) {
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return ru ? 'только что' : 'just now';
    if (ago.inMinutes < 60) {
      return ru ? '${ago.inMinutes} мин. назад' : '${ago.inMinutes} min ago';
    }
    if (ago.inHours < 24) {
      return ru ? '${ago.inHours} ч. назад' : '${ago.inHours} h ago';
    }
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
