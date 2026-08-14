import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_transaction_anchor_fix.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  test('transaction sync preserves recurring anchor across wire round-trip', () {
    SyncTransactionAnchorFix.install();
    final collection = SyncCodec.byName('transactions');
    expect(collection, isNotNull);

    final anchor = DateTime(2026, 1, 31, 9, 30);
    final movedDate = DateTime(2026, 2, 28, 9, 30);
    final transaction = TransactionModel(
      id: 'recurring-rent',
      title: 'Rent',
      amount: 1000,
      type: TransactionType.expense,
      date: movedDate,
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
      recurringAnchor: anchor,
    );

    final payload = collection!.encode(transaction);
    expect(payload['recurringAnchor'], anchor.toIso8601String());

    final decoded = collection.decode(payload) as TransactionModel?;
    expect(decoded, isNotNull);
    expect(decoded!.date, movedDate);
    expect(decoded.recurringAnchor, anchor);
    expect(decoded.recurringAnchorDate, anchor);
  });

  test('legacy transaction payload without anchor still decodes', () {
    SyncTransactionAnchorFix.install();
    final collection = SyncCodec.byName('transactions');
    expect(collection, isNotNull);

    final date = DateTime(2026, 3, 28, 9, 30);
    final payload = <String, dynamic>{
      'id': 'legacy-recurring',
      'title': 'Legacy rent',
      'amount': 1000.0,
      'type': TransactionType.expense.name,
      'date': date.toIso8601String(),
      'isRecurring': true,
      'recurringPeriod': RecurringPeriod.monthly.name,
    };

    final decoded = collection!.decode(payload) as TransactionModel?;
    expect(decoded, isNotNull);
    expect(decoded!.recurringAnchor, isNull);
    expect(decoded.recurringAnchorDate, date);
  });
}
