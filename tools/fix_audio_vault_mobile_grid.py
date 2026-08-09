from pathlib import Path

path = Path('lib/features/audio/audio_vault_v2_screen.dart')
text = path.read_text(encoding='utf-8')

if 'audioVaultSingleColumnMobile' not in text:
    old = '''              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .92,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _beatCard(beats[i], beats),
                    childCount: beats.length,
                  ),
                ),
              ),'''
    new = '''              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                sliver: SliverLayoutBuilder(
                  // audioVaultSingleColumnMobile: a 360px phone must not be
                  // split into two ~158px beat cards. Desktop keeps the dense
                  // multi-column archive, mobile gets one readable card.
                  builder: (context, constraints) {
                    final narrow = constraints.crossAxisExtent < 600;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent:
                            narrow ? constraints.crossAxisExtent : 280,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: narrow ? 1.02 : .92,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _beatCard(beats[i], beats),
                        childCount: beats.length,
                      ),
                    );
                  },
                ),
              ),'''
    if text.count(old) != 1:
        raise SystemExit(f'Audio Vault grid anchor count={text.count(old)}')
    text = text.replace(old, new, 1)
    print('Audio Vault single-column mobile grid applied.')
else:
    print('Audio Vault mobile grid already present.')

if 'audioVaultFooterWrap' not in text:
    old = '''              Row(children: [
                _fileBadge('MP3', beat.mp3Path, beat),
                const SizedBox(width: 6),
                _fileBadge('WAV', beat.wavPath, beat),
                const SizedBox(width: 6),
                _fileBadge('TRACK', beat.trackoutPath, beat),
                const SizedBox(width: 6),
                _quickAudioActions(beat),
                const Spacer(),
                if (beat.attachments.isNotEmpty) ...[
                  Icon(Icons.description_outlined,
                      size: 15, color: AppTheme.textMuted),
                  const SizedBox(width: 3),
                  Text('${beat.attachments.length}',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                ],
              ]),'''
    new = '''              // audioVaultFooterWrap: file/ALS/AI actions can grow
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
              ),'''
    if text.count(old) != 1:
        raise SystemExit(f'Audio Vault footer anchor count={text.count(old)}')
    text = text.replace(old, new, 1)
    print('Audio Vault responsive footer wrap applied.')
else:
    print('Audio Vault footer wrap already present.')

path.write_text(text, encoding='utf-8')
