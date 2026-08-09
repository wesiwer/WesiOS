from pathlib import Path

# HomeAgenda header: title/trailing/action must fit a 286px GlassCard body.
agenda_path = Path('lib/features/home/widgets/home_agenda.dart')
agenda = agenda_path.read_text(encoding='utf-8')
if 'homeAgendaCompactAction' not in agenda:
    old = '''    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            // Серый на светлой теме, читаемый secondary на тёмной —
            // не textPrimary (белый), иначе «белый на белом».
            color: AppTheme.textSecondary,
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (trailingIsAlert ? AppTheme.accentRed : AppTheme.accent)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color:
                    trailingIsAlert ? AppTheme.accentRed : AppTheme.accent,
              ),
            ),
          ),
        ],
        Spacer(),
        TextButton(
          onPressed: onAll,
          child: Text(WesiLocale.get('all'),
              style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    );'''
    new = '''    // homeAgendaCompactAction: keep title/badge/action inside a 286px
    // GlassCard body on 360px phones.
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (trailingIsAlert
                              ? AppTheme.accentRed
                              : AppTheme.accent)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trailingIsAlert
                            ? AppTheme.accentRed
                            : AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onAll,
          child: Text(
            WesiLocale.get('all'),
            style: TextStyle(color: AppTheme.accent),
          ),
        ),
      ],
    );'''
    if agenda.count(old) != 1:
        raise SystemExit(f'HomeAgenda header anchor count={agenda.count(old)}')
    agenda = agenda.replace(old, new, 1)
    agenda_path.write_text(agenda, encoding='utf-8')
    print('HomeAgenda responsive header applied.')
else:
    print('HomeAgenda responsive header already present.')

# AppUpdateCard: long version/size labels plus Skip should wrap instead of overflow.
update_path = Path('lib/core/widgets/app_update_card.dart')
update = update_path.read_text(encoding='utf-8')
if 'updateActionWrap' not in update:
    old = '''          return Row(
            children: [
              _button(
                ru
                    ? 'Обновить${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}'
                    : 'Update${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}',
                _install,
              ),
              if (!widget.compact) ...[
                SizedBox(width: 8),
                TextButton(
                  onPressed: () => _skip(release.version),
                  child: Text(
                    ru ? 'Пропустить' : 'Skip',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ],
            ],
          );'''
    new = '''          // updateActionWrap: long version/size labels must wrap on phones.
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _button(
                ru
                    ? 'Обновить${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}'
                    : 'Update${release!.sizeBytes != null ? ' · ${_size(release.sizeBytes)}' : ''}',
                _install,
              ),
              if (!widget.compact)
                TextButton(
                  onPressed: () => _skip(release.version),
                  child: Text(
                    ru ? 'Пропустить' : 'Skip',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
            ],
          );'''
    if update.count(old) != 1:
        raise SystemExit(f'AppUpdate action anchor count={update.count(old)}')
    update = update.replace(old, new, 1)
    update_path.write_text(update, encoding='utf-8')
    print('AppUpdate responsive action wrap applied.')
else:
    print('AppUpdate responsive action wrap already present.')
