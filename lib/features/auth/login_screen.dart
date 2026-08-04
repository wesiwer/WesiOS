import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/firebase_rest_service.dart';
import '../team/services/team_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';

/// Вход в профиль.
///
/// Учётные записи заводит владелец в консоли Firebase и выдаёт людям почту и
/// пароль. Регистрации отсюда нет намеренно: иначе любой, у кого есть
/// сборка, завёл бы себе профиль в чужом проекте.
///
/// **Пароли нигде в проекте не хранятся.** Их проверяет Firebase Auth, и
/// наружу он отдаёт только токен. Сверять логин с записью в базе было бы
/// ошибкой: чтобы сверить, приложение должно эту запись прочитать — то есть
/// любой вошедший смог бы вычитать чужие пароли.
///
/// Вход не обязателен. Без него приложение работает целиком локально — как
/// и работало; аккаунт нужен только для синхронизации между устройствами.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
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
    // Уже вошли и просили запомнить — спрашивать заново незачем.
    if (FirebaseRestService.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goHome());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _goHome() {
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _signIn() async {
    final entered = _email.text.trim();
    final password = _password.text;
    if (entered.isEmpty || password.isEmpty) {
      setState(() => _error = _ru
          ? 'Введите логин или почту и пароль'
          : 'Enter login or email and password');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // Сперва — сотрудник, заведённый владельцем. Его логин короткий и почты
    // может не иметь вовсе, поэтому проверять его через Firebase бессмысленно.
    final employee = TeamService.verify(entered, password);
    if (employee != null) {
      await TeamService.signIn(employee);
      if (!mounted) return;
      _goHome();
      return;
    }

    // Не сотрудник — значит вход владельца по почте в Firebase.
    if (!entered.contains('@')) {
      setState(() {
        _busy = false;
        _error = _ru ? 'Неверный логин или пароль' : 'Wrong login or password';
      });
      return;
    }

    final failure = await FirebaseRestService.signIn(entered, password);
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure.describe(russian: _ru);
      });
      return;
    }

    // «Запомнить» решает только одно: переживёт ли сессия перезапуск. Сам
    // вход уже состоялся и до закрытия программы работает в любом случае.
    if (!_remember) await FirebaseRestService.forgetOnExit();
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
                      _ru ? 'Вход в профиль' : 'Sign in',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: _ru ? 'Логин или почта' : 'Login or email',
                      prefixIcon: Icon(Icons.alternate_email,
                          size: 18, color: AppTheme.textMuted),
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
                      prefixIcon: Icon(Icons.key,
                          size: 18, color: AppTheme.textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                            color: AppTheme.textMuted),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.accentRed),
                    ),
                  ],
                  const SizedBox(height: 6),
                  InkWell(
                    onTap:
                        _busy ? null : () => setState(() => _remember = !_remember),
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
                                  fontSize: 13, color: AppTheme.textSecondary),
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
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _ru ? 'Войти' : 'Sign in',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy ? null : _goHome,
                    child: Text(
                      _ru
                          ? 'Продолжить без аккаунта'
                          : 'Continue without an account',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ru
                        ? 'Без аккаунта всё работает и хранится только на этом '
                            'устройстве. Аккаунт нужен, чтобы цифры совпадали '
                            'на телефоне и на компьютере.'
                        : 'Without an account everything works and stays on '
                            'this device only. An account is what keeps the '
                            'numbers in step across devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, height: 1.4, color: AppTheme.textMuted),
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
