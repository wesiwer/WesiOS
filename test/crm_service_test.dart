import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_crm_test');
    Hive.init(dir.path);
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await CrmService.clearForTest();
    await OrganizationService.ensureBaseline();
  });

  CrmClient client(String id, {CrmClientStatus status = CrmClientStatus.active}) {
    final now = DateTime(2026, 8, 6);
    return CrmClient(
      id: id,
      name: 'Клиент $id',
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('клиент, сделка и касание сохраняются и читаются', () async {
    final c = client('c1');
    await CrmService.saveClient(c);
    await CrmService.saveDeal(CrmDeal(
      id: 'd1',
      clientId: c.id,
      title: 'Внедрение',
      amount: 100000,
      probability: 50,
      createdAt: DateTime(2026, 8, 6),
      updatedAt: DateTime(2026, 8, 6),
    ));
    await CrmService.saveInteraction(CrmInteraction(
      id: 'i1',
      clientId: c.id,
      title: 'Созвон',
      kind: InteractionKind.call,
      at: DateTime(2026, 8, 7),
    ));

    expect((await CrmService.clients()).single.id, 'c1');
    expect((await CrmService.deals()).single.weightedAmount, 50000);
    expect((await CrmService.interactions()).single.kind, InteractionKind.call);
  });

  test('следующий шаг из касания обновляет карточку клиента', () async {
    final c = client('c1');
    await CrmService.saveClient(c);
    final next = DateTime(2026, 9, 1);

    await CrmService.saveInteraction(CrmInteraction(
      id: 'i1',
      clientId: c.id,
      title: 'Отправить предложение',
      at: DateTime(2026, 8, 7),
      nextActionAt: next,
    ));

    expect((await CrmService.clients()).single.nextContactAt, next);
  });

  test('сводка считает воронку, выигранное и архив отдельно', () async {
    await CrmService.saveClient(client('active'));
    await CrmService.saveClient(client('archived', status: CrmClientStatus.archived));
    final now = DateTime(2026, 8, 6);
    await CrmService.saveDeal(CrmDeal(
      id: 'open',
      clientId: 'active',
      title: 'Открытая',
      amount: 200,
      probability: 25,
      createdAt: now,
      updatedAt: now,
    ));
    await CrmService.saveDeal(CrmDeal(
      id: 'won',
      clientId: 'active',
      title: 'Выигранная',
      amount: 300,
      probability: 100,
      stage: DealStage.won,
      createdAt: now,
      updatedAt: now,
    ));

    final summary = await CrmService.summary();
    expect(summary.clients, 1);
    expect(summary.openDeals, 1);
    expect(summary.pipelineAmount, 200);
    expect(summary.weightedPipeline, 50);
    expect(summary.wonDeals, 1);
    expect(summary.wonAmount, 300);
  });

  test('удаление клиента каскадно удаляет сделки и историю', () async {
    final c = client('c1');
    final now = DateTime(2026, 8, 6);
    await CrmService.saveClient(c);
    await CrmService.saveDeal(CrmDeal(
      id: 'd1',
      clientId: c.id,
      title: 'Сделка',
      createdAt: now,
      updatedAt: now,
    ));
    await CrmService.saveInteraction(CrmInteraction(
      id: 'i1',
      clientId: c.id,
      title: 'Заметка',
      at: now,
    ));

    await CrmService.deleteClient(c.id);

    expect(await CrmService.clients(), isEmpty);
    expect(await CrmService.deals(), isEmpty);
    expect(await CrmService.interactions(), isEmpty);
  });
}
