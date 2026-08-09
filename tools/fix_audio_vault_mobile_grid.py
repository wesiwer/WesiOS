from pathlib import Path

path = Path('lib/features/audio/audio_vault_v2_screen.dart')
text = path.read_text(encoding='utf-8')

# The current archive already has the correct responsive grid:
# 4/3/2 columns on wide screens and exactly 1 column below 560 px.
# Do not replace it with the obsolete MaxCrossAxisExtent implementation.
if 'final columns = c.maxWidth >= 1200' not in text or 'c.maxWidth >= 560' not in text:
    raise SystemExit('Current responsive Audio Vault grid markers not found')
print('Audio Vault grid already mobile-safe (1 column below 560 px).')

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
