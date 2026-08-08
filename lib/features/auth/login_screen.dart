import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/security/session_service.dart';
import '../../core/sync/sync_auto.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_engine.dart';
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
  final _code = TextEditingController();
  final _passwordFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _remember = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _challengeId;
  String? _maskedEmail;

  bool get _ru => WesiLocale.isRussian;
  bool get _waitingCode => _challengeId != null;

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
    _code.dispose();
    _passwordFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _goHome() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Future<void> _sendCode() async {
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
      _maskedEmail = result.maskedEmail;
      _code.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  Future<void> _verifyCode() async {
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
      setState(() {
        _busy = false;
        _error = result.error ??
            (_ru ? 'Не удалось подтвердить вход' : 'Unable to verify sign-in');
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

    _password.clear();
    _code.clear();
    SessionService.startHeartbeat();

    if (employee.isOwner) {
      await SyncEngine.runOnLaunch();
      SyncAuto.start();
    } else {
      SyncAuto.stop();
    }

    if (!mounted) return;
    _goHome();
  }

  void _backToPassword() {
    if (_busy) return;
    setState(() {
      _challengeId = null;
      _maskedEmail = null;
      _code.clear();
      _error = null;
    });
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
                      _waitingCode
                          ? (_ru ? 'Подтверждение входа' : 'Verify sign-in')
                          : (_ru ? 'Вход в WesiOS' : 'Sign in to WesiOS'),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _waitingCode
                        ? (_ru
                            ? 'Мы отправили шестизначный код на ${_maskedEmail ?? 'вашу почту'}. Код действует 10 минут.'
                            : 'A six-digit code was sent to ${_maskedEmail ?? 'your email'}. It is valid for 10 minutes.')
                        : (_ru
                            ? 'Сначала подтвердите логин и пароль. После этого WesiOS пришлёт одноразовый код на почту профиля.'
                            : 'First confirm your login and password. WesiOS will then send a one-time code to your profile email.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (!_waitingCode) ..._passwordStep() else ..._codeStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordStep() => [
        TextField(
          controller: _login,
          enabled: !_busy,
          autofocus: true,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: _ru ? 'Логин' : 'Login',
            prefixIcon: Icon(Icons.person_outline,
                size: 18, color: AppTheme.textMuted),
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
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: AppTheme.textMuted,
              ),
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
        _button(
          onTap: _sendCode,
          label: _ru ? 'Получить код' : 'Send code',
          busyLabel: _ru ? 'Проверяю…' : 'Checking…',
        ),
      ];

  List<Widget> _codeStep() => [
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _verifyCode(),
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
          ),
          decoration: InputDecoration(
            counterText: '',
            labelText: _ru ? 'Код из письма' : 'Email code',
            prefixIcon:
                Icon(Icons.shield_outlined, size: 18, color: AppTheme.textMuted),
          ),
        ),
        _errorWidget(),
        const SizedBox(height: 18),
        _button(
          onTap: _verifyCode,
          label: _ru ? 'Подтвердить и войти' : 'Verify and sign in',
          busyLabel: _ru ? 'Подтверждаю…' : 'Verifying…',
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _sendCode,
          child: Text(_ru ? 'Отправить новый код' : 'Send a new code'),
        ),
        TextButton(
          onPressed: _busy ? null : _backToPassword,
          child: Text(_ru ? 'Назад к логину и паролю' : 'Back to password'),
        ),
      ];

  Widget _errorWidget() => _error == null
      ? const SizedBox(height: 6)
      : Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.accentRed),
          ),
        );

  Widget _button({
    required Future<void> Function() onTap,
    required String label,
    required String busyLabel,
  }) =>
      HoverButton(
        onTap: _busy ? () {} : onTap,
        padding: const EdgeInsets.symmetric(vertical: 15),
        backgroundColor: _busy ? AppTheme.surface : AppTheme.accent,
        child: Center(
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(busyLabel,
                        style: const TextStyle(color: Colors.white)),
                  ],
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      );
}
