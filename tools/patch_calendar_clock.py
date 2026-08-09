from pathlib import Path


def replace_once(path: str, old: str, new: str, *, already: str | None = None) -> None:
    p = Path(path)
    text = p.read_text()
    if old in text:
        p.write_text(text.replace(old, new, 1))
        return
    if already is not None and already in text:
        return
    raise SystemExit(f'anchor not found in {path}: {old[:100]!r}')


# ---------------------------------------------------------------- UI fixes
# Weekday label: avoid cascade/precedence ambiguity.
time_screen = Path('lib/features/time_center/time_center_screen.dart')
text = time_screen.read_text()
old = """    return days.toList()..sort() is List<int>\n        ? (days.toList()..sort()).map(_weekdayShort).join(' · ')\n        : '';\n"""
new = """    final sorted = days.toList()..sort();\n    return sorted.map(_weekdayShort).join(' · ');\n"""
if old in text:
    text = text.replace(old, new, 1)
# New reminder dialog must re-evaluate disabled Save button while typing.
needle = """                  TextField(\n                    controller: title,\n                    autofocus: original == null,\n                    decoration: InputDecoration(labelText: _ru ? 'Что напомнить' : 'Title'),\n                  ),\n"""
replacement = """                  TextField(\n                    controller: title,\n                    autofocus: original == null,\n                    onChanged: (_) => setDialogState(() {}),\n                    decoration: InputDecoration(labelText: _ru ? 'Что напомнить' : 'Title'),\n                  ),\n"""
if needle in text:
    text = text.replace(needle, replacement, 1)
elif "onChanged: (_) => setDialogState(() {})," not in text:
    raise SystemExit('time reminder title validation anchor not found')
time_screen.write_text(text)

calendar = Path('lib/features/calendar/calendar_v2_screen.dart')
text = calendar.read_text()
old_clamp = """          _selected = DateTime(\n            _visibleMonth.year,\n            _visibleMonth.month,\n            _selected.day.clamp(\n              1,\n              DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day,\n            ),\n          );\n"""
new_clamp = """          final maxDay =\n              DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;\n          final selectedDay = _selected.day > maxDay ? maxDay : _selected.day;\n          _selected = DateTime(\n            _visibleMonth.year,\n            _visibleMonth.month,\n            selectedDay,\n          );\n"""
if old_clamp in text:
    text = text.replace(old_clamp, new_clamp, 1)
elif 'final selectedDay = _selected.day > maxDay ? maxDay : _selected.day;' not in text:
    raise SystemExit('calendar month clamp anchor not found')
needle = """                  TextField(\n                    controller: title,\n                    autofocus: event == null,\n                    decoration: InputDecoration(labelText: _ru ? 'Название' : 'Title'),\n                  ),\n"""
replacement = """                  TextField(\n                    controller: title,\n                    autofocus: event == null,\n                    onChanged: (_) => setDialogState(() {}),\n                    decoration: InputDecoration(labelText: _ru ? 'Название' : 'Title'),\n                  ),\n"""
if needle in text:
    text = text.replace(needle, replacement, 1)
elif "onChanged: (_) => setDialogState(() {})," not in text:
    raise SystemExit('calendar event title validation anchor not found')
calendar.write_text(text)

# ---------------------------------------------------------------- dependency
pubspec = Path('pubspec.yaml')
text = pubspec.read_text()
if '\n  timezone:' not in text:
    anchor = '  flutter_local_notifications: ^17.2.3\n'
    if anchor not in text:
        raise SystemExit('flutter_local_notifications dependency anchor not found')
    text = text.replace(anchor, anchor + '  timezone: ^0.9.4\n', 1)
pubspec.write_text(text)

# ---------------------------------------------------------------- Android scheduling
manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text()
if 'android.permission.SCHEDULE_EXACT_ALARM' not in text:
    anchor = '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    if anchor not in text:
        raise SystemExit('manifest POST_NOTIFICATIONS anchor not found')
    text = text.replace(
        anchor,
        anchor + '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />\n',
        1,
    )
if 'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver' not in text:
    receivers = '''\n        <!-- Scheduled Calendar/Time Center notifications survive process death\n             and are restored after reboot/package replacement. -->\n        <receiver\n            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"\n            android:exported="false" />\n        <receiver\n            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"\n            android:exported="false">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>\n'''
    anchor = '        <meta-data\n            android:name="flutterEmbedding"\n            android:value="2" />\n'
    if anchor not in text:
        raise SystemExit('manifest flutterEmbedding anchor not found')
    text = text.replace(anchor, receivers + '\n' + anchor, 1)
manifest.write_text(text)

# ---------------------------------------------------------------- routing
router = Path('lib/core/routes/app_router.dart')
text = router.read_text()
time_import = "import '../../features/time_center/time_center_screen.dart';\n"
if time_import not in text:
    anchor = "import '../../features/calendar/calendar_screen.dart';\n"
    if anchor not in text:
        raise SystemExit('router calendar import anchor not found')
    text = text.replace(anchor, anchor + time_import, 1)
if "case '/time':" not in text:
    anchor = """      case '/calendar':\n        return _slideUpRoute(_AccessGate(\n          module: TeamModules.calendar,\n          child: CalendarScreen(),\n        ));\n"""
    if anchor not in text:
        raise SystemExit('router calendar route anchor not found')
    text = text.replace(
        anchor,
        anchor + """      case '/time':\n        return _slideUpRoute(\n          _AccessGate(child: const TimeCenterScreen()),\n        );\n""",
        1,
    )
router.write_text(text)

# ---------------------------------------------------------------- Home clock
home = Path('lib/features/home/home_screen.dart')
text = home.read_text()
old_tip = """? 'Открыть календарь · долгий тап — стиль часов'\n                          : 'Open calendar · long-press for clock style'"""
new_tip = """? 'Открыть центр времени · долгий тап — стиль часов'\n                          : 'Open Time Center · long-press for clock style'"""
if old_tip in text:
    text = text.replace(old_tip, new_tip, 1)
if "onTap: () => Navigator.pushNamed(context, '/calendar')," in text:
    text = text.replace(
        "onTap: () => Navigator.pushNamed(context, '/calendar'),",
        "onTap: () => Navigator.pushNamed(context, '/time'),",
        1,
    )
elif "onTap: () => Navigator.pushNamed(context, '/time')," not in text:
    raise SystemExit('home clock route anchor not found')
home.write_text(text)

# ---------------------------------------------------------------- startup restore
main = Path('lib/main.dart')
text = main.read_text()
time_import = "import 'features/time_center/services/time_schedule_automation.dart';\n"
if time_import not in text:
    anchor = "import 'features/treasury/services/recurring_payment_automation.dart';\n"
    if anchor not in text:
        raise SystemExit('main recurring import anchor not found')
    text = text.replace(anchor, anchor + time_import, 1)
if 'TimeScheduleAutomation.shared.start();' not in text:
    anchor = '  RecurringPaymentAutomation.shared.start();\n'
    if anchor not in text:
        raise SystemExit('main recurring automation call anchor not found')
    text = text.replace(
        anchor,
        anchor
        + "\n  // Restore Calendar/Time Center schedules after Hive is ready.\n"
        + "  TimeScheduleAutomation.shared.start();\n",
        1,
    )
main.write_text(text)

# ---------------------------------------------------------------- Calendar Sync
codec = Path('lib/core/sync/sync_codec.dart')
text = codec.read_text()
calendar_imports = (
    "import '../../features/calendar/models/calendar_event.dart';\n"
    "import '../../features/calendar/services/calendar_event_service.dart';\n"
)
if "../../features/calendar/models/calendar_event.dart" not in text:
    anchor = "import '../../features/chats/models/chat_message.dart';\n"
    if anchor not in text:
        raise SystemExit('sync import anchor not found')
    text = text.replace(anchor, calendar_imports + anchor, 1)

if 'class CalendarEventsSync extends SyncCollection<dynamic>' not in text:
    anchor = '/// Состав.\n'
    if anchor not in text:
        raise SystemExit('calendar sync class anchor not found')
    block = r'''/// Собственные события Calendar синхронизируются между устройствами.
/// Time Center (будильники/таймер/секундомер) остаётся device-local, чтобы
/// одно и то же локальное действие не срабатывало одновременно везде.
class CalendarEventsSync extends SyncCollection<dynamic> {
  @override
  void notifyChanged() {
    CalendarEventService.revision.value++;
    CalendarEventService().restoreSchedules();
  }

  @override
  String get name => 'calendar_events';

  @override
  String get boxName => CalendarEventService.boxName;

  @override
  String idOf(dynamic value) =>
      value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) {
    if (value is! Map) return const {};
    try {
      return CalendarEvent.fromJson(value).toJson();
    } catch (_) {
      return const {};
    }
  }

  @override
  dynamic decode(Map<String, dynamic> fields) {
    try {
      final event = CalendarEvent.fromJson(fields);
      if (event.id.isEmpty || event.title.trim().isEmpty) return null;
      return event.toJson();
    } catch (_) {
      return null;
    }
  }

  @override
  Box<dynamic>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    try {
      return Hive.box<dynamic>(boxName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Box<dynamic>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<dynamic>(boxName)
      : await Hive.openBox<dynamic>(boxName);

  @override
  Map<String, dynamic> local() {
    final b = box();
    if (b == null) return const {};
    final out = <String, dynamic>{};
    for (final raw in b.values) {
      if (raw is! Map) continue;
      try {
        final event = CalendarEvent.fromJson(raw);
        if (event.id.isEmpty || event.title.trim().isEmpty) continue;
        out[event.id] = event.toJson();
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final decoded = decode(fields);
    if (decoded is! Map) return false;
    final event = CalendarEvent.fromJson(decoded);
    await b.put(event.id, event.toJson());
    return true;
  }

  @override
  Future<void> removeById(String id) async => box()?.delete(id);
}

'''
    text = text.replace(anchor, block + anchor, 1)
if 'CalendarEventsSync(),' not in text:
    anchor = '    TasksSync(),\n'
    if anchor not in text:
        raise SystemExit('sync collection list anchor not found')
    text = text.replace(anchor, anchor + '    CalendarEventsSync(),\n', 1)
codec.write_text(text)

# ---------------------------------------------------------------- final guards
checks = {
    'pubspec.yaml': ['timezone: ^0.9.4'],
    'android/app/src/main/AndroidManifest.xml': [
        'SCHEDULE_EXACT_ALARM',
        'ScheduledNotificationReceiver',
        'ScheduledNotificationBootReceiver',
    ],
    'lib/core/routes/app_router.dart': ["case '/time':", 'TimeCenterScreen'],
    'lib/features/home/home_screen.dart': ["pushNamed(context, '/time')"],
    'lib/main.dart': ['TimeScheduleAutomation.shared.start();'],
    'lib/core/sync/sync_codec.dart': ["String get name => 'calendar_events';", 'CalendarEventsSync(),'],
    'lib/features/calendar/calendar_screen.dart': ["export 'calendar_v2_screen.dart';"],
    'lib/features/calendar/calendar_v2_screen.dart': ['ModuleStage.ready'],
}
for filename, needles in checks.items():
    body = Path(filename).read_text()
    for needle in needles:
        if needle not in body:
            raise SystemExit(f'{needle!r} missing from {filename}')
