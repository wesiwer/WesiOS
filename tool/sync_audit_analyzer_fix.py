from pathlib import Path

# AudioBeatsSync lives in sync_codec_files.dart and is not re-exported by
# sync_codec.dart. Import its defining library explicitly before subclassing it.
p = Path('lib/core/sync/sync_audit_extensions.dart')
text = p.read_text()
needle = "import 'sync_codec.dart';\n"
extra = "import 'sync_codec.dart';\nimport 'sync_codec_files.dart';\n"
if "import 'sync_codec_files.dart';" not in text:
    if text.count(needle) != 1:
        raise SystemExit('sync_audit_extensions.dart: sync codec import mismatch')
    p.write_text(text.replace(needle, extra, 1))

# WesiAiApi gained thinkingMode in the current API. Test doubles must preserve
# that named argument or analyzer rejects the override before tests can run.
for filename, expected in [
    ('test/wesi_ai_memory_engine_test.dart', 1),
    ('test/wesi_ai_queue_hardening_test.dart', 3),
]:
    p = Path(filename)
    text = p.read_text()
    if 'bool thinkingMode = false,' in text:
        continue
    needle = (
        "    Map<String, dynamic> taskState = const <String, dynamic>{},\n"
        "    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],\n"
    )
    replacement = (
        "    Map<String, dynamic> taskState = const <String, dynamic>{},\n"
        "    bool thinkingMode = false,\n"
        "    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],\n"
    )
    count = text.count(needle)
    if count != expected:
        raise SystemExit(f'{filename}: expected {expected} WesiAiApi signatures, got {count}')
    p.write_text(text.replace(needle, replacement))
