import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/sync/pocketbase_transport.dart';
import '../../core/sync/sync_codec.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';

/// Вход в корпоративную синхронизацию WesiOS.
///
/// Адрес сервера больше не является пользовательской настройкой. Приложение
/// всегда подключается к защищённому Wesi endpoint, поэтому человек вводит
/// только свои учётные данные и не может случайно отправить пароль на чужой
/// адрес из-за опечатки.
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
  late final TextEditingController _login =
      TextEditingController(text: SyncEndpoint.login);
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    SyncEndpoint.ensureDefaultServer();
  }

  @override
  void dispose() {
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
    final login = _login.text.trim();
    final password = _password.text;
    if (login.isEmpty || password.isEmpty) {
      _say(_ru ? 'Нужны логин и пароль' : 'Login and password required',
          error: true);
      return;
    }

    setState(() => _busy = true);
    await SyncEndpoint.configure(login: login);

    final transport = PocketBaseTransport(
      SyncEndpoint.url ?? SyncEndpoint.defaultUrl,
    );
    final res = await transport.signIn(login, password);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!res.ok) {
      _say(res.failure!.describe(russian: _ru), error: true);
      return;
    }

    _password.clear();
    _say(_ru ? 'Сервер подключён' : 'Server connected');
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
                        icon: Icon(Icons.arrow_back,
                            color: AppTheme.textPrimary),
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
                      _field(
                        controller: _login,
                        label: _ru ? 'Логин или почта' : 'Login or email',
                        hint: 'WesiOff',
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
                      _privacyNote(),
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
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.cloud_outlined,
                  size: 21, color: AppTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wesi Cloud',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _ru
                        ? 'Основной сервер выбирается автоматически'
                        : 'The main server is selected automatically',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_outline,
                size: 17, color: AppTheme.accentGreen),
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
                          ? 'Один тихий обмен при открытии программы'
                          : 'One silent exchange when the app opens')
                      : (_ru
                          ? 'Сначала войдите в Wesi Cloud'
                          : 'Sign in to Wesi Cloud first'),
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
                ? (value) async {
                    await SyncEndpoint.setEnabled(value);
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
            _ru ? 'Что хранится на сервере' : 'What is stored on the server',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final collection in SyncCodec.collections)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 5, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    names[collection.name] ?? collection.name,
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

  Widget _privacyNote() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.security_outlined,
                size: 16, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _ru
                    ? 'Пароль после входа не сохраняется. На устройстве остаётся '
                        'только ограниченный серверный токен. Пароль Wesi Shield '
                        'и приватные ключи на сервер не отправляются.'
                    : 'The password is not stored after sign-in. Only a limited '
                        'server token remains on the device. Wesi Shield and '
                        'private keys are never uploaded.',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      );

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: !obscure,
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  TextStyle(fontSize: 13, color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface.withOpacity(0.35),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
          ),
        ],
      );

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    bool muted = false,
    bool filled = false,
  }) =>
      Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: filled
              ? AppTheme.accent
              : muted
                  ? AppTheme.surface.withOpacity(0.45)
                  : AppTheme.surfaceLight.withOpacity(0.55),
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: filled
                      ? AppTheme.accent
                      : AppTheme.glassBorder,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
}
