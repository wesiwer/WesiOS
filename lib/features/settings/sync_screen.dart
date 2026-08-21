import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/local_backup_service.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/sync/sync_auto.dart';
import '../../core/sync/sync_codec.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_manual_direction.dart';
import '../../core/sync/sync_recovery.dart';
import '../../core/sync/sync_recovery_guard.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';

/// Synchronization status and controls for the already authenticated WesiOS
/// session. Authentication itself lives only on the main MFA login screen.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SyncScreen()),
  );

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _expiryTimer;

  bool get _ru => WesiLocale.isRussian;
  bool get _signedIn => TeamService.current != null && SyncEndpoint.isConnected;

  @override
  void initState() {
    super.initState();
    unawaited(SyncEndpoint.ensureDefaults());
    _scheduleExpiryRefresh();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final raw = SyncEndpoint.session?['expiresAt'];
    final expiresAt = DateTime.tryParse('$raw');
    if (expiresAt == null) return;
    final delay = expiresAt.difference(DateTime.now());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay + const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _goToLogin({bool clearCurrent = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (clearCurrent) {
      await TeamService.signOut();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _exportLocalBackup() async {
    if (_busy || TeamService.current?.isOwner != true) return;
    setState(() => _busy = true);
    try {
      final backup = await LocalBackupService.create();
      await Share.shareXFiles(<XFile>[
        XFile.fromData(
          backup.bytes,
          mimeType: 'application/octet-stream',
          name: backup.fileName,
        ),
      ], subject: _ru ? 'Резервная копия WesiOS' : 'WesiOS backup');
      if (!mounted) return;
      _say(
        _ru
            ? 'Резервная копия ${backup.fileName} подготовлена: ${backup.records} записей и ${backup.settingsCount} бизнес-настроек. Сохраните именно этот файл .wesibackup в надёжное место.'
            : 'Backup prepared: ${backup.records} records and ${backup.settingsCount} business settings. Save the file to Files or another safe location.',
      );
    } catch (error) {
      _say(
        _ru
            ? 'Не удалось создать резервную копию: $error'
            : 'Could not create backup: $error',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreLocalBackup() async {
    if (_busy || TeamService.current?.isOwner != true) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['wesibackup'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final raw = picked.files.single.bytes;
    if (raw == null) {
      _say(
        _ru
            ? 'Не удалось прочитать выбранный файл.'
            : 'Could not read the selected file.',
        error: true,
      );
      return;
    }
    final bytes = Uint8List.fromList(raw);

    LocalBackupInspection inspection;
    try {
      inspection = LocalBackupService.inspect(bytes);
    } on LocalBackupException catch (error) {
      final text = error.code == 'BACKUP_FORMAT_INVALID'
          ? (_ru
                ? 'Выберите файл .wesibackup, созданный кнопкой экспорта резервной копии. Служебный JSON восстановить здесь нельзя.'
                : 'Choose a .wesibackup file created by Backup export. Internal JSON files cannot be restored here.')
          : (_ru
                ? 'Резервная копия не прошла проверку: ${error.message}'
                : 'Backup validation failed: ${error.message}');
      _say(text, error: true);
      return;
    } catch (_) {
      _say(
        _ru
            ? 'Не удалось прочитать выбранную резервную копию.'
            : 'Could not read the selected backup.',
        error: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _ru ? 'Восстановить локальные данные?' : 'Restore local data?',
        ),
        content: Text(
          _ru
              ? 'Копия от ${_when(inspection.createdAt)}. В ней ${inspection.records} записей в ${inspection.counts.length} разделах и ${inspection.settingsCount} бизнес-настроек.\n\nСовпадающие записи на телефоне будут заменены данными из копии. Остальные локальные записи не удаляются. Перед записью обычная синхронизация будет заблокирована, а при ошибке приложение попытается вернуть исходное локальное состояние.'
              : 'Backup from ${_when(inspection.createdAt)}. It contains ${inspection.records} records in ${inspection.counts.length} sections and ${inspection.settingsCount} business settings.\n\nMatching local records will be replaced by the backup. Other local records are not deleted. Normal sync will be locked before writing and the app will attempt to roll back the local state if restoration fails.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_ru ? 'Восстановить' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final report = await LocalBackupService.restore(bytes);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      report.ok
          ? (_ru
                ? 'Восстановлено ${report.restored} записей. Они помечены как свежие локальные изменения. Обычная синхронизация пока заблокирована — сначала создайте проверенную серверную копию.'
                : 'Restored ${report.restored} records. They are marked as fresh local changes. Normal sync remains locked until you create a verified server copy.')
          : (report.message ??
                (_ru ? 'Восстановление не выполнено.' : 'Restore failed.')),
      error: !report.ok,
    );
  }

  Future<void> _runRecovery() async {
    if (_busy || !_signedIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ru ? 'Безопасный перенос' : 'Protected local upload'),
        content: Text(
          _ru
              ? 'Сначала будет создана отдельная локальная резервная копия. Затем данные этого устройства отправятся на сервер без скачивания серверных записей и без удаления локальных данных. Обычная синхронизация останется заблокированной до полной проверки.'
              : 'A separate local backup will be created first. This device will then upload its business data without pulling server rows or deleting local data. Normal sync stays locked until verification completes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _ru ? 'Создать копию и перенести' : 'Back up and upload',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final report = await SyncRecovery.run();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(report.describe(russian: _ru), error: !report.ok);
  }

  Future<void> _releaseRecoveryLock() async {
    if (_busy || !SyncRecovery.verified) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ru ? 'Серверная копия проверена' : 'Server copy verified'),
        content: Text(
          _ru
              ? 'Все локальные записи из защитного снимка совпали с сервером. Снять блокировку обычной синхронизации? Автосинхронизация останется выключенной, пока вы сами её не включите.'
              : 'Every local row in the protected snapshot matches the server. Release the normal-sync lock? Automatic sync will remain off until you enable it yourself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_ru ? 'Оставить защиту' : 'Keep locked'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_ru ? 'Снять блокировку' : 'Release lock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await SyncRecovery.releaseVerifiedSafetyLock();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      _ru
          ? 'Защитная блокировка снята. Автоматическая синхронизация всё ещё выключена.'
          : 'Recovery lock released. Automatic sync is still disabled.',
    );
  }

  Future<void> _manualUploadDevice() async {
    if (_busy || !_signedIn || TeamService.current?.isOwner != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _ru ? 'Отправить данные с устройства?' : 'Upload device data?',
        ),
        content: Text(
          _ru
              ? 'Телефон станет источником истины для бизнес-данных. Перед отправкой WesiOS создаст резервную копию, затем отправит локальные записи на сервер без скачивания серверных данных и проверит их обратным чтением. После успешной проверки можно использовать обычную автоматическую синхронизацию.'
              : 'This device becomes authoritative for business data. WesiOS creates a backup first, uploads local rows without downloading server data, then verifies them by reading them back. Normal automatic sync can be used after verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_ru ? 'Отправить с устройства' : 'Upload device'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final report = await SyncManualDirection.uploadDeviceAuthoritative();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(report.describe(russian: _ru), error: !report.ok);
  }

  Future<void> _manualDownloadServer() async {
    if (_busy || !_signedIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _ru ? 'Принять данные с сервера?' : 'Download server data?',
        ),
        content: Text(
          _ru
              ? 'WesiOS сначала сохранит защитную локальную копию. Затем серверные записи будут применены на устройстве без отправки локальных данных на сервер. Совпадающие записи могут быть заменены серверной версией; локальные записи, которых на сервере нет, автоматически не удаляются.'
              : 'WesiOS saves a local safety backup first. Server rows are then applied to this device without uploading local data. Matching rows may be replaced by the server version; local rows absent from the server are not automatically deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_ru ? 'Принять с сервера' : 'Download server'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final report = await SyncManualDirection.downloadServerAuthoritative();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(report.describe(russian: _ru), error: !report.ok);
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    if (!_signedIn) {
      _say(
        _ru
            ? 'Сеанс WesiOS завершён. Войдите заново.'
            : 'Your WesiOS session has ended. Sign in again.',
        error: true,
      );
      await _goToLogin();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ru ? 'Ручная синхронизация' : 'Manual sync'),
        content: Text(
          _ru
              ? 'Выберите, какая сторона сейчас является источником данных.'
              : 'Choose which side is the data source for this pass.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'download'),
            child: Text(_ru ? 'Принять с сервера' : 'Download server'),
          ),
          if (TeamService.current?.isOwner == true)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'upload'),
              child: Text(_ru ? 'Отправить с устройства' : 'Upload device'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'upload') await _manualUploadDevice();
    if (choice == 'download') await _manualDownloadServer();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SyncEndpoint.revision,
      builder: (context, _, __) {
        final signedIn = _signedIn;
        final owner = TeamService.current?.isOwner == true;
        final recoveryLocked = SyncRecoveryGuard.active;
        _scheduleExpiryRefresh();
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    kTitleBarInset + 12,
                    kHasCustomTitleBar ? 148 : 16,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: AppTheme.textPrimary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: WesiTitle(
                          _ru ? 'Синхронизация' : 'Sync',
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _statusCard(signedIn),
                      const SizedBox(height: 14),
                      _serverCard(),
                      const SizedBox(height: 14),
                      _sessionCard(signedIn),
                      const SizedBox(height: 14),
                      _button(
                        label: _ru ? 'Ручная синхронизация' : 'Manual sync',
                        onTap: (_busy || !signedIn) ? null : _syncNow,
                        filled: true,
                      ),
                      if (signedIn && owner) ...[
                        const SizedBox(height: 10),
                        _button(
                          label: recoveryLocked
                              ? (SyncRecovery.verified
                                    ? (_ru
                                          ? 'Серверная копия проверена — снять защиту'
                                          : 'Server copy verified — release lock')
                                    : (_ru
                                          ? 'Безопасно перенести данные с телефона'
                                          : 'Safely upload this device'))
                              : (_ru
                                    ? 'Создать защитную копию на сервере'
                                    : 'Create protected server copy'),
                          onTap: _busy
                              ? null
                              : (recoveryLocked && SyncRecovery.verified
                                    ? _releaseRecoveryLock
                                    : _runRecovery),
                        ),
                      ],
                      if (owner) ...[
                        const SizedBox(height: 10),
                        _button(
                          label: _ru
                              ? 'Экспортировать локальную резервную копию'
                              : 'Export local backup',
                          onTap: _busy ? null : _exportLocalBackup,
                        ),
                        const SizedBox(height: 10),
                        _button(
                          label: _ru
                              ? 'Импортировать резервную копию (.wesibackup)'
                              : 'Import backup (.wesibackup)',
                          onTap: _busy ? null : _restoreLocalBackup,
                          muted: true,
                        ),
                      ],
                      if (recoveryLocked) ...[
                        const SizedBox(height: 10),
                        Text(
                          SyncRecovery.verified
                              ? (_ru
                                    ? 'Защитный режим: серверная копия уже проверена. Обычный pull всё ещё заблокирован.'
                                    : 'Recovery mode: the server copy is verified. Normal pull is still locked.')
                              : (_ru
                                    ? 'Защитный режим: обычная синхронизация отключена, локальные бизнес-данные не будут заменены серверными.'
                                    : 'Recovery mode: normal sync is disabled and local business data cannot be replaced by server rows.'),
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                      if (!signedIn) ...[
                        const SizedBox(height: 10),
                        _button(
                          label: _ru ? 'Войти в WesiOS' : 'Sign in to WesiOS',
                          onTap: _busy ? null : () => _goToLogin(),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: _messageIsError
                                ? AppTheme.accentRed
                                : AppTheme.accentGreen,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _autoToggle(signedIn),
                      const SizedBox(height: 18),
                      _whatSyncs(),
                      const SizedBox(height: 14),
                      _securityNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _serverCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface.withOpacity(0.32),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: AppTheme.glassBorder),
    ),
    child: Row(
      children: [
        Icon(Icons.dns_outlined, size: 20, color: AppTheme.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ru ? 'Сервер WesiOS' : 'WesiOS server',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'api.wesi-inc.ru · TLS',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        Icon(Icons.lock_outline, size: 17, color: AppTheme.accentGreen),
      ],
    ),
  );

  Widget _statusCard(bool signedIn) {
    final last = SyncEndpoint.lastRun;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: signedIn
              ? AppTheme.accentGreen.withOpacity(0.35)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            signedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 22,
            color: signedIn ? AppTheme.accentGreen : AppTheme.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn
                      ? (_ru ? 'Сервер подключён' : 'Server connected')
                      : (_ru ? 'Требуется вход' : 'Sign-in required'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  last == null
                      ? (_ru ? 'Обмена ещё не было' : 'No exchange yet')
                      : (_ru
                            ? 'Последний обмен: ${_when(last)}'
                            : 'Last exchange: ${_when(last)}'),
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionCard(bool signedIn) {
    final employee = TeamService.current;
    final login = SyncEndpoint.login.trim();
    return _infoCard(
      title: _ru ? 'Сеанс WesiOS' : 'WesiOS session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            signedIn
                ? (login.isEmpty ? (employee?.displayName ?? 'WesiOS') : login)
                : (_ru
                      ? 'Подтверждённый серверный сеанс отсутствует или истёк.'
                      : 'The verified server session is missing or expired.'),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: signedIn ? AppTheme.textSecondary : AppTheme.textMuted,
            ),
          ),
          if (signedIn) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _button(
                    label: _ru ? 'Войти заново' : 'Sign in again',
                    onTap: _busy ? null : () => _goToLogin(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    label: _ru ? 'Выйти' : 'Sign out',
                    onTap: _busy ? null : () => _goToLogin(),
                    muted: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoToggle(bool signedIn) {
    final on = SyncEndpoint.enabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ru ? 'Автоматическая синхронизация' : 'Automatic sync',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: signedIn ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  SyncRecoveryGuard.active
                      ? (_ru
                            ? 'Заблокирована защитным переносом'
                            : 'Locked by protected upload')
                      : signedIn
                      ? (_ru
                            ? 'Данные отправляются после изменений и при запуске'
                            : 'Data is sent after changes and on launch')
                      : (_ru
                            ? 'Включится после подтверждённого входа'
                            : 'Turns on after verified sign-in'),
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: on && signedIn && !SyncRecoveryGuard.active,
            activeColor: AppTheme.accent,
            onChanged: signedIn && !SyncRecoveryGuard.active
                ? (value) async {
                    await SyncEndpoint.setEnabled(value);
                    if (value) {
                      SyncAuto.start();
                    } else {
                      SyncAuto.stop(force: true);
                    }
                    if (mounted) setState(() {});
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _whatSyncs() {
    final names = _ru
        ? const {
            'organizations': 'Организации',
            'organization_grants': 'Права сотрудников',
            'accounts': 'Счета',
            'transactions': 'Операции',
            'tasks': 'Задачи',
            'articles': 'База знаний',
            'employees': 'Сотрудники',
            'calendar_events': 'Календарь',
            'user_profiles': 'Профили',
            'task_ai_memory': 'Память задач',
            'inter_org_transfers': 'Переводы между организациями',
            'transaction_audit': 'История финансов',
            'critical_audit': 'Журнал безопасности',
            'roadmap_projects': 'Roadmap — проекты',
            'roadmap_items': 'Roadmap — элементы',
            'crm_clients': 'CRM — клиенты',
            'crm_deals': 'CRM — сделки',
            'crm_interactions': 'CRM — взаимодействия',
            'finance_categories': 'Финансовые категории',
            'sandbox_transactions': 'Песочница — операции',
            'what_if_presets': 'Сценарии What-if',
          }
        : const {
            'accounts': 'Accounts',
            'transactions': 'Operations',
            'tasks': 'Tasks',
            'articles': 'Your articles',
            'employees': 'People',
          };
    return _infoCard(
      title: _ru ? 'Что синхронизируется' : 'What is synchronised',
      child: Column(
        children: [
          for (final collection in SyncCodec.collections)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 5, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    names[collection.name] ??
                        (_ru
                            ? 'Системные данные WesiOS'
                            : 'WesiOS system data'),
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _securityNote() => _infoCard(
    title: _ru ? 'Безопасность' : 'Security',
    child: Text(
      _ru
          ? 'У синхронизации больше нет отдельного входа. Она использует тот же подтверждённый MFA-сеанс, что и WesiOS. Пароль на экране синхронизации не запрашивается и не хранится.'
          : 'Sync no longer has a separate sign-in. It uses the same verified MFA session as WesiOS. The sync screen never asks for or stores your password.',
      style: TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.textMuted),
    ),
  );

  Widget _infoCard({required String title, required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surface.withOpacity(0.3),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.glassBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    bool muted = false,
    bool filled = false,
  }) => Material(
    color: filled
        ? AppTheme.accent
        : muted
        ? AppTheme.surface.withOpacity(0.45)
        : AppTheme.surfaceLight.withOpacity(0.55),
    borderRadius: BorderRadius.circular(11),
    child: InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: onTap == null
                  ? AppTheme.textMuted
                  : filled
                  ? Colors.white
                  : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}
