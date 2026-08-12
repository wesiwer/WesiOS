from pathlib import Path

p = Path('lib/features/tasks/ai/widgets/wesi_ai_suggestions_panel.dart')
s = p.read_text(encoding='utf-8')

s = s.replace(
    "return 'Учитываю историю работы, ваши решения, роли, загрузку, отдых и Wesi Horizon.';",
    "return 'Учитываю бизнес-цепочку, узкие места, историю, ваши решения, загрузку и Wesi Horizon.';",
)
s = s.replace(
    "return 'Учитываю историю работы, ваши решения, роли, загрузку и отдых. Финансы недоступны этому профилю.';",
    "return 'Учитываю бизнес-цепочку, узкие места, историю, ваши решения и загрузку. Финансы недоступны этому профилю.';",
)

old_height = "height: compact ? 248 : 236,"
if old_height in s:
    s = s.replace(old_height, "height: compact ? 282 : 270,")

anchor = """          Text(
            suggestion.whyNow,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          ),
          const SizedBox(height: 7),"""
replacement = """          Text(
            suggestion.whyNow,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          ),
          if (suggestion.strategicReason.isNotEmpty) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_tree_outlined,
                      size: 13, color: AppTheme.accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      suggestion.strategicReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${(suggestion.strategicScore * 100).round()}%',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 7),"""
if anchor not in s:
    raise SystemExit('strategic UI anchor not found')
s = s.replace(anchor, replacement)

p.write_text(s, encoding='utf-8')
print('Wesi AI strategy v3 UI patch applied')
