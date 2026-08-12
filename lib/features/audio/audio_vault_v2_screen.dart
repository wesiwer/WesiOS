import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../team/services/team_service.dart';
import '../team/widgets/employee_or_custom_field.dart';
import 'models/audio_vault_extended_models.dart';
import 'models/audio_vault_models.dart';
import 'services/audio_player_service.dart';
import 'services/audio_vault_extras_service.dart';
import 'services/audio_vault_service.dart';
import 'widgets/ableton_project_panel.dart';
import 'widgets/audio_analysis_panel.dart';
import 'widgets/audio_music_hub.dart';
import 'widgets/audio_visualizer.dart';
import 'widgets/horizon_contract_dialog.dart';
import 'widgets/lease_countdown.dart';

class AudioVaultV2Screen extends StatefulWidget {
  const AudioVaultV2Screen({super.key});

  @override
  State<AudioVaultV2Screen> createState() => _AudioVaultV2ScreenState();
}

class _AudioVaultV2ScreenState extends State<AudioVaultV2Screen> {
  final _search = TextEditingController();
  final _minBpm = TextEditingController();
  final _maxBpm = TextEditingController();
  int _tab = 0;
  BeatStage? _stage;
  String? _authorId;
  String _sort = 'updated';
  bool _favoritesOnly = false;
  VisualizerMode _visualizer = VisualizerMode.water;
  final Set<String> _quickAnalyzing = <String>{};
  bool _batchAnalyzing = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    AudioVaultService.revision.addListener(_refresh);
    AudioVaultExtrasService.revision.addListener(_refresh);
    TeamService.revision.addListener(_refresh);
    AudioPlayerService.initialize();
  }

  @override
  void dispose() {
    AudioVaultService.revision.removeListener(_refresh);
    AudioVaultExtrasService.revision.removeListener(_refresh);
    TeamService.revision.removeListener(_refresh);
    _search.dispose();
    _minBpm.dispose();
    _maxBpm.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<List<BeatEntry>> _beats() async {
    var list = await AudioVaultService.all();
    final q = _search.text.trim().toLowerCase();
    final min = int.tryParse(_minBpm.text.trim());
    final max = int.tryParse(_maxBpm.text.trim());
    if (q.isNotEmpty) {
      list = list.where((b) {
        final author = TeamService.byId(b.authorEmployeeId)?.displayName ?? '';
        return [
          b.title,
          b.genre,
          b.mood,
          b.musicalKey,
          b.tags.join(' '),
          b.notes,
          author,
          b.lease?.artistName ?? '',
          b.lease?.socialUrl ?? '',
        ].join(' ').toLowerCase().contains(q);
      }).toList();
    }
    if (_stage != null) list = list.where((b) => b.stage == _stage).toList();
    if (_authorId != null)
      list = list.where((b) => b.authorEmployeeId == _authorId).toList();
    if (_favoritesOnly) list = list.where((b) => b.favorite).toList();
    if (min != null) list = list.where((b) => b.bpm >= min).toList();
    if (max != null) list = list.where((b) => b.bpm <= max).toList();
    switch (_sort) {
      case 'title':
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'bpm':
        list.sort((a, b) => a.bpm.compareTo(b.bpm));
        break;
      case 'created':
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'author':
        list.sort((a, b) =>
            (TeamService.byId(a.authorEmployeeId)?.displayName ?? '').compareTo(
                TeamService.byId(b.authorEmployeeId)?.displayName ?? ''));
        break;
      case 'stage':
        list.sort((a, b) => a.stage.index.compareTo(b.stage.index));
        break;
      case 'lease':
        list.sort((a, b) {
          final ad = a.lease?.endsAt;
          final bd = b.lease?.endsAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
        break;
      default:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const WesiTitle('Audio Vault', size: 20),
        actions: [
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
        ],
      ),
      body: Column(children: [
        _tabs(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _archive(),
              _player(),
              AudioMusicHub(
                  onLocalPlaybackStarted: () => setState(() => _tab = 1)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _tabs() {
    final tabs = [
      ('Архив', Icons.archive_outlined),
      ('Плеер', Icons.graphic_eq),
      ('Music Hub', Icons.library_music_outlined),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = _tab == i;
          return InkWell(
            onTap: () => setState(() => _tab = i),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withOpacity(.15)
                    : AppTheme.surface.withOpacity(.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? AppTheme.accent.withOpacity(.5)
                        : AppTheme.glassBorder),
              ),
              child: Row(children: [
                Icon(tabs[i].$2,
                    size: 17,
                    color: selected ? AppTheme.accent : AppTheme.textMuted),
                const SizedBox(width: 7),
                Text(tabs[i].$1,
                    style: TextStyle(
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _archive() => FutureBuilder<List<BeatEntry>>(
        future: _beats(),
        builder: (context, snapshot) {
          final beats = snapshot.data ?? const <BeatEntry>[];
          return Column(children: [
            _filterBar(),
            Expanded(
              child: beats.isEmpty
                  ? _emptyArchive()
                  : LayoutBuilder(builder: (context, c) {
                      final columns = c.maxWidth >= 1200
                          ? 4
                          : c.maxWidth >= 850
                              ? 3
                              : c.maxWidth >= 560
                                  ? 2
                                  : 1;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 130),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 1 ? 1.7 : 1.03,
                        ),
                        itemCount: beats.length,
                        itemBuilder: (_, i) => _beatCard(beats[i], beats),
                      );
                    }),
            ),
          ]);
        },
      );

  Widget _filterBar() {
    final employees = TeamService.all;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Название, артист, жанр, тег, комментарий…',
                prefixIcon:
                    Icon(Icons.search, size: 19, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surface.withOpacity(.45),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          DropdownButton<BeatStage?>(
            value: _stage,
            dropdownColor: AppTheme.surface,
            hint:
                Text('Все стадии', style: TextStyle(color: AppTheme.textMuted)),
            items: [
              const DropdownMenuItem<BeatStage?>(
                  value: null, child: Text('Все стадии')),
              ...BeatStage.values.map((s) => DropdownMenuItem<BeatStage?>(
                  value: s, child: Text(_stageName(s)))),
            ],
            onChanged: (v) => setState(() => _stage = v),
          ),
          DropdownButton<String?>(
            value: _authorId,
            dropdownColor: AppTheme.surface,
            hint:
                Text('Все авторы', style: TextStyle(color: AppTheme.textMuted)),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Все авторы')),
              ...employees.map((e) => DropdownMenuItem<String?>(
                  value: e.id, child: Text(e.displayName))),
            ],
            onChanged: (v) => setState(() => _authorId = v),
          ),
          SizedBox(
              width: 72,
              child: TextField(
                  controller: _minBpm,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'BPM от', isDense: true))),
          SizedBox(
              width: 72,
              child: TextField(
                  controller: _maxBpm,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'до', isDense: true))),
          DropdownButton<String>(
            value: _sort,
            dropdownColor: AppTheme.surface,
            items: const [
              DropdownMenuItem(
                  value: 'updated', child: Text('Недавно изменённые')),
              DropdownMenuItem(value: 'created', child: Text('Новые')),
              DropdownMenuItem(value: 'title', child: Text('Название')),
              DropdownMenuItem(value: 'bpm', child: Text('BPM')),
              DropdownMenuItem(value: 'author', child: Text('Автор')),
              DropdownMenuItem(value: 'stage', child: Text('Стадия')),
              DropdownMenuItem(
                  value: 'lease', child: Text('Ближайшее продление')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'updated'),
          ),
          FilterChip(
            selected: _favoritesOnly,
            label: const Text('Избранное'),
            avatar: const Icon(Icons.star_outline, size: 16),
            onSelected: (v) => setState(() => _favoritesOnly = v),
          ),
          if (_stage != null ||
              _authorId != null ||
              _favoritesOnly ||
              _minBpm.text.isNotEmpty ||
              _maxBpm.text.isNotEmpty)
            TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text('Сбросить')),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _stage = null;
      _authorId = null;
      _favoritesOnly = false;
      _minBpm.clear();
      _maxBpm.clear();
    });
  }

  Widget _emptyArchive() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.album_outlined, size: 54, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text('Архив битов пуст',
              style: TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
              'Добавь первый бит и собери MP3 / WAV / Trackout / проект / документы в одной карточке.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: _createBeat,
              icon: const Icon(Icons.add),
              label: const Text('Добавить бит')),
        ]),
      );

  Widget _beatCard(BeatEntry beat, List<BeatEntry> queue) {
    final author =
        TeamService.byId(beat.authorEmployeeId)?.displayName ?? 'Не указан';
    final hasCover =
        beat.coverPath != null && File(beat.coverPath!).existsSync();
    return InkWell(
      onTap: () => _openBeat(beat),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              hasCover
                  ? Image.file(File(beat.coverPath!), fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                        AppTheme.accent.withOpacity(.35),
                        AppTheme.background
                      ])),
                      child: Icon(Icons.graphic_eq,
                          size: 56, color: AppTheme.accent.withOpacity(.75)),
                    ),
              Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(.76)
                  ])))),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  onPressed: () => AudioVaultService.save(
                      beat.copyWith(favorite: !beat.favorite)),
                  icon: Icon(beat.favorite ? Icons.star : Icons.star_border,
                      color:
                          beat.favorite ? Colors.amber : AppTheme.textPrimary),
                ),
              ),
              if (beat.playablePath != null)
                Center(
                  child: IconButton.filled(
                    onPressed: () async {
                      await AudioPlayerService.playBeat(beat, queue: queue);
                      if (mounted) setState(() => _tab = 1);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 34),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(beat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                      Text(author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(.72),
                              fontSize: 11)),
                    ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 5, children: [
                _pill(_stageName(beat.stage), _stageColor(beat.stage)),
                if (beat.bpm > 0) _pill('${beat.bpm} BPM', AppTheme.accent),
                if (beat.musicalKey.isNotEmpty)
                  _pill(beat.musicalKey, AppTheme.textMuted),
                if (beat.lease != null)
                  LeaseCountdown(lease: beat.lease!, compact: true),
              ]),
              const SizedBox(height: 9),
              // audioVaultFooterWrap: file/ALS/AI actions can grow
              // with scores and must wrap instead of overflowing narrow cards.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _fileBadge('MP3', beat.mp3Path, beat),
                  _fileBadge('WAV', beat.wavPath, beat),
                  _fileBadge('TRACK', beat.trackoutPath, beat),
                  _quickAudioActions(beat),
                  if (beat.attachments.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            size: 15, color: AppTheme.textMuted),
                        const SizedBox(width: 3),
                        Text('${beat.attachments.length}',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 9)),
                      ],
                    ),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _fileBadge(String label, String? path, BeatEntry beat) {
    final exists = path != null && File(path).existsSync();
    return InkWell(
      onTap: exists
          ? () => AudioVaultService.sharePath(path,
              subject: '${beat.title} — $label')
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: exists
              ? AppTheme.accentGreen.withOpacity(.11)
              : AppTheme.background.withOpacity(.32),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: exists
                  ? AppTheme.accentGreen.withOpacity(.3)
                  : AppTheme.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: exists ? AppTheme.accentGreen : AppTheme.textMuted)),
      ),
    );
  }

  Future<(BeatExtendedMeta, AudioAnalysisReport?)> _quickAudioState(
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
          final wavExists =
              beat.wavPath != null && File(beat.wavPath!).existsSync();
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

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(.25))),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
      );

  Widget _player() => ValueListenableBuilder<AudioPlayerState>(
        valueListenable: AudioPlayerService.state,
        builder: (context, state, _) {
          final beat = state.beat;
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
              children: [
                Row(children: [
                  Expanded(
                      child: Text(beat?.title ?? 'Ничего не играет',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900))),
                  DropdownButton<VisualizerMode>(
                    value: _visualizer,
                    dropdownColor: AppTheme.surface,
                    items: VisualizerMode.values
                        .map((v) => DropdownMenuItem(
                            value: v, child: Text(_visualizerName(v))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _visualizer = v ?? VisualizerMode.water),
                  ),
                ]),
                const SizedBox(height: 12),
                AudioVisualizer(
                    mode: _visualizer,
                    height:
                        MediaQuery.sizeOf(context).height < 700 ? 270 : 380),
                const SizedBox(height: 14),
                _fullPlayerControls(state),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: VisualizerMode.values
                      .map((v) => ChoiceChip(
                          selected: _visualizer == v,
                          onSelected: (_) => setState(() => _visualizer = v),
                          label: Text(_visualizerName(v))))
                      .toList(),
                ),
              ]);
        },
      );

  Widget _fullPlayerControls(AudioPlayerState state) {
    final total = state.duration.inMilliseconds;
    final progress = total <= 0
        ? 0.0
        : (state.position.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder)),
      child: Column(children: [
        Slider(
            value: progress,
            onChanged: total <= 0
                ? null
                : (v) => AudioPlayerService.seek(
                    Duration(milliseconds: (total * v).round()))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: AudioPlayerService.previous,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 34),
          IconButton(
              onPressed: AudioPlayerService.toggle,
              icon: Icon(
                  state.playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: AppTheme.accent),
              iconSize: 54),
          IconButton(
              onPressed: AudioPlayerService.next,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 34),
          const SizedBox(width: 18),
          const Icon(Icons.volume_down_rounded, size: 18),
          SizedBox(
              width: 150,
              child: Slider(
                  value: state.volume,
                  onChanged: AudioPlayerService.setVolume)),
        ]),
      ]),
    );
  }

  Future<void> _createBeat() async {
    final result = await _BeatEditorV2.show(context);
    if (result == null) return;
    await AudioVaultService.save(result);
    if (mounted) setState(() {});
  }

  Future<void> _openBeat(BeatEntry beat) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _BeatDetailsV2(beatId: beat.id)));
    if (mounted) setState(() {});
  }

  String _stageName(BeatStage s) => switch (s) {
        BeatStage.idea => 'Идея',
        BeatStage.draft => 'Черновик',
        BeatStage.production => 'Продакшн',
        BeatStage.mixing => 'Сведение',
        BeatStage.mastering => 'Мастеринг',
        BeatStage.ready => 'Готов',
        BeatStage.negotiating => 'Переговоры',
        BeatStage.leased => 'Аренда',
        BeatStage.sold => 'Продан',
        BeatStage.exclusive => 'Эксклюзив',
        BeatStage.archived => 'Архив'
      };
  Color _stageColor(BeatStage s) => switch (s) {
        BeatStage.ready => AppTheme.accentGreen,
        BeatStage.negotiating => Colors.orange,
        BeatStage.leased => Colors.amber,
        BeatStage.sold || BeatStage.exclusive => Colors.purpleAccent,
        BeatStage.archived => AppTheme.textMuted,
        _ => AppTheme.accent
      };
  String _visualizerName(VisualizerMode v) => switch (v) {
        VisualizerMode.water => 'Water Tank',
        VisualizerMode.membrane => 'Мембрана',
        VisualizerMode.spectrum => 'Спектр',
        VisualizerMode.particles => 'Частицы',
        VisualizerMode.tunnel => 'Тоннель',
        VisualizerMode.aurora => 'Аврора',
        VisualizerMode.orbit => 'Орбиты',
        VisualizerMode.pulseGrid => 'Pulse Grid'
      };
}

class _BeatEditorV2 extends StatefulWidget {
  final BeatEntry? initial;
  const _BeatEditorV2({this.initial});

  static Future<BeatEntry?> show(BuildContext context, {BeatEntry? initial}) =>
      showDialog<BeatEntry>(
          context: context, builder: (_) => _BeatEditorV2(initial: initial));

  @override
  State<_BeatEditorV2> createState() => _BeatEditorV2State();
}

class _BeatEditorV2State extends State<_BeatEditorV2> {
  late final TextEditingController title;
  late final TextEditingController bpm;
  late final TextEditingController key;
  late final TextEditingController genre;
  late final TextEditingController mood;
  late final TextEditingController tags;
  late final TextEditingController notes;
  String? authorId;
  late BeatStage stage;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    title = TextEditingController(text: b?.title ?? '');
    bpm =
        TextEditingController(text: b == null || b.bpm == 0 ? '' : '${b.bpm}');
    key = TextEditingController(text: b?.musicalKey ?? '');
    genre = TextEditingController(text: b?.genre ?? '');
    mood = TextEditingController(text: b?.mood ?? '');
    tags = TextEditingController(text: b?.tags.join(', ') ?? '');
    notes = TextEditingController(text: b?.notes ?? '');
    authorId = b?.authorEmployeeId ?? TeamService.current?.id;
    stage = b?.stage ?? BeatStage.draft;
  }

  @override
  void dispose() {
    title.dispose();
    bpm.dispose();
    key.dispose();
    genre.dispose();
    mood.dispose();
    tags.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(widget.initial == null ? 'Новый бит' : 'Редактировать бит'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(children: [
            _field(title, 'Название'),
            const SizedBox(height: 10),
            EmployeeOrCustomField(
              label: 'Ответственный / автор',
              value: authorId,
              storeEmployeeId: true,
              allowCustom: false,
              allowEmpty: false,
              onChanged: (value) => setState(() => authorId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<BeatStage>(
              value: stage,
              dropdownColor: AppTheme.surface,
              decoration: const InputDecoration(labelText: 'Стадия'),
              items: BeatStage.values
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(_stageRu(s))))
                  .toList(),
              onChanged: (v) => setState(() => stage = v ?? stage),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(bpm, 'BPM', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(key, 'Тональность')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(genre, 'Жанр')),
              const SizedBox(width: 10),
              Expanded(child: _field(mood, 'Настроение')),
            ]),
            const SizedBox(height: 10),
            _field(tags, 'Теги через запятую'),
            const SizedBox(height: 10),
            TextField(
                controller: notes,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                    labelText: 'Заметки', alignLabelWithHint: true)),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: title.text.trim().isEmpty ? null : _save,
            child: Text(widget.initial == null ? 'Создать' : 'Сохранить')),
      ],
    );
  }

  void _save() {
    final tagList = tags.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final initial = widget.initial;
    if (initial == null) {
      final now = DateTime.now();
      Navigator.pop(
        context,
        BeatEntry(
          id: now.microsecondsSinceEpoch.toString(),
          title: title.text.trim(),
          authorEmployeeId: authorId ?? TeamService.current?.id ?? 'owner',
          bpm: int.tryParse(bpm.text.trim()) ?? 0,
          musicalKey: key.text.trim(),
          genre: genre.text.trim(),
          mood: mood.text.trim(),
          tags: tagList,
          notes: notes.text.trim(),
          stage: stage,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      Navigator.pop(
        context,
        initial.copyWith(
          title: title.text.trim(),
          authorEmployeeId: authorId ?? initial.authorEmployeeId,
          bpm: int.tryParse(bpm.text.trim()) ?? 0,
          musicalKey: key.text.trim(),
          genre: genre.text.trim(),
          mood: mood.text.trim(),
          tags: tagList,
          notes: notes.text.trim(),
          stage: stage,
        ),
      );
    }
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      );

  String _stageRu(BeatStage s) => switch (s) {
        BeatStage.idea => 'Идея',
        BeatStage.draft => 'Черновик',
        BeatStage.production => 'Продакшн',
        BeatStage.mixing => 'Сведение',
        BeatStage.mastering => 'Мастеринг',
        BeatStage.ready => 'Готов',
        BeatStage.negotiating => 'Переговоры',
        BeatStage.leased => 'Аренда',
        BeatStage.sold => 'Продан',
        BeatStage.exclusive => 'Эксклюзив',
        BeatStage.archived => 'Архив'
      };
}

class _BeatDetailsV2 extends StatefulWidget {
  final String beatId;
  const _BeatDetailsV2({required this.beatId});

  @override
  State<_BeatDetailsV2> createState() => _BeatDetailsV2State();
}

class _BeatDetailsV2State extends State<_BeatDetailsV2> {
  BeatEntry? beat;
  final comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    beat = await AudioVaultService.byId(widget.beatId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = beat;
    if (b == null) {
      return Scaffold(
          backgroundColor: AppTheme.background,
          body: const Center(child: CircularProgressIndicator()));
    }
    final author = TeamService.byId(b.authorEmployeeId)?.displayName ?? '—';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(b.title),
        actions: [
          IconButton(
              onPressed: () => _edit(b),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать'),
          IconButton(
              onPressed: () => _delete(b),
              icon: Icon(Icons.delete_outline, color: AppTheme.accentRed)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
        children: [
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 800;
            final cover = _cover(b);
            final info = _info(b, author);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 340, child: cover),
                    const SizedBox(width: 16),
                    Expanded(child: info)
                  ])
                : Column(children: [cover, const SizedBox(height: 14), info]);
          }),
          const SizedBox(height: 16),
          _files(b),
          const SizedBox(height: 16),
          AbletonProjectPanel(beatId: b.id),
          const SizedBox(height: 16),
          AudioAnalysisPanel(beat: b),
          const SizedBox(height: 16),
          _lease(b),
          const SizedBox(height: 16),
          _documents(b),
          const SizedBox(height: 16),
          _comments(b),
        ],
      ),
    );
  }

  Widget _cover(BeatEntry b) => AspectRatio(
        aspectRatio: 1,
        child: InkWell(
          onTap: () => _importCore(b, BeatFileKind.cover),
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: b.coverPath != null && File(b.coverPath!).existsSync()
                ? Image.file(File(b.coverPath!), fit: BoxFit.cover)
                : Container(
                    color: AppTheme.surface,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 54, color: AppTheme.accent),
                          const SizedBox(height: 8),
                          Text('Добавить обложку',
                              style: TextStyle(color: AppTheme.textMuted)),
                        ]),
                  ),
          ),
        ),
      );

  Widget _info(BeatEntry b, String author) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.glassBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(b.title,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900))),
            IconButton(
                onPressed: () => _edit(b),
                icon: const Icon(Icons.edit_outlined)),
          ]),
          Text('Автор: $author', style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(_stageRu(b.stage)),
            if (b.bpm > 0) _chip('${b.bpm} BPM'),
            if (b.musicalKey.isNotEmpty) _chip(b.musicalKey),
            if (b.genre.isNotEmpty) _chip(b.genre),
            if (b.mood.isNotEmpty) _chip(b.mood),
            ...b.tags.map(_chip),
          ]),
          if (b.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(b.notes,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.45)),
          ],
        ]),
      );

  Widget _chip(String text) => Chip(label: Text(text));

  Widget _files(BeatEntry b) => _section(
        'Файлы мастера',
        Icons.folder_copy_outlined,
        Column(children: [
          _fileRow(b, 'MP3', BeatFileKind.mp3, b.mp3Path),
          _fileRow(b, 'WAV', BeatFileKind.wav, b.wavPath),
          _fileRow(b, 'Track out', BeatFileKind.trackout, b.trackoutPath),
        ]),
      );

  Widget _fileRow(BeatEntry b, String title, BeatFileKind kind, String? path) {
    final exists = path != null && File(path).existsSync();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(exists ? Icons.check_circle : Icons.upload_file,
          color: exists ? AppTheme.accentGreen : AppTheme.textMuted),
      title: Text(title),
      subtitle: Text(
          exists
              ? File(path).path.split(Platform.pathSeparator).last
              : 'Не загружен',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: exists ? 'Заменить' : 'Загрузить',
            onPressed: () => _importCore(b, kind),
            icon: const Icon(Icons.upload_rounded)),
        if (exists)
          IconButton(
              tooltip: 'Достать / отправить',
              onPressed: () => AudioVaultService.sharePath(path,
                  subject: '${b.title} — $title'),
              icon: Icon(Icons.ios_share, color: AppTheme.accent)),
      ]),
    );
  }

  Widget _lease(BeatEntry b) {
    final l = b.lease;
    return _section(
      'Сделка / аренда',
      Icons.handshake_outlined,
      l == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                  onPressed: () => _editLease(b),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить аренду / сделку')))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(l.artistName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16))),
                LeaseCountdown(lease: l),
              ]),
              if (l.socialUrl.isNotEmpty)
                TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(l.socialUrl),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.link),
                    label: Text(l.socialUrl)),
              Text('Срок: ${_date(l.startsAt)} → ${_date(l.endsAt)}'),
              if (l.amount > 0)
                Text('Сумма: ${l.amount.toStringAsFixed(0)} ${l.currency}'),
              if (l.notes.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(l.notes)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () => _editLease(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Продлить / изменить')),
                OutlinedButton.icon(
                    onPressed: () => HorizonContractDialog.show(context, b),
                    icon: const Icon(Icons.query_stats),
                    label: const Text('Horizon: ожидания денег')),
                TextButton.icon(
                  onPressed: () async {
                    beat = await AudioVaultService.clearLease(b);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Закрыть аренду'),
                ),
              ]),
            ]),
    );
  }

  Widget _documents(BeatEntry b) => _section(
        'Документы и вложения',
        Icons.description_outlined,
        Column(children: [
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                  onPressed: () => _addAttachment(b),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Прикрепить документ / договор'))),
          for (final a in b.attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(a.name),
              subtitle: Text(_bytes(a.bytes)),
              trailing: IconButton(
                  onPressed: () => AudioVaultService.sharePath(a.path,
                      subject: '${b.title} — ${a.name}'),
                  icon: const Icon(Icons.ios_share)),
            ),
        ]),
      );

  Widget _comments(BeatEntry b) => _section(
        'Комментарии / история',
        Icons.forum_outlined,
        Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: comment,
                    decoration: const InputDecoration(
                        hintText:
                            'Например: договор отправлен, ждём ответ артиста…'))),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () async {
                beat = await AudioVaultService.addComment(b, comment.text);
                comment.clear();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.send),
            ),
          ]),
          const SizedBox(height: 10),
          for (final c in b.comments.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                  child: Icon(Icons.person_outline, size: 17)),
              title: Text(c.text),
              subtitle: Text(
                  '${TeamService.byId(c.authorId)?.displayName ?? 'WesiOS'} · ${_dateTime(c.createdAt)}'),
            ),
        ]),
      );

  Widget _section(String title, IconData icon, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.glassBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppTheme.accent),
            const SizedBox(width: 9),
            Text(title,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15))
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Future<void> _edit(BeatEntry b) async {
    final updated = await _BeatEditorV2.show(context, initial: b);
    if (updated == null) return;
    await AudioVaultService.save(updated);
    beat = updated;
    if (mounted) setState(() {});
  }

  Future<void> _importCore(BeatEntry b, BeatFileKind kind) async {
    final path =
        await AudioVaultService.importSingleFile(beatId: b.id, kind: kind);
    if (path == null) return;
    beat = switch (kind) {
      BeatFileKind.mp3 => b.copyWith(mp3Path: path),
      BeatFileKind.wav => b.copyWith(wavPath: path),
      BeatFileKind.trackout => b.copyWith(trackoutPath: path),
      BeatFileKind.cover => b.copyWith(coverPath: path),
      _ => b,
    };
    await AudioVaultService.save(beat!);
    if (mounted) setState(() {});
  }

  Future<void> _addAttachment(BeatEntry b) async {
    final file = await AudioVaultService.importAttachment(
        beatId: b.id, kind: BeatFileKind.document);
    if (file == null) return;
    beat = b.copyWith(attachments: [...b.attachments, file]);
    await AudioVaultService.save(beat!);
    if (mounted) setState(() {});
  }

  Future<void> _editLease(BeatEntry b) async {
    final l = await _LeaseDialogV2.show(context, b.lease);
    if (l == null) return;
    beat = await AudioVaultService.setLease(b, l, createCalendarReminder: true);
    if (mounted) setState(() {});
  }

  Future<void> _delete(BeatEntry b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить бит?'),
        content: Text(
            '«${b.title}» и его локальные копии файлов Audio Vault будут удалены. Ableton project по исходному пути не удаляется.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await AudioVaultService.delete(b);
      if (mounted) Navigator.pop(context);
    }
  }

  String _stageRu(BeatStage s) => switch (s) {
        BeatStage.idea => 'Идея',
        BeatStage.draft => 'Черновик',
        BeatStage.production => 'Продакшн',
        BeatStage.mixing => 'Сведение',
        BeatStage.mastering => 'Мастеринг',
        BeatStage.ready => 'Готов',
        BeatStage.negotiating => 'Переговоры',
        BeatStage.leased => 'Аренда',
        BeatStage.sold => 'Продан',
        BeatStage.exclusive => 'Эксклюзив',
        BeatStage.archived => 'Архив'
      };
  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  String _dateTime(DateTime d) =>
      '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _bytes(int n) => n > 1024 * 1024
      ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(n / 1024).toStringAsFixed(0)} KB';
}

class _LeaseDialogV2 extends StatefulWidget {
  final BeatLease? initial;
  const _LeaseDialogV2(this.initial);

  static Future<BeatLease?> show(BuildContext context, BeatLease? initial) =>
      showDialog<BeatLease>(
          context: context, builder: (_) => _LeaseDialogV2(initial));

  @override
  State<_LeaseDialogV2> createState() => _LeaseDialogV2State();
}

class _LeaseDialogV2State extends State<_LeaseDialogV2> {
  late final TextEditingController artist;
  late final TextEditingController social;
  late final TextEditingController amount;
  late final TextEditingController notes;
  late DateTime start;
  late DateTime end;

  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    artist = TextEditingController(text: l?.artistName ?? '');
    social = TextEditingController(text: l?.socialUrl ?? '');
    amount = TextEditingController(
        text: l == null || l.amount == 0 ? '' : l.amount.toStringAsFixed(0));
    notes = TextEditingController(text: l?.notes ?? '');
    start = l?.startsAt ?? DateTime.now();
    end = l?.endsAt ?? DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    artist.dispose();
    social.dispose();
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Аренда / сделка'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(children: [
              TextField(
                  controller: artist,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Исполнитель / покупатель')),
              const SizedBox(height: 10),
              TextField(
                  controller: social,
                  decoration:
                      const InputDecoration(labelText: 'Ссылка на соцсеть')),
              const SizedBox(height: 10),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Сумма, RUB')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: ListTile(
                        title: const Text('Начало'),
                        subtitle: Text(_d(start)),
                        onTap: () => _pick(true))),
                Expanded(
                    child: ListTile(
                        title: const Text('Окончание / продление'),
                        subtitle: Text(_d(end)),
                        onTap: () => _pick(false))),
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(labelText: 'Комментарий к сделке')),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.calendar_month, color: AppTheme.accent),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text(
                        'Дата окончания автоматически синхронизируется с Tasks/Calendar. При продлении дедлайн обновится.',
                        style: TextStyle(fontSize: 11))),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: artist.text.trim().isEmpty
                ? null
                : () {
                    final now = DateTime.now();
                    Navigator.pop(
                      context,
                      BeatLease(
                        id: widget.initial?.id ??
                            now.microsecondsSinceEpoch.toString(),
                        artistName: artist.text.trim(),
                        socialUrl: social.text.trim(),
                        startsAt: start,
                        endsAt: end,
                        amount:
                            double.tryParse(amount.text.replaceAll(',', '.')) ??
                                0,
                        currency: 'RUB',
                        notes: notes.text.trim(),
                        reminderTaskId: widget.initial?.reminderTaskId,
                      ),
                    );
                  },
            child: const Text('Сохранить'),
          ),
        ],
      );

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? start : end;
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked != null) {
      setState(() {
        if (isStart) {
          start = picked;
          if (end.isBefore(start)) end = start.add(const Duration(days: 30));
        } else {
          end = picked;
        }
      });
    }
  }

  String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
