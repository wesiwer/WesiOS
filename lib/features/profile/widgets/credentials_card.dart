import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';

/// Логин и пароль для входа в приложение.
///
/// **Почему это здесь, а не зашито в сборку.** Логин и пароль конкретного
/// человека — его и только его. Репозиторий открыт: пароль, вписанный в
/// код «чтобы работало сразу», немедленно становится известен всем, кто
/// откроет исходники. Поэтому задаёт их человек, у себя, в два нажатия.
///
/// Пароль здесь не показывается никогда — ни свой, ни чужой. В хранилище
/// его и нет: лежит PBKDF2-хеш с солью, из которого пароль не достать.
/// Забыли — не «посмотреть», а задать новый.
class ProfileCredentialsCard extends StatefulWidget {
  const ProfileCredentialsCard({super.key});

  @override
  State<ProfileCredentialsCard> createState() =>
      _ProfileCredentialsCardState();
}

class _ProfileCredentialsCardState extends State<ProfileCredentialsCard> {
  bool get _ru => WesiLocale.isRussian;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppTheme.surface),
    );
  }

  Future<void> _changeLogin() async {
    final me = TeamService.current ?? TeamService.owner;
    if (me == null) return;

    final controller = TextEditingController(text: me.login);
    final entered = await _ask(
      title: _ru ? 'Логин для входа' : 'Login',
      hint: _ru ? 'Например: WesiOff' : 'For example: WesiOff',
      controller: controller,
      obscure: false,
    );
    controller.dispose();
    if (entered == null) return;

    final result = await TeamService.setLogin(me.id, entered);
    if (!mounted) return;
    setState(() {});

    _say(switch (result) {
      TeamService.loginOk => _ru ? 'Логин изменён' : 'Login changed',
      TeamService.loginTaken =>
        _ru ? 'Такой логин уже занят' : 'That login is taken',
      TeamService.loginBad => _ru
          ? 'Слишком короткий логин — от трёх знаков'
          : 'Too short — three characters minimum',
      _ => _ru ? 'Не получилось' : 'Failed',
    });
  }

  Future<void> _changePassword() async {
    final me = TeamService.current ?? TeamService.owner;
    if (me == null) return;

    final controller = TextEditingController();
    final entered = await _ask(
      title: _ru ? 'Новый пароль' : 'New password',
      hint: _ru ? 'Не короче шести знаков' : 'At least six characters',
      controller: controller,
      obscure: true,
    );
    final password = entered?.trim() ?? '';
    controller.dispose();
    if (entered == null) return;

    // Шесть знаков — не «безопасно», а нижняя граница, ниже которой пароль
    // подбирается за минуты. Настаивать на большем в приложении, которое
    // держат в кармане, бессмысленно: люди начнут писать его на бумажке.
    if (password.length < 6) {
      _say(_ru ? 'Слишком короткий пароль' : 'Password is too short');
      return;
    }

    final ok = await TeamService.setPassword(me.id, password);
    if (!mounted) return;
    _say(ok
        ? (_ru ? 'Пароль изменён' : 'Password changed')
        : (_ru
            ? 'Пароль изменён здесь, но сервер недоступен — на портал он '
                'приедет при следующем обмене'
            : 'Changed locally; the server was unreachable'));
  }

  Future<String?> _ask({
    required String title,
    required String hint,
    required TextEditingController controller,
    required bool obscure,
  }) =>
      showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppTheme.glassBorder),
          ),
          title: Text(title,
              style: TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  TextStyle(fontSize: 13, color: AppTheme.textMuted),
              isDense: true,
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.glassBorder)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.accent)),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_ru ? 'Отмена' : 'Cancel',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(_ru ? 'Сохранить' : 'Save',
                  style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TeamService.revision,
      builder: (context, _, __) {
        final me = TeamService.current ?? TeamService.owner;
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
                          _ru ? 'Вход в приложение' : 'App sign-in',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary),
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
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _ru
                    ? 'Пароль нигде не показывается — в хранилище его нет, '
                        'лежит только отпечаток, из которого пароль не '
                        'восстановить. Забыли — задайте новый.'
                    : 'The password is never shown: only a hash is stored. '
                        'If you forget it, set a new one.',
                style: TextStyle(
                    fontSize: 10.5, height: 1.45, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _button(_ru ? 'Сменить логин' : 'Change login',
                      me == null ? null : _changeLogin),
                  const SizedBox(width: 8),
                  _button(_ru ? 'Сменить пароль' : 'Change password',
                      me == null ? null : _changePassword),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _button(String label, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: onTap == null
                  ? AppTheme.textMuted
                  : AppTheme.textSecondary,
            ),
          ),
        ),
      );
}
