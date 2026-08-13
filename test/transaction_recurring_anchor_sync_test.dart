import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_transaction_anchor_fix.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  setUpAll(SyncTransactionAnchorFix.install);

  test('transaction sync preserves recurring anchor across round trip', () {
    final anchor = DateTime.utc(2026, 1, 31, 12);
    final currentDate = DateTime.utc(2026, 2, 28, 12);
    final transaction = TransactionModel(
      id: 'recurring-anchor-round-trip',
      title: 'Аренда',
      amount: 120000,
      type: TransactionType.expense,
      date: currentDate,
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
      recurringAnchor: anchor,
    );

    final codec = SyncCodec.byName('transactions');
    expect(codec, isNotNull);

    final encoded = codec!.encode(transaction);
    expect(encoded['recurringAnchor'], anchor.toIso8601String());

    final decoded = codec.decode(encoded) as TransactionModel?;
    expect(decoded, isNotNull);
    expect(decoded!.recurringAnchor, anchor);
    expect(decoded.recurringAnchorDate, anchor);
    expect(decoded.date, currentDate);
  });

  test('legacy sync payload without anchor falls back to transaction date', () {
    final date = DateTime.utc(2026, 2, 28, 12);
    final transaction = TransactionModel(
      id: 'recurring-anchor-legacy',
      title: 'Legacy recurring',
      amount: 5000,
      type: TransactionType.expense,
      date: date,
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
    );

    final codec = SyncCodec.byName('transactions')!;
    final legacy = codec.encode(transaction)..remove('recurringAnchor');
    final decoded = codec.decode(legacy) as TransactionModel?;

    expect(decoded, isNotNull);
    expect(decoded!.recurringAnchor, isNull);
    expect(decoded.recurringAnchorDate, date);
  });
}
