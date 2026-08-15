import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/wesi_ai_chat_controller.dart';
import 'wesi_ai_backup_service.dart';
import 'wesi_ai_d2d_service.dart';

class WesiAiBackupSheet extends StatefulWidget {
  final WesiAiChatController controller;

  const WesiAiBackupSheet({
    super.key,
    required this.controller,
  });

  @override
  State<WesiAiBackupSheet> createState() => _WesiAiBackupSheetState();
}

class _WesiAiBackupSheetState extends State<WesiAiBackupSheet> {
  bool _busy = false;
  String? _status;

  WesiAiChatController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final conversations = controller.state.conversations;
          final importantCount = conversations
              .where((conversation) => conversation.importantForBackup)
              .length;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .88,
            minChildSize: .55,
            maxChildSize: .97,
            builder: (context, scroll) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Backup и перенос Wesi AI',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Отмечено важных чатов: $importantCount. Backup и D2D включают их сообщения, память и доступные локальные артефакты.',
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || importantCount == 0
                            ? null
                            : () => _exportBackup(context),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Создать backup'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _importBackup(context),
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Импорт backup'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy || importantCount == 0
                            ? null
                            : () => _startTransfer(context),
                        icon: const Icon(Icons.wifi_tethering_rounded),
                        label: const Text('Передать по LAN'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _receiveTransfer(context),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Принять по LAN'),
                      ),
                    ],
                  ),
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_status!),
                    ),
                  ),
                const Divider(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Важные чаты',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Expanded(
                  child: conversations.isEmpty
                      ? const Center(child: Text('Чатов пока нет'))
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.only(bottom: 28),
                          itemCount: conversations.length,
                          itemBuilder: (context, index) {
                            final conversation = conversations[index];
                            return SwitchListTile.adaptive(
                              title: Text(conversation.title),
                              subtitle: Text(
                                '${conversation.persona.name}${conversation.projectId == null ? '' : ' · проект'}',
                              ),
                              value: conversation.importantForBackup,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      controller.setConversationBackupImportant(
                                        conversation.id,
                                        value,
                                      ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _exportBackup(BuildContext context) async {
    final passphrase = await _askPassphrase(
      context,
      title: 'Пароль для backup',
      confirm: true,
    );
    if (passphrase == null) return;
    await _run(() async {
      final result = await WesiAiBackupService.exportImportantBackup(
        controller.state,
        passphrase,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Backup готов: ${result.build.conversationCount} чатов, '
            '${result.build.artifactCount} артефактов.';
      });
      await Share.shareXFiles(
        <XFile>[XFile(result.path)],
        subject: 'Wesi AI Important Backup',
      );
    });
  }

  Future<void> _importBackup(BuildContext context) async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['wbackup'],
      allowMultiple: false,
    );
    final path = pick?.files.single.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    final passphrase = await _askPassphrase(
      context,
      title: 'Пароль backup',
      confirm: false,
    );
    if (passphrase == null) return;
    await _run(() async {
      final result = await WesiAiBackupService.importEncryptedBackup(
        path: path,
        passphrase: passphrase,
        current: controller.state,
      );
      await controller.applyRestoredState(result.state);
      if (!mounted) return;
      setState(() {
        _status = 'Импортировано: ${result.importedConversations} чатов, '
            '${result.importedMessages} сообщений, '
            '${result.restoredArtifacts} артефактов.';
      });
    });
  }

  Future<void> _startTransfer(BuildContext context) async {
    await _run(() async {
      final session = await WesiAiD2DService.startSender(controller.state);
      if (!mounted) {
        await session.stop();
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Передача по LAN/Wi‑Fi'),
          content: SizedBox(
            width: 560,
            child: ValueListenableBuilder<WesiAiD2DStatus>(
              valueListenable: session.status,
              builder: (context, status, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fingerprint: ${session.descriptor.fingerprint}'),
                  const SizedBox(height: 6),
                  Text('Статус: ${_d2dStatusLabel(status)}'),
                  const SizedBox(height: 8),
                  const Text(
                    'На втором устройстве откройте «Принять по LAN» и вставьте одноразовый код:',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(session.transferCode),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: session.transferCode),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Копировать код'),
            ),
            TextButton(
              onPressed: () async {
                await session.stop();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
      if (mounted) {
        setState(() {
          _status = 'D2D: ${_d2dStatusLabel(session.status.value)}';
        });
      }
    });
  }

  Future<void> _receiveTransfer(BuildContext context) async {
    final transferController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Принять Wesi AI по LAN/Wi‑Fi'),
        content: TextField(
          controller: transferController,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Одноразовый transfer code',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = transferController.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Принять'),
          ),
        ],
      ),
    );
    transferController.dispose();
    if (code == null) return;
    await _run(() async {
      final result = await WesiAiD2DService.receive(
        transferCode: code,
        current: controller.state,
      );
      await controller.applyRestoredState(result.state);
      if (!mounted) return;
      setState(() {
        _status = 'D2D импорт: ${result.importedConversations} чатов, '
            '${result.restoredArtifacts} артефактов.';
      });
    });
  }

  Future<String?> _askPassphrase(
    BuildContext context, {
    required String title,
    required bool confirm,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
            ),
            if (confirm) ...[
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Повторите пароль'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = first.text;
              if (value.trim().length < 8) return;
              if (confirm && value != second.text) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (error) {
      if (mounted) setState(() => _status = 'Операция не завершена: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _d2dStatusLabel(WesiAiD2DStatus status) => switch (status) {
        WesiAiD2DStatus.ready => 'готов к подключению',
        WesiAiD2DStatus.transferring => 'передача',
        WesiAiD2DStatus.completed => 'завершено',
        WesiAiD2DStatus.expired => 'время истекло',
        WesiAiD2DStatus.stopped => 'остановлено',
        WesiAiD2DStatus.failed => 'ошибка',
      };
}
