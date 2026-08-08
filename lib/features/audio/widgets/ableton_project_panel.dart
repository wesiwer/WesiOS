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
              'Привяжи исходный .als. WesiOS сохранит путь, а сам проект останется на своём месте вместе с samples/packs.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
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
                  child: Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 11),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.link),
              label: Text(path == null ? 'Привязать .als' : 'Изменить путь'),
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
