import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';

/// Управление данными входа профиля.
///
/// Для владельца логин и новый пароль задаются одним действием и сразу
/// отправляются в PocketBase. Пароль нигде не сохраняется открытым: локально
/// остаётся PBKDF2-отпечаток, сервер хранит собственный безопасный хеш.
class ProfileCredentialsCard extends StatefulWidget {
  const ProfileCredentialsCard({super.key});

  @override
  State<ProfileCredentialsCard> createState() =>
      _ProfileCredentialsCardState();
}

class _ProfileCredentialsCardState extends State<ProfileCredentialsCard> {
  bool _busy = false;

  bool get _ru => WesiLocale.isRussian;

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.accentRed : AppTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _configureOwner() async {
    var me = TeamService.current ?? TeamService.owner;
    me ??= await TeamService.ensureOwner();
    if (me == null || !mounted) return;

    if (SyncEndpoint.session == null) {
      _say(
        _ru
            ? 'Сначала один раз войдите в Wesi Cloud в разделе «Синхронизация». '
                'Адрес сервера уже подставляется автоматически.'
            : 'Sign in to Wesi Cloud in Sync first. The server address is '
                'selected automatically.',
        error: true,
      );
      return;
    }

    final result = await showDialog<_CredentialsInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CredentialsDialog(
        initialLogin: me!.login == 'owner' ? '' : me.login,
      ),
    );
    if (result == null || !mounted) return;

    final login = result.login.trim();
    final password = result.password;
    if (login.length < 3) {
      _say(
        _ru ? 'Логин должен быть не короче трёх знаков' : 'Login is too short',
        error: true,
      );
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(login)) {
      _say(
        _ru
            ? 'В логине допустимы латинские буквы, цифры, точка, дефис и подчёркивание'
            : 'Use Latin letters, numbers, dot, dash or underscore',
        error: true,
      );
      return;
    }
    if (password.length < 8) {
      _say(
        _ru ? 'Пароль должен содержать минимум 8 знаков' : 'Use at least 8 characters',
        error: true,
      );
      return;
    }

    setState(() => _busy = true);
    final loginResult = await TeamService.setLogin(me.id, login);
    if (loginResult != TeamService.loginOk) {
      if (mounted) setState(() => _busy = false);
      _say(
        switch (loginResult) {
          TeamService.loginTaken =>
            _ru ? 'Такой логин уже занят' : 'That login is already taken',
          TeamService.loginBad =>
            _ru ? 'Логин не подходит' : 'The login is invalid',
          _ => _ru ? 'Не удалось изменить логин' : 'Could not change login',
        },
        error: true,
      );
      return;
    }

    // setPassword обновляет локальный безопасный отпечаток, вызывает
    // server provision и затем выполняет настоящий контрольный вход теми же
    // данными. true означает, что сервер уже принимает эту пару.
    final uploaded = await TeamService.setPassword(me.id, password);
    if (!mounted) return;
    setState(() => _busy = false);

    if (uploaded) {
      _say(
        _ru
            ? 'Логин и пароль сохранены и подтверждены сервером. Напишите ChatGPT, что данные отправлены.'
            : 'Credentials were saved and verified by the server.',
      );
    } else {
      _say(
        _ru
            ? 'Данные сохранены на устройстве, но сервер их не подтвердил. Проверьте вход в Wesi Cloud и повторите.'
            : 'Saved locally, but the server did not confirm them.',
        error: true,
      );
    }
  }

  Future<void> _changeEmployeePassword() async {
    final me = TeamService.current;
    if (me == null) return;
    final result = await showDialog<_CredentialsInput>(
      context: context,
      builder: (_) => _CredentialsDialog(
        initialLogin: me.login,
        lockLogin: true,
      ),
    );
    if (result == null) return;
    if (result.password.length < 8) {
      _say(_ru ? 'Пароль слишком короткий' : 'Password is too short',
          error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await TeamService.setPassword(me.id, result.password);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      ok
          ? (_ru ? 'Пароль обновлён на сервере' : 'Password updated')
          : (_ru
              ? 'Пароль изменён локально, но сервер недоступен'
              : 'Changed locally; server unavailable'),
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TeamService.revision,
      builder: (context, _, __) {
        final me = TeamService.current ?? TeamService.owner;
        final ownerMode = TeamService.isOwnerSession;
        final serverConnected = SyncEndpoint.session != null;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.badge_outlined,
                      size: 19, color: AppTheme.accent),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ownerMode
                              ? (_ru ? 'Вход владельца' : 'Owner sign-in')
                              : (_ru ? 'Вход в приложение' : 'App sign-in'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          me == null
                              ? (_ru ? 'Профиль не заведён' : 'No profile yet')
                              : (_ru
                                  ? 'Логин: ${me.login}'
                                  : 'Login: ${me.login}'),
                          style: TextStyle(
                              fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: serverConnected
                          ? AppTheme.accentGreen
                          : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      serverConnected
                          ? (_ru
                              ? 'Wesi Cloud подключён — данные можно отправить'
                              : 'Wesi Cloud connected')
                          : (_ru
                              ? 'Wesi Cloud не подключён'
                              : 'Wesi Cloud is not connected'),
                      style: TextStyle(
                        fontSize: 10.8,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ownerMode
                    ? (_ru
                        ? 'Укажите свой логин и новый пароль. Они отправятся на сервер по HTTPS и сразу проверятся настоящим входом. Сам пароль после этого нигде не показывается.'
                        : 'Choose your login and password. They are uploaded over HTTPS and verified immediately.')
                    : (_ru
                        ? 'Пароль нигде не показывается: хранится только безопасный отпечаток.'
                        : 'Only a secure password hash is stored.'),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.45,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _button(
                  ownerMode
                      ? (_ru
                          ? 'Указать логин и пароль · отправить на сервер'
                          : 'Set credentials and upload')
                      : (_ru ? 'Сменить пароль' : 'Change password'),
                  _busy
                      ? null
                      : ownerMode
                          ? _configureOwner
                          : _changeEmployeePassword,
                  primary: ownerMode,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _button(
    String label,
    VoidCallback? onTap, {
    bool primary = false,
  }) =>
      Material(
        color: primary
            ? AppTheme.accent
            : AppTheme.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: primary ? AppTheme.accent : AppTheme.glassBorder,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: onTap == null
                    ? AppTheme.textMuted
                    : primary
                        ? Colors.white
                        : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      );
}

class _CredentialsInput {
  final String login;
  final String password;

  const _CredentialsInput(this.login, this.password);
}

class _CredentialsDialog extends StatefulWidget {
  final String initialLogin;
  final bool lockLogin;

  const _CredentialsDialog({
    required this.initialLogin,
    this.lockLogin = false,
  });

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final TextEditingController _login =
      TextEditingController(text: widget.initialLogin);
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _showPassword = false;
  String? _error;

  bool get _ru => WesiLocale.isRussian;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final login = _login.text.trim();
    if (login.length < 3) {
      setState(() => _error = _ru ? 'Укажите логин' : 'Enter a login');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error =
          _ru ? 'Пароль — минимум 8 знаков' : 'Use at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error =
          _ru ? 'Пароли не совпадают' : 'Passwords do not match');
      return;
    }
    Navigator.pop(
      context,
      _CredentialsInput(login, _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.glassBorder),
      ),
      title: Text(
        _ru ? 'Данные входа' : 'Sign-in credentials',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              controller: _login,
              label: _ru ? 'Логин' : 'Login',
              enabled: !widget.lockLogin,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _password,
              label: _ru ? 'Новый пароль' : 'New password',
              obscure: !_showPassword,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _confirm,
              label: _ru ? 'Повторите пароль' : 'Repeat password',
              obscure: !_showPassword,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _showPassword,
              activeColor: AppTheme.accent,
              title: Text(
                _ru ? 'Показать пароль' : 'Show password',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary),
              ),
              onChanged: (value) =>
                  setState(() => _showPassword = value == true),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.accentRed),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _ru ? 'Отмена' : 'Cancel',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            _ru ? 'Сохранить и отправить' : 'Save and upload',
            style: TextStyle(color: AppTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    bool enabled = true,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        autocorrect: false,
        enableSuggestions: !obscure,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.surfaceLight.withOpacity(0.3),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: AppTheme.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: AppTheme.accent),
          ),
        ),
      );
}
