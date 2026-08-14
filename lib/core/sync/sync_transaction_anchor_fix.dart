import '../../features/treasury/models/transaction_model.dart';
import 'sync_codec.dart';

/// Compatibility layer for the recurring-payment anchor in transaction sync.
///
/// Local Hive already persists [TransactionModel.recurringAnchor], but the
/// historical wire codec predates that field. Until every installation uses a
/// codec that knows about the anchor natively, this wrapper upgrades only the
/// transactions collection at runtime without changing any other sync rules.
class SyncTransactionAnchorFix {
  SyncTransactionAnchorFix._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    for (var i = 0; i < SyncCodec.collections.length; i++) {
      final collection = SyncCodec.collections[i];
      if (collection.name != 'transactions') continue;
      SyncCodec.collections[i] = _TransactionsWithAnchorSync();
      _installed = true;
      return;
    }
  }
}

class _TransactionsWithAnchorSync extends TransactionsSync {
  @override
  Map<String, dynamic> encode(TransactionModel value) {
    final fields = super.encode(value);
    fields['recurringAnchor'] = value.recurringAnchor?.toIso8601String();
    return fields;
  }

  @override
  TransactionModel? decode(Map<String, dynamic> fields) {
    final decoded = super.decode(fields);
    if (decoded == null) return null;
    final raw = fields['recurringAnchor'];
    final anchor = raw is String ? DateTime.tryParse(raw) : null;
    if (anchor == null) return decoded;
    return decoded.copyWith(recurringAnchor: anchor);
  }
}
