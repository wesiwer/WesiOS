import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_journal.dart';

/// Что считается «своей правкой».
///
/// От этого зависит автоматический обмен, и ошибка здесь не видна глазами:
/// приложение просто начинает без остановки ходить на сервер. Приехавшее с
/// сервера пишется в те же боксы, что и правки человека, — и если считать
/// всё подряд, получается вечный круг: применили чужое → запустился обмен →
/// снова применили → снова обмен. Без единого действия человека.
void main() {
  late Directory dir;
  late Box<String> box;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_auto');
    Hive.init(dir.path);
    await SyncJournal.open();
    box = await Hive.openBox<String>('probe_box');
    SyncJournal.attach('проверка', box);
  });

  tearDownAll(() async {
    await SyncJournal.detach();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  /// Hive рассылает события подписчикам не мгновенно — даём им дойти.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  test('правка человека считается', () async {
    final was = SyncJournal.localChanges.value;
    await box.put('a', 'первое');
    await settle();
    expect(SyncJournal.localChanges.value, greaterThan(was));
  });

  test('приехавшее с сервера — не считается', () async {
    // Это и есть защита от вечного круга. Движок предупреждает журнал через
    // expect перед тем, как применить чужую запись.
    final was = SyncJournal.localChanges.value;
    SyncJournal.expect('проверка', 'b', SyncStamp(DateTime.utc(2026)));
    await box.put('b', 'приехало');
    await settle();
    expect(SyncJournal.localChanges.value, was,
        reason: 'иначе применение чужой правки запускало бы новый обмен');
  });

  test('удаление человеком считается', () async {
    await box.put('c', 'третье');
    await settle();
    final was = SyncJournal.localChanges.value;
    await box.delete('c');
    await settle();
    expect(SyncJournal.localChanges.value, greaterThan(was));
  });

  test('ожидание снимается один раз, а не навсегда', () async {
    // Иначе одна чужая правка глушила бы все последующие правки человека по
    // тому же ключу — и они молча не уезжали бы.
    SyncJournal.expect('проверка', 'd', SyncStamp(DateTime.utc(2026)));
    await box.put('d', 'приехало');
    await settle();

    final was = SyncJournal.localChanges.value;
    await box.put('d', 'а это уже я');
    await settle();
    expect(SyncJournal.localChanges.value, greaterThan(was));
  });

  test('отметка времени приехавшего берётся с сервера, а не текущая', () async {
    // Своё время означало бы «правка прямо сейчас», и запись уехала бы
    // обратно как более свежая.
    final serverTime = DateTime.utc(2026, 1, 1, 12);
    SyncJournal.expect('проверка', 'e', SyncStamp(serverTime));
    await box.put('e', 'приехало');
    await settle();
    expect(SyncJournal.stampOf('проверка', 'e')!.updatedAt, serverTime);
  });
}
