from pathlib import Path

path = Path('scripts/wesi_ai_chat_ux_once.py')
text = path.read_text(encoding='utf-8')

# One-shot guard: after the generated product slice is committed, later pushes
# on the temporary branch must not try to patch the same anchors again.
needle = "from pathlib import Path\n\n\n"
if "WESI_AI_CHAT_UX.md').exists()" not in text:
    text = text.replace(
        needle,
        "from pathlib import Path\n\n\nif Path('docs/WESI_AI_CHAT_UX.md').exists():\n    print('Wesi AI chat UX slice already generated')\n    raise SystemExit(0)\n\n\n",
        1,
    )

# The embedded Dart test itself uses triple single quotes, so the surrounding
# Python literal must use triple double quotes.
start = text.index("write('test/wesi_ai_rich_message_test.dart'")
docs = text.index("write('docs/WESI_AI_CHAT_UX.md'", start)
chunk = text[start:docs]
chunk = chunk.replace("r'''import 'package:flutter/material.dart';", "r\"\"\"import 'package:flutter/material.dart';", 1)
end = chunk.rfind("''')")
if end < 0:
    raise RuntimeError('test literal terminator not found')
chunk = chunk[:end] + '\"\"\")' + chunk[end + 4:]
text = text[:start] + chunk + text[docs:]

# These sections intentionally remove old code, so checking for the old marker
# would incorrectly skip the replacement on the first run.
text = text.replace("    marker='class WesiAiTypewriterText',\n)", "    marker=None,\n)", 1)
text = text.replace("    marker='safeReasoningSummary(message)',\n)", "    marker=None,\n)", 1)

# Use a marker produced by the new final-stream agent event, not the old done.
old_marker = "    marker=\"answer: finalStream.full,\\n        toolResults,\\n      });\\n      res.end();\",\n)"
new_marker = "    marker=\"const totalDiff = aggregateDiffStats(toolResults);\\n      writeNdjson(res, {\\n        type: 'agent',\",\n)"
text = text.replace(old_marker, new_marker, 1)

# SizedBox.height is double; num.clamp returns num.
text = text.replace(
    "final height = (size.height * 0.78).clamp(420.0, 720.0);",
    "final height = (size.height * 0.78).clamp(420.0, 720.0).toDouble();",
)

path.write_text(text, encoding='utf-8')
print('chat UX patcher repaired')
