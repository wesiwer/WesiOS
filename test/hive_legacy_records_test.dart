import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

/// Записи, сделанные прошлой версией приложения, обязаны читаться этой.
///
/// Обычные тесты этого не ловят: они всегда начинают с пустых коробок, а
/// значит любая запись в них уже написана сегодняшним кодом. Поломка живёт
/// ровно в промежутке — «поле добавили, а на устройстве его нет», — и
/// проявляется только на данных, которых в тестах никогда не бывает.
///
/// Здесь старый формат воспроизводится честно: адаптером, который пишет
/// ровно столько полей, сколько писала выпущенная версия. Он объявлен под
/// своим typeId, поэтому не спорит с настоящим, а запись потом читается
/// настоящим адаптером — как это и происходит после обновления.
///
/// Цена ошибки здесь — не «неудобно»: журнал операций читается при запуске,
/// и нечитаемая запись означает чёрный экран вместо приложения.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_legacy');
    Hive.init(dir.path);
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
    Hive.registerAdapter(AccountKindAdapter());
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(AccountModelAdapter());
  });

  /// Пишет запись старым адаптером и возвращает управление новому.
  ///
  /// Два адаптера на один typeId Hive не держит — это и правильно, иначе
  /// формат записи стал бы непредсказуемым. Поэтому старый подменяет новый
  /// на время записи и уступает обратно перед чтением: ровно то, что
  /// происходит на устройстве при обновлении приложения.
  Future<void> writeAsOldVersion<L>(
    TypeAdapter<L> legacy,
    TypeAdapter<dynamic> current,
    String boxName,
    String key,
    L record,
  ) async {
    Hive.registerAdapter(legacy, override: true);
    final box = await Hive.openBox<dynamic>(boxName);
    await box.clear();
    await box.put(key, record);
    await box.close();
    Hive.registerAdapter(current, override: true);
  }

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('операция из прошлой версии читается и не теряет данных', () async {
    // Пишем ровно 13 полей — столько писала выпущенная версия 0.19.22.
    await writeAsOldVersion(
      _LegacyTransactionWriter(),
      TransactionModelAdapter(),
      'legacy_tx',
      'T1',
      _LegacyTransaction(
        id: 'T1',
        title: 'Аренда студии',
        amount: 30000,
        type: TransactionType.expense,
        date: DateTime.utc(2026, 7, 15),
        category: 'Студия',
        description: 'ежемесячно',
        isRecurring: true,
        recurringPeriod: RecurringPeriod.monthly,
        isAnomaly: false,
        zScore: null,
        accountId: 'main',
        recurringAnchor: DateTime.utc(2026, 1, 15),
      ),
    );

    final reopened = await Hive.openBox<TransactionModel>('legacy_tx');
    final tx = reopened.get('T1');

    expect(tx, isNotNull,
        reason: 'операция, заведённая прошлой версией, обязана открыться');
    expect(tx!.title, 'Аренда студии');
    expect(tx.amount, 30000);
    expect(tx.type, TransactionType.expense);
    expect(tx.date, DateTime.utc(2026, 7, 15));
    expect(tx.isRecurring, isTrue);
    expect(tx.recurringPeriod, RecurringPeriod.monthly);
    expect(tx.recurringAnchor, DateTime.utc(2026, 1, 15),
        reason: 'якорь регулярного платежа терять нельзя — иначе дата съедет');

    // Поля, которых у старой записи нет, берут умолчание, а не падают.
    expect(tx.source, TransactionSource.manual);
    expect(tx.originalCurrency, 'RUB');
    expect(tx.organizationBaseCurrency, 'RUB');
    expect(tx.fxRateToReporting, 1.0);
    expect(tx.fxSource, 'legacy');
    expect(tx.organizationId, isNull,
        reason: 'принадлежность организации проставляет миграция, а не чтение');
    await reopened.close();
  });

  test('счёт из прошлой версии читается и не теряет данных', () async {
    await writeAsOldVersion(
      _LegacyAccountWriter(),
      AccountModelAdapter(),
      'legacy_acc',
      'main',
      _LegacyAccount(
        id: 'main',
        name: 'Основной',
        kind: AccountKind.main,
        openingBalance: 125000,
        colorValue: 0xFFF97316,
        createdAt: DateTime.utc(2025, 3, 1),
        archived: false,
        note: 'основной счёт',
      ),
    );

    final reopened = await Hive.openBox<AccountModel>('legacy_acc');
    final account = reopened.get('main');

    expect(account, isNotNull, reason: 'без счёта не откроется вся касса');
    expect(account!.name, 'Основной');
    expect(account.openingBalance, 125000);
    expect(account.createdAt, DateTime.utc(2025, 3, 1));
    expect(account.note, 'основной счёт');

    expect(account.minimumBalance, 0);
    expect(account.allowNetting, isTrue);
    expect(account.currency, 'RUB');
    expect(account.fxHaircut, 0.03);
    expect(account.transferDelayDays, 0);
    await reopened.close();
  });

  test('запись этой версии читается без потерь', () async {
    // Обратная сторона: терпимость к старому формату не должна ломать новый.
    final box = await Hive.openBox<TransactionModel>('roundtrip');
    await box.clear();
    final original = TransactionModel(
      id: 'T2',
      title: 'Продажа бита',
      amount: 15000,
      type: TransactionType.income,
      date: DateTime.utc(2026, 8, 13),
      organizationId: 'org_wesi_beats',
      source: TransactionSource.crm,
      originalAmount: 150,
      originalCurrency: 'USD',
      organizationBaseAmount: 15000,
      organizationBaseCurrency: 'RUB',
      fxRateToReporting: 100,
      fxRateAt: DateTime.utc(2026, 8, 13),
      fxSource: 'cbr',
    );
    await box.put('T2', original);
    await box.close();

    final reopened = await Hive.openBox<TransactionModel>('roundtrip');
    final tx = reopened.get('T2')!;
    expect(tx.source, TransactionSource.crm);
    expect(tx.originalCurrency, 'USD');
    expect(tx.originalAmount, 150);
    expect(tx.fxRateToReporting, 100);
    expect(tx.fxSource, 'cbr');
    expect(tx.organizationId, 'org_wesi_beats');
    await reopened.close();
  });

  test('задача из прошлой версии читается и не теряет данных', () async {
    // Задачи читаются при запуске той же миграцией, что и операции со
    // счетами. Здесь поля организации добавлены как nullable, и падать не
    // должно — тест закрепляет это, чтобы следующая правка модели не
    // повторила историю с операциями.
    await writeAsOldVersion(
      _LegacyTaskWriter(),
      TaskModelAdapter(),
      'legacy_task',
      'T1',
      _LegacyTask(
        id: 'T1',
        title: 'Свести трек',
        description: 'к пятнице',
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        createdAt: DateTime.utc(2026, 6, 1),
        dueDate: DateTime.utc(2026, 6, 5),
        assignee: 'wesi',
        subtasks: const [],
        tags: const ['студия'],
        order: 3,
      ),
    );

    final box = await Hive.openBox<TaskModel>('legacy_task');
    final task = box.get('T1');

    expect(task, isNotNull);
    expect(task!.title, 'Свести трек');
    expect(task.status, TaskStatus.inProgress);
    expect(task.priority, TaskPriority.high);
    expect(task.dueDate, DateTime.utc(2026, 6, 5));
    expect(task.tags, ['студия']);
    expect(task.order, 3);
    expect(task.organizationId, isNull);
    expect(task.responsibleEmployeeId, isNull);
    await box.close();
  });

  test('профиль из прошлой версии открывается и сохраняет права', () async {
    // Коробка сотрудников открывается при запуске раньше всего остального.
    // Нечитаемый профиль здесь — это не «пропал человек из списка», а
    // приложение, которое не открывается ни у кого.
    await writeAsOldVersion(
      _LegacyEmployeeWriter(),
      EmployeeModelAdapter(),
      'legacy_team',
      'E1',
      _LegacyEmployee(
        id: 'E1',
        login: 'anna',
        fullName: 'Анна',
        nickname: 'ann',
        position: 'менеджер',
        phone: '+7 900 000-00-00',
        email: 'anna@wesi.local',
        socials: const {'tg': '@ann'},
        notes: '',
        permissions: const TeamPermissions(
          moduleList: [TeamModules.tasks, TeamModules.crm],
          canManageTeam: false,
        ),
        passwordHash: 'hash',
        passwordSalt: 'salt',
        avatarIndex: 3,
        createdAt: DateTime.utc(2025, 11, 2),
        isOwner: false,
        demoStats: const {},
        photo: null,
      ),
    );

    final box = await Hive.openBox<EmployeeModel>('legacy_team');
    final person = box.get('E1');

    expect(person, isNotNull,
        reason: 'профиль, заведённый прошлой версией, обязан открыться');
    expect(person!.login, 'anna', reason: 'по логину человек и входит');
    expect(person.email, 'anna@wesi.local',
        reason: 'на почту приходит код подтверждения — без неё не войти');
    expect(person.passwordHash, 'hash');
    expect(person.passwordSalt, 'salt');
    expect(person.isOwner, isFalse);

    // Права обязаны сохраниться ровно те, что были выданы.
    expect(person.permissions.allows(TeamModules.tasks), isTrue);
    expect(person.permissions.allows(TeamModules.crm), isTrue);
    expect(person.permissions.allows(TeamModules.treasury), isFalse,
        reason: 'чужих прав появиться не должно');
    expect(person.permissions.canManageTeam, isFalse);

    // Поля, которых у старого профиля нет, берут умолчание.
    expect(person.skills, isEmpty);
    expect(person.weeklyCapacityPoints, 10);
    expect(person.workloadMinRatio, .65);
    expect(person.workloadMaxRatio, 1.10);
    expect(person.workloadAlertTarget, 'manager');
    expect(person.managerEmployeeId, isNull);
    await box.close();
  });

  test('операция из ветки орг-иерархии читается со сдвигом полей', () async {
    // Самая коварная из раскладок. Поле 12 там — organizationId (строка), а
    // после слияния под этим номером лежит recurringAnchor (дата). Прочитать
    // одно как другое нельзя: приведение падает, и вместе с ним падает
    // каждый экран, где читаются операции.
    await writeAsOldVersion(
      _ShiftedTransactionWriter(),
      TransactionModelAdapter(),
      'shifted_tx',
      'T9',
      _ShiftedTransaction(
        id: 'T9',
        title: 'Продажа бита',
        amount: 15000,
        type: TransactionType.income,
        date: DateTime.utc(2026, 8, 1),
        accountId: 'main',
        organizationId: 'org_wesi_beats',
        source: TransactionSource.crm,
        createdBy: 'wesi',
        originalCurrency: 'USD',
        fxRateToReporting: 100,
        fxSource: 'cbr',
      ),
    );

    final box = await Hive.openBox<TransactionModel>('shifted_tx');
    final tx = box.get('T9');

    expect(tx, isNotNull, reason: 'иначе экран финансов не открывается вовсе');
    expect(tx!.title, 'Продажа бита');
    expect(tx.amount, 15000);
    // Поля, сдвинутые на одно, обязаны встать на свои места.
    expect(tx.organizationId, 'org_wesi_beats',
        reason: 'иначе операция уедет не в ту организацию');
    expect(tx.source, TransactionSource.crm);
    expect(tx.createdBy, 'wesi');
    expect(tx.originalCurrency, 'USD');
    expect(tx.fxRateToReporting, 100);
    expect(tx.fxSource, 'cbr');
    // Якоря в той раскладке не существовало — его и не должно появиться.
    expect(tx.recurringAnchor, isNull);
    await box.close();
  });

  test('целое число в денежном поле не роняет чтение', () async {
    // Ноль вполне мог записаться целым. Жёсткое приведение к double? на нём
    // падает, хотя данные исправны.
    await writeAsOldVersion(
      _IntMoneyWriter(),
      TransactionModelAdapter(),
      'int_money_tx',
      'T8',
      const _IntMoney(),
    );
    final box = await Hive.openBox<TransactionModel>('int_money_tx');
    expect(box.get('T8')?.amount, 0);
    await box.close();
  });

  test('объявленное число полей совпадает с записанным', () {
    // Адаптер написан руками, а значит номер поля можно и забыть. Заголовок
    // говорит «полей 30», а записано 29 — Hive прочитает мусор, и заметить
    // это по одному лишь чтению новых записей нельзя.
    final tx = _CountingWriter();
    TransactionModelAdapter().write(
      tx,
      TransactionModel(
        id: 'x',
        title: 'x',
        amount: 1,
        type: TransactionType.income,
        date: DateTime.utc(2026),
      ),
    );
    expect(tx.declared, 30);
    expect(tx.written, 30, reason: 'объявлено ${tx.declared}, записано ${tx.written}');

    final account = _CountingWriter();
    AccountModelAdapter().write(
      account,
      AccountModel(id: 'x', name: 'x', createdAt: DateTime.utc(2026)),
    );
    expect(account.declared, 14);
    expect(account.written, 14);

    final person = _CountingWriter();
    EmployeeModelAdapter().write(
      person,
      EmployeeModel(
        id: 'x',
        login: 'x',
        fullName: 'x',
        createdAt: DateTime.utc(2026),
      ),
    );
    expect(person.declared, 23);
    expect(person.written, 23);
  });
}

/// Считает, сколько полей адаптер объявил и сколько на самом деле записал.
class _CountingWriter implements BinaryWriter {
  int declared = 0;
  int written = 0;
  var _first = true;

  @override
  void writeByte(int value) {
    if (_first) {
      declared = value;
      _first = false;
      return;
    }
    written++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// --------------------------------------------------------------- старый вид

class _LegacyTransaction {
  final String id;
  final String title;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String? category;
  final String? description;
  final bool isRecurring;
  final RecurringPeriod? recurringPeriod;
  final bool isAnomaly;
  final double? zScore;
  final String? accountId;
  final DateTime? recurringAnchor;

  const _LegacyTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    this.category,
    this.description,
    this.isRecurring = false,
    this.recurringPeriod,
    this.isAnomaly = false,
    this.zScore,
    this.accountId,
    this.recurringAnchor,
  });
}

/// Пишет запись ровно так, как это делала выпущенная версия: 13 полей.
///
/// typeId тот же, что у настоящей операции, — иначе прочитать написанное
/// настоящим адаптером было бы нельзя, а именно это и проверяется. Читать
/// этим адаптером ничего не нужно, поэтому [read] не поддержан.
class _LegacyTransactionWriter extends TypeAdapter<_LegacyTransaction> {
  @override
  final int typeId = 1;

  @override
  _LegacyTransaction read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _LegacyTransaction obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.isRecurring)
      ..writeByte(8)
      ..write(obj.recurringPeriod)
      ..writeByte(9)
      ..write(obj.isAnomaly)
      ..writeByte(10)
      ..write(obj.zScore)
      ..writeByte(11)
      ..write(obj.accountId)
      ..writeByte(12)
      ..write(obj.recurringAnchor);
  }
}

class _LegacyAccount {
  final String id;
  final String name;
  final AccountKind kind;
  final double openingBalance;
  final int colorValue;
  final DateTime createdAt;
  final bool archived;
  final String? note;

  const _LegacyAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingBalance,
    required this.colorValue,
    required this.createdAt,
    required this.archived,
    this.note,
  });
}

class _LegacyAccountWriter extends TypeAdapter<_LegacyAccount> {
  @override
  final int typeId = 15;

  @override
  _LegacyAccount read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _LegacyAccount obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.kind)
      ..writeByte(3)
      ..write(obj.openingBalance)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.archived)
      ..writeByte(7)
      ..write(obj.note);
  }
}

class _LegacyTask {
  final String id;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String? assignee;
  final List<SubTask> subtasks;
  final List<String> tags;
  final int order;

  const _LegacyTask({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.dueDate,
    this.assignee,
    required this.subtasks,
    required this.tags,
    required this.order,
  });
}

/// Пишет задачу в 11 полей — столько писала выпущенная версия.
class _LegacyTaskWriter extends TypeAdapter<_LegacyTask> {
  @override
  final int typeId = 13;

  @override
  _LegacyTask read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _LegacyTask obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.priority)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.dueDate)
      ..writeByte(7)
      ..write(obj.assignee)
      ..writeByte(8)
      ..write(obj.subtasks)
      ..writeByte(9)
      ..write(obj.tags)
      ..writeByte(10)
      ..write(obj.order);
  }
}

class _LegacyEmployee {
  final String id;
  final String login;
  final String fullName;
  final String nickname;
  final String position;
  final String phone;
  final String email;
  final Map<String, String> socials;
  final String notes;
  final TeamPermissions permissions;
  final String passwordHash;
  final String passwordSalt;
  final int avatarIndex;
  final DateTime createdAt;
  final bool isOwner;
  final Map<String, double> demoStats;
  final Uint8List? photo;

  const _LegacyEmployee({
    required this.id,
    required this.login,
    required this.fullName,
    required this.nickname,
    required this.position,
    required this.phone,
    required this.email,
    required this.socials,
    required this.notes,
    required this.permissions,
    required this.passwordHash,
    required this.passwordSalt,
    required this.avatarIndex,
    required this.createdAt,
    required this.isOwner,
    required this.demoStats,
    this.photo,
  });
}

/// Пишет профиль в 17 полей — так было до навыков и учёта нагрузки.
class _LegacyEmployeeWriter extends TypeAdapter<_LegacyEmployee> {
  @override
  final int typeId = 21;

  @override
  _LegacyEmployee read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _LegacyEmployee obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.login)
      ..writeByte(2)
      ..write(obj.fullName)
      ..writeByte(3)
      ..write(obj.nickname)
      ..writeByte(4)
      ..write(obj.position)
      ..writeByte(5)
      ..write(obj.phone)
      ..writeByte(6)
      ..write(obj.email)
      ..writeByte(7)
      ..write(obj.socials)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.permissions)
      ..writeByte(10)
      ..write(obj.passwordHash)
      ..writeByte(11)
      ..write(obj.passwordSalt)
      ..writeByte(12)
      ..write(obj.avatarIndex)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.isOwner)
      ..writeByte(15)
      ..write(obj.demoStats)
      ..writeByte(16)
      ..write(obj.photo);
  }
}

class _ShiftedTransaction {
  final String id;
  final String title;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String? accountId;
  final String? organizationId;
  final TransactionSource source;
  final String? createdBy;
  final String originalCurrency;
  final double fxRateToReporting;
  final String fxSource;

  const _ShiftedTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    this.accountId,
    this.organizationId,
    required this.source,
    this.createdBy,
    required this.originalCurrency,
    required this.fxRateToReporting,
    required this.fxSource,
  });
}

/// Пишет операцию так, как это делала сборка ветки орг-иерархии: 29 полей,
/// организация под номером 12, всё остальное сдвинуто на одно.
class _ShiftedTransactionWriter extends TypeAdapter<_ShiftedTransaction> {
  @override
  final int typeId = 1;

  @override
  _ShiftedTransaction read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _ShiftedTransaction obj) {
    writer
      ..writeByte(29)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.title)
      ..writeByte(2)..write(obj.amount)
      ..writeByte(3)..write(obj.type)
      ..writeByte(4)..write(obj.date)
      ..writeByte(5)..write(null)
      ..writeByte(6)..write(null)
      ..writeByte(7)..write(false)
      ..writeByte(8)..write(null)
      ..writeByte(9)..write(false)
      ..writeByte(10)..write(null)
      ..writeByte(11)..write(obj.accountId)
      ..writeByte(12)..write(obj.organizationId)
      ..writeByte(13)..write(null)
      ..writeByte(14)..write(null)
      ..writeByte(15)..write(obj.source)
      ..writeByte(16)..write(obj.createdBy)
      ..writeByte(17)..write(null)
      ..writeByte(18)..write(null)
      ..writeByte(19)..write(null)
      ..writeByte(20)..write(null)
      ..writeByte(21)..write(null)
      ..writeByte(22)..write(null)
      ..writeByte(23)..write(obj.originalCurrency)
      ..writeByte(24)..write(null)
      ..writeByte(25)..write('RUB')
      ..writeByte(26)..write(obj.fxRateToReporting)
      ..writeByte(27)..write(null)
      ..writeByte(28)..write(obj.fxSource);
  }
}

class _IntMoney {
  const _IntMoney();
}

/// Пишет сумму целым числом — так вполне мог записаться ноль.
class _IntMoneyWriter extends TypeAdapter<_IntMoney> {
  @override
  final int typeId = 1;

  @override
  _IntMoney read(BinaryReader reader) =>
      throw UnsupportedError('старый адаптер только пишет');

  @override
  void write(BinaryWriter writer, _IntMoney obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)..write('T8')
      ..writeByte(1)..write('Ноль')
      ..writeByte(2)..write(0)
      ..writeByte(3)..write(TransactionType.income)
      ..writeByte(4)..write(DateTime.utc(2026, 8, 1))
      ..writeByte(5)..write(null)
      ..writeByte(6)..write(null)
      ..writeByte(7)..write(false)
      ..writeByte(8)..write(null)
      ..writeByte(9)..write(false)
      ..writeByte(10)..write(null)
      ..writeByte(11)..write(null)
      ..writeByte(12)..write(null);
  }
}
