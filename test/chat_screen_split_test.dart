import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/chats/chat_screen.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/models/chat_thread.dart';
import 'package:wesios/features/chats/services/chat_service.dart';
import 'package:wesios/features/chats/services/message_store.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

/// Кнопка «Разделить» — нажатием, на настоящем экране.
///
/// Проверять её отдельно от экрана бесполезно: сама карточка нажимается
/// прекрасно, а ломалось всё вокруг неё. Сначала записанная метка никем не
/// читалась, потом метки ставились по одной с ожиданием диска — и на живой
/// переписке между нажатием и любым видимым откликом проходила секунда.
/// Со стороны это ровно «кнопка не нажимается».
///
/// ВАЖНО: `Hive.close()` в конце здесь **нельзя**. Экран пишет в Hive из
/// initState, а под поддельным временем `testWidgets` такая запись не
/// завершается никогда — закрытие на ней виснет навсегда.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 5, 10);
  final later = base.add(const Duration(days: 1));

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_split_screen');
    Hive.init(dir.path);
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(MessageKindAdapter());
    Hive.registerAdapter(DeliveryStateAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(ChatThreadAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await MessageStore.open();
    await ChatService.open();
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  setUp(() async {
    await Hive.box<ChatMessage>(MessageStore.boxName).clear();
    await Hive.box<ChatThread>(ChatService.boxName).clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();

    await TeamService.save(EmployeeModel(
      id: 'own',
      login: 'own',
      fullName: 'Владелец',
      isOwner: true,
      permissions: TeamPermissions.owner,
      createdAt: base,
    ));
    await TeamService.save(EmployeeModel(
      id: 'e2',
      login: 'e2',
      fullName: 'Иван',
      permissions: const TeamPermissions(),
      createdAt: base,
    ));

    final chat = await ChatService.direct('e2', now: base);
    // Разговор с явной сменой темы посередине: склад → прайс, плюс пауза.
    const lines = [
      'Отгрузили десять паллет на склад в Пушкино вчера вечером',
      'Принял, накладные подпишу и передам в бухгалтерию',
      'Там ещё две паллеты остались, не влезли в машину совсем',
      'Прайс поставщика комплектующих вырос на восемь процентов',
      'Восемь процентов это много, ищем второго поставщика срочно',
      'По прайсу решение нужно принять до конца недели обязательно',
    ];
    for (var i = 0; i < lines.length; i++) {
      await MessageStore.send(
        chatId: chat.id,
        authorId: i.isEven ? 'own' : 'e2',
        body: lines[i],
        now: base.add(Duration(minutes: i * 3 + (i == 3 ? 300 : 0))),
      );
    }
  });

  Future<ChatThread> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chat = ChatService.all().first;
    await tester.pumpWidget(MaterialApp(home: ChatScreen(chatId: chat.id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return chat;
  }

  List<int> markedPositions(String chatId) => MessageStore.of(chatId, now: later)
      .asMap()
      .entries
      .where((e) => e.value.topicId != null)
      .map((e) => e.key)
      .toList();

  testWidgets('вопрос показан, нажатие делит, карточка пропадает',
      (tester) async {
    // Один виджет-тест на файл — намеренно.
    //
    // Экран пишет в Hive из initState, а под поддельным временем такая
    // запись не завершается. Незавершённые записи первого теста повисают на
    // боксе, и `clear()` в подготовке второго ждёт их вечно. Проверять по
    // одному экрану за файл дешевле, чем городить обходные пути.
    final chat = await open(tester);

    expect(find.text('Разделить'), findsOneWidget,
        reason: 'вопрос о разделении должен показаться');
    expect(markedPositions(chat.id), isEmpty);

    await tester.tap(find.text('Разделить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Здесь ловилась настоящая поломка: метки ставились циклом с ожиданием
    // диска на каждой, и до конца доходила одна. Получался блок из одного
    // сообщения — на экране почти незаметный, и кнопка выглядела мёртвой.
    final marked = markedPositions(chat.id);
    expect(marked.length, greaterThan(1),
        reason: 'блок из одного сообщения означает, что пометилось не всё');
    expect(marked.last, MessageStore.of(chat.id, now: later).length - 1,
        reason: 'помечено должно быть до конца переписки');

    // Вопрос, который остаётся после ответа, — это тот же «не нажимается»:
    // человек нажал, а карточка на месте. Так и было, пока экран узнавал об
    // изменении только после записи на диск.
    expect(find.text('Разделить'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
