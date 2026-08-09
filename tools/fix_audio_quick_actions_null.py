from pathlib import Path

path = Path('lib/features/audio/audio_vault_v2_screen.dart')
text = path.read_text(encoding='utf-8')

pairs = [
    (
        'final abletonExists = hasAbleton && File(abletonPath!).existsSync();',
        'final abletonExists = hasAbleton && File(abletonPath).existsSync();',
    ),
    (
        'onTap: () => _openAbletonQuick(abletonPath!),',
        'onTap: () => _openAbletonQuick(abletonPath),',
    ),
]

for old, new in pairs:
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit(f'Ableton promotion anchor not found: {new}')

path.write_text(text, encoding='utf-8')
print('Audio Vault quick actions use Dart flow-promoted Ableton path.')
