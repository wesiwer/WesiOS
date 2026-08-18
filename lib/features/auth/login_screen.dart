import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/security/session_service.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_feature_extensions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../team/services/portal_account_service.dart';
import '../team/services/team_service.dart';

/// Единственный вход в WesiOS: пароль + одноразовый код из почты.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _setupEmail = TextEditingController();
  final _code = TextEditingController();
  final _passwordFocus = FocusNode();
  final _setupEmailFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _remember = true;
  bool _busy = false;
  bool _obscure = true;
  bool _needsEmailSetup = false;
  String? _error;
  String? _challengeId;
  String? _maskedEmail;

  bool get _ru => WesiLocale.isRussian;
  bool get _passwordStep => _challengeId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreIfValid());
  }

  Future<void> _restoreIfValid() async {
    if (!mounted) return;
    if (TeamService.current != null && SyncEndpoint.isConnected) {
      SessionService.startHeartbeat();
      _goHome();
      return;
    }
    if (TeamService.current != null || SyncEndpoint.session != null) {
      await TeamService.signOut();
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _setupEmail.dispose();
    _code.dispose();
    _passwordFocus.dispose();
    _setupEmailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _goHome() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final entered = _login.text.trim();
    final password = _password.text;
    if (entered.isEmpty || password.isEmpty) {
      setState(() => _error =
          _ru ? 'Введите логин и пароль' : 'Enter your login and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await PortalAccountService.beginSignIn(
      login: entered,
      password: password,
      purpose: 'app',
    );
    if (!mounted) return;
    if (!result.ok || result.challengeId == null) {
      setState(() {
        _busy = false;
        _error = result.error ??
            (_ru ? 'Не удалось отправить код' : 'Unable to send the code');
      });
      return;
    }

    setState(() {
      _busy = false;
      _challengeId = result.challengeId;
      _needsEmailSetup = result.emailSetupRequired;
      _maskedEmail = result.maskedEmail;
      _code.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_needsEmailSetup) {
        _setupEmailFocus.requestFocus();
      } else {
        _codeFocus.requestFocus();
      }
    });
  }

  Future<void> _submitOwnerEmail() async {
    if (_busy) return;
    final challenge = _challengeId;
    if (challenge == null) return;
    final email = _setupEmail.text.trim();
    if (!PortalAccountService.validSecurityEmail(email)) {
      setState(() => _error = _ru
          ? 'Укажите действующую электронную почту'
          : 'Enter a valid email address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await PortalAccountService.setupOwnerEmail(
      challengeId: challenge,
      email: email,
    );
    if (!mounted) return;
    if (!result.ok || result.challengeId == null) {
      setState(() {
        _busy = false;
        _error = result.error ??
            (_ru
                ? 'Не удалось отправить код на эту почту'
                : 'Unable to send the code');
      });
      return;
    }
    setState(() {
      _busy = false;
      _needsEmailSetup = false;
      _challengeId = result.challengeId;
      _maskedEmail = result.maskedEmail;
      _code.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    final challengeId = _challengeId;
    if (challengeId == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = _ru
          ? 'Введите 6 цифр из письма'
          : 'Enter the 6 digits from the email');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await PortalAccountService.verifySignIn(
      challengeId: challengeId,
      code: _code.text,
      remember: _remember,
    );
    if (!mounted) return;
    if (!result.ok || result.identity == null) {
      final challengeEnded = _challengeEnded(result);
      setState(() {
        _busy = false;
        if (challengeEnded) {
          _challengeId = null;
          _maskedEmail = null;
          _needsEmailSetup = false;
          _code.clear();
          _error = _ru
              ? 'Эта попытка входа уже завершена. Запросите новый код.'
              : 'This sign-in attempt has ended. Request a new code.';
        } else {
          _error = result.error ??
              (_ru
                  ? 'Не удалось подтвердить вход'
                  : 'Unable to verify sign-in');
        }
      });
      return;
    }
    await _finishLogin(result.identity!);
  }

  bool _challengeEnded(PortalLoginResult result) {
    if (result.statusCode != 401) return false;
    final message = (result.error ?? '').toLowerCase();
    return message.contains('уже использован') ||
        message.contains('срок действия кода истёк') ||
        message.contains('слишком много неверных попыток') ||
        message.contains('проверка входа истекла') ||
        message.contains('эта попытка входа завершена') ||
        message.contains('challenge expired');
  }

  Future<void> _finishLogin(PortalAppIdentity identity) async {
    final employee = await TeamService.applyServerIdentity(
      identity,
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

    _password.clear();
    _code.clear();
    SessionService.startHeartbeat();

    // TeamService.applyServerIdentity() меняет TeamService.revision. Listener
    // SyncFeatureExtensions на это изменение уже может запустить account
    // rebind: stop(force) -> SyncEngine.reset() -> bind private boxes -> first
    // sync. Раньше LoginScreen сразу параллельно запускал ещё один
    // SyncEngine.runOnLaunch(), и два контура могли одновременно сбрасывать и
    // открывать journal/private boxes. Это особенно проявлялось после смены
    // сотрудника на уже запущенном устройстве: часть remote apply терялась или
    // первый poll видел промежуточное состояние.
    //
    // rebindCurrentAccountAndSync() сам сериализован: если listener уже начал
    // работу, мы await-им тот же Future; если нет — запускаем его здесь. После
    // его завершения full pull выполнен и SyncAuto уже включён ровно один раз.
    await SyncFeatureExtensions.rebindCurrentAccountAndSync();

    if (!mounted) return;
    setState(() => _busy = false);
    _goHome();
  }

  void _backToPassword() {
    if (_busy) return;
    setState(() {
      _challengeId = null;
      _maskedEmail = null;
      _needsEmailSetup = false;
      _code.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _passwordStep
        ? (_ru ? 'Вход в WesiOS' : 'Sign in to WesiOS')
        : _needsEmailSetup
            ? (_ru ? 'Защитите профиль почтой' : 'Add a security email')
            : (_ru ? 'Подтверждение входа' : 'Verify sign-in');
    final description = _passwordStep
        ? (_ru
            ? 'Сначала подтвердите логин и пароль. После этого WesiOS пришлёт одноразовый код на почту профиля.'
            : 'First confirm your login and password. WesiOS will then send a one-time code to your profile email.')
        : _needsEmailSetup
            ? (_ru
                ? 'Это разовая миграция старого профиля владельца. Укажите почту: WesiOS отправит код и закрепит адрес только после правильного подтверждения.'
                : 'One-time owner migration: the email is saved only after a code sent to it is verified.')
            : (_ru
                ? 'Мы отправили шестизначный код на ${_maskedEmail ?? 'вашу почту'}. Код действует 10 минут.'
                : 'A six-digit code was sent to ${_maskedEmail ?? 'your email'}. It is valid for 10 minutes.');

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
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, height: 1.4, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 28),
                  if (_passwordStep)
                    ..._passwordWidgets()
                  else if (_needsEmailSetup)
                    ..._emailSetupWidgets()
                  else
                    ..._codeWidgets(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordWidgets() => [
        TextField(
          controller: _login,
          enabled: !_busy,
          autofocus: true,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: _ru ? 'Логин' : 'Login',
            prefixIcon:
                Icon(Icons.person_outline, size: 18, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => _sendCode(),
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: _ru ? 'Пароль' : 'Password',
            prefixIcon: Icon(Icons.key, size: 18, color: AppTheme.textMuted),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18, color: AppTheme.textMuted),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        _errorWidget(),
        const SizedBox(height: 6),
        InkWell(
          onTap: _busy ? null : () => setState(() => _remember = !_remember),
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
                  child: Text(_ru ? 'Запомнить меня' : 'Remember me',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _button(
          onTap: _sendCode,
          label: _ru ? 'Получить код' : 'Send code',
          busyLabel: _ru ? 'Проверяю…' : 'Checking…',
        ),
      ];

  List<Widget> _emailSetupWidgets() => [
        TextField(
          controller: _setupEmail,
          focusNode: _setupEmailFocus,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitOwnerEmail(),
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: _ru ? 'Электронная почта' : 'Email address',
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.alternate_email,
                size: 18, color: AppTheme.textMuted),
          ),
        ),
        _errorWidget(),
        const SizedBox(height: 18),
        _button(
          onTap: _submitOwnerEmail,
          label: _ru ? 'Отправить код на эту почту' : 'Send code to this email',
          busyLabel: _ru ? 'Отправляю…' : 'Sending…',
        ),
        const SizedBox(height: 8),
        TextButton(
            onPressed: _busy ? null : _backToPassword,
            child: Text(_ru ? 'Назад' : 'Back')),
      ];

  List<Widget> _codeWidgets() => [
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => _verifyCode(),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 8),
          decoration: InputDecoration(
            labelText: _ru ? 'Код из письма' : 'Email code',
            counterText: '',
          ),
        ),
        _errorWidget(),
        const SizedBox(height: 18),
        _button(
          onTap: _verifyCode,
          label: _ru ? 'Войти' : 'Sign in',
          busyLabel: _ru ? 'Вхожу…' : 'Signing in…',
        ),
        const SizedBox(height: 8),
        TextButton(
            onPressed: _busy ? null : _backToPassword,
            child: Text(_ru ? 'Назад' : 'Back')),
      ];

  Widget _errorWidget() {
    final error = _error;
    if (error == null || error.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(error,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFFFF6B6B), fontSize: 12, height: 1.35)),
    );
  }

  Widget _button({
    required VoidCallback onTap,
    required String label,
    required String busyLabel,
  }) {
    return HoverButton(
      onTap: _busy ? null : onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_busy ? busyLabel : label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}
