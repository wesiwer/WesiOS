from pathlib import Path

path = Path('lib/features/home/home_screen.dart')
text = path.read_text(encoding='utf-8')
if 'compactHeader' in text and 'showText: !compactHeader' in text:
    print('Compact Home header already present.')
    raise SystemExit(0)

old = '''                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: WesiContextMenu(
                            title: 'WesiOS',
                            description: WesiLocale.isRussian
                                ? 'WesiOS — Business Operating System. Управляйте бизнесом по-новому.'
                                : 'WesiOS — Business Operating System. Manage your business in a new way.',
                            purpose: WesiLocale.isRussian
                                ? 'Центральная панель управления всеми системами Wesi'
                                : 'Central dashboard for all Wesi systems',
                            children: [
                              WesiWordmark(size: 26),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _HoverIconButton(
                              icon: Icons.search,
                              onTap: () => GlobalSearchSheet.show(context),
                            ),
                            const SizedBox(width: 6),
                            if (_isDesktop) ...[
                              Tooltip(
                                message: WesiLocale.isRussian
                                    ? 'Синхронизировать сейчас'
                                    : 'Sync now',
                                child: _HoverIconButton(
                                  icon: _syncing
                                      ? Icons.sync_disabled
                                      : Icons.sync,
                                  onTap: _syncNow,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const AlertsBell(size: 28),
                            const SizedBox(width: 6),
                            const _ProfileDropdown(),
                          ],
                        ),
                      ],
                    ),'''
new = '''                    LayoutBuilder(
                      builder: (context, headerConstraints) {
                        // На телефоне после горизонтальных padding остаётся
                        // около 328 px. Полный wordmark + search + alerts +
                        // avatar физически не помещаются в одну строку.
                        // Сам знак W сохраняем всегда, текст скрываем только
                        // при действительно узкой шапке.
                        final compactHeader = headerConstraints.maxWidth < 360;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: WesiContextMenu(
                                title: 'WesiOS',
                                description: WesiLocale.isRussian
                                    ? 'WesiOS — Business Operating System. Управляйте бизнесом по-новому.'
                                    : 'WesiOS — Business Operating System. Manage your business in a new way.',
                                purpose: WesiLocale.isRussian
                                    ? 'Центральная панель управления всеми системами Wesi'
                                    : 'Central dashboard for all Wesi systems',
                                children: [
                                  WesiWordmark(
                                    size: compactHeader ? 24 : 26,
                                    showText: !compactHeader,
                                    markFirst: true,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _HoverIconButton(
                                  icon: Icons.search,
                                  onTap: () => GlobalSearchSheet.show(context),
                                ),
                                const SizedBox(width: 6),
                                if (_isDesktop) ...[
                                  Tooltip(
                                    message: WesiLocale.isRussian
                                        ? 'Синхронизировать сейчас'
                                        : 'Sync now',
                                    child: _HoverIconButton(
                                      icon: _syncing
                                          ? Icons.sync_disabled
                                          : Icons.sync,
                                      onTap: _syncNow,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                const AlertsBell(size: 28),
                                const SizedBox(width: 6),
                                const _ProfileDropdown(),
                              ],
                            ),
                          ],
                        );
                      },
                    ),'''

count = text.count(old)
if count != 1:
    raise SystemExit(f'Expected one Home header anchor, got {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Compact Home header applied.')
