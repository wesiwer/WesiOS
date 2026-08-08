import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../team/services/team_service.dart';
import 'models/audio_vault_models.dart';
import 'services/audio_player_service.dart';
import 'services/audio_vault_service.dart';
import 'widgets/audio_visualizer.dart';

class AudioVaultScreen extends StatefulWidget {
  const AudioVaultScreen({super.key});

  @override
  State<AudioVaultScreen> createState() => _AudioVaultScreenState();
}

class _AudioVaultScreenState extends State<AudioVaultScreen> {
  final _search = TextEditingController();
  int _tab = 0;
  BeatStage? _stage;
  String _sort = 'updated';
  bool _favoritesOnly = false;
  VisualizerMode _visualizer = VisualizerMode.water;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    AudioVaultService.revision.addListener(_refresh);
    TeamService.revision.addListener(_refresh);
    AudioPlayerService.initialize();
  }

  @override
  void dispose() {
    AudioVaultService.revision.removeListener(_refresh);
    TeamService.revision.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<List<BeatEntry>> _beats() async {
    var list = await AudioVaultService.all();
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((b) {
        final author = TeamService.byId(b.authorEmployeeId)?.displayName ?? '';
        return [b.title, b.genre, b.mood, b.musicalKey, b.tags.join(' '), author]
            .join(' ')
            .toLowerCase()
            .contains(q);
      }).toList();
    }
    if (_stage != null) list = list.where((b) => b.stage == _stage).toList();
    if (_favoritesOnly) list = list.where((b) => b.favorite).toList();
    switch (_sort) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'bpm':
        list.sort((a, b) => a.bpm.compareTo(b.bpm));
      case 'created':
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
          if (_tab == 0)
            IconButton(
              tooltip: _ru ? 'Добавить бит' : 'Add beat',
              onPressed: _createBeat,
              icon: Icon(Icons.add_circle_outline, color: AppTheme.accent),
            ),
        ],
      ),
      body: Column(
        children: [
          _tabs(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [_archive(), _player(), _musicHub()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final tabs = [
      (_ru ? 'Архив' : 'Archive', Icons.archive_outlined),
      (_ru ? 'Плеер' : 'Player', Icons.graphic_eq),
      (_ru ? 'Музыка' : 'Music', Icons.library_music_outlined),
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
                color: selected ? AppTheme.accent.withOpacity(.15) : AppTheme.surface.withOpacity(.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? AppTheme.accent.withOpacity(.5) : AppTheme.glassBorder),
              ),
              child: Row(children: [
                Icon(tabs[i].$2, size: 17, color: selected ? AppTheme.accent : AppTheme.textMuted),
                const SizedBox(width: 7),
                Text(tabs[i].$1, style: TextStyle(color: selected ? AppTheme.textPrimary : AppTheme.textMuted, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _archive() {
    return FutureBuilder<List<BeatEntry>>(
      future: _beats(),
      builder: (context, snapshot) {
        final beats = snapshot.data ?? const <BeatEntry>[];
        return Column(children: [
          _filterBar(),
          Expanded(
            child: beats.isEmpty
                ? _emptyArchive()
                : LayoutBuilder(builder: (context, c) {
                    final columns = c.maxWidth >= 1200 ? 4 : c.maxWidth >= 850 ? 3 : c.maxWidth >= 560 ? 2 : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: columns == 1 ? 1.85 : 1.12),
                      itemCount: beats.length,
                      itemBuilder: (_, i) => _beatCard(beats[i], beats),
                    );
                  }),
          ),
        ]);
      },
    );
  }

  Widget _filterBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(hintText: _ru ? 'Название, жанр, автор, тег…' : 'Title, genre, author, tag…', prefixIcon: Icon(Icons.search, size: 19, color: AppTheme.textMuted), filled: true, fillColor: AppTheme.surface.withOpacity(.45), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          DropdownButton<BeatStage?>(
            value: _stage,
            dropdownColor: AppTheme.surface,
            hint: Text(_ru ? 'Все стадии' : 'All stages', style: TextStyle(color: AppTheme.textMuted)),
            items: [DropdownMenuItem(value: null, child: Text(_ru ? 'Все стадии' : 'All stages')), ...BeatStage.values.map((s) => DropdownMenuItem(value: s, child: Text(_stageName(s))))],
            onChanged: (v) => setState(() => _stage = v),
          ),
          DropdownButton<String>(
            value: _sort,
            dropdownColor: AppTheme.surface,
            items: [DropdownMenuItem(value: 'updated', child: Text(_ru ? 'Недавно изменённые' : 'Recently updated')), DropdownMenuItem(value: 'created', child: Text(_ru ? 'Новые' : 'Newest')), DropdownMenuItem(value: 'title', child: Text(_ru ? 'По названию' : 'Title')), const DropdownMenuItem(value: 'bpm', child: Text('BPM'))],
            onChanged: (v) => setState(() => _sort = v ?? 'updated'),
          ),
          FilterChip(selected: _favoritesOnly, label: Text(_ru ? 'Избранное' : 'Favorites'), avatar: const Icon(Icons.star_outline, size: 16), onSelected: (v) => setState(() => _favoritesOnly = v)),
        ]),
      );

  Widget _emptyArchive() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.album_outlined, size: 54, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(_ru ? 'Архив битов пуст' : 'Beat archive is empty', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(_ru ? 'Добавь первый бит — MP3/WAV/Trackout можно прикрепить сразу.' : 'Add your first beat and attach MP3/WAV/Trackout.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _createBeat, icon: const Icon(Icons.add), label: Text(_ru ? 'Добавить бит' : 'Add beat')),
        ]),
      );

  Widget _beatCard(BeatEntry beat, List<BeatEntry> queue) {
    final author = TeamService.byId(beat.authorEmployeeId)?.displayName ?? (_ru ? 'Не указан' : 'Unknown');
    final hasCover = beat.coverPath != null && File(beat.coverPath!).existsSync();
    return InkWell(
      onTap: () => _openBeat(beat),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.55), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.glassBorder)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              hasCover ? Image.file(File(beat.coverPath!), fit: BoxFit.cover) : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.accent.withOpacity(.35), AppTheme.background])), child: Icon(Icons.graphic_eq, size: 56, color: AppTheme.accent.withOpacity(.75))),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(.72)])))),
              Positioned(right: 8, top: 8, child: IconButton.filledTonal(onPressed: () => AudioVaultService.save(beat.copyWith(favorite: !beat.favorite)), icon: Icon(beat.favorite ? Icons.star : Icons.star_border, color: beat.favorite ? Colors.amber : AppTheme.textPrimary))),
              if (beat.playablePath != null) Center(child: IconButton.filled(onPressed: () async { await AudioPlayerService.playBeat(beat, queue: queue); if (mounted) setState(() => _tab = 1); }, icon: const Icon(Icons.play_arrow_rounded, size: 34))),
              Positioned(left: 12, right: 12, bottom: 10, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(beat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)), Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 11))])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(children: [
              Row(children: [_pill(_stageName(beat.stage), _stageColor(beat.stage)), if (beat.bpm > 0) ...[const SizedBox(width: 6), _pill('${beat.bpm} BPM', AppTheme.accent)], if (beat.musicalKey.isNotEmpty) ...[const SizedBox(width: 6), _pill(beat.musicalKey, AppTheme.textMuted)]]),
              const SizedBox(height: 9),
              Row(children: [_fileBadge('MP3', beat.mp3Path, beat), const SizedBox(width: 6), _fileBadge('WAV', beat.wavPath, beat), const SizedBox(width: 6), _fileBadge('TRACK', beat.trackoutPath, beat), const Spacer(), if (beat.lease != null) Icon(Icons.timer_outlined, size: 18, color: AppTheme.accent)]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _fileBadge(String label, String? path, BeatEntry beat) {
    final exists = path != null && File(path).existsSync();
    return InkWell(
      onTap: exists ? () => AudioVaultService.sharePath(path, subject: '${beat.title} — $label') : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: exists ? AppTheme.accentGreen.withOpacity(.11) : AppTheme.background.withOpacity(.32), borderRadius: BorderRadius.circular(8), border: Border.all(color: exists ? AppTheme.accentGreen.withOpacity(.3) : AppTheme.glassBorder)), child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: exists ? AppTheme.accentGreen : AppTheme.textMuted))),
    );
  }

  Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.25))), child: Text(text, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800)));

  Widget _player() => ValueListenableBuilder<AudioPlayerState>(
        valueListenable: AudioPlayerService.state,
        builder: (context, state, _) {
          final beat = state.beat;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
            Row(children: [Expanded(child: Text(beat?.title ?? (_ru ? 'Ничего не играет' : 'Nothing playing'), style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w900))), DropdownButton<VisualizerMode>(value: _visualizer, dropdownColor: AppTheme.surface, items: VisualizerMode.values.map((v) => DropdownMenuItem(value: v, child: Text(_visualizerName(v)))).toList(), onChanged: (v) => setState(() => _visualizer = v ?? VisualizerMode.water))]),
            const SizedBox(height: 12),
            AudioVisualizer(mode: _visualizer, height: MediaQuery.sizeOf(context).height < 700 ? 270 : 380),
            const SizedBox(height: 14),
            _fullPlayerControls(state),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: VisualizerMode.values.map((v) => ChoiceChip(selected: _visualizer == v, onSelected: (_) => setState(() => _visualizer = v), label: Text(_visualizerName(v)))).toList()),
          ]);
        },
      );

  Widget _fullPlayerControls(AudioPlayerState state) {
    final total = state.duration.inMilliseconds;
    final progress = total <= 0 ? 0.0 : (state.position.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.48), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.glassBorder)),
      child: Column(children: [
        Slider(value: progress, onChanged: total <= 0 ? null : (v) => AudioPlayerService.seek(Duration(milliseconds: (total * v).round()))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: AudioPlayerService.previous, icon: const Icon(Icons.skip_previous_rounded), iconSize: 34),
          IconButton(onPressed: AudioPlayerService.toggle, icon: Icon(state.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: AppTheme.accent), iconSize: 54),
          IconButton(onPressed: AudioPlayerService.next, icon: const Icon(Icons.skip_next_rounded), iconSize: 34),
          const SizedBox(width: 18),
          const Icon(Icons.volume_down_rounded, size: 18),
          SizedBox(width: 150, child: Slider(value: state.volume, onChanged: AudioPlayerService.setVolume)),
        ]),
      ]),
    );
  }

  Widget _musicHub() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        children: [
          Text('Music Hub', style: TextStyle(color: AppTheme.textPrimary, fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(_ru ? 'Фоновая музыка не смешивается с архивом битов. Плеер продолжит работать на других экранах WesiOS.' : 'Background music stays separate from your beat archive and keeps playing across WesiOS.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          _hubTile(icon: Icons.folder_open, title: _ru ? 'Открыть скачанный трек' : 'Open downloaded track', subtitle: _ru ? 'MP3 / WAV / OGG / FLAC с устройства' : 'MP3 / WAV / OGG / FLAC from this device', onTap: _openLooseTrack),
          const SizedBox(height: 10),
          _hubTile(icon: Icons.sensors, title: 'Spotify Connect', subtitle: _ru ? 'Открыть Spotify сейчас; внутреннее управление подключается после OAuth Spotify.' : 'Open Spotify now; in-app transport controls require Spotify OAuth.', onTap: _openSpotify),
          const SizedBox(height: 18),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.glassBorder)), child: Row(children: [Icon(Icons.info_outline, color: AppTheme.accent), const SizedBox(width: 10), Expanded(child: Text(_ru ? 'Spotify не отдаёт защищённый аудиопоток стороннему плееру. Для управления прямо из WesiOS будет использоваться Spotify Web API/Connect после привязки аккаунта.' : 'Spotify does not expose its protected stream to third-party players. In-app controls will use Spotify Web API/Connect after account linking.', style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4)))])),
        ],
      );

  Widget _hubTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.52), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.glassBorder)), child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: AppTheme.accent.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppTheme.accent)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: TextStyle(color: AppTheme.textMuted, fontSize: 11))])), Icon(Icons.chevron_right, color: AppTheme.textMuted)])));

  Future<void> _openLooseTrack() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'wav', 'ogg', 'flac']);
    final path = result?.files.single.path;
    if (path == null) return;
    final name = result!.files.single.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final now = DateTime.now();
    final temp = BeatEntry(id: 'music-${now.microsecondsSinceEpoch}', title: name, authorEmployeeId: TeamService.current?.id ?? 'owner', mp3Path: path, stage: BeatStage.ready, createdAt: now, updatedAt: now);
    await AudioPlayerService.playBeat(temp, queue: [temp]);
    if (mounted) setState(() => _tab = 1);
  }

  Future<void> _openSpotify() async {
    final uri = Uri.parse('spotify:');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(Uri.parse('https://open.spotify.com'), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _createBeat() async {
    final result = await _BeatEditor.show(context);
    if (result == null) return;
    await AudioVaultService.save(result);
    if (mounted) setState(() {});
  }

  Future<void> _openBeat(BeatEntry beat) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _BeatDetailsScreen(beatId: beat.id)));
    if (mounted) setState(() {});
  }

  String _stageName(BeatStage s) => switch (s) { BeatStage.idea => _ru ? 'Идея' : 'Idea', BeatStage.draft => _ru ? 'Черновик' : 'Draft', BeatStage.production => _ru ? 'Продакшн' : 'Production', BeatStage.mixing => _ru ? 'Сведение' : 'Mixing', BeatStage.mastering => _ru ? 'Мастеринг' : 'Mastering', BeatStage.ready => _ru ? 'Готов' : 'Ready', BeatStage.negotiating => _ru ? 'Переговоры' : 'Negotiating', BeatStage.leased => _ru ? 'Аренда' : 'Leased', BeatStage.sold => _ru ? 'Продан' : 'Sold', BeatStage.exclusive => _ru ? 'Эксклюзив' : 'Exclusive', BeatStage.archived => _ru ? 'Архив' : 'Archived' };
  Color _stageColor(BeatStage s) => switch (s) { BeatStage.ready => AppTheme.accentGreen, BeatStage.negotiating => Colors.orange, BeatStage.leased => Colors.amber, BeatStage.sold || BeatStage.exclusive => Colors.purpleAccent, BeatStage.archived => AppTheme.textMuted, _ => AppTheme.accent };
  String _visualizerName(VisualizerMode v) => switch (v) { VisualizerMode.water => 'Water Tank', VisualizerMode.membrane => _ru ? 'Мембрана' : 'Membrane', VisualizerMode.spectrum => _ru ? 'Спектр' : 'Spectrum', VisualizerMode.particles => _ru ? 'Частицы' : 'Particles', VisualizerMode.tunnel => _ru ? 'Тоннель' : 'Tunnel', VisualizerMode.aurora => _ru ? 'Аврора' : 'Aurora', VisualizerMode.orbit => _ru ? 'Орбиты' : 'Orbit', VisualizerMode.pulseGrid => 'Pulse Grid' };
}

class _BeatEditor extends StatefulWidget {
  const _BeatEditor();
  static Future<BeatEntry?> show(BuildContext context) => showDialog<BeatEntry>(context: context, builder: (_) => const _BeatEditor());
  @override
  State<_BeatEditor> createState() => _BeatEditorState();
}

class _BeatEditorState extends State<_BeatEditor> {
  final title = TextEditingController();
  final bpm = TextEditingController();
  final key = TextEditingController();
  final genre = TextEditingController();
  final mood = TextEditingController();
  String? authorId;

  @override
  void initState() { super.initState(); authorId = TeamService.current?.id; }

  @override
  Widget build(BuildContext context) {
    final employees = TeamService.all;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Новый бит'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(children: [
        _field(title, 'Название'), const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: authorId, dropdownColor: AppTheme.surface, decoration: const InputDecoration(labelText: 'Автор'), items: employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))).toList(), onChanged: (v) => setState(() => authorId = v)),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: _field(bpm, 'BPM', number: true)), const SizedBox(width: 10), Expanded(child: _field(key, 'Тональность'))]), const SizedBox(height: 10),
        Row(children: [Expanded(child: _field(genre, 'Жанр')), const SizedBox(width: 10), Expanded(child: _field(mood, 'Настроение'))]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: title.text.trim().isEmpty ? null : () { final now = DateTime.now(); Navigator.pop(context, BeatEntry(id: now.microsecondsSinceEpoch.toString(), title: title.text.trim(), authorEmployeeId: authorId ?? TeamService.current?.id ?? 'owner', bpm: int.tryParse(bpm.text.trim()) ?? 0, musicalKey: key.text.trim(), genre: genre.text.trim(), mood: mood.text.trim(), stage: BeatStage.draft, createdAt: now, updatedAt: now)); }, child: const Text('Создать'))],
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) => TextField(controller: c, keyboardType: number ? TextInputType.number : null, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: label));
}

class _BeatDetailsScreen extends StatefulWidget {
  final String beatId;
  const _BeatDetailsScreen({required this.beatId});
  @override
  State<_BeatDetailsScreen> createState() => _BeatDetailsScreenState();
}

class _BeatDetailsScreenState extends State<_BeatDetailsScreen> {
  BeatEntry? beat;
  final comment = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { beat = await AudioVaultService.byId(widget.beatId); if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final b = beat;
    if (b == null) return Scaffold(backgroundColor: AppTheme.background, body: const Center(child: CircularProgressIndicator()));
    final author = TeamService.byId(b.authorEmployeeId)?.displayName ?? '—';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: AppTheme.background, title: Text(b.title), actions: [IconButton(onPressed: () => _delete(b), icon: Icon(Icons.delete_outline, color: AppTheme.accentRed))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
        LayoutBuilder(builder: (context, c) { final wide = c.maxWidth > 800; final cover = _cover(b); final info = _info(b, author); return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 340, child: cover), const SizedBox(width: 16), Expanded(child: info)]) : Column(children: [cover, const SizedBox(height: 14), info]); }),
        const SizedBox(height: 16), _files(b), const SizedBox(height: 16), _lease(b), const SizedBox(height: 16), _documents(b), const SizedBox(height: 16), _comments(b),
      ]),
    );
  }

  Widget _cover(BeatEntry b) => AspectRatio(aspectRatio: 1, child: InkWell(onTap: () => _importCore(b, BeatFileKind.cover), borderRadius: BorderRadius.circular(20), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: b.coverPath != null && File(b.coverPath!).existsSync() ? Image.file(File(b.coverPath!), fit: BoxFit.cover) : Container(color: AppTheme.surface, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, size: 54, color: AppTheme.accent), const SizedBox(height: 8), Text('Добавить обложку', style: TextStyle(color: AppTheme.textMuted))])))));

  Widget _info(BeatEntry b, String author) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.5), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.glassBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text('Автор: $author', style: TextStyle(color: AppTheme.textMuted)), const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [if (b.bpm > 0) _chip('${b.bpm} BPM'), if (b.musicalKey.isNotEmpty) _chip(b.musicalKey), if (b.genre.isNotEmpty) _chip(b.genre), if (b.mood.isNotEmpty) _chip(b.mood)]), const SizedBox(height: 14),
          DropdownButtonFormField<BeatStage>(value: b.stage, dropdownColor: AppTheme.surface, decoration: const InputDecoration(labelText: 'Стадия'), items: BeatStage.values.map((s) => DropdownMenuItem(value: s, child: Text(_stageRu(s)))).toList(), onChanged: (s) async { if (s != null) { beat = b.copyWith(stage: s); await AudioVaultService.save(beat!); if (mounted) setState(() {}); } }), const SizedBox(height: 14),
          TextFormField(initialValue: b.notes, minLines: 3, maxLines: 7, decoration: const InputDecoration(labelText: 'Заметки по биту', alignLabelWithHint: true), onFieldSubmitted: (v) async { beat = b.copyWith(notes: v); await AudioVaultService.save(beat!); }),
        ]),
      );

  Widget _chip(String text) => Chip(label: Text(text));
  Widget _files(BeatEntry b) => _section('Файлы мастера', Icons.folder_copy_outlined, Column(children: [_fileRow(b, 'MP3', BeatFileKind.mp3, b.mp3Path), _fileRow(b, 'WAV', BeatFileKind.wav, b.wavPath), _fileRow(b, 'Track out', BeatFileKind.trackout, b.trackoutPath)]));

  Widget _fileRow(BeatEntry b, String title, BeatFileKind kind, String? path) {
    final exists = path != null && File(path).existsSync();
    return ListTile(contentPadding: EdgeInsets.zero, leading: Icon(exists ? Icons.check_circle : Icons.upload_file, color: exists ? AppTheme.accentGreen : AppTheme.textMuted), title: Text(title), subtitle: Text(exists ? File(path).path.split(Platform.pathSeparator).last : 'Не загружен', maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: exists ? 'Заменить' : 'Загрузить', onPressed: () => _importCore(b, kind), icon: const Icon(Icons.upload_rounded)), if (exists) IconButton(tooltip: 'Достать / отправить', onPressed: () => AudioVaultService.sharePath(path, subject: '${b.title} — $title'), icon: Icon(Icons.ios_share, color: AppTheme.accent))]));
  }

  Widget _lease(BeatEntry b) {
    final l = b.lease;
    return _section('Сделка / аренда', Icons.handshake_outlined, l == null
        ? Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => _editLease(b), icon: const Icon(Icons.add), label: const Text('Добавить аренду / сделку')))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l.artistName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), if (l.socialUrl.isNotEmpty) TextButton.icon(onPressed: () => launchUrl(Uri.parse(l.socialUrl), mode: LaunchMode.externalApplication), icon: const Icon(Icons.link), label: Text(l.socialUrl)), Text('Срок: ${_date(l.startsAt)} → ${_date(l.endsAt)}'), if (l.amount > 0) Text('Сумма: ${l.amount.toStringAsFixed(0)} ${l.currency}'), if (l.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.notes)), const SizedBox(height: 8), Row(children: [OutlinedButton.icon(onPressed: () => _editLease(b), icon: const Icon(Icons.edit_outlined), label: const Text('Изменить')), const SizedBox(width: 8), TextButton.icon(onPressed: () async { beat = await AudioVaultService.clearLease(b); if (mounted) setState(() {}); }, icon: const Icon(Icons.close), label: const Text('Закрыть аренду'))]) ]));
  }

  Widget _documents(BeatEntry b) => _section('Документы и вложения', Icons.description_outlined, Column(children: [Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _addAttachment(b), icon: const Icon(Icons.attach_file), label: const Text('Прикрепить документ / договор'))), for (final a in b.attachments) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.insert_drive_file_outlined), title: Text(a.name), subtitle: Text(_bytes(a.bytes)), trailing: IconButton(onPressed: () => AudioVaultService.sharePath(a.path, subject: '${b.title} — ${a.name}'), icon: const Icon(Icons.ios_share)))]));

  Widget _comments(BeatEntry b) => _section('Комментарии / история', Icons.forum_outlined, Column(children: [Row(children: [Expanded(child: TextField(controller: comment, decoration: const InputDecoration(hintText: 'Например: Иван арендовал до 15 сентября…'))), const SizedBox(width: 8), IconButton.filled(onPressed: () async { beat = await AudioVaultService.addComment(b, comment.text); comment.clear(); if (mounted) setState(() {}); }, icon: const Icon(Icons.send))]), const SizedBox(height: 10), for (final c in b.comments.reversed) ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.person_outline, size: 17)), title: Text(c.text), subtitle: Text('${TeamService.byId(c.authorId)?.displayName ?? 'WesiOS'} · ${_dateTime(c.createdAt)}'))]));

  Widget _section(String title, IconData icon, Widget child) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.surface.withOpacity(.45), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.glassBorder)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: AppTheme.accent), const SizedBox(width: 9), Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15))]), const SizedBox(height: 12), child]));

  Future<void> _importCore(BeatEntry b, BeatFileKind kind) async {
    final path = await AudioVaultService.importSingleFile(beatId: b.id, kind: kind);
    if (path == null) return;
    beat = switch (kind) { BeatFileKind.mp3 => b.copyWith(mp3Path: path), BeatFileKind.wav => b.copyWith(wavPath: path), BeatFileKind.trackout => b.copyWith(trackoutPath: path), BeatFileKind.cover => b.copyWith(coverPath: path), _ => b };
    await AudioVaultService.save(beat!);
    if (mounted) setState(() {});
  }

  Future<void> _addAttachment(BeatEntry b) async { final file = await AudioVaultService.importAttachment(beatId: b.id, kind: BeatFileKind.document); if (file == null) return; beat = b.copyWith(attachments: [...b.attachments, file]); await AudioVaultService.save(beat!); if (mounted) setState(() {}); }
  Future<void> _editLease(BeatEntry b) async { final l = await _LeaseDialog.show(context, b.lease); if (l == null) return; beat = await AudioVaultService.setLease(b, l, createCalendarReminder: true); if (mounted) setState(() {}); }
  Future<void> _delete(BeatEntry b) async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Удалить бит?'), content: Text('«${b.title}» и его локальные файлы будут удалены из Audio Vault.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))])); if (ok == true) { await AudioVaultService.delete(b); if (mounted) Navigator.pop(context); } }

  String _stageRu(BeatStage s) => switch (s) { BeatStage.idea => 'Идея', BeatStage.draft => 'Черновик', BeatStage.production => 'Продакшн', BeatStage.mixing => 'Сведение', BeatStage.mastering => 'Мастеринг', BeatStage.ready => 'Готов', BeatStage.negotiating => 'Переговоры', BeatStage.leased => 'Аренда', BeatStage.sold => 'Продан', BeatStage.exclusive => 'Эксклюзив', BeatStage.archived => 'Архив' };
  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  String _dateTime(DateTime d) => '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _bytes(int n) => n > 1024 * 1024 ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB' : '${(n / 1024).toStringAsFixed(0)} KB';
}

class _LeaseDialog extends StatefulWidget {
  final BeatLease? initial;
  const _LeaseDialog(this.initial);
  static Future<BeatLease?> show(BuildContext context, BeatLease? initial) => showDialog<BeatLease>(context: context, builder: (_) => _LeaseDialog(initial));
  @override
  State<_LeaseDialog> createState() => _LeaseDialogState();
}

class _LeaseDialogState extends State<_LeaseDialog> {
  late final TextEditingController artist;
  late final TextEditingController social;
  late final TextEditingController amount;
  late final TextEditingController notes;
  late DateTime start;
  late DateTime end;

  @override
  void initState() { super.initState(); final l = widget.initial; artist = TextEditingController(text: l?.artistName ?? ''); social = TextEditingController(text: l?.socialUrl ?? ''); amount = TextEditingController(text: l == null || l.amount == 0 ? '' : l.amount.toStringAsFixed(0)); notes = TextEditingController(text: l?.notes ?? ''); start = l?.startsAt ?? DateTime.now(); end = l?.endsAt ?? DateTime.now().add(const Duration(days: 30)); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Аренда / сделка'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(children: [
          TextField(controller: artist, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Исполнитель / покупатель')), const SizedBox(height: 10),
          TextField(controller: social, decoration: const InputDecoration(labelText: 'Ссылка на соцсеть')), const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Сумма, RUB')), const SizedBox(height: 10),
          Row(children: [Expanded(child: ListTile(title: const Text('Начало'), subtitle: Text(_d(start)), onTap: () => _pick(true))), Expanded(child: ListTile(title: const Text('Окончание / продление'), subtitle: Text(_d(end)), onTap: () => _pick(false)))]), const SizedBox(height: 10),
          TextField(controller: notes, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Комментарий к сделке')), const SizedBox(height: 8),
          Row(children: [Icon(Icons.calendar_month, color: AppTheme.accent), const SizedBox(width: 8), const Expanded(child: Text('На дату окончания автоматически будет создано напоминание в Tasks и календаре.', style: TextStyle(fontSize: 11)))]),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: artist.text.trim().isEmpty ? null : () { final now = DateTime.now(); Navigator.pop(context, BeatLease(id: widget.initial?.id ?? now.microsecondsSinceEpoch.toString(), artistName: artist.text.trim(), socialUrl: social.text.trim(), startsAt: start, endsAt: end, amount: double.tryParse(amount.text.replaceAll(',', '.')) ?? 0, currency: 'RUB', notes: notes.text.trim(), reminderTaskId: widget.initial?.reminderTaskId)); }, child: const Text('Сохранить'))],
      );

  Future<void> _pick(bool isStart) async { final initial = isStart ? start : end; final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) setState(() { if (isStart) { start = picked; } else { end = picked; } }); }
  String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
