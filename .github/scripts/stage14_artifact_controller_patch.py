from pathlib import Path

path = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
text = path.read_text()

old_text = "? 'Локальная генерация $label завершена. Файл сохранён: ${result.outputPath}'"
new_text = "? 'Локальная генерация $label завершена. Файл сохранён в WesiOS.'"
if text.count(old_text) != 1:
    raise SystemExit(f'artifact message marker count={text.count(old_text)}')
text = text.replace(old_text, new_text, 1)

old_metadata = """              if (result.outputPath != null) 'localPath': result.outputPath,
              if (result.mimeType != null) 'mimeType': result.mimeType,
"""
new_metadata = """              if (result.outputPath != null) 'localPath': result.outputPath,
              if (result.mimeType != null) 'mimeType': result.mimeType,
              if (result.byteSize != null) 'byteSize': result.byteSize,
              if (result.sha256Hex != null) 'sha256': result.sha256Hex,
              'artifactOwned': result.ok && result.outputPath != null,
"""
if text.count(old_metadata) != 1:
    raise SystemExit(f'artifact metadata marker count={text.count(old_metadata)}')
text = text.replace(old_metadata, new_metadata, 1)
path.write_text(text)
