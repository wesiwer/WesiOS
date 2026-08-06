import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/feedback/wesi_feedback.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';
import 'models/chat_message.dart';
import 'models/chat_thread.dart';
import 'services/ai_topic_judge.dart';
import 'services/attachment_store.dart';
import 'services/chat_delivery.dart';
import 'services/chat_service.dart';
import 'services/chat_sync.dart';
import 'services/message_store.dart';
import 'services/topic_judge.dart';
import 'services/topic_privacy.dart';
import 'services/topic_refiner.dart';
import 'widgets/chat_settings_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/sticker_sheet.dart';
import 'widgets/topic_divider.dart';
import 'widgets/topic_question_card.dart';

/// Переписка.
///
/// **Блоки тем — не украшение, а главная особенность.** Разговор режется на
/// осознанные части, и там, где программа не уверена, она спрашивает
/// человека прямо в ленте, а не молча делает по-своему.
class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  static Future<void> open(BuildContext context, String chatId) =>
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  ChatMessage? _replyTo;
  bool _searching = false;
  String _query = '';

  /// Разметка после участия модели. null — пока показываем местную.
  ChatLayout? _refined;

  /// По какому состоянию переписки она посчитана. Без этого модель
  /// опрашивалась бы на каждую перерисовку экрана — то есть на каждое
  /// нажатие клавиши в поле ввода.
  String? _refinedFor;
  bool _refining = false;

  bool get _ru => WesiLocale.isRussian;

  ChatThread? get _chat => ChatService.byId(widget.chatId);

  @override
  void initState() {
    super.initState();
    ChatService.markOpened(widget.chatId);
    // Чистка при входе, а не по таймеру: сообщение с вышедшим сроком не
    // должно дождаться, пока кто-то вспомнит про уборку.
    MessageStore.sweep();
    // Пока переписка открыта, обмениваемся с сервером часто — иначе
    // сообщение собеседника приедет в лучшем случае при следующем запуске
    // программы.
    ChatSync.watch();
  }

  @override
  void dispose() {
    // Отметку ставим и на выходе: человек мог читать долго, и всё, что
    // пришло за это время, он уже видел.
    ChatService.markOpened(widget.chatId);
    ChatSync.unwatch();
    _input.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send({String? sticker}) async {
    final chat = _chat;
    if (chat == null) return;
    final text = sticker ?? _input.text;
    if (text.trim().isEmpty) return;

    // Через сервис, а не прямо в хранилище: срок жизни у чата может быть
    // свой, и уедет ли сообщение куда-нибудь — тоже решается там.
    await ChatService.send(
      chatId: chat.id,
      body: text,
      kind: sticker == null ? MessageKind.text : MessageKind.sticker,
      replyTo: _replyTo?.id,
    );
    // Отправили — не ждём следующего тика, отправляем сразу.
    ChatSync.nudge();
    WesiFeedback.send();
    if (!mounted) return;
    setState(() {
      _input.clear();
      _replyTo = null;
    });
    _toBottom();
  }

  void _toBottom() {
    // Кадром позже: список ещё не перестроился, и прокручивать пока некуда.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _stickers() async {
    final picked = await StickerSheet.show(context);
    if (picked != null) await _send(sticker: picked);
  }

  void _actions(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageActions(
        message: m,
        mine: m.authorId == ChatService.meId,
        onReply: () => setState(() => _replyTo = m),
        onEdit: () => _edit(m),
        onReact: () => _pickReaction(m),
        onChanged: () => setState(() {}),
      ),
    );
  }

  /// Приложить файл.
  ///
  /// Подпись берётся из поля ввода: человек часто пишет «вот договор» и
  /// прикладывает — заставлять его отправлять это двумя сообщениями
  /// незачем.
  Future<void> _attach() async {
    final chat = _chat;
    if (chat == null) return;

    final picked = await FilePicker.platform.pickFiles(withData: false);
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (path == null) return;

    final result = await ChatService.sendFile(
      chatId: chat.id,
      sourcePath: path,
      displayName: file!.name,
      caption: _input.text,
    );
    ChatSync.nudge();
    if (!mounted) return;

    if (result is ChatMessage) {
      setState(() {
        _input.clear();
        _replyTo = null;
      });
      _toBottom();
      return;
    }

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (result) {
        AttachmentStore.tooBig => _ru
            ? 'Файл больше ${AttachmentStore.maxBytes ~/ (1024 * 1024)} МБ. '
                'Такой не отправится: хранилища для больших файлов пока нет, '
                'и отправка молча висела бы.'
            : 'File is too large',
        AttachmentStore.empty =>
          _ru ? 'Файл пустой' : 'The file is empty',
        AttachmentStore.gone =>
          _ru ? 'Файл не найден' : 'File not found',
        _ => _ru ? 'Не удалось приложить файл' : 'Could not attach the file',
      }),
      backgroundColor: AppTheme.surface,
    ));
  }

  /// Открыть вложение системными средствами.
  ///
  /// Своего просмотрщика нет намеренно: у телефона и компьютера уже есть
  /// приложения для pdf, таблиц и картинок, и они умеют это лучше.
  Future<void> _openAttachment(ChatMessage m) async {
    final file = m.attachment;
    if (file == null || !file.isHere) return;
    await Share.shareXFiles([XFile(file.path)], text: file.name);
  }

  /// Откликнуться на сообщение.
  ///
  /// Тот же символ повторно снимает отклик — иначе случайно поставленный
  /// «палец вверх» убрать было бы нечем.
  Future<void> _react(ChatMessage m, String emoji) async {
    await MessageStore.react(id: m.id, by: ChatService.meId, emoji: emoji);
    ChatSync.nudge();
    if (mounted) setState(() {});
  }

  /// Показать набор откликов.
  Future<void> _pickReaction(ChatMessage m) async {
    final mine = m.reactions[ChatService.meId];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in MessageStore.reactionChoices)
              GestureDetector(
                onTap: () => Navigator.pop(context, e),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    // Свой отклик подсвечен: иначе непонятно, ставишь ты
                    // его или снимаешь.
                    color: e == mine
                        ? AppTheme.accent.withOpacity(0.18)
                        : AppTheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: e == mine
                          ? AppTheme.accent.withOpacity(0.6)
                          : AppTheme.glassBorder,
                    ),
                  ),
                  child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 24))),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _react(m, picked);
  }

  /// Поправить своё сообщение.
  Future<void> _edit(ChatMessage m) async {
    final controller = TextEditingController(text: m.body);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppTheme.glassBorder)),
        title: Text(_ru ? 'Поправить сообщение' : 'Edit message',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Отмена' : 'Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_ru ? 'Сохранить' : 'Save',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;

    final result = await MessageStore.edit(
      id: m.id,
      by: ChatService.meId,
      body: text,
    );
    if (!mounted) return;
    setState(() {});

    final complaint = switch (result) {
      MessageEditResult.ok || MessageEditResult.unchanged => null,
      MessageEditResult.gone =>
        _ru ? 'Сообщения больше нет' : 'The message is gone',
      MessageEditResult.notMine =>
        _ru ? 'Чужое сообщение править нельзя' : 'Not your message',
      MessageEditResult.notEditable =>
        _ru ? 'Это сообщение не правится' : 'This message cannot be edited',
      MessageEditResult.empty => _ru
          ? 'Пустое сообщение. Чтобы убрать его, удалите'
          : 'Empty message. Delete it instead',
    };
    if (complaint != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(complaint),
        backgroundColor: AppTheme.surface,
      ));
    }
  }

  /// Разметка ленты, живущая между кадрами.
  ///
  /// Пересчитывается только когда переписка изменилась. Иначе объект
  /// создавался заново на каждую перерисовку — а вместе с ним терялись
  /// отметки «про это место не спрашивать».
  ChatLayout _layoutFor(List<ChatMessage> messages) {
    final signature = messages.isEmpty
        ? 'пусто'
        : '${messages.length}/${messages.last.id}/${_manualMark(messages)}';
    if (_layout != null && _layoutFor_ == signature) return _layout!;

    _layout = _refined ?? TopicDivider.planFor(messages);
    _layoutFor_ = signature;
    return _layout!;
  }

  ChatLayout? _layout;
  String? _layoutFor_;

  /// Часть подписи состояния: сколько сообщений размечено вручную.
  ///
  /// Без этого разделение не появлялось бы до следующего сообщения:
  /// количество и последний идентификатор от нажатия «Разделить» не
  /// меняются, и разметка бралась бы из кэша — прежняя.
  static int _manualMark(List<ChatMessage> messages) {
    var n = 0;
    for (final m in messages) {
      if (m.topicId != null) n++;
    }
    return n;
  }

  /// Спросить модель про спорные границы тем.
  ///
  /// Запускается после кадра, а не вместо него: местная разметка рисуется
  /// сразу, модель уточняет её потом. Ждать ответа с пустым экраном ради
  /// заголовков — плохой размен.
  ///
  /// Если модель не настроена, [TopicRefiner] сам вернёт местный результат,
  /// и в разметке будет честно написано, чем она сделана.
  void _refineTopics(ChatThread chat) {
    if (_refining) return;

    // Переписку читаем **здесь**, а не берём из кадра, который нас позвал.
    //
    // Так и ломалась кнопка «Разделить». Вызов ставится в очередь после
    // каждой перерисовки, и в очереди оказывается вызов со списком,
    // прочитанным ДО разделения. Он досчитывал разметку по старому списку —
    // без ручных границ — и клал её поверх свежей. Заголовок пропадал,
    // вопрос возвращался, и со стороны это выглядело как «нажал, и ничего».
    final messages = MessageStore.of(chat.id);
    final prepared = TopicDivider.prepare(messages);
    if (prepared == null) return;

    // Подпись состояния: сколько сообщений, какое последнее и сколько
    // размечено руками. Последнее обязательно: от нажатия «Разделить»
    // количество и последний идентификатор не меняются, и без него
    // пересчёт считался бы уже сделанным.
    final signature = '${chat.id}/${messages.length}/${messages.last.id}'
        '/${_manualMark(messages)}';
    if (_refinedFor == signature) return;

    _refining = true;
    TopicRefiner
        .refine(
      messages: prepared.input,
      kind: chat.kind,
      judge: TopicPrivacy.modelWillBeAsked(chat.kind)
          ? AiTopicJudge()
          : const HeuristicJudge(),
      modelUrl: AiEndpoint.baseUrl,
    )
        .then((result) {
      if (!mounted) return;
      setState(() {
        _refined = TopicDivider.fromRefined(messages, prepared, result);
        _layout = null;
        _refinedFor = signature;
        _refining = false;
      });
    }).catchError((_) {
      // Модель не ответила — остаёмся на местной разметке. Ошибка модели не
      // должна мешать переписываться.
      //
      // Подпись состояния запоминается и здесь, а не только при успехе:
      // иначе неудача не запоминается, следующий кадр видит «ещё не
      // считали» и обращается снова — и так на каждый кадр, пока открыт
      // чат. Отказавшая модель превратилась бы в бесконечный поток запросов
      // ровно тогда, когда с ней и так что-то не так.
      if (mounted) {
        setState(() {
          _refinedFor = signature;
          _refining = false;
        });
      }
    });
  }

  Future<void> _settings(ChatThread chat) async {
    final left = await ChatSettingsSheet.show(context, chat.id);
    if (!mounted) return;
    // Вышли из группы — оставаться в её переписке не на что.
    if (left == true) {
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  void _stopSearch() => setState(() {
        _searching = false;
        _query = '';
        _search.clear();
      });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessageStore.revision,
      builder: (context, _, __) {
        final chat = _chat;
        if (chat == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Text(_ru ? 'Разговор удалён' : 'Chat removed',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
          );
        }
        final searching = _searching && _query.trim().isNotEmpty;
        final messages = searching
            ? MessageStore.search(chat.id, _query)
            : MessageStore.of(chat.id);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              children: [
                _header(chat),
                if (_searching) _searchBar(found: messages.length),
                Expanded(
                  child: messages.isEmpty
                      ? (searching ? _nothingFound() : _empty())
                      : _list(chat, messages, searching: searching),
                ),
                // В поиске нижняя часть не нужна: там показан не разговор, а
                // выборка из него, и «ответить» на строчку из выборки значило
                // бы ответить непонятно куда.
                if (!_searching) ...[
                  if (_replyTo != null) _replyBar(),
                  _composer(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(ChatThread chat) {
    final other = chat.otherThan(ChatService.meId);
    final person = other == null ? null : TeamService.byId(other);
    // Две строки под названием собираются из настоящего положения дел, а не
    // пишутся руками: кто читает — и уедет ли написанное отсюда вообще.
    final local = ChatDelivery.whyLocal(chat, russian: _ru);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          8, kTitleBarInset + 10, kHasCustomTitleBar ? 148 : 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.arrow_back,
                color: AppTheme.textPrimary),
            onPressed: () =>
                _searching ? _stopSearch() : Navigator.pop(context),
          ),
          if (person != null)
            WesiAvatar(size: 34, index: person.avatarIndex, photo: person.photo)
          else
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Icon(Icons.groups_outlined,
                  size: 17, color: AppTheme.textMuted),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ChatService.titleOf(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 1),
                // Кто читает переписку — прямо в шапке, а не в настройках.
                // Человек должен видеть это, когда пишет, а не когда ищет.
                Text(
                  TopicPrivacy.describe(chat.kind, russian: _ru),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                ),
                if (local != null)
                  Text(
                    local,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: _ru ? 'Поиск' : 'Search',
            icon: Icon(Icons.search, size: 19, color: AppTheme.textMuted),
            onPressed: () => setState(() => _searching = !_searching),
          ),
          IconButton(
            tooltip: _ru ? 'О разговоре' : 'About the chat',
            icon: Icon(Icons.tune, size: 18, color: AppTheme.textMuted),
            onPressed: () => _settings(chat),
          ),
        ],
      ),
    );
  }

  Widget _searchBar({required int found}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: TextField(
          controller: _search,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: _ru ? 'Искать в переписке' : 'Search this chat',
            hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            prefixIcon:
                Icon(Icons.search, size: 18, color: AppTheme.textMuted),
            suffixIcon: _query.trim().isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _ru ? 'найдено $found' : '$found found',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                  ),
            isDense: true,
            filled: true,
            fillColor: AppTheme.surfaceLight.withOpacity(0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
      );

  Widget _nothingFound() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _ru
                ? 'Ничего не найдено.\n\nПоиск идёт по тому, что ещё хранится: '
                    'сообщения старше срока уже стёрты, а сохранённое навсегда '
                    'ищется в архиве.'
                : 'Nothing found.\n\nOnly messages still kept are searched; '
                    'archived ones are searched in the archive.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
          ),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _ru
                ? 'Сообщений пока нет.\n\nОбычные сообщения хранятся месяц. '
                    'Всё, что должно остаться навсегда, — долгим нажатием '
                    'в архив.'
                : 'No messages yet.\n\nOrdinary messages are kept for a '
                    'month. Long-press to archive what must survive.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppTheme.textMuted),
          ),
        ),
      );

  Widget _list(
    ChatThread chat,
    List<ChatMessage> messages, {
    required bool searching,
  }) {
    // Блоки тем считаются из самой переписки. Заголовок вставляется перед
    // первым сообщением каждого блока, а спорные места превращаются в
    // карточку с вопросом.
    //
    // В поиске блоков нет намеренно: они считаются по паузам и по тому, как
    // меняется словарь от сообщения к сообщению, а в выборке соседние
    // сообщения — не соседние. Границы получились бы выдуманными, и вопрос
    // «разделить тут?» задавался бы про место, которого в разговоре нет.
    //
    // Вне поиска сначала рисуем местную разметку, а следующим кадром просим
    // модель уточнить её. Так заголовки появляются сразу, а не после
    // ожидания сети.
    //
    // Разметка держится в состоянии, а не считается заново на каждый кадр.
    // Пересчёт выбрасывал объект вместе с пометками «не надо»: человек
    // отвечал на вопрос, следующий кадр строил новую разметку, и тот же
    // вопрос возвращался. Со стороны кнопка «Не надо» не работала.
    final blocks = searching ? null : _layoutFor(messages);
    if (!searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refineTopics(chat);
      });
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final mine = m.authorId == ChatService.meId;
        final divider = blocks?.headerAt(i);
        final question = blocks?.questionAt(i);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (divider != null) TopicDivider(title: divider),
            if (question != null)
              TopicQuestionCard(
                question: question,
                onSplit: () => _splitAt(messages, question.index),
                onKeep: () =>
                    setState(() => blocks?.dismiss(question.index)),
              ),
            // В выборке рядом оказываются сообщения из разных дней, и без
            // даты непонятно, что именно нашлось.
            if (searching) _foundAt(m),
            MessageBubble(
              message: m,
              mine: mine,
              showAuthor: chat.isGroup && !mine,
              replyTo: m.replyTo == null
                  ? null
                  : MessageStore.byId(m.replyTo!),
              onLongPress: () => _actions(m),
              highlight: searching ? _query : '',
              onReact: (emoji) => _react(m, emoji),
              onOpenAttachment: () => _openAttachment(m),
            ),
          ],
        );
      },
    );
  }

  Widget _foundAt(ChatMessage m) {
    final at = m.at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final who = TeamService.byId(m.authorId)?.displayName ??
        (m.authorId == ChatService.meId ? (_ru ? 'Вы' : 'You') : '');
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2, left: 4, right: 4),
      child: Text(
        '${[
          if (who.isNotEmpty) who,
        ].join()} · ${two(at.day)}.${two(at.month)}.${at.year} '
            '${two(at.hour)}:${two(at.minute)}',
        style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
      ),
    );
  }

  Future<void> _splitAt(List<ChatMessage> messages, int index) async {
    // Разделение — это метка темы на сообщениях после границы, а не
    // удаление и не перенос. Ничего не теряется, и решение обратимо.
    //
    // Разметку, посчитанную до этого, выбрасываем целиком — и местную, и
    // полученную от модели. Иначе граница записалась бы, а на экране
    // осталась бы прежняя картинка: ровно то, из-за чего кнопка выглядела
    // неработающей.
    _layout = null;
    _refined = null;
    _refinedFor = null;

    final topicId = 't${DateTime.now().microsecondsSinceEpoch}';
    await MessageStore.assignTopic(
      [for (var i = index; i < messages.length; i++) messages[i].id],
      topicId,
    );
    if (mounted) setState(() {});
  }

  Widget _replyBar() => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          border: Border(top: BorderSide(color: AppTheme.glassBorder)),
        ),
        child: Row(
          children: [
            Container(width: 2.5, height: 30, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru ? 'Ответ' : 'Reply',
                    style: TextStyle(fontSize: 10, color: AppTheme.accent),
                  ),
                  Text(
                    _replyTo!.isSticker ? '🖼' : _replyTo!.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 17, color: AppTheme.textMuted),
              onPressed: () => setState(() => _replyTo = null),
            ),
          ],
        ),
      );

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.35),
        border: Border(top: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: _ru ? 'Стикеры' : 'Stickers',
            icon: Icon(Icons.emoji_emotions_outlined,
                size: 22, color: AppTheme.textMuted),
            onPressed: _stickers,
          ),
          IconButton(
            tooltip: _ru ? 'Приложить файл' : 'Attach a file',
            icon: Icon(Icons.attach_file,
                size: 21, color: AppTheme.textMuted),
            onPressed: _attach,
          ),
          Expanded(
            child: ConstrainedBox(
              // Растёт до пяти строк и дальше прокручивается: без предела
              // длинное сообщение выдавило бы переписку с экрана целиком.
              constraints: const BoxConstraints(maxHeight: 116),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: _ru ? 'Сообщение' : 'Message',
                  hintStyle:
                      TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppTheme.surfaceLight.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.glassBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _input.text.trim().isEmpty ? null : _send,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _input.text.trim().isEmpty
                    ? AppTheme.surface
                    : AppTheme.accent.withOpacity(0.2),
                border: Border.all(
                  color: _input.text.trim().isEmpty
                      ? AppTheme.glassBorder
                      : AppTheme.accent.withOpacity(0.6),
                ),
              ),
              child: Icon(
                Icons.arrow_upward,
                size: 19,
                color: _input.text.trim().isEmpty
                    ? AppTheme.textMuted
                    : AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Что можно сделать с сообщением.
class _MessageActions extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onReact;
  final VoidCallback onChanged;

  const _MessageActions({
    required this.message,
    required this.mine,
    required this.onReply,
    required this.onEdit,
    required this.onReact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            context,
            Icons.reply,
            ru ? 'Ответить' : 'Reply',
            () {
              Navigator.pop(context);
              onReply();
            },
          ),
          if (!message.isSystem)
            _row(
              context,
              Icons.add_reaction_outlined,
              ru ? 'Отклик' : 'React',
              () {
                Navigator.pop(context);
                onReact();
              },
              hint: ru
                  ? 'Ответить, не прерывая разговор'
                  : 'Answer without interrupting',
            ),
          // Править можно только своё и только слова. Отказ показывается не
          // здесь, а в самом хранилище: правило, живущее в одном экране,
          // обходится вторым.
          if (mine && message.editable)
            _row(
              context,
              Icons.edit_outlined,
              ru ? 'Изменить' : 'Edit',
              () {
                Navigator.pop(context);
                onEdit();
              },
              hint: ru
                  ? 'У сообщения появится пометка «изменено»'
                  : 'The message will be marked as edited',
            ),
          if (!message.isSticker)
            _row(
              context,
              Icons.copy_all_outlined,
              ru ? 'Скопировать' : 'Copy',
              () {
                Clipboard.setData(ClipboardData(text: message.body));
                Navigator.pop(context);
              },
            ),
          if (message.archived)
            _row(
              context,
              Icons.unarchive_outlined,
              ru ? 'Убрать из архива' : 'Remove from archive',
              () async {
                await MessageStore.unarchive(message.id);
                if (context.mounted) Navigator.pop(context);
                onChanged();
              },
              hint: ru
                  ? 'Снова начнёт храниться месяц'
                  : 'Will be kept for a month again',
            )
          else
            _row(
              context,
              Icons.archive_outlined,
              ru ? 'В архив' : 'Archive',
              () async {
                await MessageStore.archiveMessage(message.id);
                if (context.mounted) Navigator.pop(context);
                onChanged();
              },
              hint: ru
                  ? 'Останется навсегда, даже когда чат очистится'
                  : 'Kept forever, even when the chat is cleared',
            ),
          _row(
            context,
            Icons.delete_outline,
            ru ? 'Удалить' : 'Delete',
            () async {
              final removed = await MessageStore.remove(message.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (!removed) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ru
                      ? 'Архивное сообщение не удаляется — сначала уберите '
                          'его из архива'
                      : 'Archived messages cannot be deleted'),
                  backgroundColor: AppTheme.surface,
                ));
              }
              onChanged();
            },
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? hint,
    bool danger = false,
  }) {
    final color = danger ? AppTheme.accentRed : AppTheme.textPrimary;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 19, color: color),
      title: Text(label, style: TextStyle(fontSize: 13.5, color: color)),
      subtitle: hint == null
          ? null
          : Text(hint,
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
      onTap: onTap,
    );
  }
}
