import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

import 'fake_sync_transport.dart';

/// Клиенты и сделки не синхронизировались вообще: их не было в списке
/// коллекций, а хранились они одной строкой JSON на весь список. Для CRM это
/// особенно больно — карточки ведут разные люди одновременно.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 12, 10);

  CrmClient client(String id, String name) => CrmClient(
        id: id,
        name: name,
        createdAt: base,
        updatedAt: base,
      );

  CrmDeal deal(String id, String clientId, String title, double amount) =>
      CrmDeal(
        id: id,
        clientId: clientId,
        title: title,
        amount: amount,
        createdAt: base,
        updatedAt: base,
      );

  CrmInteraction touch(String id, String clientId, String title) =>
      CrmInteraction(
        id: id,
        clientId: clientId,
        kind: InteractionKind.call,
        title: title,
        at: base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_crm_sync');
    Hive.init(dir.path);
    // CRM теперь привязана к организации: без неё запись некуда положить.
    if (!Hive.isAdapterRegistered(80)) {
      Hive.registerAdapter(OrganizationStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(81)) {
      Hive.registerAdapter(OrganizationModelAdapter());
    }
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<String>(CrmService.clientsBoxName);
    await Hive.openBox<String>(CrmService.dealsBoxName);
    await Hive.openBox<String>(CrmService.interactionsBoxName);
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    await CrmService.clearForTest();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  test('клиенты, сделки и касания участвуют в обмене', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names, contains('crm_clients'));
    expect(names, contains('crm_deals'));
    expect(names, contains('crm_interactions'));
  });

  test('заведённый клиент со сделкой уезжает на сервер', () async {
    await CrmService.saveClient(client('C1', 'Иван'));
    await CrmService.saveDeal(deal('D1', 'C1', 'Альбом', 150000));
    await CrmService.saveInteraction(touch('T1', 'C1', 'Созвон'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    final report = await SyncEngine.run(transport: t, now: base);

    expect(report.ok, isTrue, reason: report.describe());
    expect(t.store['crm_clients']?['C1']?.fields['name'], 'Иван');
    expect(t.store['crm_deals']?['D1']?.fields['amount'], 150000);
    expect(t.store['crm_interactions']?['T1'], isNotNull);
  });

  test('клиент, заведённый в команде, приезжает целиком', () async {
    final t = FakeSyncTransport();
    t.seed('crm_clients', 'C2', client('C2', 'Мария').toJson(), base);
    t.seed('crm_deals', 'D2', deal('D2', 'C2', 'Клип', 80000).toJson(), base);

    await SyncEngine.run(transport: t, now: base);

    final clients = await CrmService.clients();
    expect(clients.map((c) => c.id), contains('C2'));
    expect(clients.firstWhere((c) => c.id == 'C2').name, 'Мария');
    final deals = await CrmService.deals();
    expect(deals.firstWhere((d) => d.id == 'D2').amount, 80000);
  });

  test('двое правят разные карточки — обе правки выживают', () async {
    await CrmService.saveClient(client('C1', 'Иван'));
    await CrmService.saveClient(client('C2', 'Мария'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);

    final later = base.add(const Duration(hours: 1));
    // Коллега переименовал второго клиента.
    t.seed(
      'crm_clients',
      'C2',
      client('C2', 'Мария Петрова').copyWith(updatedAt: later).toJson(),
      later,
    );
    // Мы в это же время правим первого.
    await CrmService.saveClient(client('C1', 'Иван Сидоров'));
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('crm_clients', 'C1', SyncStamp(later));

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    final names = {for (final c in await CrmService.clients()) c.id: c.name};
    expect(names['C1'], 'Иван Сидоров', reason: 'наша правка потерялась');
    expect(names['C2'], 'Мария Петрова', reason: 'чужая правка не доехала');
  });

  test('перенос сделки по воронке не трогает соседние сделки', () async {
    // Сделка без клиента теперь не заводится — и правильно: висящая в
    // воздухе сделка никому ни о чём не говорит.
    await CrmService.saveClient(client('C1', 'Иван'));
    await CrmService.saveDeal(deal('D1', 'C1', 'Альбом', 150000));
    await CrmService.saveDeal(deal('D2', 'C1', 'Клип', 80000));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    t.calls.clear();

    await CrmService.moveDeal('D1', DealStage.won);
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('crm_deals', 'D1',
        SyncStamp(base.add(const Duration(hours: 1))));

    final report = await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    // Уехать должна ровно одна сделка. Раньше правка любой из них
    // переписывала весь список, и на сервер уходили обе.
    final pushes =
        t.calls.where((c) => c.startsWith('push:crm_deals:')).toList();
    expect(pushes, ['push:crm_deals:1'],
        reason: 'на сервер уехало лишнее: $pushes');
    expect(report.ok, isTrue);
  });

  test('удалённый клиент уносит свои сделки и не воскресает', () async {
    await CrmService.saveClient(client('C3', 'Разовый'));
    await CrmService.saveDeal(deal('D3', 'C3', 'Разовая', 5000));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    expect(t.store['crm_deals']?['D3'], isNotNull);

    await CrmService.deleteClient('C3');
    await Future<void>.delayed(Duration.zero);

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 1)));

    expect(t.store['crm_clients']!['C3']!.deleted, isTrue);
    expect(t.store['crm_deals']!['D3']!.deleted, isTrue,
        reason: 'сделки удалённого клиента обязаны уйти вместе с ним');

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));
    expect((await CrmService.clients()).map((c) => c.id), isNot(contains('C3')));
    expect((await CrmService.deals()).map((d) => d.id), isNot(contains('D3')));
  });

  test('данные из старого формата переносятся, а не пропадают', () async {
    final legacy = await Hive.openBox<dynamic>(CrmService.boxName);
    await legacy.clear();
    await legacy.put(
      'clients_v1',
      jsonEncode([client('OLD1', 'Старый клиент').toJson()]),
    );
    await legacy.put(
      'deals_v1',
      jsonEncode([deal('OLDD1', 'OLD1', 'Старая сделка', 1000).toJson()]),
    );

    final clients = await CrmService.clients();
    expect(clients.map((c) => c.id), contains('OLD1'));
    expect((await CrmService.deals()).map((d) => d.id), contains('OLDD1'));

    // Повторное обращение не плодит дублей и не откатывает правки.
    await CrmService.saveClient(client('OLD1', 'Переименован'));
    final again = await CrmService.clients();
    expect(again.where((c) => c.id == 'OLD1').length, 1);
    expect(again.firstWhere((c) => c.id == 'OLD1').name, 'Переименован');
  });
}
