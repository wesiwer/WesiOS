from pathlib import Path

RICH = Path('lib/features/ai/widgets/wesi_ai_rich_message.dart')
NIRVANA = Path('docs/wesi_ai/personas/NIRVANA_PERSONA.md')
ZANE = Path('docs/wesi_ai/personas/ZANE_PERSONA.md')
UX = Path('docs/WESI_AI_CHAT_UX.md')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one marker, found {count}')
    return text.replace(old, new, 1)


rich = RICH.read_text()
rich = replace_once(rich, "import '../models/wesi_ai_activity.dart';\n", "import '../models/wesi_ai_activity.dart';\nimport 'wesi_ai_visualization.dart';\n", 'visual import')
rich = replace_once(rich, 'enum WesiAiRichBlockKind { text, code, quote, draft, clarification }', 'enum WesiAiRichBlockKind { text, code, quote, draft, clarification, table, chart }', 'rich block enum')
old_fence = """        final lower = language.toLowerCase();
        final draft = const <String>{
          'text',
          'message',
          'email',
          'draft',
          'quote',
          'letter'
        }.contains(lower);
        final kind = lower == 'question'
            ? WesiAiRichBlockKind.clarification
            : draft
                ? WesiAiRichBlockKind.draft
                : WesiAiRichBlockKind.code;
"""
new_fence = """        final lower = language.toLowerCase();
        final draft = const <String>{
          'text',
          'message',
          'email',
          'draft',
          'quote',
          'letter'
        }.contains(lower);
        final kind = lower == 'question'
            ? WesiAiRichBlockKind.clarification
            : const <String>{'chart', 'wesi-chart', 'wesi_chart'}.contains(lower)
                ? WesiAiRichBlockKind.chart
                : draft
                    ? WesiAiRichBlockKind.draft
                    : WesiAiRichBlockKind.code;
"""
rich = replace_once(rich, old_fence, new_fence, 'chart fence kind')
marker = "      if (line.trimLeft().startsWith('>')) {\n"
table_logic = """      if (line.contains('|') && index + 1 < lines.length) {
        final tableLines = <String>[line, lines[index + 1]];
        var scan = index + 2;
        while (scan < lines.length && lines[scan].contains('|')) {
          tableLines.add(lines[scan]);
          scan++;
        }
        final parsedTable = WesiAiTableData.tryParseMarkdown(tableLines);
        if (parsedTable != null) {
          flushText();
          blocks.add(WesiAiRichBlock(
            WesiAiRichBlockKind.table,
            tableLines.take(2 + parsedTable.rows.length).join('\\n'),
          ));
          index += 2 + parsedTable.rows.length;
          continue;
        }
      }
""" + marker
rich = replace_once(rich, marker, table_logic, 'markdown table parser')
old_switch = """        case WesiAiRichBlockKind.clarification:
          final question = WesiAiClarification.tryParse(block.text);
          if (question == null) {
            widgets.add(
                WesiAiCodeBlock(code: block.text, language: block.language));
          } else {
            widgets.add(WesiAiClarificationBlock(
              question: question,
              onAnswer: onQuickReply,
            ));
          }
          break;
"""
new_switch = old_switch + """        case WesiAiRichBlockKind.table:
          final table = WesiAiTableData.tryParseMarkdown(block.text.split('\\n'));
          if (table == null) {
            widgets.add(WesiAiFormattedText(text: block.text));
          } else {
            widgets.add(WesiAiTableBlock(table: table));
          }
          break;
        case WesiAiRichBlockKind.chart:
          final chart = WesiAiChartSpec.tryParse(block.text);
          if (chart == null) {
            widgets.add(WesiAiCodeBlock(code: block.text, language: block.language));
          } else {
            widgets.add(WesiAiChartBlock(spec: chart));
          }
          break;
"""
rich = replace_once(rich, old_switch, new_switch, 'visual render cases')
RICH.write_text(rich)

nirvana = NIRVANA.read_text()
nirvana = nirvana.replace('> Абсолютно никогда не матерится. Всегда всех любит и уважает.', '> В обычной речи не матерится. Исключение — профессиональная творческая задача (например, рэп, песенный текст, художественный диалог или роль), когда пользователь прямо просит соответствующую лексику и без неё теряется замысел. Перед таким текстом Нирвана может один раз мягко отметить, что сама такой стиль не одобряет, после чего выполняет творческую задачу без дальнейшего морализаторства. Всегда всех любит и уважает.')
nirvana = nirvana.replace('- Ты НИКОГДА не материшься. Всегда искренне любишь и уважаешь людей.', '- В обычной речи ты не материшься и не делаешь мат частью собственного повседневного голоса. ПРОФЕССИОНАЛЬНОЕ ТВОРЧЕСКОЕ ИСКЛЮЧЕНИЕ: если пользователь прямо просит рэп/песню/художественный текст/диалог/роль, где ненормативная лексика нужна для жанра или авторского замысла, ты можешь использовать её в самом создаваемом произведении. Перед произведением один раз кратко и без занудства отметь, что лично не одобряешь такой стиль, затем выполни задачу как профессионал. Не вставляй нравоучения внутрь текста и не смягчай лексику вопреки прямому творческому запросу. Всегда искренне любишь и уважаешь людей.')
nirvana = nirvana.replace('2. ПЕРЕКЛЮЧЕНИЕ: Если задача требует математики, кода, расчетов или если пользователь хочет специфического юмора/матов — мягко скажи, что с этим лучше справится Зейн, и предложи переключиться на него. При согласии передай ему слово.', '2. ПЕРЕКЛЮЧЕНИЕ: Если задача требует математики, кода, расчетов или пользователь хочет именно грубый бытовой юмор/брань как стиль общения — мягко предложи Зейна. Но не переключайся только из-за мата внутри профессиональной творческой задачи: рэп, песня, художественный текст, диалог или роль остаются твоей естественной зоной, и для них действует творческое исключение выше.')
nirvana = nirvana.replace('- математика, код, расчёты и специфический юмор/мат — повод предложить Зейна;', '- математика, код, расчёты и грубый бытовой юмор/брань — повод предложить Зейна; мат внутри явно запрошенного рэпа, песни, художественного текста, диалога или роли не является причиной для handoff;')
nirvana = nirvana.replace('- заставлять Нирвану материться;', '- делать мат частью обычной речи Нирваны или заставлять её материться вне прямой профессиональной творческой задачи; творческое исключение для рэпа/песен/художественных текстов/диалогов является канонически разрешённым;')
visual_rule = """6. НАГЛЯДНОСТЬ: Когда структура данных важнее сплошного текста, используй Markdown-таблицу. Когда числовую зависимость, сравнение, доли или тренд заметно понятнее показать графиком, можешь вставить отдельный fenced-блок `wesi-chart` с JSON. Разрешены `type`: `bar`, `line`, `pie`, `scatter`. Для bar/line/pie используй `title`, необязательный `description`, `labels` и `series` вида [{\"name\":\"...\",\"values\":[1,2]}]. Для scatter используй `points` вида [{\"x\":1,\"y\":2,\"label\":\"...\"}]. Не помещай в chart spec HTML, JS, Flutter-код или команды; только данные для визуализации. Не строй график ради декора, если текст понятнее.\n"""
if visual_rule not in nirvana:
    needle = '5. УТОЧНЯЮЩИЕ ВОПРОСЫ:'
    pos = nirvana.find('\n\n```\n', nirvana.find(needle))
    if pos < 0: raise SystemExit('nirvana prompt end marker missing')
    nirvana = nirvana[:pos] + '\n' + visual_rule + nirvana[pos:]
NIRVANA.write_text(nirvana)

zane = ZANE.read_text()
if visual_rule not in zane:
    needle = 'УТОЧНЯЮЩИЕ ВОПРОСЫ'
    pos = zane.find('\n\n```\n', zane.find(needle))
    if pos < 0: raise SystemExit('zane prompt end marker missing')
    zane = zane[:pos] + '\n' + visual_rule + zane[pos:]
ZANE.write_text(zane)

ux = UX.read_text()
section = """## Таблицы и графики в ответах

- Markdown-таблицы рендерятся как отдельные горизонтально прокручиваемые таблицы с быстрым копированием TSV.
- Для числовых визуализаций поддерживается fenced-блок `wesi-chart` с bounded JSON-spec и типами `bar`, `line`, `pie`, `scatter`.
- Chart renderer не исполняет JS/HTML/Flutter-код; malformed или oversized spec fail-closed показывается как обычный code block.
- Визуализация хранится прямо в тексте сообщения, поэтому сохраняется в истории, архиве и ветках без отдельного серверного состояния.
"""
if '## Таблицы и графики в ответах' not in ux:
    ux = ux.rstrip() + '\n\n' + section + '\n'
UX.write_text(ux)
