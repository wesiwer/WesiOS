import 'package:flutter/material.dart';
import '../team/services/team_service.dart';
import 'controllers/wesi_ai_chat_controller.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}
class _AiAssistantScreenState extends State<AiAssistantScreen> {
  WesiAiChatController? controller; final composer = TextEditingController();
  @override void initState() { super.initState(); final employee = TeamService.current; if (employee != null) { controller = WesiAiChatController(store: WesiAiLocalStore(employee.id)); controller!.addListener(_refresh); controller!.load(); } }
  void _refresh() { if (mounted) setState(() {}); }
  @override void dispose() { controller?.removeListener(_refresh); controller?.dispose(); composer.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final c = controller; if (c == null) return const Scaffold(body: Center(child: Text('Войдите в профиль сотрудника, чтобы открыть Wesi AI'))); if (c.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final active = c.state.activeConversation; final messages = active == null ? const <WesiAiMessage>[] : c.state.messagesFor(active.id);
    return Scaffold(appBar: AppBar(title: const Text('Wesi AI'), actions: [DropdownButton<WesiAiTier>(value: c.state.tier, underline: const SizedBox(), onChanged: c.sending ? null : (v) { if (v != null) c.setTier(v); }, items: const [DropdownMenuItem(value: WesiAiTier.fast, child: Text('Wesi AI Быстрый')), DropdownMenuItem(value: WesiAiTier.pro, child: Text('Wesi AI Pro')), DropdownMenuItem(value: WesiAiTier.maximum, child: Text('Wesi AI Максимальный'))]), const SizedBox(width: 12)]), body: Row(children: [
      SizedBox(width: 260, child: Column(children: [Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 6, runSpacing: 6, children: [FilledButton.tonal(onPressed: c.sending ? null : () => c.createConversation(WesiAiPersona.zane), child: const Text('Зейн')), FilledButton.tonal(onPressed: c.sending ? null : () => c.createConversation(WesiAiPersona.nirvana), child: const Text('Нирвана')), OutlinedButton(onPressed: c.sending ? null : () => c.createConversation(WesiAiPersona.lobby), child: const Text('Лобби'))])), Expanded(child: ListView.builder(itemCount: c.state.conversations.length, itemBuilder: (_, i) { final item = c.state.conversations[i]; return ListTile(selected: item.id == c.state.activeConversationId, title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(item.persona.name), onTap: c.sending ? null : () => c.selectConversation(item.id)); }))])),
      const VerticalDivider(width: 1), Expanded(child: active == null ? const Center(child: Text('Выберите Зейна или Нирвану и начните чат')) : Column(children: [Expanded(child: messages.isEmpty ? const Center(child: Text('История этого чата хранится локально')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: messages.length, itemBuilder: (_, i) { final m = messages[i]; return ListTile(leading: m.kind == WesiAiMessageKind.error ? const Icon(Icons.error_outline) : null, title: Text(m.text)); })), if (c.sending) const LinearProgressIndicator(), Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: TextField(controller: composer, enabled: !c.sending, minLines: 1, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Сообщение Wesi AI'), onSubmitted: c.sending ? null : (_) => _send(c))), const SizedBox(width: 6), IconButton.filled(onPressed: c.sending ? null : () => _send(c), icon: c.sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward))]))]))
    ]));
  }
  Future<void> _send(WesiAiChatController c) async { final text = composer.text.trim(); if (text.isEmpty || c.sending) return; composer.clear(); await c.addUserMessage(text); }
}
