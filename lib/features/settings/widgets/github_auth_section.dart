import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/github_auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';

/// Вход в GitHub для автообновления.
///
/// Релизы WesiOS лежат в приватном репозитории — без входа приложение их
/// просто не видит. Вход сделан через device flow: человек не создаёт и не
/// копирует никаких токенов, он один раз подтверждает доступ в браузере.
class GitHubAuthSection extends StatefulWidget {
  const GitHubAuthSection({super.key});

  @override
  State<GitHubAuthSection> createState() => _GitHubAuthSectionState();
}

class _GitHubAuthSectionState extends State<GitHubAuthSection> {
  DeviceCode? _code;
  bool _waiting = false;
  bool _cancelled = false;
  String? _message;
  bool _messageIsError = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    GitHubAuthService.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    // Ожидание подтверждения живёт своим циклом; без флага оно продолжало бы
    // опрашивать GitHub после ухода с экрана.
    _cancelled = true;
    GitHubAuthService.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    setState(() {
      _message = null;
      _waiting = true;
      _cancelled = false;
    });

    final code = await GitHubAuthService.requestDeviceCode();
    if (!mounted) return;
    if (code == null) {
      setState(() {
        _waiting = false;
        _messageIsError = true;
        _message = _ru
            ? 'GitHub не выдал код. Две обычные причины: в приложении не '
                'включён «Enable Device Flow», либо client_id расходится '
                'с тем, что на GitHub, — сверьте его выше посимвольно.'
            : 'GitHub did not issue a code. Two usual causes: “Enable Device '
                'Flow” is off for the app, or the client_id differs from the '
                'one on GitHub — compare it above character by character.';
      });
      return;
    }

    setState(() => _code = code);
    // Код сразу в буфер: набирать восемь символов руками, глядя в другое
    // окно, — лишний шанс ошибиться.
    await Clipboard.setData(ClipboardData(text: code.userCode));
    await _openBrowser(code.verificationUri);

    final outcome = await GitHubAuthService.pollForToken(
      code,
      cancelled: () => _cancelled,
    );
    if (!mounted) return;

    setState(() {
      _waiting = false;
      _code = null;
      _messageIsError = outcome != DeviceAuthOutcome.success;
      _message = switch (outcome) {
        DeviceAuthOutcome.success => _ru
            ? 'Готово. Обновления теперь проверяются автоматически.'
            : 'Done. Updates will be checked automatically.',
        DeviceAuthOutcome.denied =>
          _ru ? 'Доступ не подтверждён.' : 'Access was denied.',
        DeviceAuthOutcome.expired => _ru
            ? 'Код истёк — начните заново.'
            : 'The code expired — start again.',
        DeviceAuthOutcome.failed =>
          _ru ? 'Вход не завершён.' : 'Sign-in did not complete.',
      };
    });
  }

  Future<void> _openBrowser(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Браузер мог не открыться — адрес всё равно показан на экране.
    }
  }

  Future<void> _editClientId() async {
    final ctrl = TextEditingController(text: GitHubAuthService.clientId);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          _ru ? 'client_id приложения GitHub' : 'GitHub app client_id',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? 'GitHub → Settings → Developer settings → OAuth Apps → '
                      'New OAuth App. Включите «Enable Device Flow» и '
                      'скопируйте сюда Client ID.\n\n'
                      'Это не секрет: в device flow клиент публичный по '
                      'устройству протокола, и сам по себе client_id не даёт '
                      'доступа ни к чему без вашего подтверждения в браузере.'
                  : 'GitHub → Settings → Developer settings → OAuth Apps → '
                      'New OAuth App. Enable “Device Flow” and paste the '
                      'Client ID here.\n\n'
                      'It is not a secret: in device flow the client is '
                      'public by design, and the client_id alone grants '
                      'nothing without your approval in the browser.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Client ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(WesiLocale.get('save'),
                style: TextStyle(color: AppTheme.accentOrange)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value != null) await GitHubAuthService.setClientId(value);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = GitHubAuthService.isSignedIn;
    final configured = GitHubAuthService.isConfigured;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                signedIn ? Icons.verified_user : Icons.lock_outline,
                size: 18,
                color: signedIn ? AppTheme.accentGreen : AppTheme.accentOrange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn
                      ? (_ru
                          ? 'GitHub подключён${GitHubAuthService.login == null ? '' : ' — ${GitHubAuthService.login}'}'
                          : 'GitHub connected${GitHubAuthService.login == null ? '' : ' — ${GitHubAuthService.login}'}')
                      : (_ru ? 'Вход в GitHub' : 'GitHub sign-in'),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            signedIn
                ? (_ru
                    ? 'Приложение само проверяет и ставит новые версии из '
                        'приватного репозитория.'
                    : 'The app checks for and installs new versions from the '
                        'private repository on its own.')
                : (_ru
                    ? 'Релизы лежат в приватном репозитории — без входа их не '
                        'видно. Создавать токен руками не нужно: вы один раз '
                        'подтвердите доступ в браузере.'
                    : 'Releases live in a private repository and are invisible '
                        'without sign-in. No manual token needed — you approve '
                        'once in the browser.'),
            style: TextStyle(
                fontSize: 12, height: 1.4, color: AppTheme.textMuted),
          ),
          if (configured && !signedIn) ...[
            const SizedBox(height: 10),
            // Показан целиком намеренно: секрета здесь нет, а сверить его
            // с GitHub глазами — самый быстрый способ поймать расхождение,
            // если приложение когда-нибудь пересоздадут.
            Row(
              children: [
                const Icon(Icons.tag, size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    GitHubAuthService.clientId,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_code != null) ...[
            const SizedBox(height: 14),
            _codeBlock(_code!),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 12,
                color: _messageIsError
                    ? AppTheme.accentRed
                    : AppTheme.accentGreen,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (!signedIn)
                HoverButton(
                  onTap: configured && !_waiting ? _signIn : () {},
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  backgroundColor: configured && !_waiting
                      ? AppTheme.accentOrange
                      : AppTheme.surface,
                  child: Text(
                    _waiting
                        ? (_ru ? 'Жду подтверждения…' : 'Waiting…')
                        : (_ru ? 'Войти через GitHub' : 'Sign in with GitHub'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: configured && !_waiting
                          ? Colors.white
                          : AppTheme.textMuted,
                    ),
                  ),
                )
              else
                HoverButton(
                  onTap: GitHubAuthService.signOut,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  backgroundColor: AppTheme.surface,
                  child: Text(
                    _ru ? 'Выйти' : 'Sign out',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: _editClientId,
                child: Text(
                  configured
                      ? (_ru ? 'client_id' : 'client_id')
                      : (_ru ? 'Задать client_id' : 'Set client_id'),
                  style: TextStyle(
                    fontSize: 12,
                    color: configured
                        ? AppTheme.textMuted
                        : AppTheme.accentOrange,
                  ),
                ),
              ),
            ],
          ),
          if (!configured) ...[
            const SizedBox(height: 4),
            Text(
              _ru
                  ? 'Сначала нужен client_id приложения GitHub — это делается '
                      'один раз и занимает пару минут.'
                  : 'A GitHub app client_id is required first — a one-time, '
                      'two-minute step.',
              style: TextStyle(fontSize: 11, color: AppTheme.accentOrange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _codeBlock(DeviceCode code) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentOrange.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? 'Введите этот код на странице GitHub (он уже скопирован):'
                  : 'Enter this code on the GitHub page (already copied):',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            SelectableText(
              code.userCode,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: AppTheme.accentOrange,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code.verificationUri,
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => _openBrowser(code.verificationUri),
                  child: Text(
                    _ru ? 'Открыть' : 'Open',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.accentOrange),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
