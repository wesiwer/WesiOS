import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_transport.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

import 'fake_sync_transport.dart';

/// Синхронизация — единственное место, где ошибка стоит не «неудобно», а
/// «данные пропали». Поэтому проверяется весь путь целиком: правка в боксе →
/// отметка в журнале → слияние → отправка, и обратно.
void main() {
  late Directory dir;

  final base = DateTime.utc(2026, 8, 4, 12);

  Box<TransactionModel> txBox() =>
      Hive.box<TransactionModel>('wesios_treasury');
  Box<TaskModel> taskBox() => Hive.box<TaskModel>('wesios_tasks');

  TransactionModel tx(String id, {double amount = 100, String title = 'Хлеб'}) =>
      TransactionModel(
        id: id,
        title: title,
        amount: amount,
        type: TransactionType.expense,
        date: base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_sync_test');
    Hive.init(dir.path);
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
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
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(OrganizationAccessGrantAdapter());
    Hive.registerAdapter(InterOrgTransferTypeAdapter());
    Hive.registerAdapter(InterOrgTransferModelAdapter());
    Hive.registerAdapter(TransactionAuditModelAdapter());

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
  });

  // ------------------------------------------------------------------ журнал

  group('журнал', () {
    test('отметка кодируется и читается обратно без потерь', () {
      final s = SyncStamp(DateTime.utc(2026, 8, 4, 12, 30, 15, 250));
      final back = SyncStamp.decode(s.encode())!;
      expect(back.updatedAt, s.updatedAt);
      expect(back.deleted, isFalse);

      final dead = SyncStamp(s.updatedAt, deleted: true);
      expect(SyncStamp.decode(dead.encode())!.deleted, isTrue);
    });

    test('мусор вместо отметки не разбирается, а не притворяется нулём', () {
      expect(SyncStamp.decode('вообще не отметка'), isNull);
      expect(SyncStamp.decode(null), isNull);
      expect(SyncStamp.decode(42), isNull);
    });

    test('правка в боксе сама попадает в журнал', () async {
      await txBox().put('t1', tx('t1'));
      await Future<void>.delayed(Duration.zero);

      final stamp = SyncJournal.stampOf('transactions', 't1');
      expect(stamp, isNotNull,
          reason: 'подписка на бокс не сработала — записи не отметились');
      expect(stamp!.deleted, isFalse);
    });

    test('удаление оставляет надгробие, а не пустоту', () async {
      await txBox().put('t1', tx('t1'));
      await Future<void>.delayed(Duration.zero);
      await txBox().delete('t1');
      await Future<void>.delayed(Duration.zero);

      final stamp = SyncJournal.stampOf('transactions', 't1');
      expect(stamp?.deleted, isTrue,
          reason: 'без надгробия удаление воскреснет с другого устройства');
    });

    test('старые надгробия выбрасываются, живые отметки — нет', () async {
      await SyncJournal.record(
          'transactions', 'old', SyncStamp(base, deleted: true));
      await SyncJournal.record(
          'transactions', 'fresh', SyncStamp(base, deleted: true));
      await SyncJournal.record('transactions', 'alive', SyncStamp(base));

      await SyncJournal.pruneTombstones(base.add(const Duration(days: 200)),
          keepFor: const Duration(days: 180));
      expect(SyncJournal.stampOf('transactions', 'old'), isNull);
      expect(SyncJournal.stampOf('transactions', 'alive'), isNotNull,
          reason: 'живая отметка без времени = «не менялось никогда»');

      await SyncJournal.record(
          'transactions', 'fresh', SyncStamp(base, deleted: true));
      await SyncJournal.pruneTombstones(base.add(const Duration(days: 10)));
      expect(SyncJournal.stampOf('transactions', 'fresh'), isNotNull);
    });

    test('засев отмечает только записи без отметки', () async {
      await SyncJournal.record('transactions', 'known', SyncStamp(base));
      await SyncJournal.seed('transactions', ['known', 'unknown'],
          base.add(const Duration(days: 1)));

      expect(SyncJournal.stampOf('transactions', 'known')!.updatedAt, base);
      expect(SyncJournal.stampOf('transactions', 'unknown')!.updatedAt,
          base.add(const Duration(days: 1)));
    });
  });

  // -------------------------------------------------------------------- кодек

  group('кодек', () {
    test('операция переживает круг через поля', () {
      final c = TransactionsSync();
      final original = TransactionModel(
        id: 't9',
        title: 'Аренда',
        amount: 45000.5,
        type: TransactionType.expense,
        date: DateTime.utc(2026, 7, 1, 9, 30),
        category: 'Офис',
        description: 'за июль',
        isRecurring: true,
        recurringPeriod: RecurringPeriod.monthly,
        isAnomaly: true,
        zScore: 2.75,
        accountId: 'acc1',
      );
      final back = c.decode(c.encode(original))!;

      expect(back.id, original.id);
      expect(back.title, original.title);
      expect(back.amount, original.amount);
      expect(back.type, original.type);
      expect(back.date, original.date);
      expect(back.category, original.category);
      expect(back.description, original.description);
      expect(back.isRecurring, isTrue);
      expect(back.recurringPeriod, RecurringPeriod.monthly);
      expect(back.isAnomaly, isTrue);
      expect(back.zScore, 2.75);
      expect(back.accountId, 'acc1');
    });

    test('задача переживает круг вместе с чек-листом', () {
      final c = TasksSync();
      final original = TaskModel(
        id: 'k1',
        title: 'Сдать отчёт',
        description: 'до пятницы',
        status: TaskStatus.review,
        priority: TaskPriority.urgent,
        createdAt: base,
        dueDate: base.add(const Duration(days: 3)),
        assignee: 'amber',
        subtasks: const [
          SubTask(title: 'собрать цифры', done: true),
          SubTask(title: 'проверить'),
        ],
        tags: const ['работа', 'срочно'],
        order: 7,
      );
      final back = c.decode(c.encode(original))!;

      expect(back.status, TaskStatus.review);
      expect(back.priority, TaskPriority.urgent);
      expect(back.dueDate, original.dueDate);
      expect(back.subtasks.length, 2);
      expect(back.subtasks.first.done, isTrue);
      expect(back.subtasks.last.done, isFalse);
      expect(back.tags, containsAll(['работа', 'срочно']));
      expect(back.tags.where((tag) => !tag.startsWith('wesios:')), ['работа', 'срочно']);
      expect(back.order, 7);
    });

    test('человек переживает круг вместе с правами и хешем пароля', () {
      final c = EmployeesSync();
      final original = EmployeeModel(
        id: 'e1',
        login: 'amber',
        fullName: 'Иван Петров',
        position: 'Логист',
        phone: '+79990000000',
        socials: const {'Telegram': '@amber'},
        notes: 'ставка обсуждается',
        permissions: const TeamPermissions(
          moduleList: ['tasks', 'treasury'],
          knowledgeIdList: ['a1'],
          canSeeNotes: true,
        ),
        passwordHash: 'hash',
        passwordSalt: 'salt',
        avatarIndex: 3,
        createdAt: base,
        demoStats: const {'balance': 1000.0},
      );
      final back = c.decode(c.encode(original))!;

      expect(back.login, 'amber');
      expect(back.socials['Telegram'], '@amber');
      expect(back.notes, 'ставка обсуждается');
      expect(back.permissions.modules, {'tasks', 'treasury'});
      expect(back.permissions.knowledgeIds, {'a1'});
      expect(back.permissions.canSeeNotes, isTrue);
      // Хеш обязан уехать: без него человек не войдёт со второго устройства.
      expect(back.passwordHash, 'hash');
      expect(back.passwordSalt, 'salt');
      expect(back.demoStats['balance'], 1000.0);
    });

    test('запись без обязательных полей не разбирается', () {
      final c = TransactionsSync();
      expect(c.decode({'title': 'без id'}), isNull);
      expect(c.decode({'id': 't1', 'date': base.toIso8601String()}), isNull,
          reason: 'операция без суммы — это не операция');
      expect(c.decode({'id': 't1', 'amount': 10}), isNull,
          reason: 'операция без даты не встанет ни в один отчёт');
    });

    test('незнакомое значение перечисления не роняет разбор', () {
      final c = TasksSync();
      final back = c.decode({
        'id': 'k1',
        'title': 'из будущей версии',
        'createdAt': base.toIso8601String(),
        'status': 'quantum',
      });
      expect(back, isNotNull);
      expect(back!.status, TaskStatus.backlog);
    });

    test('встроенные статьи в обмен не идут', () {
      final c = ArticlesSync();
      final builtin = ArticleModel(
        id: 'wesios_about',
        title: 'О программе',
        body: '[]',
        section: ArticleSection.about,
        createdAt: base,
        updatedAt: base,
        builtIn: true,
      );
      final mine = ArticleModel(
        id: 'mine',
        title: 'Моя',
        body: '[]',
        section: ArticleSection.guide,
        createdAt: base,
        updatedAt: base,
      );
      expect(c.shouldSync(builtin), isFalse);
      expect(c.shouldSync(mine), isTrue);
    });

    test('имена коллекций уникальны и счета идут раньше операций', () {
      final names = [for (final c in SyncCodec.collections) c.name];
      expect(names.toSet().length, names.length);
      expect(names.indexOf('accounts'), lessThan(names.indexOf('transactions')),
          reason: 'операция не должна ни кадра ссылаться на несуществующий счёт');
    });
  });

  // ------------------------------------------------------------------ движок

  group('движок', () {
    test('без входа честно говорит об этом', () async {
      // Адрес зашит в сборку, поэтому «сервер не настроен» больше не
      // существует как состояние: единственная причина, по которой обмен
      // не идёт из коробки, — отсутствие входа. Про неё и надо говорить.
      final report = await SyncEngine.run(now: base);
      expect(report.ok, isFalse);
      expect(report.firstFailure?.code, 'NOT_SIGNED_IN');
    });

    test('без входа не пытается ничего отправить', () async {
      final t = FakeSyncTransport(signedIn: false);
      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.firstFailure?.code, 'NOT_SIGNED_IN');
      expect(t.calls, isEmpty, reason: 'ходить на сервер без входа незачем');
    });

    test('местная запись уезжает на сервер', () async {
      await txBox().put('t1', tx('t1'));
      await Future<void>.delayed(Duration.zero);

      final t = FakeSyncTransport();
      final report = await SyncEngine.run(transport: t, now: base);

      expect(report.ok, isTrue, reason: report.describe());
      expect(t.store['transactions']!.containsKey('t1'), isTrue);
      expect(t.store['transactions']!['t1']!.fields['title'], 'Хлеб');
      expect(report.uploaded, greaterThanOrEqualTo(1));
    });

    test('чужая запись приезжает и попадает в бокс', () async {
      final t = FakeSyncTransport();
      t.seed(
        'transactions',
        'remote1',
        TransactionsSync().encode(tx('remote1', title: 'Молоко')),
        base,
      );

      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isTrue, reason: report.describe());
      expect(txBox().get('remote1')?.title, 'Молоко');
      expect(report.applied, 1);
    });

    test('применённая чужая запись не уезжает обратно на следующем проходе',
        () async {
      // Ровно та качель, ради которой в журнале есть «ожидания»: без них
      // приезд чужой правки отмечается как своя, и она бесконечно ходит
      // между устройствами.
      final t = FakeSyncTransport();
      t.seed('transactions', 'remote1',
          TransactionsSync().encode(tx('remote1')), base);

      await SyncEngine.run(transport: t, now: base);
      await Future<void>.delayed(Duration.zero);

      t.calls.clear();
      final second =
          await SyncEngine.run(transport: t, now: base.add(const Duration(minutes: 1)));

      expect(second.uploaded, 0,
          reason: 'чужую правку отправили обратно — она будет ходить по кругу');
      expect(second.applied, 0);
      expect(t.calls.where((c) => c.startsWith('push:transactions')), isEmpty);
    });

    test('более свежая местная правка побеждает серверную', () async {
      // Устройство уже обменивалось: правило первого обмена («по спорным
      // записям принимаем сервер») здесь не действует.
      await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));

      final t = FakeSyncTransport();
      t.seed('transactions', 't1',
          TransactionsSync().encode(tx('t1', title: 'Старое')), base);

      await txBox().put('t1', tx('t1', title: 'Новое'));
      await SyncJournal.record(
          'transactions', 't1', SyncStamp(base.add(const Duration(hours: 1))));

      await SyncEngine.run(transport: t, now: base.add(const Duration(hours: 2)));

      expect(txBox().get('t1')!.title, 'Новое');
      expect(t.store['transactions']!['t1']!.fields['title'], 'Новое');
    });

    test('более свежая серверная правка побеждает местную', () async {
      await txBox().put('t1', tx('t1', title: 'Местное'));
      await Future<void>.delayed(Duration.zero);
      await SyncJournal.record('transactions', 't1', SyncStamp(base));

      final t = FakeSyncTransport();
      t.seed('transactions', 't1',
          TransactionsSync().encode(tx('t1', title: 'Серверное')),
          base.add(const Duration(hours: 1)));

      await SyncEngine.run(transport: t, now: base.add(const Duration(hours: 2)));
      expect(txBox().get('t1')!.title, 'Серверное');
    });

    test('удаление на другом устройстве стирает запись здесь', () async {
      await txBox().put('t1', tx('t1'));
      await Future<void>.delayed(Duration.zero);
      await SyncJournal.record('transactions', 't1', SyncStamp(base));

      final t = FakeSyncTransport();
      t.seed('transactions', 't1', const {},
          base.add(const Duration(hours: 1)), deleted: true);

      await SyncEngine.run(transport: t, now: base.add(const Duration(hours: 2)));

      expect(txBox().get('t1'), isNull,
          reason: 'удаление не доехало — запись живёт на одном устройстве');
      expect(SyncJournal.stampOf('transactions', 't1')?.deleted, isTrue);
    });

    test('удаление здесь уезжает надгробием, а не исчезновением', () async {
      await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
      final t = FakeSyncTransport();
      await txBox().put('t1', tx('t1'));
      await Future<void>.delayed(Duration.zero);
      await SyncEngine.run(transport: t, now: base);

      await txBox().delete('t1');
      await Future<void>.delayed(Duration.zero);
      await SyncEngine.run(transport: t, now: base.add(const Duration(hours: 1)));

      final onServer = t.store['transactions']!['t1']!;
      expect(onServer.deleted, isTrue,
          reason: 'без надгробия второе устройство выгрузит запись обратно');
    });

    test('обрыв связи не портит местные данные', () async {
      await txBox().put('t1', tx('t1', title: 'Целое'));
      await Future<void>.delayed(Duration.zero);

      final t = FakeSyncTransport()..failWith = SyncFailure.offline;
      final report = await SyncEngine.run(transport: t, now: base);

      expect(report.ok, isFalse);
      expect(report.firstFailure?.code, 'NETWORK');
      expect(txBox().get('t1')?.title, 'Целое');
      expect(SyncEndpoint.lastRun, isNull,
          reason: 'неудачный проход не должен отмечаться как удачный');
    });

    test('отказ одной коллекции не выдаётся за общий успех', () async {
      final t = _FailingOnceTransport('tasks');
      await txBox().put('t1', tx('t1'));
      await taskBox().put(
          'k1', TaskModel(id: 'k1', title: 'Задача', createdAt: base));
      await Future<void>.delayed(Duration.zero);

      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isFalse);
      expect(report.uploaded, greaterThan(0),
          reason: 'остальные коллекции всё-таки прошли');
      expect(SyncEndpoint.lastRun, isNull);
    });

    test('протухший пропуск выбрасывается, а не остаётся выглядеть рабочим',
        () async {
      await SyncEndpoint.saveSession(
        token: 'старый',
        userId: 'u1',
        sessionId: 'test-session',
        expiresAt: base.add(const Duration(days: 13)),
      );
      expect(SyncEndpoint.session, isNotNull);

      final t = FakeSyncTransport()..failWith = SyncFailure.notSignedIn;
      final report = await SyncEngine.run(transport: t, now: base);

      expect(report.ok, isFalse);
      expect(SyncEndpoint.session, isNull,
          reason: 'мёртвый пропуск остался — экран будет врать «подключено», '
              'а каждый проход молча отказывать');
      expect(t.isSignedIn, isFalse);
    });

    test('автоматический проход не идёт, пока его не включили', () async {
      await SyncEndpoint.configure(url: '203.0.113.10:8090');
      await SyncEndpoint.setEnabled(false);
      await txBox().put('t1', tx('t1'));

      await SyncEngine.runOnLaunch();
      expect(SyncEngine.lastReport.value, isNull,
          reason: 'выключенный обмен всё равно состоялся');
    });

    test('свежая установка не затирает сервер своими заготовками', () async {
      // Приложение само создаёт при первом запуске счёт с постоянным
      // идентификатором `main` и владельца с идентификатором `owner`. На
      // новом устройстве это пустые заготовки, и они СВЕЖЕЕ настоящих —
      // созданы только что. Без правила первого обмена они уехали бы наверх
      // поверх настоящих данных.
      final t = FakeSyncTransport();
      t.seed(
        'accounts',
        'main',
        AccountsSync().encode(AccountModel(
          id: 'main',
          name: 'Настоящий счёт',
          kind: AccountKind.main,
          openingBalance: 250000,
          createdAt: base.subtract(const Duration(days: 90)),
        )),
        base.subtract(const Duration(days: 90)),
      );

      await Hive.box<AccountModel>('wesios_accounts').put(
        'main',
        AccountModel(
          id: 'main',
          name: 'Основной счёт',
          kind: AccountKind.main,
          createdAt: base,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(SyncEndpoint.lastRun, isNull, reason: 'обменов ещё не было');
      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isTrue, reason: report.describe());

      expect(t.store['accounts']!['main']!.fields['name'], 'Настоящий счёт',
          reason: 'свежая установка затёрла настоящий счёт заготовкой');
      expect(Hive.box<AccountModel>('wesios_accounts').get('main')!.name,
          'Настоящий счёт');
      expect(
          Hive.box<AccountModel>('wesios_accounts').get('main')!.openingBalance,
          250000);
    });

    test('в первый обмен уезжает то, чего на сервере нет', () async {
      // Обратная сторона правила: устройство, где человек уже работал, при
      // первом обмене ничего не теряет.
      final t = FakeSyncTransport();
      t.seed('transactions', 'their',
          TransactionsSync().encode(tx('their', title: 'Чужая')), base);

      await txBox().put('mine', tx('mine', title: 'Моя'));
      await Future<void>.delayed(Duration.zero);

      await SyncEngine.run(transport: t, now: base);
      expect(t.store['transactions']!.keys.toSet(), {'mine', 'their'});
      expect(txBox().keys.toSet(), {'mine', 'their'});
    });

    test('правило первого обмена действует ровно один раз', () async {
      final t = FakeSyncTransport();
      await SyncEngine.run(transport: t, now: base);
      expect(SyncEndpoint.lastRun, isNotNull);

      // Теперь местная правка обязана победить более старую серверную.
      t.seed('transactions', 't1',
          TransactionsSync().encode(tx('t1', title: 'Серверное')), base);
      await txBox().put('t1', tx('t1', title: 'Местное'));
      await SyncJournal.record(
          'transactions', 't1', SyncStamp(base.add(const Duration(hours: 1))));

      await SyncEngine.run(
          transport: t, now: base.add(const Duration(hours: 2)));
      expect(t.store['transactions']!['t1']!.fields['title'], 'Местное',
          reason: 'правило первого обмена осталось включённым навсегда');
    });

    test('удачный проход отмечается временем', () async {
      final t = FakeSyncTransport();
      await SyncEngine.run(transport: t, now: base);
      expect(SyncEndpoint.lastRun, base);
    });

    test('два устройства сходятся к одному состоянию', () async {
      // Сервер общий, боксы — «второе устройство» изображается прямой
      // подстановкой в store.
      final t = FakeSyncTransport();
      t.seed('transactions', 'other',
          TransactionsSync().encode(tx('other', title: 'С телефона')), base);

      await txBox().put('mine', tx('mine', title: 'С компьютера'));
      await Future<void>.delayed(Duration.zero);

      await SyncEngine.run(transport: t, now: base.add(const Duration(minutes: 5)));

      expect(txBox().keys.toSet(), {'mine', 'other'});
      expect(t.store['transactions']!.keys.toSet(), {'mine', 'other'});
    });

    test('запись из будущей версии не помечается как усвоенная', () async {
      final t = FakeSyncTransport();
      // Нет суммы и даты — разобрать нечем.
      t.seed('transactions', 'future', const {'id': 'future'}, base);

      final report = await SyncEngine.run(transport: t, now: base);
      expect(report.ok, isTrue);
      expect(txBox().get('future'), isNull);

      final stamp = SyncJournal.stampOf('transactions', 'future');
      expect(stamp!.updatedAt.millisecondsSinceEpoch, 0,
          reason: 'иначе следующий проход решит, что запись уже усвоена');
    });
  });

  // ------------------------------------------------------------------ адрес

  group('адрес сервера', () {
    // Раньше здесь проверялся разборщик адреса, набранного руками: голый IP
    // по http, домен по https, мусор в null. Поля больше нет, разборщика
    // тоже — проверять надо то, что осталось.

    test('зашит в сборку и всегда по https', () {
      expect(SyncEndpoint.url, SyncEndpoint.defaultUrl);
      expect(SyncEndpoint.url, startsWith('https://'));
      expect(Uri.parse(SyncEndpoint.url).host, isNotEmpty);
    });

    test('сохранённый адрес из старой установки ничего не решает', () async {
      // На устройстве, где когда-то ввели IP с опечаткой, обмен молча не
      // работал бы вечно: чинить стало нечего и негде.
      await SyncEndpoint.configure(url: '203.0.113.10:8090');
      expect(SyncEndpoint.url, SyncEndpoint.defaultUrl);
    });
  });

  group('подключение', () {
    tearDown(() async => SyncEndpoint.clearSession());

    test('без пропуска — не подключены', () {
      expect(SyncEndpoint.isConnected, isFalse);
    });

    test('действующий пропуск — подключены', () async {
      await SyncEndpoint.saveSession(
        token: 't',
        userId: 'u',
        sessionId: 'test-session',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(SyncEndpoint.isConnected, isTrue);
    });

    test('протухший пропуск не считается подключением', () async {
      // Транспорт такой пропуск не примет, и если считать его подключением,
      // то у сообщений останутся «часики» — обещание отправки, которого
      // никто не выполнит.
      await SyncEndpoint.saveSession(
        token: 't',
        userId: 'u',
        sessionId: 'test-session',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(SyncEndpoint.isConnected, isFalse);
    });
  });
}

/// Транспорт, который отказывает на одной коллекции и работает на остальных.
class _FailingOnceTransport extends FakeSyncTransport {
  final String broken;

  _FailingOnceTransport(this.broken);

  @override
  Future<SyncResult<int>> push(String collection, List<SyncRecord> records) {
    if (collection == broken) {
      return Future.value(const SyncResult.fail(SyncFailure.offline));
    }
    return super.push(collection, records);
  }
}
