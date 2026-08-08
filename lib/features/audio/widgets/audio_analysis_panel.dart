import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/audio_vault_extended_models.dart';
import '../models/audio_vault_models.dart';
import '../services/audio_analysis_service.dart';
import '../services/audio_vault_extras_service.dart';

class AudioAnalysisPanel extends StatefulWidget {
  final BeatEntry beat;
  const AudioAnalysisPanel({super.key, required this.beat});

  @override
  State<AudioAnalysisPanel> createState() => _AudioAnalysisPanelState();
}

class _AudioAnalysisPanelState extends State<AudioAnalysisPanel> {
  AudioAnalysisReport? _report;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AudioAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beat.id != widget.beat.id ||
        oldWidget.beat.wavPath != widget.beat.wavPath) {
      _load();
    }
  }

  Future<void> _load() async {
    final meta = await AudioVaultExtrasService.metaFor(widget.beat.id);
    _report = meta.analysis;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
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
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.psychology_alt_outlined, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wesi AI Audio · Quick Analysis',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15)),
                  Text(
                    'Полностью локально: файл не покидает устройство.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: Text(report == null ? 'Анализировать' : 'Повторить'),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: AppTheme.accentRed, fontSize: 11.5)),
          ],
          if (report == null && !_busy) ...[
            const SizedBox(height: 12),
            Text(
              widget.beat.wavPath == null
                  ? 'Прикрепи WAV master — после этого анализ станет доступен.'
                  : 'Нажми «Анализировать»: проверю уровень, динамику, clipping, stereo/phase, спектр и streaming headroom.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 14),
            _score(report),
            const SizedBox(height: 12),
            _metrics(report),
            const SizedBox(height: 14),
            _spectrum(report),
            const SizedBox(height: 14),
            _platforms(report),
            const SizedBox(height: 14),
            _insights(report),
            const SizedBox(height: 10),
            Text(report.disclaimer,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _score(AudioAnalysisReport r) {
    final color = r.score >= 85
        ? AppTheme.accentGreen
        : r.score >= 65
            ? Colors.orange
            : AppTheme.accentRed;
    return Row(children: [
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 4),
          color: color.withOpacity(.08),
        ),
        child: Text('${r.score}',
            style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.w900)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            r.score >= 85
                ? 'Технически чисто'
                : r.score >= 65
                    ? 'Есть что поправить'
                    : 'Нужна проверка master chain',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            '${r.format} · ${r.sampleRate} Hz · ${r.bitDepth} bit · ${r.channels == 2 ? 'Stereo' : 'Mono'} · ${_duration(r.durationSeconds)}',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
          ),
        ]),
      ),
    ]);
  }

  Widget _metrics(AudioAnalysisReport r) {
    final metrics = <(String, String, String)>[
      ('LUFS est.', '${r.estimatedIntegratedLufs.toStringAsFixed(1)} LUFS', 'Средняя воспринимаемая громкость'),
      ('True Peak est.', '${r.estimatedTruePeakDbtp.toStringAsFixed(2)} dBTP', 'Риск inter-sample peaks'),
      ('Sample Peak', '${r.peakDbfs.toStringAsFixed(2)} dBFS', 'Максимальный цифровой пик'),
      ('RMS', '${r.rmsDbfs.toStringAsFixed(1)} dBFS', 'Средняя энергия'),
      ('Crest', '${r.crestFactorDb.toStringAsFixed(1)} dB', 'Punch / динамический запас'),
      ('Stereo corr.', r.stereoCorrelation.toStringAsFixed(2), 'Mono compatibility'),
      ('Clipped', '${r.clippedSamples}', 'Сэмплы у цифрового потолка'),
      ('DC offset', '${(r.dcOffset * 100).toStringAsFixed(3)}%', 'Смещение waveform относительно нуля'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth > 720 ? 4 : c.maxWidth > 420 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: metrics.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: columns == 1 ? 4.4 : 2.35,
        ),
        itemBuilder: (_, i) {
          final m = metrics[i];
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.background.withOpacity(.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.$1, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
              const Spacer(),
              Text(m.$2,
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 2),
              Text(m.$3, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 8.5)),
            ]),
          );
        },
      );
    });
  }

  Widget _spectrum(AudioAnalysisReport r) {
    final maxValue = r.spectralBalance.values.fold<double>(.0001, (a, b) => b > a ? b : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Спектральный баланс',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
      const SizedBox(height: 8),
      for (final e in r.spectralBalance.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 108, child: Text(e.key, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (e.value / maxValue).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: AppTheme.background,
                  color: AppTheme.accent.withOpacity(.85),
                ),
              ),
            ),
            SizedBox(width: 42, child: Text('${(e.value * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textSecondary, fontSize: 9.5))),
          ]),
        ),
    ]);
  }

  Widget _platforms(AudioAnalysisReport r) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Площадки / delivery',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 7),
          for (final p in r.platformChecks)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (p.ok ? AppTheme.accentGreen : Colors.orange).withOpacity(.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: (p.ok ? AppTheme.accentGreen : Colors.orange).withOpacity(.22)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(p.ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    size: 18, color: p.ok ? AppTheme.accentGreen : Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.platform, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(p.summary, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.7, height: 1.35)),
                ])),
              ]),
            ),
        ],
      );

  Widget _insights(AudioAnalysisReport r) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wesi AI Audio — замечания',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 7),
          for (final item in r.insights)
            _insight(item),
        ],
      );

  Widget _insight(AudioAiInsight item) {
    final color = switch (item.severity) {
      AudioIssueSeverity.critical => AppTheme.accentRed,
      AudioIssueSeverity.warning => Colors.orange,
      AudioIssueSeverity.info => AppTheme.accent,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 7),
          Expanded(child: Text(item.title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 11))),
        ]),
        const SizedBox(height: 4),
        Text(item.detail, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.8, height: 1.35)),
        if (item.action != null && item.action!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Что сделать: ${item.action!}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 9.8, height: 1.35)),
        ],
      ]),
    );
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _report = await AudioVaultExtrasService.analyzeBeat(widget.beat);
    } on AudioAnalysisException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Ошибка анализа: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _duration(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
