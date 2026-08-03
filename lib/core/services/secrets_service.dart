import 'package:flutter/foundation.dart';

import '../security/secret_vault.dart';
import 'firebase_rest_service.dart';

/// Ключи от внешних сервисов, которыми пользуется само приложение.
///
/// Смысл: человек не вводит и не копирует ничего. Владелец один раз кладёт
/// ключи в документ `secrets/default` (экран «Ключи»), а у всех остальных
/// приложение забирает их само при входе и просто работает.
///
/// Где что лежит:
/// - **облако** — источник правды, `secrets/default` в Firestore;
/// - **зашифрованное хранилище** ([SecretVault]) — копия на диске, чтобы
///   ключи работали без сети и не лежали открытым текстом;
/// - **память** — то, что отдаётся вызывающему прямо сейчас.
///
/// Чего здесь НЕТ и быть не может. «Сотрудник ключей не видит» — это про
/// интерфейс, а не про защиту: раз приложение на его устройстве ключом
/// пользуется, ключ на устройстве есть. Секрет, который сотруднику видеть
/// нельзя, в это хранилище класть нельзя — ему место на сервере, как токену
/// телеграм-бота в вебхуке.
class SecretsService {
  SecretsService._();

  /// Документ с рабочим набором ключей. Правила Firestore дают его читать
  /// любому вошедшему, а менять — только администратору.
  static const String documentPath = 'secrets/default';

  static Map<String, String> _memory = const {};

  /// Меняется после каждой успешной синхронизации — экраны перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Когда ключи последний раз пришли из облака.
  static DateTime? lastSyncedAt;

  /// Известные приложению ключи. Пустая карта — ещё не синхронизировались.
  static Map<String, String> get all => Map.unmodifiable(_memory);

  static bool get isEmpty => _memory.isEmpty;

  /// Значение ключа или null.
  ///
  /// Порядок поиска: память → зашифрованное хранилище. В облако за одним
  /// ключом не ходим: сеть в геттере сделала бы непредсказуемым любой вызов.
  static String? value(String name) {
    final v = _memory[name];
    if (v != null && v.isNotEmpty) return v;
    return SecretVault.read(name);
  }

  /// Забрать ключи из облака.
  ///
  /// Возвращает true, если набор действительно получен. Тихо возвращает
  /// false, когда входа нет или нет связи: отсутствие ключей — обычное
  /// состояние (приложение работает и локально), а не ошибка, о которой
  /// надо кричать пользователю.
  static Future<bool> sync() async {
    if (!FirebaseRestService.isSignedIn) return false;
    final doc = await FirebaseRestService.getDocument(documentPath);
    if (doc == null) return false;

    _memory = Map<String, String>.from(doc);
    lastSyncedAt = DateTime.now();

    // Копия на диск — только если хранилище открыто. Закрыто — значит
    // шифровать нечем, и класть ключи открытым текстом мы не станем.
    if (SecretVault.unlocked.value) {
      for (final e in _memory.entries) {
        await SecretVault.write(e.key, e.value);
      }
    }

    revision.value++;
    return true;
  }

  /// Поднять ключи с диска, не трогая сеть — для старта без интернета.
  static void loadCached() {
    if (!SecretVault.unlocked.value) return;
    final names = SecretVault.names;
    if (names.isEmpty) return;
    final restored = <String, String>{};
    for (final n in names) {
      final v = SecretVault.read(n);
      if (v != null) restored[n] = v;
    }
    if (restored.isEmpty) return;
    _memory = restored;
    revision.value++;
  }

  /// Забыть ключи в памяти — при выходе из аккаунта.
  ///
  /// Зашифрованную копию не трогаем: она принадлежит устройству и защищена
  /// паролем Wesi Shield, а не сессией Firebase.
  static void forget() {
    _memory = const {};
    lastSyncedAt = null;
    revision.value++;
  }
}
