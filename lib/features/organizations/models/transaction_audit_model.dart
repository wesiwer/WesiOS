import 'package:hive/hive.dart';

part 'transaction_audit_model.g.dart';

@HiveType(typeId: 85)
class TransactionAuditModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String transactionId;
  @HiveField(2)
  final String changedBy;
  @HiveField(3)
  final DateTime changedAt;
  @HiveField(4)
  final String? beforeJson;
  @HiveField(5)
  final String? afterJson;
  @HiveField(6)
  final String? reason;
  @HiveField(7)
  final String organizationId;

  const TransactionAuditModel({
    required this.id,
    required this.transactionId,
    required this.changedBy,
    required this.changedAt,
    this.beforeJson,
    this.afterJson,
    this.reason,
    required this.organizationId,
  });
}
