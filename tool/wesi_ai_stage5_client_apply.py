from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"patch anchor missing: {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


blocks = ROOT / "lib/features/ai/models/wesi_ai_content_blocks.dart"
replace_once(
    blocks,
    "  media,\n}",
    "  media,\n  confirmation,\n}",
)
replace_once(
    blocks,
    "      case WesiAiContentBlockType.table:\n",
    """      case WesiAiContentBlockType.confirmation:\n        final id = _text(data['id'], 180);\n        final expiresAt = DateTime.tryParse(_text(data['expiresAt'], 80));\n        final rawPreview = data['preview'];\n        if (!RegExp(r'^wai_confirm_[A-Za-z0-9_-]{16,180}$').hasMatch(id) ||\n            expiresAt == null ||\n            rawPreview is! Map) {\n          return null;\n        }\n        final preview = Map<String, dynamic>.from(rawPreview);\n        if (_text(preview['risk'], 24) != 'DESTRUCTIVE') return null;\n        return WesiAiContentBlock(\n          type: type,\n          data: <String, dynamic>{\n            'id': id,\n            'expiresAt': expiresAt.toUtc().toIso8601String(),\n            'preview': <String, dynamic>{\n              'tool': _text(preview['tool'], 120),\n              'module': _text(preview['module'], 80),\n              'action': _text(preview['action'], 80),\n              'risk': 'DESTRUCTIVE',\n              if (_text(preview['targetId'], 180).isNotEmpty)\n                'targetId': _text(preview['targetId'], 180),\n            },\n          },\n        );\n\n      case WesiAiContentBlockType.table:\n""",
)
replace_once(
    blocks,
    "      if (item['verified'] != true || item['ok'] != true) continue;\n      final result = item['result'];\n",
    """      if (item['verified'] != true) continue;\n      if ('${item['code'] ?? ''}' == 'CONFIRMATION_REQUIRED') {\n        final rawConfirmation = item['confirmation'];\n        if (rawConfirmation is Map && blocks.length < maxBlocks) {\n          final block = WesiAiContentBlock.fromJson(<String, dynamic>{\n            'type': 'confirmation',\n            'data': Map<String, dynamic>.from(rawConfirmation),\n          });\n          if (block != null) blocks.add(block);\n        }\n        continue;\n      }\n      if (item['ok'] != true) continue;\n      final result = item['result'];\n""",
)

message = ROOT / "lib/features/ai/widgets/wesi_ai_message_content.dart"
replace_once(
    message,
    "import '../models/wesi_ai_content_blocks.dart';\n",
    "import '../models/wesi_ai_content_blocks.dart';\nimport '../wesi_ai_action_api.dart';\n",
)
replace_once(
    message,
    "        WesiAiContentBlockType.media => _MediaBlock(data: block.data),\n",
    "        WesiAiContentBlockType.media => _MediaBlock(data: block.data),\n        WesiAiContentBlockType.confirmation =>\n          _ActionConfirmationBlock(data: block.data),\n",
)
replace_once(
    message,
    "class _KnowledgeBlock extends StatelessWidget {\n",
    """class _ActionConfirmationBlock extends StatefulWidget {\n  final Map<String, dynamic> data;\n\n  const _ActionConfirmationBlock({required this.data});\n\n  @override\n  State<_ActionConfirmationBlock> createState() =>\n      _ActionConfirmationBlockState();\n}\n\nclass _ActionConfirmationBlockState extends State<_ActionConfirmationBlock> {\n  bool _running = false;\n  bool _terminal = false;\n  bool _success = false;\n  String? _message;\n\n  Future<void> _confirm() async {\n    if (_running || _terminal) return;\n    final id = '${widget.data['id'] ?? ''}'.trim();\n    final expiresAt = DateTime.tryParse('${widget.data['expiresAt'] ?? ''}');\n    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {\n      setState(() {\n        _terminal = true;\n        _message = 'Срок подтверждения истёк. Повторите запрос к Wesi AI.';\n      });\n      return;\n    }\n    setState(() => _running = true);\n    final result = await const WesiAiActionApi().confirm(id);\n    if (!mounted) return;\n    setState(() {\n      _running = false;\n      _success = result.ok;\n      _message = result.ok\n          ? 'Действие выполнено.'\n          : (result.message ?? 'Не удалось выполнить действие.');\n      _terminal = result.ok ||\n          (result.code != null &&\n              result.code != 'NETWORK' &&\n              result.code != 'WAI_CONFIRMATION_BAD_RESPONSE');\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final previewRaw = widget.data['preview'];\n    final preview = previewRaw is Map\n        ? Map<String, dynamic>.from(previewRaw)\n        : const <String, dynamic>{};\n    final module = '${preview['module'] ?? ''}'.trim();\n    final action = '${preview['action'] ?? ''}'.trim();\n    final target = '${preview['targetId'] ?? ''}'.trim();\n    final expiresAt = DateTime.tryParse('${widget.data['expiresAt'] ?? ''}');\n    final expired = expiresAt == null ||\n        !expiresAt.isAfter(DateTime.now().toUtc());\n    final disabled = _running || _terminal || expired;\n\n    return Card(\n      child: Padding(\n        padding: const EdgeInsets.all(12),\n        child: Column(\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Row(\n              children: [\n                Icon(Icons.warning_amber_rounded,\n                    color: theme.colorScheme.error),\n                const SizedBox(width: 8),\n                Expanded(\n                  child: Text(\n                    'Требуется подтверждение действия',\n                    style: theme.textTheme.titleSmall\n                        ?.copyWith(fontWeight: FontWeight.w700),\n                  ),\n                ),\n              ],\n            ),\n            const SizedBox(height: 8),\n            Text(\n              [\n                if (module.isNotEmpty) 'Раздел: $module',\n                if (action.isNotEmpty) 'Действие: $action',\n                if (target.isNotEmpty) 'Объект: $target',\n              ].join(' · '),\n              style: theme.textTheme.bodySmall,\n            ),\n            const SizedBox(height: 10),\n            if (_message != null) ...[\n              Text(\n                _message!,\n                style: theme.textTheme.bodySmall?.copyWith(\n                  color: _success\n                      ? theme.colorScheme.primary\n                      : theme.colorScheme.error,\n                ),\n              ),\n              const SizedBox(height: 8),\n            ],\n            FilledButton.icon(\n              onPressed: disabled ? null : _confirm,\n              icon: _running\n                  ? const SizedBox.square(\n                      dimension: 16,\n                      child: CircularProgressIndicator(strokeWidth: 2),\n                    )\n                  : const Icon(Icons.verified_user_outlined),\n              label: Text(\n                _success\n                    ? 'Выполнено'\n                    : expired\n                        ? 'Подтверждение истекло'\n                        : 'Подтвердить действие',\n              ),\n            ),\n          ],\n        ),\n      ),\n    );\n  }\n}\n\nclass _KnowledgeBlock extends StatelessWidget {\n""",
)

print("Stage 5 client confirmation patch applied")
