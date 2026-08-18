from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing patch anchor: {label}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    out, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"regex patch failed ({count}): {label}")
    return out


root = Path('.')

# ---------------------------------------------------------------------------
# Wesi AI chat composer: queue UX + send/stop state + compact queue viewer.
# ---------------------------------------------------------------------------
path = root / 'lib/features/ai/ai_assistant_v2_screen.dart'
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    """  void initState() {\n    super.initState();\n    _voice.addListener(_onVoiceChanged);\n""",
    """  void initState() {\n    super.initState();\n    _composer.addListener(_onComposerChanged);\n    _voice.addListener(_onVoiceChanged);\n""",
    'composer listener init',
)

text = replace_once(
    text,
    """  void _refresh() {\n""",
    """  void _onComposerChanged() {\n    if (mounted) setState(() {});\n  }\n\n  void _refresh() {\n""",
    'composer listener method',
)

text = replace_once(
    text,
    """    _voice.removeListener(_onVoiceChanged);\n    _voice.dispose();\n    _composer.dispose();\n""",
    """    _voice.removeListener(_onVoiceChanged);\n    _voice.dispose();\n    _composer.removeListener(_onComposerChanged);\n    _composer.dispose();\n""",
    'composer listener dispose',
)

text = replace_once(
    text,
    """  Widget _composerBar(WesiAiManagedChatController controller) => Padding(\n""",
    """  bool get _composerHasPayload =>\n      _composer.text.trim().isNotEmpty || _attachments.isNotEmpty;\n\n  Widget _composerBar(WesiAiManagedChatController controller) => Padding(\n""",
    'composer payload getter',
)

queue_widget = """                    if (controller.queuedTurnCount > 0)\n                      Align(\n                        alignment: Alignment.centerRight,\n                        child: Padding(\n                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 7),\n                          child: Material(\n                            color: Theme.of(context)\n                                .colorScheme\n                                .surfaceContainerHighest,\n                            shape: StadiumBorder(\n                              side: BorderSide(\n                                color: Theme.of(context).dividerColor,\n                              ),\n                            ),\n                            clipBehavior: Clip.antiAlias,\n                            child: InkWell(\n                              customBorder: const StadiumBorder(),\n                              onTap: () => _showQueuedTurns(controller),\n                              child: Padding(\n                                padding: const EdgeInsets.symmetric(\n                                  horizontal: 12,\n                                  vertical: 8,\n                                ),\n                                child: Row(\n                                  mainAxisSize: MainAxisSize.min,\n                                  children: [\n                                    const Icon(Icons.schedule_rounded, size: 19),\n                                    const SizedBox(width: 7),\n                                    Text(\n                                      '${controller.queuedTurnCount}',\n                                      style: const TextStyle(\n                                        fontWeight: FontWeight.w700,\n                                      ),\n                                    ),\n                                  ],\n                                ),\n                              ),\n                            ),\n                          ),\n                        ),\n                      ),\n                    if (_attachments.isNotEmpty)"""
text = regex_once(
    text,
    r"                    if \(controller\.queuedTurnCount > 0\)\n.*?                    if \(_attachments\.isNotEmpty\)",
    queue_widget,
    'compact queue pill',
)

old_stop_status = """                        if (controller.sending)\n                          IconButton(\n                            tooltip: 'Остановить текущую работу',\n                            onPressed: () =>\n                                unawaited(controller.stopActiveWork()),\n                            icon: const Icon(Icons.stop_circle_outlined),\n                          ),\n                        if (controller.sending ||\n                            controller.queuedTurnCount > 0)\n                          Padding(\n                            padding: const EdgeInsets.only(right: 6),\n                            child: Text(\n                              controller.sending\n                                  ? 'Ответ обрабатывается'\n                                  : 'Обрабатываю очередь',\n                              style: Theme.of(context).textTheme.labelSmall,\n                            ),\n                          ),\n"""
text = replace_once(text, old_stop_status, '', 'old stop/status controls')

old_send = """                        IconButton.filled(\n                          tooltip: controller.sending\n                              ? 'Добавить сообщение в очередь'\n                              : 'Отправить',\n                          onPressed: () => _send(controller),\n                          icon: const Icon(Icons.arrow_upward_rounded),\n                        ),\n"""
new_send = """                        if (controller.sending && !_composerHasPayload)\n                          IconButton.filled(\n                            tooltip: 'Остановить текущую работу',\n                            onPressed: () =>\n                                unawaited(controller.stopActiveWork()),\n                            icon: const Icon(Icons.stop_rounded),\n                          )\n                        else\n                          IconButton.filled(\n                            tooltip: controller.sending\n                                ? 'Добавить сообщение в очередь'\n                                : 'Отправить',\n                            onPressed: _composerHasPayload\n                                ? () => _send(controller)\n                                : null,\n                            icon: const Icon(Icons.arrow_upward_rounded),\n                          ),\n"""
text = replace_once(text, old_send, new_send, 'send/stop primary action')

queue_sheet = r"""
  Future<void> _showQueuedTurns(
    WesiAiManagedChatController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final queued = controller.queuedTurns;
          final height = MediaQuery.sizeOf(context).height * 0.58;
          return SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Очередь',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (queued.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('${queued.length}'),
                        ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: queued.isEmpty
                      ? const Center(child: Text('Очередь пуста'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                          itemCount: queued.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final turn = queued[index];
                            final local = turn.queuedAt.toLocal();
                            final hour = local.hour.toString().padLeft(2, '0');
                            final minute =
                                local.minute.toString().padLeft(2, '0');
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  turn.preview,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${turn.intentLabel} · $hour:$minute',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

"""
text = replace_once(
    text,
    """  Future<void> _pickAttachments() async {\n""",
    queue_sheet + """  Future<void> _pickAttachments() async {\n""",
    'queue viewer sheet',
)

text = replace_once(
    text,
    """          final width = size.width < 620 ? size.width - 24 : 560.0;\n          final height = (size.height * 0.78).clamp(420.0, 720.0).toDouble();\n          return Dialog(\n            insetPadding: const EdgeInsets.all(12),\n""",
    """          final width = size.width < 620 ? size.width - 32 : 520.0;\n          final height = (size.height * 0.58).clamp(360.0, 560.0).toDouble();\n          return Dialog(\n            insetPadding: const EdgeInsets.symmetric(\n              horizontal: 16,\n              vertical: 24,\n            ),\n""",
    'camera dialog dimensions',
)

text = replace_once(
    text,
    """    if (controller.processing || answer.trim().isEmpty) return;\n""",
    """    if (answer.trim().isEmpty) return;\n""",
    'quick reply queue support',
)

path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Camera preview: fill the small modal with aspect-preserving crop.
# ---------------------------------------------------------------------------
path = root / 'lib/features/ai/widgets/wesi_ai_camera_capture.dart'
text = path.read_text(encoding='utf-8')
start = text.find("  @override\n  Widget build(BuildContext context) {")
if start < 0:
    raise SystemExit('missing patch anchor: camera build')
end = text.rfind('\n}')
if end <= start:
    raise SystemExit('missing patch anchor: camera class end')

camera_build = r"""  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final width = portrait ? previewSize.height : previewSize.width;
    final height = portrait ? previewSize.width : previewSize.height;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width,
            height: height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            _cameraPreview(controller)
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Камера недоступна',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          if (_cameras.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: _loading || _capturing ? null : _switchCamera,
                icon: const Icon(
                  Icons.cameraswitch_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: Center(
              child: GestureDetector(
                onTap: controller != null && !_loading && !_capturing
                    ? _takePicture
                    : null,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    color: _capturing ? Colors.white38 : Colors.white24,
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
"""
text = text[:start] + camera_build + text[end:]
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Rich message code blocks: expose Run only after streaming has completed.
# ---------------------------------------------------------------------------
path = root / 'lib/features/ai/widgets/wesi_ai_rich_message.dart'
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    """import '../models/wesi_ai_activity.dart';\nimport 'wesi_ai_visualization.dart';\n""",
    """import '../models/wesi_ai_activity.dart';\nimport 'wesi_ai_code_console.dart';\nimport 'wesi_ai_visualization.dart';\n""",
    'code console import',
)

old_code_render = "WesiAiCodeBlock(code: block.text, language: block.language)"
count = text.count(old_code_render)
if count < 1:
    raise SystemExit('missing patch anchor: rich code render')
text = text.replace(
    old_code_render,
    "WesiAiCodeBlock(\n              code: block.text,\n              language: block.language,\n              runnable: !streaming,\n            )",
)

text = replace_once(
    text,
    """class WesiAiCodeBlock extends StatelessWidget {\n  final String code;\n  final String language;\n\n  const WesiAiCodeBlock({super.key, required this.code, this.language = ''});\n""",
    """class WesiAiCodeBlock extends StatelessWidget {\n  final String code;\n  final String language;\n  final bool runnable;\n\n  const WesiAiCodeBlock({\n    super.key,\n    required this.code,\n    this.language = '',\n    this.runnable = true,\n  });\n""",
    'code block runnable property',
)

text = replace_once(
    text,
    """  Future<void> _expand(BuildContext context) => showDialog<void>(\n""",
    """  Future<void> _run(BuildContext context) => WesiAiCodeConsole.open(\n        context,\n        code: code,\n        language: language,\n      );\n\n  Future<void> _expand(BuildContext context) => showDialog<void>(\n""",
    'code block run method',
)

text = replace_once(
    text,
    """                IconButton(\n                  tooltip: 'Копировать код',\n""",
    """                if (runnable && WesiAiCodeConsole.supports(language))\n                  IconButton.filledTonal(\n                    tooltip: 'Запустить код',\n                    visualDensity: VisualDensity.compact,\n                    onPressed: () => _run(context),\n                    icon: const Icon(Icons.play_arrow_rounded, size: 19),\n                  ),\n                IconButton(\n                  tooltip: 'Копировать код',\n""",
    'run button in code block',
)

path.write_text(text, encoding='utf-8')

print('Wesi AI inline console, queue UX and camera patch applied.')
