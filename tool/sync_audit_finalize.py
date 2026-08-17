from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1))


# Profile: an already-open screen must repaint when remote profile data arrives,
# but controller writes caused by that repaint must never echo back as a local edit.
p = Path("lib/features/profile/profile_screen.dart")
text = p.read_text()
if "_applyingSyncedProfile" not in text:
    text = text.replace(
        "  String? _savedHint;\n  Timer? _debounce;\n",
        "  String? _savedHint;\n  Timer? _debounce;\n  bool _applyingSyncedProfile = false;\n",
        1,
    )
    text = text.replace(
        "    _loadAll();\n    for (final c in [\n",
        "    _loadAll();\n    ProfileService.revision.addListener(_onProfileRevision);\n    for (final c in [\n",
        1,
    )
    text = text.replace(
        "  void _scheduleSave() {\n    _debounce?.cancel();\n",
        "  void _scheduleSave() {\n    if (_applyingSyncedProfile) return;\n    _debounce?.cancel();\n",
        1,
    )
    marker = "  Future<void> _autoSave() async {\n"
    method = """  void _onProfileRevision() {\n    if (!mounted || _applyingSyncedProfile) return;\n    final box = Hive.box('wesios_settings');\n    _applyingSyncedProfile = true;\n    try {\n      final idx = box.get('avatar_index');\n      _selectedAvatarIndex = idx is int ? idx : 0;\n      _nameCtrl.text = '${box.get('profile_name', defaultValue: '')}';\n      _emailCtrl.text = '${box.get('profile_email', defaultValue: '')}';\n      _gender = '${box.get('profile_gender', defaultValue: 'Не указан')}';\n      _country = '${box.get('profile_country', defaultValue: 'Не указана')}';\n      final birth = box.get('profile_birth');\n      _birthDate = birth is String && birth.isNotEmpty\n          ? DateTime.tryParse(birth)\n          : null;\n    } finally {\n      _applyingSyncedProfile = false;\n    }\n    if (mounted) setState(() {});\n  }\n\n"""
    if text.count(marker) != 1:
        raise SystemExit("profile_screen.dart: autosave marker mismatch")
    text = text.replace(marker, method + marker, 1)
    text = text.replace(
        "  void dispose() {\n    _debounce?.cancel();\n",
        "  void dispose() {\n    ProfileService.revision.removeListener(_onProfileRevision);\n    _debounce?.cancel();\n",
        1,
    )
    p.write_text(text)


# Chat: messages and thread metadata are distinct synced collections.
p = Path("lib/features/chats/chat_screen.dart")
text = p.read_text()
if "valueListenable: ChatService.revision" not in text:
    old_open = """  Widget build(BuildContext context) {\n    return ValueListenableBuilder<int>(\n      valueListenable: MessageStore.revision,\n      builder: (context, _, __) {\n"""
    new_open = """  Widget build(BuildContext context) {\n    return ValueListenableBuilder<int>(\n      valueListenable: ChatService.revision,\n      builder: (context, _, __) => ValueListenableBuilder<int>(\n        valueListenable: MessageStore.revision,\n        builder: (context, __, ___) {\n"""
    if text.count(old_open) != 1:
        raise SystemExit("chat_screen.dart: build open mismatch")
    text = text.replace(old_open, new_open, 1)
    old_close = """        );\n      },\n    );\n  }\n\n  Widget _header(ChatThread chat) {"""
    new_close = """        );\n        },\n      ),\n    );\n  }\n\n  Widget _header(ChatThread chat) {"""
    if text.count(old_close) != 1:
        raise SystemExit("chat_screen.dart: build close mismatch")
    text = text.replace(old_close, new_close, 1)
    p.write_text(text)


# Treasury: remote transactions/accounts already notify their services, but the
# open screen historically listened only to organization changes. Subscribe to
# both data revisions so an already-open Finance screen reloads immediately.
p = Path("lib/features/treasury/treasury_screen.dart")
text = p.read_text()
if "TreasuryService.revision.addListener(_loadData);" not in text:
    old = """    OrganizationContext.revision.addListener(_onOrganizationContextChanged);\n    _loadData();\n"""
    new = """    OrganizationContext.revision.addListener(_onOrganizationContextChanged);\n    TreasuryService.revision.addListener(_loadData);\n    AccountService.revision.addListener(_loadData);\n    _loadData();\n"""
    if text.count(old) != 1:
        raise SystemExit("treasury_screen.dart: init listener marker mismatch")
    text = text.replace(old, new, 1)
    old = """    OrganizationContext.revision.removeListener(_onOrganizationContextChanged);\n    super.dispose();\n"""
    new = """    OrganizationContext.revision.removeListener(_onOrganizationContextChanged);\n    TreasuryService.revision.removeListener(_loadData);\n    AccountService.revision.removeListener(_loadData);\n    super.dispose();\n"""
    if text.count(old) != 1:
        raise SystemExit("treasury_screen.dart: dispose listener marker mismatch")
    p.write_text(text.replace(old, new, 1))


# Revision-v2 rolling-deploy fallback.
p = Path("lib/core/sync/pocketbase_transport.dart")
text = p.read_text()
if "rolling deploy" not in text:
    old = """  Future<SyncResult<String>> revision() async {\n    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);\n    final res = await _send('GET', '/api/wesi/sync/revision-v2');\n    if (res.failure != null) return SyncResult.fail(res.failure!);\n    final revision = res.value!['revision'];\n    if (revision is! String || revision.isEmpty) {\n      return const SyncResult.fail(\n        SyncFailure('NOT_WESIOS', 'Сервер не вернул ревизию синхронизации'),\n      );\n    }\n    return SyncResult.ok(revision);\n  }\n"""
    new = """  Future<SyncResult<String>> revision() async {\n    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);\n    final res = await _send('GET', '/api/wesi/sync/revision-v2');\n    if (res.failure != null) {\n      // During a rolling deploy an updated client may start before the new\n      // PocketBase hook. Keep live sync alive on the legacy endpoint until\n      // revision-v2 becomes available.\n      if (res.failure!.code == 'NOT_WESIOS') {\n        final legacy = await _send('GET', '/api/wesi/sync/revision');\n        if (legacy.failure != null) return SyncResult.fail(legacy.failure!);\n        return SyncResult.ok(revisionFromResponse(legacy.value!));\n      }\n      return SyncResult.fail(res.failure!);\n    }\n    final revision = res.value!['revision'];\n    if (revision is! String || revision.isEmpty) {\n      return const SyncResult.fail(\n        SyncFailure('NOT_WESIOS', 'Сервер не вернул ревизию синхронизации'),\n      );\n    }\n    return SyncResult.ok(revision);\n  }\n"""
    if text.count(old) != 1:
        raise SystemExit("pocketbase_transport.dart: revision block mismatch")
    p.write_text(text.replace(old, new, 1))


# Portable Audio Vault codec extends the canonical codec from sync_codec_crm.
p = Path("lib/core/sync/sync_audit_extensions.dart")
text = p.read_text()
if "import 'sync_codec_crm.dart';" not in text:
    anchor = "import 'sync_codec.dart';\n"
    if text.count(anchor) != 1:
        raise SystemExit("sync_audit_extensions.dart: codec import marker mismatch")
    p.write_text(text.replace(anchor, anchor + "import 'sync_codec_crm.dart';\n", 1))


# Regression registry includes the second-pass hidden business state too.
p = Path("test/sync_audit_extensions_test.dart")
text = p.read_text()
if "sync_business_extensions.dart" not in text:
    text = text.replace(
        "import 'package:wesios/core/sync/sync_audit_extensions.dart';\n",
        "import 'package:wesios/core/sync/sync_audit_extensions.dart';\n"
        "import 'package:wesios/core/sync/sync_business_extensions.dart';\n",
        1,
    )
    text = text.replace(
        "  setUpAll(SyncAuditExtensions.install);\n",
        "  setUpAll(() {\n    SyncAuditExtensions.install();\n    SyncBusinessExtensions.install();\n  });\n",
        1,
    )
    needle = "      'audio_extras',\n"
    extra = """      'audio_extras',\n      'finance_categories',\n      'team_skills',\n      'time_center',\n      'horizon_predictions',\n      'horizon_learning',\n      'horizon_competition',\n      'horizon_contracts',\n      'task_ai_memory',\n"""
    if text.count(needle) != 1:
        raise SystemExit("sync_audit_extensions_test.dart: registry marker mismatch")
    text = text.replace(needle, extra, 1)
    p.write_text(text)


# WesiAiApi gained thinkingMode; old test doubles must keep the exact override
# contract or the whole application no longer passes static analysis.
for path in [
    "test/wesi_ai_memory_engine_test.dart",
    "test/wesi_ai_queue_hardening_test.dart",
]:
    p = Path(path)
    text = p.read_text()
    if "bool thinkingMode = false," not in text:
        marker = "    WesiAiRequestCancellation? cancellation,\n"
        count = text.count(marker)
        if count == 0:
            raise SystemExit(f"{path}: WesiAiApi send marker missing")
        text = text.replace(
            marker,
            marker + "    bool thinkingMode = false,\n",
        )
        p.write_text(text)
