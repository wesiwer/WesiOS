from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

test = ROOT / 'test/wesi_job_queue_test.dart'
text = test.read_text(encoding='utf-8')
old = "'x' * (WesiDurableJobQueue.maxJournalBytes + 1)"
new = "List<String>.filled(WesiDurableJobQueue.maxJournalBytes + 1, 'x').join()"
if old in text:
    text = text.replace(old, new, 1)
if "'x' * (WesiDurableJobQueue.maxJournalBytes + 1)" in text:
    raise SystemExit('unsupported Dart string multiplication remains')
test.write_text(text, encoding='utf-8')

print('Stage 8 one-shot validation fix applied')
