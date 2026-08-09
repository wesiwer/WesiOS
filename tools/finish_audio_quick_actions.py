from pathlib import Path

path = Path('lib/features/audio/audio_vault_v2_screen.dart')
text = path.read_text(encoding='utf-8')
if '_quickAudioActions(BeatEntry beat)' in text:
    print('Audio Vault quick actions already present.')
    raise SystemExit(0)


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'Expected exactly one Audio Vault anchor, got {count}: {old[:100]!r}'
        )
    text = text.replace(old, new, 1)


replace_once(
    "import 'models/audio_vault_models.dart';",
    "import 'models/audio_vault_extended_models.dart';\n"
    "import 'models/audio_vault_models.dart';",
)

replace_once(
    "  VisualizerMode _visualizer = VisualizerMode.water;\n",
    "  VisualizerMode _visualizer = VisualizerMode.water;\n"
    "  final Set<String> _quickAnalyzing = <String>{};\n"
    "  bool _batchAnalyzing = false;\n",
)

replace_once(
    """        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'Добавить бит',
              onPressed: _createBeat,
              icon: Icon(Icons.add_circle_outline, color: AppTheme.accent),
            ),
        ],""",
    """        actions: [
          if (_tab == 0) ...[
            IconButton(
              tooltip: 'Wesi AI: анализировать новые / изменённые WAV',
              onPressed: _batchAnalyzing ? null : _analyzePendingBeats,
              icon: _batchAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.auto_awesome, color: AppTheme.accent),
            ),
            IconButton(
              tooltip: 'Добавить бит',
              onPressed: _createBeat,
              icon: Icon(Icons.add_circle_outline, color: AppTheme.accent),
            ),
          ],
        ],""",
)

replace_once(
    """                _fileBadge('TRACK', beat.trackoutPath, beat),
                const Spacer(),""",
    """                _fileBadge('TRACK', beat.trackoutPath, beat),
                const SizedBox(width: 6),
                _quickAudioActions(beat),
                const Spacer(),""",
)

marker = "  Widget _pill(String text, Color color) => Container("
methods = r'''  Future<(BeatExtendedMeta, AudioAnalysisReport?)> _quickAudioState(
    BeatEntry beat,
  ) async {
    final meta = await AudioVaultExtrasService.metaFor(beat.id);
    final report = await AudioVaultExtrasService.analysisForBeat(beat);
    return (meta, report);
  }

  Widget _quickAudioActions(BeatEntry beat) =>
      FutureBuilder<(BeatExtendedMeta, AudioAnalysisReport?)>(
        future: _quickAudioState(beat),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();

          final meta = data.$1;
          final report = data.$2;
          final abletonPath = meta.abletonProjectPath;
          final hasAbleton = abletonPath != null && abletonPath.isNotEmpty;
          final abletonExists = hasAbleton && File(abletonPath).existsSync();
          final wavExists = beat.wavPath != null && File(beat.wavPath!).existsSync();
          final stale = meta.analysis != null && report == null;
          final analyzing = _quickAnalyzing.contains(beat.id);

          final scoreColor = report == null
              ? (stale ? Colors.orange : AppTheme.accent)
              : report.score >= 85
                  ? AppTheme.accentGreen
                  : report.score >= 65
                      ? Colors.orange
                      : AppTheme.accentRed;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAbleton)
                _miniActionBadge(
                  label: 'ALS',
                  icon: abletonExists
                      ? Icons.music_note_rounded
                      : Icons.link_off_rounded,
                  color: abletonExists ? AppTheme.accent : AppTheme.accentRed,
                  onTap: () => _openAbletonQuick(abletonPath),
                ),
              if (hasAbleton && (wavExists || report != null || stale))
                const SizedBox(width: 5),
              if (wavExists || report != null || stale)
                _miniActionBadge(
                  label: analyzing
                      ? 'AI…'
                      : report != null
                          ? 'AI ${report.score}'
                          : stale
                              ? 'AI ↻'
                              : 'AI',
                  icon: analyzing
                      ? Icons.hourglass_top_rounded
                      : Icons.psychology_alt_outlined,
                  color: scoreColor,
                  onTap: analyzing ? null : () => _quickAnalyzeBeat(beat),
                ),
            ],
          );
        },
      );

  Widget _miniActionBadge({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _openAbletonQuick(String path) async {
    final error = await AudioVaultExtrasService.openAbletonProject(path);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _quickAnalyzeBeat(BeatEntry beat) async {
    if (_quickAnalyzing.contains(beat.id)) return;
    setState(() => _quickAnalyzing.add(beat.id));
    try {
      final report = await AudioVaultExtrasService.analyzeBeat(beat);
      if (!mounted) return;
      final critical = report.insights
          .where((e) => e.severity == AudioIssueSeverity.critical)
          .length;
      final warning = report.insights
          .where((e) => e.severity == AudioIssueSeverity.warning)
          .length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wesi AI · ${beat.title}: ${report.score}/100 · '
            '${report.estimatedIntegratedLufs.toStringAsFixed(1)} LUFS · '
            '${report.estimatedTruePeakDbtp.toStringAsFixed(2)} dBTP · '
            '$critical крит. / $warning предупр.',
          ),
          action: SnackBarAction(
            label: 'Отчёт',
            onPressed: () => _openBeat(beat),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wesi AI: не удалось проанализировать «${beat.title}»: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _quickAnalyzing.remove(beat.id));
    }
  }

  Future<void> _analyzePendingBeats() async {
    if (_batchAnalyzing) return;
    setState(() => _batchAnalyzing = true);
    var analyzed = 0;
    var skipped = 0;
    var failed = 0;
    try {
      final beats = await AudioVaultService.all();
      final candidates = beats
          .where((b) => b.wavPath != null && File(b.wavPath!).existsSync())
          .toList();

      for (final beat in candidates) {
        final current = await AudioVaultExtrasService.analysisForBeat(beat);
        if (current != null) {
          skipped++;
          continue;
        }
        if (mounted) setState(() => _quickAnalyzing.add(beat.id));
        try {
          await AudioVaultExtrasService.analyzeBeat(beat);
          analyzed++;
        } catch (_) {
          failed++;
        } finally {
          if (mounted) setState(() => _quickAnalyzing.remove(beat.id));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wesi AI batch: $analyzed новых отчётов · '
              '$skipped уже актуальны · $failed ошибок.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _batchAnalyzing = false);
    }
  }

'''
if marker not in text:
    raise SystemExit('Audio Vault method insertion marker not found')
text = text.replace(marker, methods + marker, 1)
path.write_text(text, encoding='utf-8')
print('Audio Vault quick ALS/AI actions applied.')
