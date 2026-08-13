import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

import 'fake_sync_transport.dart';

/// Сценарии, в которых устройств больше двух и события идут внахлёст.
///
/// «То задачи отваливаются» — это почти всегда не одна поломка, а стечение
/// обстоятельств: кто-то правил в офлайне, кто-то удалил, кто-то вернулся
/// через неделю. Такие расклады руками не проверить, а цена ошибки — не
/// «неудобно», а «данные пропали».
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 12, 12);

  Box<TaskModel> taskBox() => Hive.box<TaskModel>('wesios_tasks');

  TaskModel task(String id, String title) => TaskModel(
        id: id,
        title: title,
        status: TaskStatus.backlog,
        priority: TaskPriority.normal,
        createdAt: base,
      );

  Map<String, dynamic> taskFields(String id, String title) => {
        'id': id,
        'title': title,
        'status': 'backlog',
        'priority': 'normal',
        'createdAt': base.toIso8601String(),
        'order': 0,
      };

  /// Правка «от человека»: пишем в бокс и ставим отметку нужным временем.
  Future<void> edit(String id, String title, DateTime at) async {
    await taskBox().put(id, task(id, title));
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('tasks', id, SyncStamp(at));
  }

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_multi');
    Hive.init(dir.path);
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(AccountKindAdapter());
    Hive.registerAdapter(AccountModelAdapter());
    Hive.registerAdapter(ArticleSectionAdapter());
    Hive.registerAdapter(ArticleModelAdapter());
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<ArticleModel>('wesios_knowledge');
    await Hive.openBox<EmployeeModel>('wesios_team');
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    for (final c in SyncCodec.collections) {
      await c.box()?.clear();
    }
    await SyncEngine.prepare(now: base);
    // Не первый обмен: правило «принимаем сервер» проверяется отдельно и
    // здесь только мешало бы увидеть обычное слияние.
    await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
  });

  test('правка позже удаления возвращает задачу к жизни', () async {
    // Один удалил, второй через час передумал и переоткрыл. Победить обязана
    // более поздняя правка: удаление не должно быть сильнее только потому,
    // что оно удаление.
    final t = FakeSyncTransport();
    t.seed('tasks', 'T1', const {}, base, deleted: true);

    await edit('T1', 'Всё-таки делаем', base.add(const Duration(hours: 1)));
    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    expect(taskBox().get('T1')?.title, 'Всё-таки делаем');
    expect(t.store['tasks']!['T1']!.deleted, isFalse,
        reason: 'сервер обязан узнать, что задачу вернули');
  });

  test('удаление позже правки уносит задачу у всех', () async {
    final t = FakeSyncTransport();
    await edit('T2', 'Черновик', base);
    await SyncEngine.run(transport: t, now: base);
    expect(t.store['tasks']!['T2']!.deleted, isFalse);

    // Второе устройство удалило задачу позже.
    t.seed('tasks', 'T2', const {}, base.add(const Duration(hours: 1)),
        deleted: true);

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));
    expect(taskBox().containsKey('T2'), isFalse,
        reason: 'удаление обязано доехать');
  });

  test('устройство, пролежавшее неделю, не воскрешает удалённое', () async {
    // Классика: ноутбук лежал выключенным, на нём осталась запись, которую
    // за это время удалили с телефона. Надгробие на сервере обязано победить.
    final t = FakeSyncTransport();
    await edit('T3', 'Старая задача', base);
    await SyncEngine.run(transport: t, now: base);

    final week = base.add(const Duration(days: 7));
    t.seed('tasks', 'T3', const {}, week, deleted: true);

    await SyncEngine.run(transport: t, now: week.add(const Duration(hours: 1)));
    expect(taskBox().containsKey('T3'), isFalse);
  });

  test('трое правят разные задачи — не теряется ни одна', () async {
    final t = FakeSyncTransport();
    // Двое уже положили своё на сервер.
    t.seed('tasks', 'A', taskFields('A', 'От Ани'), base);
    t.seed('tasks', 'B', taskFields('B', 'От Бори'), base);
    // Третий правит своё, ничего не зная о первых двух.
    await edit('C', 'От Веси', base);

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(minutes: 1)));

    final titles = {
      for (final id in ['A', 'B', 'C']) id: taskBox().get(id)?.title,
    };
    expect(titles, {'A': 'От Ани', 'B': 'От Бори', 'C': 'От Веси'});
    expect(t.store['tasks']!.length, 3,
        reason: 'на сервере обязаны оказаться все три');
  });

  test('офлайн-правки уезжают все разом, когда связь вернулась', () async {
    final t = FakeSyncTransport()
      ..failWith = const SyncFailure('NETWORK', 'нет сети');

    for (var i = 1; i <= 5; i++) {
      await edit('O$i', 'Офлайн $i', base.add(Duration(minutes: i)));
    }
    final offline = await SyncEngine.run(transport: t, now: base);
    expect(offline.ok, isFalse);

    t.failWith = null;
    final online = await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 1)));

    expect(online.ok, isTrue, reason: online.describe());
    expect(t.store['tasks']!.length, 5,
        reason: 'ни одна офлайн-правка не должна потеряться');
  });

  test('запись от более новой версии не мешает остальным', () async {
    final t = FakeSyncTransport();
    // Поле, которого эта версия не понимает, и обязательного createdAt нет —
    // запись не разберётся.
    t.seed('tasks', 'FUTURE', {'id': 'FUTURE', 'somethingNew': 42}, base);
    t.seed('tasks', 'OK', taskFields('OK', 'Обычная'), base);

    final report = await SyncEngine.run(transport: t, now: base);

    expect(taskBox().get('OK')?.title, 'Обычная',
        reason: 'непонятная соседняя запись не должна мешать');
    expect(taskBox().containsKey('FUTURE'), isFalse);
    // Отметка сброшена в начало времён — на следующем проходе, уже после
    // обновления приложения, запись попробуют разобрать снова.
    expect(SyncJournal.stampOf('tasks', 'FUTURE')?.updatedAt.year, 1970);
    expect(report.ok, isTrue);
  });

  test('одна и та же правка не ходит по кругу между устройствами', () async {
    // Применив чужую правку, устройство не должно объявить её своей и
    // отправить обратно — иначе двое устройств будут гонять запись вечно.
    final t = FakeSyncTransport();
    t.seed('tasks', 'LOOP', taskFields('LOOP', 'Приехала'), base);

    await SyncEngine.run(transport: t, now: base.add(const Duration(minutes: 1)));
    t.calls.clear();

    final second = await SyncEngine.run(
        transport: t, now: base.add(const Duration(minutes: 2)));

    expect(second.uploaded, 0,
        reason: 'отправлять нечего: правка чужая и уже применена');
    expect(t.calls.where((c) => c.startsWith('push:tasks')), isEmpty);
  });

  test('порядок коллекций не даёт операции обогнать свой счёт', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names.indexOf('accounts'), lessThan(names.indexOf('transactions')),
        reason: 'операция без счёта показалась бы висящей в воздухе');
    expect(names.indexOf('employees'), lessThan(names.indexOf('chats')));
    expect(names.indexOf('chats'), lessThan(names.indexOf('messages')));
    expect(names.indexOf('roadmap_projects'),
        lessThan(names.indexOf('roadmap_items')),
        reason: 'веха без своего проекта осталась бы сиротой');
    expect(names.indexOf('crm_clients'), lessThan(names.indexOf('crm_deals')));
    expect(names.indexOf('crm_deals'),
        lessThan(names.indexOf('crm_interactions')));
  });
}
