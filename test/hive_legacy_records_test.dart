import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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
