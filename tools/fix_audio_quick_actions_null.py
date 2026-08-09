from pathlib import Path

path = Path('lib/features/audio/audio_vault_v2_screen.dart')
text = path.read_text(encoding='utf-8')
old1 = 'final abletonExists = hasAbleton && File(abletonPath).existsSync();'
new1 = 'final abletonExists = hasAbleton && File(abletonPath!).existsSync();'
old2 = 'onTap: () => _openAbletonQuick(abletonPath),'
new2 = 'onTap: () => _openAbletonQuick(abletonPath!),'

if old1 in text:
    text = text.replace(old1, new1, 1)
elif new1 not in text:
    raise SystemExit('Ableton exists null-safety anchor not found')

if old2 in text:
    text = text.replace(old2, new2, 1)
elif new2 not in text:
    raise SystemExit('Ableton open null-safety anchor not found')

path.write_text(text, encoding='utf-8')
print('Audio Vault quick action null-safety fixed.')
