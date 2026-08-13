import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/security/secret_vault.dart';
import '../../core/services/firebase_rest_service.dart';
import '../../core/services/secrets_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';

/// Экран ключей от внешних сервисов.
///
/// Три замка подряд, и каждый закрывает своё:
///
/// 1. **Wesi Shield** — от того, кто взял устройство. Пароль открывает
///    локальное хранилище, где лежит зашифрованная копия.
/// 2. **Вход в Firebase** — от того, у кого просто есть сборка приложения.
/// 3. **Правила Firestore** — от всех остальных. Это единственный замок,
///    который нельзя обойти, переписав приложение: проверка происходит у
///    Google.
///
/// Обычный пользователь сюда не попадает и о ключах не узнаёт: приложение
/// работает целиком локально и без них.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  Map<String, String>? _remote;
  bool _loading = false;
  bool? _isAdmin;
  String? _error;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    SecretVault.revision.addListener(_refresh);
    FirebaseRestService.revision.addListener(_refresh);
    if (FirebaseRestService.isSignedIn) _load();
  }

  @override
  void dispose() {
    SecretVault.revision.removeListener(_refresh);
    FirebaseRestService.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Загрузка под страховкой.
  ///
  /// Раньше исключение в середине цепочки `await` оставляло `_loading`
  /// включённым навсегда: экран показывал вечный спиннер и не говорил, что
  /// именно сломалось. Теперь любая неудача заканчивает загрузку — экран
  /// покажет то, что успел, а не будет притворяться, что ещё грузится.
  Future<void> _load() async {
    try {
      await _loadInner();
    } catch (error) {
      debugPrint('keys_screen: загрузка не удалась — $error');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadInner() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final admin = await FirebaseRestService.isAdmin();
    // Ключи тянет SecretsService — он же делает это сам при запуске и при
    // входе. Здесь просто просим обновить, чтобы экран показывал свежее.
    await SecretsService.sync();
    final doc = SecretsService.all;
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _remote = doc;
      _loading = false;
      if (!admin) {
        // Не «нет доступа»: читать рабочий набор может любой вошедший — на
        // том и построено автоподключение. Закрыто именно ИЗМЕНЕНИЕ.
        _error = _ru
            ? 'Менять ключи может только владелец. Приложение пользуется ими '
                'само — вводить ничего не нужно.'
            : 'Only the owner can change the keys. The app uses them '
                'automatically — nothing to enter.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 8, 16, 32),
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: AppTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: WesiTitle(_ru ? 'Ключи' : 'Keys', size: 22),
                ),
                SizedBox(width: kHasCustomTitleBar ? 140 : 0),
              ],
            ),
            SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _ru
                    ? 'Ключи от внешних сервисов. Приложению для работы они '
                        'не нужны — оно работает локально.'
                    : 'Keys for external services. The app does not need them '
                        'to work — it runs locally.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
            SizedBox(height: 18),
            _vaultCard(),
            SizedBox(height: 14),
            _firebaseCard(),
            if (_error != null) ...[
              SizedBox(height: 14),
              _card(
                child: Row(
                  children: [
                    Icon(Icons.block,
                        size: 17, color: AppTheme.accentRed),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.accentRed)),
                    ),
                  ],
                ),
              ),
            ],
            if (_isAdmin == true) ...[
              const SizedBox(height: 14),
              _secretsCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ Shield

  Widget _vaultCard() {
    final reason = SecretVault.lockReason;
    final open = reason == null;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(open ? Icons.lock_open : Icons.lock,
                  size: 18,
                  color: open ? AppTheme.accentGreen : AppTheme.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  open
                      ? (_ru ? 'Хранилище открыто' : 'Vault unlocked')
                      : (_ru ? 'Хранилище закрыто' : 'Vault locked'),
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
            switch (reason) {
              null => _ru
                  ? 'Ключи расшифровываются и работают без сети.'
                  : 'Keys are decrypted and work offline.',
              VaultLockReason.noPassword => _ru
                  ? 'Сначала задайте пароль в Wesi Shield — без него ключ '
                      'шифрования выводить не из чего.'
                  : 'Set a password in Wesi Shield first — without it there '
                      'is nothing to derive the encryption key from.',
              VaultLockReason.locked => _ru
                  ? 'Введите пароль Wesi Shield, чтобы расшифровать '
                      'локальную копию.'
                  : 'Enter the Wesi Shield password to decrypt the local copy.',
            },
            style: TextStyle(
                fontSize: 12, height: 1.4, color: AppTheme.textMuted),
          ),
          SizedBox(height: 14),
          if (reason == VaultLockReason.noPassword)
            HoverButton(
              onTap: () => Navigator.pushNamed(context, '/shield'),
              padding:
                  EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              backgroundColor: AppTheme.accent,
              child: Text(_ru ? 'Открыть Wesi Shield' : 'Open Wesi Shield',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            )
          else
            Row(
              children: [
                if (!open)
                  HoverButton(
                    onTap: _unlockVault,
                    padding: EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    backgroundColor: AppTheme.accent,
                    child: Text(_ru ? 'Разблокировать' : 'Unlock',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  )
                else
                  HoverButton(
                    onTap: () => setState(SecretVault.lock),
                    padding: EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    backgroundColor: AppTheme.surface,
                    child: Text(_ru ? 'Закрыть' : 'Lock',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary)),
                  ),
                Spacer(),
                Text(
                  _ru
                      ? 'локально: ${SecretVault.names.length}'
                      : 'local: ${SecretVault.names.length}',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _unlockVault() async {
    final password = await _askText(
      title: _ru ? 'Пароль Wesi Shield' : 'Wesi Shield password',
      hint: _ru ? 'Пароль' : 'Password',
      obscure: true,
    );
    if (password == null || password.isEmpty) return;
    await SecretVault.unlock(password);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- Firebase

  Widget _firebaseCard() {
    final signedIn = FirebaseRestService.isSignedIn;
    final configured = FirebaseProject.isConfigured;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(signedIn ? Icons.cloud_done : Icons.cloud_off,
                  size: 18,
                  color:
                      signedIn ? AppTheme.accentGreen : AppTheme.textMuted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn
                      ? FirebaseRestService.session!.email
                      : (_ru ? 'Вход в Firebase' : 'Firebase sign-in'),
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
            !configured
                ? (_ru
                    ? 'Проект Firebase не настроен.'
                    : 'The Firebase project is not configured.')
                : signedIn
                    ? (_ru
                        ? 'Доступ к ключам решают правила Firestore, а не '
                            'приложение.'
                        : 'Access is decided by Firestore rules, not by the app.')
                    : (_ru
                        ? 'Учётная запись заводится в консоли Firebase. '
                            'Регистрации из приложения нет намеренно.'
                        : 'Accounts are created in the Firebase console. '
                            'Sign-up from the app is deliberately absent.'),
            style: TextStyle(
                fontSize: 12, height: 1.4, color: AppTheme.textMuted),
          ),
          // Пока учётной записи не существует, вход отвечает «неверная почта
          // или пароль» — и это читается как «вход сломан». Показываем прямо
          // здесь, что и где нужно один раз завести.
          if (configured && !signedIn) ...[
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru ? 'Если войти не удаётся' : 'If sign-in fails',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary),
                  ),
                  SizedBox(height: 6),
                  Text(
                    _ru
                        ? 'Скорее всего, учётной записи ещё нет. Один раз:\n'
                            '1. console.firebase.google.com → проект '
                            '${FirebaseProject.projectId}\n'
                            '2. Authentication → Sign-in method → включить '
                            'Email/Password\n'
                            '3. Authentication → Users → Add user: почта и пароль\n'
                            '4. Войти здесь этой парой, скопировать UID снизу\n'
                            '5. Firestore → создать документ admins/<UID>'
                        : 'Most likely the account does not exist yet. Once:\n'
                            '1. console.firebase.google.com → project '
                            '${FirebaseProject.projectId}\n'
                            '2. Authentication → Sign-in method → enable '
                            'Email/Password\n'
                            '3. Authentication → Users → Add user\n'
                            '4. Sign in here, copy the UID shown below\n'
                            '5. Firestore → create document admins/<UID>',
                    style: TextStyle(
                        fontSize: 11, height: 1.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
          if (signedIn) ...[
            SizedBox(height: 8),
            SelectableText(
              'UID: ${FirebaseRestService.session!.uid}',
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
            SizedBox(height: 4),
            Text(
              _ru
                  ? 'Этот UID нужен, чтобы создать документ admins/<UID> '
                      'в консоли Firebase — без него доступа не будет.'
                  : 'This UID is what you create the admins/<UID> document '
                      'from in the Firebase console.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
          SizedBox(height: 14),
          Row(
            children: [
              if (!signedIn)
                HoverButton(
                  onTap: configured ? _signIn : () {},
                  padding: EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  backgroundColor:
                      configured ? AppTheme.accent : AppTheme.surface,
                  child: Text(
                    _ru ? 'Войти' : 'Sign in',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: configured
                            ? Colors.white
                            : AppTheme.textMuted),
                  ),
                )
              else ...[
                HoverButton(
                  onTap: _load,
                  padding: EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  backgroundColor: AppTheme.accent,
                  child: Text(
                    _loading
                        ? (_ru ? 'Читаю…' : 'Loading…')
                        : (_ru ? 'Обновить' : 'Refresh'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                HoverButton(
                  onTap: () async {
                    await FirebaseRestService.signOut();
                    if (mounted) {
                      setState(() {
                        _remote = null;
                        _isAdmin = null;
                        _error = null;
                      });
                    }
                  },
                  padding: EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  backgroundColor: AppTheme.surface,
                  child: Text(_ru ? 'Выйти' : 'Sign out',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textPrimary)),
                ),
              ],
              Spacer(),
              TextButton(
                onPressed: _configureProject,
                child: Text(
                  _ru ? 'Проект' : 'Project',
                  style: TextStyle(
                    fontSize: 12,
                    color: configured
                        ? AppTheme.textMuted
                        : AppTheme.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    try {
      final email = await _askText(
        title: _ru ? 'Почта' : 'Email',
        hint: 'name@example.com',
      );
      if (email == null || email.isEmpty) return;
      if (!mounted) return;
      final password = await _askText(
        title: _ru ? 'Пароль Firebase' : 'Firebase password',
        hint: _ru ? 'Пароль' : 'Password',
        obscure: true,
      );
      if (password == null || password.isEmpty) return;
  
      setState(() => _loading = true);
      final failure = await FirebaseRestService.signIn(email, password);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure?.describe(russian: _ru);
      });
      if (failure == null) await _load();
    
    } catch (error) {
      // Действие не должно оставлять кнопку в вечной загрузке:
      // человек не поймёт, идёт что-то или уже нет.
      debugPrint('keys: _signIn не удалось — $error');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _configureProject() async {
    final apiKey = await _askText(
      title: 'Firebase apiKey',
      hint: 'AIza…',
      initial: FirebaseProject.apiKey,
    );
    if (apiKey == null) return;
    if (!mounted) return;
    final projectId = await _askText(
      title: 'Firebase projectId',
      hint: 'wesios-…',
      initial: FirebaseProject.projectId,
    );
    if (projectId == null) return;
    await FirebaseProject.configure(apiKey: apiKey, projectId: projectId);
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------- секреты

  Widget _secretsCard() {
    final remote = _remote ?? const <String, String>{};
    final open = SecretVault.lockReason == null;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_ru ? 'Ключи' : 'Keys',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ),
              TextButton(
                onPressed: _addSecret,
                child: Text(_ru ? 'Добавить' : 'Add',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.accent)),
              ),
            ],
          ),
          if (remote.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _ru ? 'Пока ни одного' : 'None yet',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            ...remote.entries.map((e) => _secretRow(e.key, e.value, open)),
        ],
      ),
    );
  }

  Widget _secretRow(String name, String value, bool open) => Padding(
        padding: EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.vpn_key_outlined,
                size: 15, color: AppTheme.accent),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textPrimary)),
                  Text(
                    // Показываем только хвост: подсмотреть через плечо целый
                    // ключ проще, чем кажется, а для сверки достаточно
                    // последних символов.
                    value.length <= 6
                        ? '••••'
                        : '••••${value.substring(value.length - 4)}',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy,
                  size: 15, color: AppTheme.textMuted),
              tooltip: _ru ? 'Скопировать' : 'Copy',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(_ru ? 'Скопировано' : 'Copied'),
                  ));
                }
              },
            ),
            IconButton(
              icon: Icon(Icons.edit,
                  size: 15, color: AppTheme.textMuted),
              onPressed: () => _editSecret(name, value),
            ),
          ],
        ),
      );

  Future<void> _addSecret() async {
    final name = await _askText(
      title: _ru ? 'Название ключа' : 'Key name',
      hint: 'stripe_secret',
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    await _editSecret(name, '');
  }

  Future<void> _editSecret(String name, String current) async {
    try {
      final value = await _askText(
        title: name,
        hint: _ru ? 'Значение' : 'Value',
        initial: current,
      );
      if (value == null) return;
  
      final next = {...(_remote ?? const <String, String>{}), name: value};
      setState(() => _loading = true);
      final failure =
          await FirebaseRestService.setDocument('secrets/default', next);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure?.describe(russian: _ru);
        if (failure == null) _remote = next;
      });
      if (failure == null && SecretVault.unlocked.value) {
        await SecretVault.write(name, value);
      }
    
    } catch (error) {
      // Действие не должно оставлять кнопку в вечной загрузке:
      // человек не поймёт, идёт что-то или уже нет.
      debugPrint('keys: _editSecret не удалось — $error');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------ утилиты

  Future<String?> _askText({
    required String title,
    required String hint,
    String? initial,
    bool obscure = false,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title,
            style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: obscure,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
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
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );
}
