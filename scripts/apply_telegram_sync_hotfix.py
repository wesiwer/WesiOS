from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def p(rel):
    return ROOT / rel


def read(rel):
    return p(rel).read_text(encoding='utf-8')


def write(rel, value):
    p(rel).write_text(value, encoding='utf-8')


def replace_once(rel, old, new):
    text = read(rel)
    if text.count(old) != 1:
        raise SystemExit(f'{rel}: expected one marker, got {text.count(old)}: {old[:100]!r}')
    write(rel, text.replace(old, new, 1))


# 1) Telegram icon: use the explicit upper-right paper-plane mark everywhere.
replace_once(
    'lib/features/profile/profile_with_telegram.dart',
    "import '../../core/theme/app_theme.dart';\n",
    "import '../../core/theme/app_theme.dart';\nimport '../../core/widgets/wesi_telegram_icon.dart';\n",
)
replace_once(
    'lib/features/profile/profile_with_telegram.dart',
    "icon: const Icon(Icons.telegram, size: 19),",
    "icon: const WesiTelegramIcon(size: 19),",
)

replace_once(
    'lib/features/profile/telegram_link_screen.dart',
    "import '../../core/widgets/window_controls.dart';\n",
    "import '../../core/widgets/window_controls.dart';\nimport '../../core/widgets/wesi_telegram_icon.dart';\n",
)
replace_once(
    'lib/features/profile/telegram_link_screen.dart',
    "child: Icon(Icons.telegram, color: AppTheme.accent, size: 30),",
    "child: WesiTelegramIcon(color: AppTheme.accent, size: 30),",
)

# 2) Telegram deep-link: never trust a stale configured username. Ask Telegram
# which username belongs to the configured token immediately before issuing a
# one-time link. This also survives future BotFather username changes.
gateway = 'server/pb_hooks/wesi_telegram_gateway.js'
replace_once(
    gateway,
    '''function sendTyping(cfg, chatId) {\n  telegramApi(cfg, "sendChatAction", {chat_id: chatId, action: "typing"});\n}\n''',
    '''function resolveBotUsername(cfg) {\n  const me = telegramApi(cfg, "getMe", {});\n  const username = me && me.ok === true && me.result\n    ? String(me.result.username || "").replace(/^@/, "")\n    : "";\n  if (!/^[A-Za-z0-9_]{5,32}$/.test(username)) {\n    return {ok: false, code: me && me.code || "TELEGRAM_BOT_IDENTITY_UNAVAILABLE"};\n  }\n  return {ok: true, username: username};\n}\n\nfunction sendTyping(cfg, chatId) {\n  telegramApi(cfg, "sendChatAction", {chat_id: chatId, action: "typing"});\n}\n''',
)
replace_once(
    gateway,
    '''  const ticket = store.createLinkCode(\n    e.app,\n    identity,\n    selected.id,\n    body.timezoneOffsetMinutes,\n  );\n  return e.json(200, {\n    ok: true,\n    linked: false,\n    code: ticket.code,\n    expiresAt: ticket.payload.expiresAt,\n    botUsername: cfg.botUsername,\n    deepLink: `https://t.me/${cfg.botUsername}?start=${encodeURIComponent(ticket.code)}`,\n    activeOrganizationId: selected.id,\n  });\n''',
    '''  const bot = resolveBotUsername(cfg);\n  if (!bot.ok) {\n    return e.json(502, {\n      ok: false,\n      code: "TELEGRAM_BOT_IDENTITY_UNAVAILABLE",\n      message: "Не удалось проверить имя Telegram-бота. Повторите попытку позже.",\n    });\n  }\n  const ticket = store.createLinkCode(\n    e.app,\n    identity,\n    selected.id,\n    body.timezoneOffsetMinutes,\n  );\n  return e.json(200, {\n    ok: true,\n    linked: false,\n    code: ticket.code,\n    expiresAt: ticket.payload.expiresAt,\n    botUsername: bot.username,\n    deepLink: `https://t.me/${bot.username}?start=${encodeURIComponent(ticket.code)}`,\n    activeOrganizationId: selected.id,\n  });\n''',
)

# 3) Replace the obsolete second login form in Sync with the current MFA session.
# The old screen called PocketBaseTransport.signIn(), which intentionally always
# returns MFA_REQUIRED now, and considered any non-null (even expired) session
# signed in. The new screen has one source of truth: SyncEndpoint.isConnected.
SYNC_SCREEN = r'''import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/sync/sync_auto.dart';
import '../../core/sync/sync_codec.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';

/// Synchronization status and controls for the already authenticated WesiOS
/// session. Authentication itself lives only on the main MFA login screen.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SyncScreen()),
      );

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _expiryTimer;

  bool get _ru => WesiLocale.isRussian;
  bool get _signedIn => TeamService.current != null && SyncEndpoint.isConnected;

  @override
  void initState() {
    super.initState();
    unawaited(SyncEndpoint.ensureDefaults());
    _scheduleExpiryRefresh();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final raw = SyncEndpoint.session?['expiresAt'];
    final expiresAt = DateTime.tryParse('$raw');
    if (expiresAt == null) return;
    final delay = expiresAt.difference(DateTime.now());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay + const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _goToLogin({bool clearCurrent = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (clearCurrent) {
      await TeamService.signOut();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    if (!_signedIn) {
      _say(
        _ru
            ? 'Сеанс WesiOS завершён. Войдите заново, затем синхронизация продолжится автоматически.'
            : 'Your WesiOS session has ended. Sign in again to resume sync.',
        error: true,
      );
      await _goToLogin();
      return;
    }

    setState(() => _busy = true);
    final report = await SyncAuto.now();
    if (!mounted) return;

    if (report.firstFailure?.code == 'NOT_SIGNED_IN') {
      setState(() => _busy = false);
      _say(
        _ru
            ? 'Сеанс WesiOS завершён. Требуется повторный вход.'
            : 'Your WesiOS session has ended. Sign in again.',
        error: true,
      );
      await _goToLogin();
      return;
    }

    setState(() => _busy = false);
    _say(report.describe(russian: _ru), error: !report.ok);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SyncEndpoint.revision,
      builder: (context, _, __) {
        final signedIn = _signedIn;
        _scheduleExpiryRefresh();
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    kTitleBarInset + 12,
                    kHasCustomTitleBar ? 148 : 16,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: WesiTitle(
                          _ru ? 'Синхронизация' : 'Sync',
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _statusCard(signedIn),
                      const SizedBox(height: 14),
                      _serverCard(),
                      const SizedBox(height: 14),
                      _sessionCard(signedIn),
                      const SizedBox(height: 14),
                      _button(
                        label: _ru
                            ? 'Синхронизировать сейчас'
                            : 'Synchronise now',
                        onTap: (_busy || !signedIn) ? null : _syncNow,
                        filled: true,
                      ),
                      if (!signedIn) ...[
                        const SizedBox(height: 10),
                        _button(
                          label: _ru ? 'Войти в WesiOS' : 'Sign in to WesiOS',
                          onTap: _busy ? null : () => _goToLogin(),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: _messageIsError
                                ? AppTheme.accentRed
                                : AppTheme.accentGreen,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _autoToggle(signedIn),
                      const SizedBox(height: 18),
                      _whatSyncs(),
                      const SizedBox(height: 14),
                      _securityNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _serverCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.32),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 20, color: AppTheme.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru ? 'Сервер WesiOS' : 'WesiOS server',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'api.wesi-inc.ru · TLS',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 17, color: AppTheme.accentGreen),
          ],
        ),
      );

  Widget _statusCard(bool signedIn) {
    final last = SyncEndpoint.lastRun;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: signedIn
              ? AppTheme.accentGreen.withOpacity(0.35)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            signedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 22,
            color: signedIn ? AppTheme.accentGreen : AppTheme.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn
                      ? (_ru ? 'Сервер подключён' : 'Server connected')
                      : (_ru ? 'Требуется вход' : 'Sign-in required'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  last == null
                      ? (_ru ? 'Обмена ещё не было' : 'No exchange yet')
                      : (_ru
                          ? 'Последний обмен: ${_when(last)}'
                          : 'Last exchange: ${_when(last)}'),
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionCard(bool signedIn) {
    final employee = TeamService.current;
    final login = SyncEndpoint.login.trim();
    return _infoCard(
      title: _ru ? 'Сеанс WesiOS' : 'WesiOS session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            signedIn
                ? (login.isEmpty
                    ? (employee?.displayName ?? 'WesiOS')
                    : login)
                : (_ru
                    ? 'Подтверждённый серверный сеанс отсутствует или истёк.'
                    : 'The verified server session is missing or expired.'),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: signedIn ? AppTheme.textSecondary : AppTheme.textMuted,
            ),
          ),
          if (signedIn) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _button(
                    label: _ru ? 'Войти заново' : 'Sign in again',
                    onTap: _busy ? null : () => _goToLogin(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    label: _ru ? 'Выйти' : 'Sign out',
                    onTap: _busy ? null : () => _goToLogin(),
                    muted: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoToggle(bool signedIn) {
    final on = SyncEndpoint.enabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ru ? 'Автоматическая синхронизация' : 'Automatic sync',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: signedIn ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  signedIn
                      ? (_ru
                          ? 'Данные отправляются после изменений и при запуске'
                          : 'Data is sent after changes and on launch')
                      : (_ru
                          ? 'Включится после подтверждённого входа'
                          : 'Turns on after verified sign-in'),
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: on && signedIn,
            activeColor: AppTheme.accent,
            onChanged: signedIn
                ? (value) async {
                    await SyncEndpoint.setEnabled(value);
                    if (value) {
                      SyncAuto.start();
                    } else {
                      SyncAuto.stop(force: true);
                    }
                    if (mounted) setState(() {});
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _whatSyncs() {
    final names = _ru
        ? const {
            'accounts': 'Счета',
            'transactions': 'Операции',
            'tasks': 'Задачи',
            'articles': 'Ваши статьи',
            'employees': 'Состав',
          }
        : const {
            'accounts': 'Accounts',
            'transactions': 'Operations',
            'tasks': 'Tasks',
            'articles': 'Your articles',
            'employees': 'People',
          };
    return _infoCard(
      title: _ru ? 'Что синхронизируется' : 'What is synchronised',
      child: Column(
        children: [
          for (final collection in SyncCodec.collections)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 5, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    names[collection.name] ?? collection.name,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _securityNote() => _infoCard(
        title: _ru ? 'Безопасность' : 'Security',
        child: Text(
          _ru
              ? 'У синхронизации больше нет отдельного входа. Она использует тот же подтверждённый MFA-сеанс, что и WesiOS. Пароль на экране синхронизации не запрашивается и не хранится.'
              : 'Sync no longer has a separate sign-in. It uses the same verified MFA session as WesiOS. The sync screen never asks for or stores your password.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: AppTheme.textMuted,
          ),
        ),
      );

  Widget _infoCard({required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    bool muted = false,
    bool filled = false,
  }) =>
      Material(
        color: filled
            ? AppTheme.accent
            : muted
                ? AppTheme.surface.withOpacity(0.45)
                : AppTheme.surfaceLight.withOpacity(0.55),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? AppTheme.textMuted
                      : filled
                          ? Colors.white
                          : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
}
'''
write('lib/features/settings/sync_screen.dart', SYNC_SCREEN)

# Remove the accidental empty placeholder inherited from main if present.
placeholder = p('scripts/.keep')
if placeholder.exists() and placeholder.read_text(encoding='utf-8') == '':
    placeholder.unlink()

print('TELEGRAM_SYNC_HOTFIX_APPLIED')
