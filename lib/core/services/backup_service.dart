import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/knowledge/models/article_model.dart';
import '../../features/tasks/models/task_model.dart';
import '../../features/treasury/models/account_model.dart';
import '../../features/treasury/models/transaction_model.dart';

/// Результат выгрузки: путь к файлу и сколько чего в нём.
class BackupResult {
  final String path;
  final int transactions;
  final int tasks;
  final int accounts;
  final int articles;

  const BackupResult({
    required this.path,
    required this.transactions,
    required this.tasks,
    required this.accounts,
    required this.articles,
  });

  int get total => transactions + tasks + accounts + articles;
}

/// Выгрузка и очистка локальных данных.
///
/// Формат — обычный JSON, а не дамп Hive: файл должен открываться и читаться
/// человеком без этого приложения. Резервная копия, которую нечем прочитать,
/// не резервная копия.
class BackupService {
  /// Версия формата. Пишется в файл, чтобы будущий импорт мог понять, что
  /// перед ним, а не гадать по набору полей.
  static const int formatVersion = 1;

  /// Данные, которые считаются пользовательскими.
  ///
  /// Настройки сюда намеренно не входят: там лежат ключи Firebase и хэш
  /// пароля Wesi Shield, и класть их в файл, который человек перешлёт себе
  /// в мессенджер, — ровно та дыра, от которой Shield и защищает.
  static const List<String> dataBoxes = [
    'wesios_treasury',
    'wesios_tasks',
    'wesios_accounts',
    'wesios_knowledge',
    'wesios_sandbox',
    'wesios_whatif',
    'wesios_cache',
    'wesios_offline_queue',
  ];

  static Map<String, dynamic> _transaction(TransactionModel t) => {
        'id': t.id,
        'title': t.title,
        'amount': t.amount,
        'type': t.type.name,
        'date': t.date.toIso8601String(),
        'category': t.category,
        'description': t.description,
        'isRecurring': t.isRecurring,
        'recurringPeriod': t.recurringPeriod?.name,
        'isAnomaly': t.isAnomaly,
        'accountId': t.accountId,
      };

  static Map<String, dynamic> _task(TaskModel t) => {
        'id': t.id,
        'title': t.title,
        'description': t.description,
        'status': t.status.name,
        'priority': t.priority.name,
        'createdAt': t.createdAt.toIso8601String(),
        'dueDate': t.dueDate?.toIso8601String(),
        'assignee': t.assignee,
        'tags': t.tags,
        'subtasks': [
          for (final s in t.subtasks) {'title': s.title, 'done': s.done},
        ],
      };

  static Map<String, dynamic> _account(AccountModel a) => {
        'id': a.id,
        'name': a.name,
        'kind': a.kind.name,
        'openingBalance': a.openingBalance,
        'colorValue': a.colorValue,
        'createdAt': a.createdAt.toIso8601String(),
        'archived': a.archived,
        'note': a.note,
      };

  static Map<String, dynamic> _article(ArticleModel a) => {
        'id': a.id,
        'title': a.title,
        'body': a.body,
        'section': a.section.name,
        'tags': a.tags,
        'createdAt': a.createdAt.toIso8601String(),
        'updatedAt': a.updatedAt.toIso8601String(),
        'pinned': a.pinned,
      };

  static Future<List<T>> _open<T>(String name) async {
    try {
      final box = Hive.isBoxOpen(name)
          ? Hive.box<T>(name)
          : await Hive.openBox<T>(name);
      return box.values.toList();
    } catch (_) {
      // Отсутствующий или повреждённый бокс не должен срывать выгрузку
      // остальных: половина копии лучше, чем ничего.
      return const [];
    }
  }

  /// Пишет JSON во временный каталог и возвращает путь.
  ///
  /// Именно временный: файл потом отдаётся системному «поделиться»/«сохранить
  /// как», а держать вторую копию данных рядом с рабочей ни к чему.
  static Future<BackupResult> export() async {
    final transactions = await _open<TransactionModel>('wesios_treasury');
    final tasks = await _open<TaskModel>('wesios_tasks');
    final accounts = await _open<AccountModel>('wesios_accounts');
    final articles = await _open<ArticleModel>('wesios_knowledge');

    final payload = <String, dynamic>{
      'format': formatVersion,
      'app': 'WesiOS',
      'exportedAt': DateTime.now().toIso8601String(),
      'transactions': transactions.map(_transaction).toList(),
      'tasks': tasks.map(_task).toList(),
      'accounts': accounts.map(_account).toList(),
      // Встроенные статьи не выгружаем: они живут в коде и приезжают с
      // обновлением, а в копии только раздували бы файл.
      'articles':
          articles.where((a) => !a.builtIn).map(_article).toList(),
    };

    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final file = File('${dir.path}${Platform.pathSeparator}wesios-$stamp.json');
    // Отступ намеренный: файл предназначен для чтения человеком.
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    return BackupResult(
      path: file.path,
      transactions: transactions.length,
      tasks: tasks.length,
      accounts: accounts.length,
      articles: payload['articles'].length as int,
    );
  }

  /// Сколько записей будет стёрто — показывается в подтверждении.
  ///
  /// Спрашивать «точно удалить?» без числа значит спрашивать ни о чём.
  static Future<int> countLocalRecords() async {
    var total = 0;
    for (final name in dataBoxes) {
      try {
        if (Hive.isBoxOpen(name)) {
          total += Hive.box<dynamic>(name).length;
        }
      } catch (_) {
        continue;
      }
    }
    return total;
  }

  /// Стирает пользовательские данные, оставляя настройки и защиту.
  static Future<void> clearLocalData() async {
    for (final name in dataBoxes) {
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box<dynamic>(name).clear();
        } else {
          await Hive.deleteBoxFromDisk(name);
        }
      } catch (_) {
        // Один недоступный бокс не должен прерывать очистку остальных.
      }
    }
  }
}
