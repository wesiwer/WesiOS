from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def sub_once(text, pattern, repl, label):
    next_text, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{label}: expected one replacement, got {count}')
    return next_text


# ---------------------------------------------------------------- Home header
path = 'lib/features/home/home_screen.dart'
text = read(path)
header = r'''          // Шапка: верхняя строка — логотип и действия; ниже полноширинные
          // часы с календарём. Никаких OverflowBox: ширина блока совпадает с
          // «зарядом мыслей» и карточкой цитаты на любом телефоне.
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                          children: const [
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
                  ),
                  const SizedBox(height: 14),
                  Tooltip(
                    message: WesiLocale.isRussian
                        ? 'Открыть календарь · долгий тап — стиль часов'
                        : 'Open calendar · long-press for clock style',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pushNamed(context, '/calendar'),
                      onLongPress: () {
                        final next = WesiClock.savedStyle == ClockStyle.digital
                            ? ClockStyle.analog
                            : ClockStyle.digital;
                        WesiClock.setStyle(next);
                        setState(() {});
                      },
                      child: const SizedBox(
                        width: double.infinity,
                        child: WesiClock(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
'''
text = sub_once(
    text,
    r"          // Шапка:.*?\n          // Заряд и цитата",
    header + "          // Заряд и цитата",
    'Home header',
)
write(path, text)


# --------------------------------------------------------------- Wesi clock
path = 'lib/core/widgets/wesi_clock.dart'
text = read(path)
new_build = r'''  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => LayoutBuilder(
        builder: (context, constraints) {
          final screenContentWidth =
              math.max(160.0, MediaQuery.sizeOf(context).width - 32);
          final available = constraints.hasBoundedWidth &&
                  constraints.maxWidth.isFinite
              ? math.min(constraints.maxWidth, screenContentWidth)
              : screenContentWidth;
          return _buildClockBody(math.max(160.0, available), available >= 300);
        },
      ),
    );
  }

'''
text = sub_once(
    text,
    r"  @override\n  Widget build\(BuildContext context\) \{.*?\n  Widget _buildClockBody",
    new_build + "  Widget _buildClockBody",
    'WesiClock build',
)
write(path, text)


# --------------------------------------------------------- Hive compatibility
path = 'lib/features/knowledge/models/article_model.dart'
text = read(path)
for old, new in [
    ('@HiveField(7)\n  final bool builtIn;', '@HiveField(7, defaultValue: false)\n  final bool builtIn;'),
    ('@HiveField(8)\n  final bool pinned;', '@HiveField(8, defaultValue: false)\n  final bool pinned;'),
    ('@HiveField(10)\n  final bool isFolder;', '@HiveField(10, defaultValue: false)\n  final bool isFolder;'),
]:
    if old not in text:
        raise SystemExit(f'article annotation anchor not found: {old}')
    text = text.replace(old, new, 1)
write(path, text)

path = 'lib/features/knowledge/models/article_model.g.dart'
text = read(path)
for old, new in [
    ('builtIn: fields[7] as bool,', 'builtIn: fields[7] as bool? ?? false,'),
    ('pinned: fields[8] as bool,', 'pinned: fields[8] as bool? ?? false,'),
    ('isFolder: fields[10] as bool,', 'isFolder: fields[10] as bool? ?? false,'),
]:
    if old not in text:
        raise SystemExit(f'generated adapter anchor not found: {old}')
    text = text.replace(old, new, 1)
write(path, text)


# --------------------------------------------------------------- diagnostics
path = 'lib/features/knowledge/services/knowledge_service.dart'
text = read(path)
old = "    final future = Hive.openBox<ArticleModel>(_boxName).then((box) {\n      _box = box;\n      return box;\n    });"
new = "    final future = Hive.openBox<ArticleModel>(_boxName).then((box) {\n      _box = box;\n      return box;\n    }).onError((Object error, StackTrace stack) {\n      debugPrint('KnowledgeService: failed to open $_boxName: $error');\n      Error.throwWithStackTrace(error, stack);\n    });"
if old not in text:
    raise SystemExit('KnowledgeService open anchor not found')
text = text.replace(old, new, 1)
write(path, text)

print('Home layout and Knowledge Hive compatibility patch applied')
