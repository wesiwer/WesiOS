import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/sync/sync_auto.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../team/services/portal_account_service.dart';
import '../team/services/team_service.dart';

/// Единственный вход в WesiOS.
///
/// Те же логин и пароль работают на employee portal и в приложении. Доступ
/// считается подтверждённым только после двух серверных проверок:
/// 1. PocketBase проверил пароль;
/// 2. защищённый bootstrap вернул роль и разрешения этого аккаунта.
///
/// Режима «продолжить без аккаунта» больше нет. Для корпоративного приложения
/// отсутствие сессии не может означать полный локальный доступ.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _remember = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreIfValid());
  }

  Future<void> _restoreIfValid() async {
    if (!mounted) return;
    if (TeamService.current != null && SyncEndpoint.isConnected) {
      _goHome();
      return;
    }

    // Частичная старая сессия не должна оставлять приложение в неопределённом
    // состоянии: либо подтверждены и пользователь, и серверный токен, либо
    // считаем, что входа нет.
    if (TeamService.current != null || SyncEndpoint.session != null) {
      await TeamService.signOut();
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _goHome() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Future<void> _signIn() async {
    final entered = _login.text.trim();
    final password = _password.text;
    if (entered.isEmpty || password.isEmpty) {
      setState(() => _error = _ru
          ? 'Введите логин и пароль'
          : 'Enter your login and password');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await PortalAccountService.signIn(
      login: entered,
      password: password,
    );
    if (!mounted) return;

    if (!result.ok || result.identity == null) {
      await TeamService.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = result.error ??
            (_ru ? 'Не удалось выполнить вход' : 'Unable to sign in');
      });
      return;
    }

    final employee = await TeamService.applyServerIdentity(
      result.identity!,
      remember: _remember,
    );
    if (!mounted) return;
    if (employee == null) {
      await TeamService.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _ru
            ? 'Не удалось сохранить подтверждённый профиль на устройстве.'
            : 'Unable to save the verified profile on this device.';
      });
      return;
    }

    if (employee.isOwner) {
      // Полный обмен пока остаётся владельцу: текущая коллекция сервера
      // изолирована по owner id. Сотруднику не подменяем безопасность
      // отдельным личным набором данных под его token.
      await SyncEngine.runOnLaunch();
      SyncAuto.start();
    } else {
      SyncAuto.stop();
    }

    if (!mounted) return;
    _goHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: WesiWordmark(size: 34)),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _ru ? 'Вход в WesiOS' : 'Sign in to WesiOS',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _ru
                        ? 'Используйте логин и пароль, выданные владельцем. '
                            'Доступ будет открыт строго по вашим разрешениям.'
                        : 'Use the login and password issued by the owner. '
                            'Only your assigned permissions will be opened.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _login,
                    enabled: !_busy,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: _ru ? 'Логин' : 'Login',
                      prefixIcon: Icon(
                        Icons.person_outline,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: !_busy,
                    obscureText: _obscure,
                    onSubmitted: (_) => _signIn(),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: _ru ? 'Пароль' : 'Password',
                      prefixIcon: Icon(
                        Icons.key,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentRed,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _busy
                        ? null
                        : () => setState(() => _remember = !_remember),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _remember,
                            activeColor: AppTheme.accent,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _remember = v ?? true),
                          ),
                          Expanded(
                            child: Text(
                              _ru ? 'Запомнить меня' : 'Remember me',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  HoverButton(
                    onTap: _busy ? () {} : _signIn,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor:
                        _busy ? AppTheme.surface : AppTheme.accent,
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _ru ? 'Войти' : 'Sign in',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
