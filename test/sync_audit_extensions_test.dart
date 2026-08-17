import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_audit_extensions.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  setUpAll(SyncAuditExtensions.install);

  test('audited registry has one source of truth per module', () {
    final names = SyncCodec.collections.map((c) => c.name).toList();

    expect(names, containsAll(<String>[
      'tasks',
      'accounts',
      'transactions',
      'sandbox_transactions',
      'what_if_presets',
      'calendar_events',
      'roadmap_projects',
      'roadmap_items',
      'crm_clients',
      'crm_deals',
      'crm_interactions',
      'profile',
      'shield_private',
      'employees',
      'chats',
      'messages',
      'audio_beats',
      'audio_extras',
    ]));
    expect(names, isNot(contains('roadmap_state')));
    expect(names, isNot(contains('crm_state')));
    expect(names, isNot(contains('profile_private')));
    expect(names.toSet().length, names.length,
        reason: 'Одна коллекция не должна быть зарегистрирована дважды');
  });

  test('finance sync preserves recurring anchor exactly', () {
    final codec = SyncCodec.byName('transactions')!;
    final anchor = DateTime.utc(2026, 1, 31, 9, 15);
    final transaction = TransactionModel(
      id: 'recurring-anchor-test',
      title: 'Rent',
      amount: 1000,
      type: TransactionType.expense,
      date: DateTime.utc(2026, 2, 28, 9, 15),
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
      recurringAnchor: anchor,
    );

    final encoded = codec.encode(transaction);
    expect(encoded['recurringAnchor'], anchor.toIso8601String());

    final decoded = codec.decode(encoded) as TransactionModel?;
    expect(decoded, isNotNull);
    expect(decoded!.recurringAnchor, anchor);
  });

  test('Audio Vault sync keeps attachment metadata but strips device paths', () {
    final codec = SyncCodec.byName('audio_beats')!;
    final raw = jsonEncode(<String, dynamic>{
      'id': 'beat-sync-test',
      'title': 'Test',
      'authorEmployeeId': 'owner',
      'bpm': 140,
      'musicalKey': 'Am',
      'genre': 'Trap',
      'mood': 'Dark',
      'tags': <String>['test'],
      'stage': 'draft',
      'notes': '',
      'mp3Path': '/local/a.mp3',
      'wavPath': '/local/a.wav',
      'trackoutPath': '/local/a.zip',
      'coverPath': '/local/a.png',
      'attachments': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'contract-1',
          'name': 'contract.pdf',
          'path': '/local/contract.pdf',
          'kind': 'contract',
          'bytes': 1234,
          'createdAt': DateTime.utc(2026, 8, 17).toIso8601String(),
        },
      ],
      'comments': <dynamic>[],
      'lease': null,
      'favorite': false,
      'createdAt': DateTime.utc(2026, 8, 17).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 8, 17).toIso8601String(),
    });

    final encoded = codec.encode(raw);
    expect(encoded.containsKey('mp3Path'), isFalse);
    expect(encoded.containsKey('wavPath'), isFalse);
    expect(encoded.containsKey('trackoutPath'), isFalse);
    expect(encoded.containsKey('coverPath'), isFalse);

    final attachments = encoded['attachments'] as List<dynamic>;
    expect(attachments, hasLength(1));
    final attachment = Map<String, dynamic>.from(attachments.single as Map);
    expect(attachment['name'], 'contract.pdf');
    expect(attachment['kind'], 'contract');
    expect(attachment['bytes'], 1234);
    expect(attachment['path'], '');
  });
}
