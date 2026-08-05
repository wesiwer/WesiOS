import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/portal_account_service.dart';
import '../../team/services/team_service.dart';

/// Единые данные входа владельца.
///
/// Эти же логин и пароль после успешной отправки принимает портал, а после
/// отдельного подтверждения владельца их будет проверять стартовый экран
/// WesiOS. Пароль хранится только как хеш PocketBase и локальный PBKDF2-хеш.
class ProfileCredentialsCard extends StatefulWidget {
  const ProfileCredentialsCard({super.key});

  @override
  State<ProfileCredentialsCard> createState() =>
      _ProfileCredentialsCardState();
}

class _ProfileCredentialsCardState extends State<ProfileCredentialsCard> {
  bool _sending = false;
  String? _status;
  bool _statusError = false;

  bool get _ru => WesiLocale.isRussian;

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  Future<void> _configure() async {
    final me = TeamService.current ?? TeamService.owner;
    if (me == null || _sending) return;

    final draft = await _askCredentials(initialLogin: me.login);
    if (draft == null) return;

    final login = draft.login.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(login)) {
      _say(
        _ru
            ? 'Логин: 3–32 латинских символа, цифры, точка, дефис или подчёркивание.'
            : 'Use 3–32 Latin characters, digits, dot, dash or underscore.',
        error: true,
      );
      return;
    }
    if (draft.password.length < 8) {
      _say(_ru ? 'Пароль должен быть не короче 8 символов.' : 'Use at least 8 characters.',
          error: true);
      return;
    }
    if (draft.password != draft.confirmation) {
      _say(_ru ? 'Пароли не совпадают.' : 'Passwords do not match.', error: true);
      return;
    }

    final other = TeamService.byLogin(login);
    if (other != null && other.id != me.id) {
      _say(_ru ? 'Такой логин уже занят локальным профилем.' : 'That login is already used.',
          error: true);
      return;
    }

    setState(() {
      _sending = true;
      _status = _ru ? 'Отправляю и проверяю вход…' : 'Publishing and verifying…';
      _statusError = false;
    });

    final server = await PortalAccountService.configureCurrentProfile(
      employee: me,
      login: login,
      password: draft.password,
    );
    if (!server.ok) {
      if (mounted) {
        setState(() => _sending = false);
        _say(server.message, error: true);
      }
      return;
    }

    final loginResult = await TeamService.setLogin(me.id, login);
    if (loginResult != TeamService.loginOk) {
      if (mounted) {
        setState(() => _sending = false);
        _say(
          _ru
              ? 'Сервер принял данные, но локальный логин не обновился. Повторите сохранение.'
              : 'Server updated, but the local login did not.',
          error: true,
        );
      }
      return;
    }

    // setPassword сохраняет только локальный хеш и повторно подтверждает
    // серверную запись. Открытый пароль после выхода из метода исчезает.
    final passwordOk = await TeamService.setPassword(me.id, draft.password);
    if (!mounted) return;
    setState(() => _sending = false);
    _say(
      passwordOk
          ? (_ru
              ? 'Готово: профиль отправлен на сервер, логин и пароль проверены.'
              : 'Done: the profile was published and verified.')
          : (_ru
              ? 'Серверный вход проверен, но повторная локальная проверка не завершилась.'
              : 'Server sign-in worked, but the local confirmation failed.'),
      error: !passwordOk,
    );
  }

  Future<_CredentialDraft?> _askCredentials({required String initialLogin}) {
    final login = TextEditingController(
      text: initialLogin == 'owner' ? '' : initialLogin,
    );
    final password = TextEditingController();
    final confirmation = TextEditingController();
    var visible = false;

    return showDialog<_CredentialDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppTheme.glassBorder),
          ),
          title: Text(
            _ru ? 'Мой вход WesiOS' : 'My WesiOS sign-in',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru
                        ? 'Эти данные будут отправлены на api.wesi-inc.ru и станут едиными для сайта и приложения.'
                        : 'These credentials will be used by the site and the app.',
                    style: TextStyle(
                        fontSize: 12, height: 1.45, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  _dialogField(
                    controller: login,
                    label: _ru ? 'Логин' : 'Login',
                    hint: 'WesiOff',
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    controller: password,
                    label: _ru ? 'Пароль' : 'Password',
                    hint: _ru ? 'Минимум 8 символов' : 'At least 8 characters',
                    obscure: !visible,
                    suffix: IconButton(
                      onPressed: () => setDialogState(() => visible = !visible),
                      icon: Icon(
                        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 19,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    controller: confirmation,
                    label: _ru ? 'Повторите пароль' : 'Repeat password',
                    hint: '••••••••',
                    obscure: !visible,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 16, color: AppTheme.accentGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ru
                              ? 'Открытый пароль не записывается ни в Hive, ни в логи.'
                              : 'The plain password is never stored or logged.',
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.4,
                              color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_ru ? 'Отмена' : 'Cancel',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _CredentialDraft(
                  login: login.text,
                  password: password.text,
                  confirmation: confirmation.text,
                ),
              ),
              child: Text(
                _ru ? 'Отправить на сервер' : 'Publish to server',
                style: TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      login.dispose();
      password.dispose();
      confirmation.dispose();
    });
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: !obscure,
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: suffix,
              hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.background.withOpacity(0.45),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TeamService.revision,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: SyncEndpoint.revision,
        builder: (context, __, ___) {
          final me = TeamService.current ?? TeamService.owner;
          final serverSession = SyncEndpoint.session != null;
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
                        size: 20, color: AppTheme.accent),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _ru ? 'Единый вход WesiOS' : 'Unified WesiOS sign-in',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            me == null
                                ? (_ru ? 'Профиль не заведён' : 'No profile')
                                : '${_ru ? 'Логин' : 'Login'}: ${me.login}',
                            style: TextStyle(
                                fontSize: 11.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: serverSession
                            ? AppTheme.accentGreen
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  _ru
                      ? 'Задайте собственный логин и пароль. Приложение отправит их на сервер и сразу проверит вход тем же способом, что использует сайт.'
                      : 'Set your login and password. The app publishes and verifies them using the same server as the site.',
                  style: TextStyle(
                      fontSize: 10.8, height: 1.45, color: AppTheme.textMuted),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _status!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: _statusError
                          ? AppTheme.accentRed
                          : AppTheme.accentGreen,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Material(
                  color: _sending
                      ? AppTheme.surfaceLight.withOpacity(0.3)
                      : AppTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: me == null || _sending ? null : _configure,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_sending) ...[
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 9),
                          ] else ...[
                            const Icon(Icons.cloud_upload_outlined,
                                size: 18, color: Colors.white),
                            const SizedBox(width: 9),
                          ],
                          Text(
                            _sending
                                ? (_ru ? 'Проверяю…' : 'Verifying…')
                                : (_ru
                                    ? 'Указать логин и пароль'
                                    : 'Set login and password'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CredentialDraft {
  final String login;
  final String password;
  final String confirmation;

  const _CredentialDraft({
    required this.login,
    required this.password,
    required this.confirmation,
  });
}
