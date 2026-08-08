import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/audio_vault_extended_models.dart';
import '../services/audio_vault_extras_service.dart';

class AbletonProjectPanel extends StatefulWidget {
  final String beatId;
  const AbletonProjectPanel({super.key, required this.beatId});

  @override
  State<AbletonProjectPanel> createState() => _AbletonProjectPanelState();
}

class _AbletonProjectPanelState extends State<AbletonProjectPanel> {
  BeatExtendedMeta? _meta;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AbletonProjectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beatId != widget.beatId) _load();
  }

  Future<void> _load() async {
    _meta = await AudioVaultExtrasService.metaFor(widget.beatId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final path = meta?.abletonProjectPath;
    final exists = path != null && File(path).existsSync();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.music_note_rounded, color: AppTheme.accent),
            const SizedBox(width: 9),
            Text('Ableton Live Project',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          if (path == null)
            Text(
              'Привяжи исходный .als. WesiOS сохранит только путь, а сам проект останется на своём месте вместе с samples/packs.',
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppTheme.background.withOpacity(.32),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(exists ? Icons.check_circle_outline : Icons.error_outline,
                    color: exists ? AppTheme.accentGreen : AppTheme.accentRed,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    path,
                    maxLines: 3,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 10.5),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 11),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.folder_open),
              label: Text(path == null ? 'Выбрать .als' : 'Выбрать другой'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pastePath,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Вставить путь'),
            ),
            if (path != null)
              OutlinedButton.icon(
                onPressed: exists && !_busy ? _open : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Открыть в Ableton'),
              ),
            if (path != null)
              TextButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const Icon(Icons.link_off),
                label: const Text('Убрать связь'),
              ),
          ]),
          if (path != null && !exists) ...[
            const SizedBox(height: 8),
            Text(
              'Файл по сохранённому пути не найден. Если проект перенесён — укажи новый путь; WesiOS не удаляет и не перемещает исходный .als.',
              style: TextStyle(
                  color: AppTheme.accentRed, fontSize: 10, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choose() async {
    setState(() => _busy = true);
    try {
      final path = await AudioVaultExtrasService.chooseAbletonProject();
      if (path == null) return;
      await AudioVaultExtrasService.setAbletonProject(widget.beatId, path);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pastePath() async {
    final controller = TextEditingController(
      text: _meta?.abletonProjectPath ?? '',
    );
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Путь к Ableton Project'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставь полный путь к .als. Можно вставлять путь в кавычках — WesiOS их уберёт.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Например C:\\Music\\Beats\\Night Drive.als',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return;

    setState(() => _busy = true);
    try {
      final path = await AudioVaultExtrasService.validateAbletonProjectPath(raw);
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не найден существующий файл Ableton .als по этому пути.'),
            ),
          );
        }
        return;
      }
      await AudioVaultExtrasService.setAbletonProject(widget.beatId, path);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final error = await AudioVaultExtrasService.openAbletonProject(
      _meta?.abletonProjectPath,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _clear() async {
    await AudioVaultExtrasService.setAbletonProject(widget.beatId, null);
    await _load();
  }
}
