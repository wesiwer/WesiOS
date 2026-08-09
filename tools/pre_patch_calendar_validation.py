from pathlib import Path


def insert_after(path: str, marker: str) -> None:
    file = Path(path)
    text = file.read_text()
    callback = '                    onChanged: (_) => setDialogState(() {}),\n'
    if callback in text:
        return
    if marker not in text:
        raise SystemExit(f'validation marker not found in {path}: {marker!r}')
    file.write_text(text.replace(marker, marker + callback, 1))


insert_after(
    'lib/features/time_center/time_center_screen.dart',
    '                    autofocus: original == null,\n',
)
insert_after(
    'lib/features/calendar/calendar_v2_screen.dart',
    '                    autofocus: event == null,\n',
)
