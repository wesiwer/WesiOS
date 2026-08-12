import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/backup_service.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final now = DateTime(2026, 7, 1);

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_backup_test');
    Hive.init(tempDir.path);

    // path_provider ходит через канал платформы, которого в тесте нет.
    // Подменяем ответ на временный каталог самого теста.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
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

    // Боксы открываются ровно так же, как их открывают сервисы приложения —
    // с конкретными типами значений. Это принципиально: именно на типах и
    // ломалась очистка.
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<ArticleModel>('wesios_knowledge');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<ArticleModel>('wesios_knowledge').clear();
  });

  Future<void> seed() async {
    await Hive.box<TransactionModel>('wesios_treasury').put(
      'op1',
      TransactionModel(
        id: 'op1',
        title: 'Аренда',
        amount: 5000,
        type: TransactionType.expense,
        date: now,
        category: 'Офис',
      ),
    );
    await Hive.box<TaskModel>('wesios_tasks').put(
      't1',
      TaskModel(id: 't1', title: 'Отчёт', createdAt: now, tags: ['срочно']),
    );
    await Hive.box<AccountModel>('wesios_accounts').put(
      'a1',
      AccountModel(id: 'a1', name: 'Резерв', createdAt: now),
    );
    await Hive.box<ArticleModel>('wesios_knowledge').putAll({
      'k1': ArticleModel(
          id: 'k1',
          title: 'Моя статья',
          body: 'текст',
          createdAt: now,
          updatedAt: now),
      'k2': ArticleModel(
          id: 'k2',
          title: 'Встроенная',
          body: 'текст',
          createdAt: now,
          updatedAt: now,
          builtIn: true),
    });
  }

  group('openedBox', () {
    test('находит бокс, открытый с конкретным типом', () async {
      // Hive.box<dynamic> на таком боксе бросает «already open and of type».
      // Раньше это исключение глоталось try/catch, и очистка молча не
      // срабатывала, сообщая при этом об успехе.
      await seed();
      expect(BackupService.openedBox('wesios_treasury')?.length, 1);
      expect(BackupService.openedBox('wesios_tasks')?.length, 1);
      expect(BackupService.openedBox('wesios_accounts')?.length, 1);
      expect(BackupService.openedBox('wesios_knowledge')?.length, 2);
    });

    test('на неоткрытый бокс возвращает null, а не падает', () {
      expect(BackupService.openedBox('wesios_sandbox'), isNull);
    });
  });

  group('countLocalRecords', () {
    test('считает записи во всех типизированных боксах', () async {
      await seed();
      expect(await BackupService.countLocalRecords(), 5);
    });

    test('на пустых данных — ноль', () async {
      expect(await BackupService.countLocalRecords(), 0);
    });
  });

  group('clearLocalData', () {
    test('действительно стирает, а не сообщает об этом', () async {
      await seed();
      await BackupService.clearLocalData();

      expect(Hive.box<TransactionModel>('wesios_treasury').length, 0);
      expect(Hive.box<TaskModel>('wesios_tasks').length, 0);
      expect(Hive.box<AccountModel>('wesios_accounts').length, 0);
      expect(Hive.box<ArticleModel>('wesios_knowledge').length, 0);
      expect(await BackupService.countLocalRecords(), 0);
    });
  });

  group('export', () {
    test('в файле лежат данные, а не пустые списки', () async {
      await seed();
      final result = await BackupService.export();

      final json = jsonDecode(await File(result.path).readAsString())
          as Map<String, dynamic>;
      expect(json['format'], BackupService.formatVersion);
      expect((json['transactions'] as List).length, 1);
      expect((json['tasks'] as List).length, 1);
      expect((json['accounts'] as List).length, 1);
      expect((json['transactions'] as List).first['title'], 'Аренда');

      File(result.path).deleteSync();
    });

    test('встроенные статьи не выгружаются — они приезжают с обновлением',
        () async {
      await seed();
      final result = await BackupService.export();
      final json = jsonDecode(await File(result.path).readAsString())
          as Map<String, dynamic>;

      final titles =
          (json['articles'] as List).map((a) => a['title']).toList();
      expect(titles, ['Моя статья']);
      expect(result.articles, 1);

      File(result.path).deleteSync();
    });

    test('ключи и пароль в копию не попадают', () async {
      // Файл человек перешлёт себе в мессенджер. Ключи Firebase и хэш пароля
      // Shield там — ровно та дыра, от которой Shield и защищает.
      await seed();
      final result = await BackupService.export();
      final text = await File(result.path).readAsString();

      for (final forbidden in [
        'shield_hash',
        'shield_salt',
        'github_token',
        'github_refresh_token',
        'apiKey',
        'wesios_settings',
      ]) {
        expect(text.contains(forbidden), isFalse, reason: forbidden);
      }

      File(result.path).deleteSync();
    });

    test('счётчики в результате совпадают с содержимым файла', () async {
      await seed();
      final result = await BackupService.export();
      final json = jsonDecode(await File(result.path).readAsString())
          as Map<String, dynamic>;

      expect(result.transactions, (json['transactions'] as List).length);
      expect(result.tasks, (json['tasks'] as List).length);
      expect(result.total, 4);

      File(result.path).deleteSync();
    });
  });
}
