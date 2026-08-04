import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/sync/pocketbase_transport.dart';
import '../../core/sync/sync_codec.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';

/// Синхронизация с сервером.
///
/// Экран намеренно показывает адрес в том виде, в каком он реально уйдёт в
/// запрос: человек набирает `185.221.199.19:8090`, а уходит
/// `http://185.221.199.19:8090`. Молчаливая подстановка схемы — источник
/// «почему не подключается», который невозможно увидеть.
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
  late final TextEditingController _url =
      TextEditingController(text: SyncEndpoint.rawUrl);
  late final TextEditingController _login =
      TextEditingController(text: SyncEndpoint.login);
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void dispose() {
    _url.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _signIn() async {
    final address = SyncEndpoint.normalize(_url.text);
    if (address == null) {
      _say(
          _ru
              ? 'Адрес не похож на адрес сервера'
              : 'That does not look like a server address',
          error: true);
      return;
    }
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      _say(_ru ? 'Нужны логин и пароль' : 'Login and password required',
          error: true);
      return;
    }

    setState(() => _busy = true);
    await SyncEndpoint.configure(url: address, login: _login.text);

    final transport = PocketBaseTransport(address);
    final res = await transport.signIn(_login.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!res.ok) {
      _say(res.failure!.describe(russian: _ru), error: true);
      return;
    }
    // Пароль в памяти дальше не нужен: держим пропуск, а не пароль.
    _password.clear();
    _say(_ru ? 'Вход выполнен' : 'Signed in');
  }

  Future<void> _signOut() async {
    await SyncEndpoint.clearSession();
    if (!mounted) return;
    setState(() {});
    _say(_ru ? 'Вход сброшен' : 'Signed out');
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final report = await SyncEngine.run();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(report.describe(russian: _ru), error: !report.ok);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SyncEndpoint.revision,
      builder: (context, _, __) {
        final signedIn = SyncEndpoint.session != null;
        final address = SyncEndpoint.normalize(_url.text);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: WesiTitle(
                            _ru ? 'Синхронизация' : 'Sync', size: 22),
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
                      _field(
                        controller: _url,
                        label: _ru ? 'Адрес сервера' : 'Server address',
                        hint: '185.221.199.19:8090',
                        onChanged: (_) => setState(() {}),
                      ),
                      if (address != null && address != _url.text.trim())
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            _ru
                                ? 'Запрос уйдёт на $address'
                                : 'Requests will go to $address',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _login,
                        label: _ru ? 'Логин' : 'Login',
                        hint: 'wesi',
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _password,
                        label: _ru ? 'Пароль' : 'Password',
                        hint: '••••••••',
                        obscure: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _button(
                              label: signedIn
                                  ? (_ru ? 'Войти заново' : 'Sign in again')
                                  : (_ru ? 'Войти' : 'Sign in'),
                              onTap: _busy ? null : _signIn,
                            ),
                          ),
                          if (signedIn) ...[
                            const SizedBox(width: 10),
                            _button(
                              label: _ru ? 'Выйти' : 'Sign out',
                              onTap: _busy ? null : _signOut,
                              muted: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      _button(
                        label: _ru
                            ? 'Синхронизировать сейчас'
                            : 'Synchronise now',
                        onTap: (_busy || !signedIn) ? null : _syncNow,
                        filled: true,
                      ),
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
                      _honestNote(),
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
                      : (_ru ? 'Сервер не подключён' : 'Server not connected'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  last == null
                      ? (_ru
                          ? 'Обмена ещё не было'
                          : 'No exchange yet')
                      : (_ru
                          ? 'Последний обмен: ${_when(last)}'
                          : 'Last exchange: ${_when(last)}'),
                  style:
                      TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            ),
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
                  _ru ? 'Автоматически при запуске' : 'Automatically on launch',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: signedIn
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  signedIn
                      ? (_ru
                          ? 'Обмен раз при открытии программы, молча'
                          : 'One exchange when the app opens, silently')
                      : (_ru
                          ? 'Сначала войдите на сервер'
                          : 'Sign in to the server first'),
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: on && signedIn,
            activeColor: AppTheme.accent,
            onChanged: signedIn
                ? (v) async {
                    await SyncEndpoint.setEnabled(v);
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

    return Container(
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
            _ru ? 'Что уезжает на сервер' : 'What goes to the server',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in SyncCodec.collections)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.circle,
                      size: 5, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    names[c.name] ?? c.name,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _honestNote() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ru
                  ? 'Настройки, ключи и пароль Wesi Shield не уезжают никуда: '
                      'они привязаны к устройству. Встроенные статьи справки '
                      'тоже — они приходят с обновлением.\n\n'
                      'Сейчас синхронизируются устройства одной учётной '
                      'записи. Общий доступ сотрудников к одним и тем же '
                      'данным — следующий шаг, он требует прав на стороне '
                      'сервера.'
                  : 'Settings, keys and the Wesi Shield password never leave '
                      'the device. Built-in help articles do not either — '
                      'they arrive with updates.\n\n'
                      'Right now this syncs the devices of one account. '
                      'Shared access for employees is the next step; it needs '
                      'permissions on the server side.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.45, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(fontSize: 13, color: AppTheme.textMuted),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppTheme.surfaceLight.withOpacity(0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _button({
    required String label,
    VoidCallback? onTap,
    bool filled = false,
    bool muted = false,
  }) {
    final enabled = onTap != null;
    final accent = muted ? AppTheme.textMuted : AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? accent.withOpacity(enabled ? 0.18 : 0.06)
              : AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: enabled ? accent.withOpacity(0.5) : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: enabled ? accent : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
