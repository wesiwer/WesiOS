import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/security/session_service.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/portal_account_service.dart';
import '../../team/services/team_service.dart';

/// Вход и безопасность текущего профиля.
class ProfileCredentialsCard extends StatefulWidget {
  const ProfileCredentialsCard({super.key});

  @override
  State<ProfileCredentialsCard> createState() =>
      _ProfileCredentialsCardState();
}

class _ProfileCredentialsCardState extends State<ProfileCredentialsCard> {
  bool _sending = false;
  bool _loadingSessions = false;
  String? _status;
  bool _statusError = false;
  List<WesiSessionInfo> _sessions = const [];

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    SessionService.revision.addListener(_reloadSessions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSessions());
  }

  @override
  void dispose() {
    SessionService.revision.removeListener(_reloadSessions);
    super.dispose();
  }

  void _reloadSessions() => _loadSessions();

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  Future<void> _loadSessions() async {
    if (_loadingSessions || !SyncEndpoint.isConnected) return;
    if (mounted) setState(() => _loadingSessions = true);
    final sessions = await SessionService.list();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loadingSessions = false;
    });
  }

  Future<void> _endSession(WesiSessionInfo session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          session.current
              ? (_ru ? 'Выйти из аккаунта?' : 'Sign out?')
              : (_ru ? 'Завершить сеанс?' : 'End session?'),
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          session.current
              ? (_ru
                  ? 'Текущий сеанс будет завершён на сервере и приложение вернётся на экран входа.'
                  : 'This server session will end and the app will return to sign-in.')
              : (_ru
                  ? 'На устройстве «${session.deviceName.isEmpty ? session.platform : session.deviceName}» доступ будет отозван.'
                  : 'Access will be revoked on that device.'),
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
              _ru ? 'Завершить' : 'End',
              style: TextStyle(color: AppTheme.accentRed),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final ended = await SessionService.revoke(session.id);
    if (!mounted) return;
    if (!ended) {
      _say(_ru ? 'Не удалось завершить сеанс' : 'Unable to end session',
          error: true);
      return;
    }

    if (session.current) {
      await TeamService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    await _loadSessions();
  }

  Future<void> _configure() async {
    final me = TeamService.current;
    if (me == null || !me.isOwner || _sending) return;

    final draft = await _askCredentials(
      initialLogin: me.login,
      initialEmail: me.email,
    );
    if (draft == null) return;

    final login = draft.login.trim().toLowerCase();
    final email = draft.email.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(login)) {
      _say(_ru
          ? 'Логин: 3–32 латинских символа, цифры, точка, дефис или подчёркивание.'
          : 'Use 3–32 Latin characters, digits, dot, dash or underscore.',
          error: true);
      return;
    }
    if (!PortalAccountService.validSecurityEmail(email)) {
      _say(_ru ? 'Укажите действующую электронную почту.' : 'Enter a valid email.',
          error: true);
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
      _say(_ru ? 'Такой логин уже занят.' : 'That login is already used.',
          error: true);
      return;
    }

    setState(() {
      _sending = true;
      _status = _ru ? 'Сохраняю защищённый вход…' : 'Saving secure sign-in…';
      _statusError = false;
    });

    final updatedOwner = me.copyWith(email: email);
    await TeamService.save(updatedOwner);
    final server = await PortalAccountService.configureCurrentProfile(
      employee: updatedOwner,
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
    final passwordOk = await TeamService.setPasswordLocally(me.id, draft.password);
    if (!mounted) return;
    if (loginResult != TeamService.loginOk || !passwordOk) {
      setState(() => _sending = false);
      _say(_ru
          ? 'Сервер сохранил данные, но локальный профиль не обновился полностью.'
          : 'Server data was saved, but the local profile did not fully update.',
          error: true);
      return;
    }

    // Password/account changes invalidate the current authentication context.
    // Force a fresh password + email-code login with the new credentials.
    await TeamService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<_CredentialDraft?> _askCredentials({
    required String initialLogin,
    required String initialEmail,
  }) {
    final login = TextEditingController(
      text: initialLogin == 'owner' ? '' : initialLogin,
    );
    final email = TextEditingController(text: initialEmail);
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final securityEmailLocked =
        PortalAccountService.validSecurityEmail(initialEmail);
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
            _ru ? 'Мой защищённый вход' : 'My secure sign-in',
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
                    securityEmailLocked
                        ? (_ru
                            ? 'Почта для кодов уже подтверждена и защищена. Здесь можно изменить логин или пароль.'
                            : 'The security email is verified and locked. You can change login or password here.')
                        : (_ru
                            ? 'Укажите почту для кодов, новый логин и пароль. После успешной настройки почта будет защищена от обычного изменения.'
                            : 'Enter a security email, new login and password. After setup the email will be locked against normal changes.'),
                    style: TextStyle(fontSize: 12, height: 1.45, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  _dialogField(
                    controller: login,
                    label: _ru ? 'Логин' : 'Login',
                    hint: 'WesiOff',
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    controller: email,
                    label: securityEmailLocked
                        ? (_ru ? 'Подтверждённая почта для кодов' : 'Verified security email')
                        : (_ru ? 'Почта для кодов' : 'Security email'),
                    hint: 'name@example.com',
                    keyboard: TextInputType.emailAddress,
                    enabled: !securityEmailLocked,
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
                        visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_ru ? 'Отмена' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _CredentialDraft(
                  login: login.text,
                  email: email.text,
                  password: password.text,
                  confirmation: confirmation.text,
                ),
              ),
              child: Text(
                _ru ? 'Сохранить' : 'Save',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      login.dispose();
      email.dispose();
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
    TextInputType? keyboard,
    bool enabled = true,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscure,
            keyboardType: keyboard,
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
          final me = TeamService.current;
          return Column(
            children: [
              _accountCard(me),
              _sessionsCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _accountCard(dynamic me) => Container(
        margin: const EdgeInsets.only(bottom: 14),
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
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ru ? 'Защищённый вход WesiOS' : 'Secure WesiOS sign-in',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        me == null
                            ? (_ru ? 'Нет активного профиля' : 'No active profile')
                            : '${_ru ? 'Логин' : 'Login'}: ${me.login} · ${me.email.isEmpty ? (_ru ? 'почта не указана' : 'no email') : me.email}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SyncEndpoint.isConnected
                        ? AppTheme.accentGreen
                        : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: TextStyle(
                  fontSize: 11.5,
                  color:
                      _statusError ? AppTheme.accentRed : AppTheme.accentGreen,
                ),
              ),
            ],
            if (me?.isOwner == true) ...[
              const SizedBox(height: 12),
              Material(
                color: _sending
                    ? AppTheme.surfaceLight.withOpacity(0.3)
                    : AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _sending ? null : _configure,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        _sending
                            ? (_ru ? 'Сохраняю…' : 'Saving…')
                            : (_ru
                                ? 'Изменить логин или пароль'
                                : 'Change login or password'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _sessionsCard() => Container(
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
                Icon(
                  Icons.devices_outlined,
                  size: 20,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _ru ? 'Активные сеансы' : 'Active sessions',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _ru ? 'Обновить' : 'Refresh',
                  onPressed: _loadingSessions ? null : _loadSessions,
                  icon: _loadingSessions
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _ru
                  ? 'Здесь видны устройства, с которых входили в этот профиль. Любой чужой сеанс можно завершить удалённо.'
                  : 'Devices signed into this profile are listed here. Any remote session can be revoked.',
              style: TextStyle(
                fontSize: 10.8,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (!_loadingSessions && _sessions.isEmpty)
              Text(
                _ru ? 'Активные сеансы не найдены.' : 'No active sessions found.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            for (final session in _sessions) _sessionTile(session),
          ],
        ),
      );

  Widget _sessionTile(WesiSessionInfo session) {
    final device = session.deviceName.trim().isNotEmpty
        ? session.deviceName.trim()
        : (session.platform.trim().isEmpty ? 'WesiOS' : session.platform.trim());
    final details = <String>[
      if (session.platform.isNotEmpty) session.platform,
      if (session.ip.isNotEmpty) 'IP ${session.ip}',
      if (session.country.isNotEmpty) session.country,
      if (session.timezone.isNotEmpty) session.timezone,
    ].join(' · ');
    final times = _ru
        ? 'Вход: ${_date(session.createdAt)} · Последняя активность: ${_date(session.lastSeenAt)}'
        : 'Signed in: ${_date(session.createdAt)} · Last active: ${_date(session.lastSeenAt)}';

    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.28),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: session.current
              ? AppTheme.accent.withOpacity(.45)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            session.purpose == 'portal'
                ? Icons.language
                : Icons.devices_other,
            size: 19,
            color: session.current ? AppTheme.accent : AppTheme.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (session.current) ...[
                      const SizedBox(width: 7),
                      Text(
                        _ru ? 'ТЕКУЩИЙ' : 'CURRENT',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                    ],
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  times,
                  style: TextStyle(
                    fontSize: 10.2,
                    height: 1.35,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: session.current
                ? (_ru ? 'Выйти' : 'Sign out')
                : (_ru ? 'Завершить удалённо' : 'End remotely'),
            onPressed: () => _endSession(session),
            icon: Icon(
              Icons.logout,
              size: 18,
              color: AppTheme.accentRed,
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${local.year} $hh:$min';
  }
}

class _CredentialDraft {
  final String login;
  final String email;
  final String password;
  final String confirmation;

  const _CredentialDraft({
    required this.login,
    required this.email,
    required this.password,
    required this.confirmation,
  });
}
