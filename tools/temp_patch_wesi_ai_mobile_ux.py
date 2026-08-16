from pathlib import Path
import re

screen = Path('lib/features/ai/ai_assistant_v2_screen.dart')
s = screen.read_text(encoding='utf-8')
a = s.index('  Widget _sidebar(WesiAiManagedChatController controller) {')
b = s.index('  Widget _sidebarUtilities(', a)
r = s[a:b]
r = r.replace(
    '    return Column(\n      children: [',
    '    return ListView(\n      padding: EdgeInsets.zero,\n      children: [',
    1,
)
r = r.replace(
    'constraints: const BoxConstraints(maxHeight: 220),',
    'constraints: const BoxConstraints(),',
    1,
)
r = r.replace(
    '          child: ListView(\n            shrinkWrap: true,',
    '          child: ListView(\n            shrinkWrap: true,\n            physics: const NeverScrollableScrollPhysics(),',
    1,
)
old = '        Expanded(\n          child: ListView(\n            padding: const EdgeInsets.symmetric(vertical: 6),'
new = '        ListView(\n          shrinkWrap: true,\n          physics: const NeverScrollableScrollPhysics(),\n          padding: const EdgeInsets.symmetric(vertical: 6),'
assert old in r, 'conversation list anchor missing'
r = r.replace(old, new, 1)
old = '            ],\n          ),\n        ),\n      ],\n    );\n  }\n\n'
new = '            ],\n          ),\n      ],\n    );\n  }\n\n'
assert old in r, 'sidebar tail anchor missing'
r = r.replace(old, new, 1)
s = s[:a] + r + s[b:]

pattern = re.compile(
    r'      final attachment = await showDialog<WesiAiAttachment>\(.*?      \);\n      if \(attachment == null',
    re.S,
)
replacement = '''      final attachment = await Navigator.of(context).push<WesiAiAttachment>(
        MaterialPageRoute<WesiAiAttachment>(
          fullscreenDialog: true,
          builder: (_) => const WesiAiCameraCaptureScreen(),
        ),
      );
      if (attachment == null'''
s, count = pattern.subn(replacement, s, count=1)
assert count == 1, 'camera route anchor missing'
screen.write_text(s, encoding='utf-8')

rich = Path('lib/features/ai/widgets/wesi_ai_rich_message.dart')
s = rich.read_text(encoding='utf-8')
old = """  static String displayMarkdown(String markdown) => markdown.replaceAllMapped(
        RegExp(r'^\\s{0,3}#{1,6}\\s+(.+)$', multiLine: true),
        (match) => '**${match.group(1)?.trim() ?? ''}**',
      );"""
new = r'''  static String displayMarkdown(String markdown) {
    var value = markdown.replaceAllMapped(
      RegExp(r'^\s{0,3}#{1,6}\s+(.+)$', multiLine: true),
      (match) => '**${match.group(1)?.trim() ?? ''}**',
    );
    const commands = <String, String>{
      r'\times': '×',
      r'\cdot': '·',
      r'\pm': '±',
      r'\leq': '≤',
      r'\geq': '≥',
      r'\neq': '≠',
      r'\approx': '≈',
      r'\infty': '∞',
      r'\pi': 'π',
      r'\alpha': 'α',
      r'\beta': 'β',
      r'\gamma': 'γ',
    };
    for (final entry in commands.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    value = value.replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]+)\}'),
      (m) => '√(${m.group(1) ?? ''})',
    );
    value = value.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
      (m) => '(${m.group(1) ?? ''})⁄(${m.group(2) ?? ''})',
    );
    value = _script(value, true);
    value = _script(value, false);
    return value
        .replaceAll(RegExp(r'(?<!\\)\$(.+?)(?<!\\)\$'), r'$1')
        .replaceAll(RegExp(r'\\\((.*?)\\\)'), r'$1')
        .replaceAll(RegExp(r'\\\[(.*?)\\\]'), r'$1');
  }

  static String _script(String value, bool superscript) {
    const sup = <String, String>{
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵',
      '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻',
      '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
    };
    const sub = <String, String>{
      '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅',
      '6': '₆', '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋',
      '=': '₌', '(': '₍', ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'i': 'ᵢ',
      'o': 'ₒ', 'r': 'ᵣ', 'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
    };
    final map = superscript ? sup : sub;
    final marker = superscript ? '^' : '_';
    return value.replaceAllMapped(
      RegExp('${RegExp.escape(marker)}(?:\\{([^{}]+)\\}|([0-9+\\-=()nieaoruvx]+))'),
      (match) {
        final raw = match.group(1) ?? match.group(2) ?? '';
        if (raw.isEmpty || raw.split('').any((c) => !map.containsKey(c))) {
          return match.group(0) ?? '';
        }
        return raw.split('').map((c) => map[c]!).join();
      },
    );
  }'''
assert old in s, 'markdown anchor missing'
s = s.replace(old, new, 1)
old = """                  label: Text(option),
                  onPressed: onAnswer == null ? null : () => onAnswer!(option),"""
new = """                  label: Text(_visibleOption(option)),
                  onPressed: onAnswer == null ? null : () => onAnswer!(option),"""
assert old in s, 'clarification chip anchor missing'
s = s.replace(old, new, 1)
anchor = '  Future<void> _customAnswer(BuildContext context) async {'
helper = r'''  String _visibleOption(String option) {
    final value = option.trim();
    if (value == 'org_wesi_inc') return 'Wesi Inc';
    if (value == 'org_wesi_beats') return 'Wesi Beats';
    if (value.startsWith('org_')) {
      final raw = value.substring(4);
      if (RegExp(r'^\d+$').hasMatch(raw)) {
        final suffix = raw.length <= 4 ? raw : raw.substring(raw.length - 4);
        return 'Организация ••••$suffix';
      }
      return raw
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');
    }
    return value;
  }

'''
assert anchor in s, 'clarification helper anchor missing'
s = s.replace(anchor, helper + anchor, 1)
rich.write_text(s, encoding='utf-8')
