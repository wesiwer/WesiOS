from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


p = Path('lib/features/ai/backup/wesi_ai_backup_service.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''    for (final imported in decoded.memoryEntries) {
      final existing = memoryById[imported.id];
      if (existing == null || imported.updatedAt.isAfter(existing.updatedAt)) {
        memoryById[imported.id] = imported;
      }
    }
''',
    '''    for (final imported in decoded.memoryEntries) {
      final existing = memoryById[imported.id];
      memoryById[imported.id] = existing == null
          ? imported
          : _mergeMemoryEntries(existing, imported);
    }
''',
    'memory id merge',
)
s = replace_once(
    s,
    '''      final previous = dedupMemory[key];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        dedupMemory[key] = item;
      }
''',
    '''      final previous = dedupMemory[key];
      dedupMemory[key] = previous == null
          ? item
          : _mergeMemoryEntries(previous, item);
''',
    'memory normalized merge',
)
s = replace_once(
    s,
    '''  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\\s+'), ' ').trim();
}''',
    '''  static WesiAiMemoryEntry _mergeMemoryEntries(
    WesiAiMemoryEntry first,
    WesiAiMemoryEntry second,
  ) {
    final newer = second.updatedAt.isAfter(first.updatedAt) ? second : first;
    return newer.copyWith(
      manual: first.manual || second.manual,
      pinned: first.pinned || second.pinned,
      importance: first.importance >= second.importance
          ? first.importance
          : second.importance,
    );
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\\s+'), ' ').trim();
}''',
    'memory merge helper',
)
p.write_text(s, encoding='utf-8')
