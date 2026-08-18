import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/telegram_link_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/window_controls.dart';

class TelegramLinkScreen extends StatefulWidget {
  const TelegramLinkScreen({super.key});

  @override
  State<TelegramLinkScreen> createState() => _TelegramLinkScreenState();
}

class _TelegramLinkScreenState extends State<TelegramLinkScreen> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  TelegramLinkStatus _status = const TelegramLinkStatus(linked: false);
  TelegramLinkTicket? _ticket;
  Timer? _poller;
  int _polls = 0;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final result = await TelegramLinkService.status();
    if (!mounted) return;
    if (!result.ok || result.value == null) {
      setState(() {
        _loading = false;
        _error = result.message ?? (_ru ? 'Не удалось получить статус' : 'Unable to load status');
      });
      return;
    }
    final next = result.value!;
    setState(() {
      _loading = false;
      _status = next;
      _error = null;
      if (next.linked) _ticket = null;
    });
    if (next.linked) _poller?.cancel();
  }

  Future<void> _startLink() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final result = await TelegramLinkService.createLink();
    if (!mounted) return;
    if (!result.ok || result.value == null) {
      setState(() {
        _working = false;
        _error = result.message ?? (_ru ? 'Не удалось создать привязку' : 'Unable to create link');
      });
      if (result.errorCode == 'TELEGRAM_ALREADY_LINKED') await _refresh();
      return;
    }
    final ticket = result.value!;
    setState(() {
      _working = false;
      _ticket = ticket;
    });
    await launchUrl(ticket.deepLink, mode: LaunchMode.externalApplication);
    _beginPolling();
  }

  void _beginPolling() {
    _poller?.cancel();
    _polls = 0;
    _poller = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _polls++;
      await _refresh();
      if (_status.linked || _polls >= 30 || (_ticket?.expiresAt.isBefore(DateTime.now()) ?? false)) {
        timer.cancel();
      }
    });
  }

  Future<void> _revoke() async {
    if (_working) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          _ru ? 'Отвязать Telegram?' : 'Disconnect Telegram?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          _ru
              ? 'Бот сразу потеряет доступ к WesiOS. Повторная привязка потребует нового кода.'
              : 'The bot will immediately lose access to WesiOS. Reconnecting will require a new code.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _ru ? 'Отвязать' : 'Disconnect',
              style: TextStyle(color: AppTheme.accentRed),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _working = true);
    final result = await TelegramLinkService.revoke();
    if (!mounted) return;
    setState(() {
      _working = false;
      if (result.ok) {
        _status = const TelegramLinkStatus(linked: false);
        _ticket = null;
        _error = null;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _toggleRisk(bool value) async {
    final old = _status;
    setState(() {
      _status = TelegramLinkStatus(
        linked: old.linked,
        telegramUsername: old.telegramUsername,
        telegramFirstName: old.telegramFirstName,
        linkedAt: old.linkedAt,
        activeOrganizationId: old.activeOrganizationId,
        activeOrganizationName: old.activeOrganizationName,
        prefs: TelegramNotificationPrefs(
          risk: value,
          overdue: old.prefs.overdue,
          quietFromHour: old.prefs.quietFromHour,
          quietToHour: old.prefs.quietToHour,
          timezoneOffsetMinutes: old.prefs.timezoneOffsetMinutes,
        ),
      );
    });
    final result = await TelegramLinkService.updatePrefs(risk: value);
    if (!result.ok) {
      if (mounted) setState(() => _status = old);
    }
  }

  Future<void> _toggleOverdue(bool value) async {
    final old = _status;
    setState(() {
      _status = TelegramLinkStatus(
        linked: old.linked,
        telegramUsername: old.telegramUsername,
        telegramFirstName: old.telegramFirstName,
        linkedAt: old.linkedAt,
        activeOrganizationId: old.activeOrganizationId,
        activeOrganizationName: old.activeOrganizationName,
        prefs: TelegramNotificationPrefs(
          risk: old.prefs.risk,
          overdue: value,
          quietFromHour: old.prefs.quietFromHour,
          quietToHour: old.prefs.quietToHour,
          timezoneOffsetMinutes: old.prefs.timezoneOffsetMinutes,
        ),
      );
    });
    final result = await TelegramLinkService.updatePrefs(overdue: value);
    if (!result.ok) {
      if (mounted) setState(() => _status = old);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          'Telegram',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, kTitleBarInset + 6, 18, 32),
          children: [
            _hero(),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ))
            else if (_status.linked)
              ..._linkedCards()
            else
              ..._unlinkedCards(),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _message(_error!, error: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.telegram, color: AppTheme.accent, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wesi Telegram',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ru
                        ? 'Тонкий клиент WesiOS: касса, риски, задачи и важные алерты без отдельной «правды».'
                        : 'A thin WesiOS client for cash, risk, tasks and important alerts.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _unlinkedCards() => [
        _card(
          title: _ru ? 'Не подключён' : 'Not connected',
          subtitle: _ru
              ? 'Привязка одноразовая и короткоживущая. Telegram не получает пароль или серверную сессию WesiOS.'
              : 'The one-time link never exposes your WesiOS password or server session.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _working ? null : _startLink,
                icon: _working
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new),
                label: Text(_ru ? 'Подключить Telegram' : 'Connect Telegram'),
              ),
              if (_ticket != null) ...[
                const SizedBox(height: 14),
                Text(
                  _ru ? 'Если Telegram не открылся автоматически:' : 'If Telegram did not open:',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _ticket!.code));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_ru ? 'Код скопирован' : 'Code copied')),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.glassBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            '/start ${_ticket!.code}',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(Icons.copy, size: 17, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ];

  List<Widget> _linkedCards() {
    final name = _status.telegramUsername.isNotEmpty
        ? '@${_status.telegramUsername}'
        : (_status.telegramFirstName.isNotEmpty ? _status.telegramFirstName : 'Telegram');
    return [
      _card(
        title: _ru ? 'Подключён' : 'Connected',
        subtitle: '$name · ${_status.activeOrganizationName.isEmpty ? _status.activeOrganizationId : _status.activeOrganizationName}',
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accentGreen,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _ru
                  ? 'Права не копируются в Telegram: сервер проверяет их заново на каждую команду и кнопку.'
                  : 'Permissions are rechecked by WesiOS on every command and button.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _working ? null : _revoke,
              icon: const Icon(Icons.link_off),
              label: Text(_ru ? 'Отвязать Telegram' : 'Disconnect Telegram'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentRed),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _card(
        title: _ru ? 'Проактивные алерты' : 'Proactive alerts',
        subtitle: _ru ? 'Только важное. Quiet hours: 23:00–08:00.' : 'Important only. Quiet hours: 23:00–08:00.',
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _status.prefs.risk,
              onChanged: _toggleRisk,
              title: Text(
                _ru ? 'Кассовый риск' : 'Cash risk',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                _ru ? 'Когда серверный запас переходит в warning/critical' : 'When server runway enters warning/critical',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
            Divider(color: AppTheme.glassBorder, height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _status.prefs.overdue,
              onChanged: _toggleOverdue,
              title: Text(
                _ru ? 'Просроченные задачи' : 'Overdue tasks',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                _ru ? 'Сводка при изменении количества просрочек' : 'Digest when overdue count changes',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _card(
        title: _ru ? 'Команды MVP' : 'MVP commands',
        subtitle: '/brief · /cash · /risk · /today · /overdue · /org',
        child: Text(
          _ru
              ? 'В группах бот не показывает чувствительные цифры. Для кассы, рисков и задач используется личный чат.'
              : 'Sensitive values are never shown in groups. Use the private chat for cash, risk and tasks.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.45),
        ),
      ),
    ];
  }

  Widget _card({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? leading,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _message(String value, {bool error = false}) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: (error ? AppTheme.accentRed : AppTheme.accent).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (error ? AppTheme.accentRed : AppTheme.accent).withOpacity(0.35),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: error ? AppTheme.accentRed : AppTheme.textPrimary,
            fontSize: 12,
          ),
        ),
      );
}
