/// Optional cash impact attached to a Task through its existing `tags` field.
///
/// No Hive schema migration is required. Existing tags remain untouched; one
/// machine-readable `cash:` tag lets Wesi Horizon treat a dated task as a
/// committed obligation or a probabilistic incoming/outgoing event.
enum TaskCashDirection { income, expense }

class TaskCashImpact {
  final TaskCashDirection direction;
  final double amount;
  final bool committed;
  final double probability;

  const TaskCashImpact({
    required this.direction,
    required this.amount,
    this.committed = true,
    this.probability = 1.0,
  });

  double get signedAmount =>
      direction == TaskCashDirection.income ? amount.abs() : -amount.abs();

  String get tag {
    final signed = signedAmount >= 0
        ? '+${signedAmount.abs().toStringAsFixed(2)}'
        : '-${signedAmount.abs().toStringAsFixed(2)}';
    if (committed) return 'cash:$signed';
    return 'cash:uncertain:$signed@${probability.clamp(0.01, 0.99).toStringAsFixed(2)}';
  }

  static bool isCashTag(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '');
    return normalized.startsWith('cash:') || normalized.startsWith('money:');
  }

  static TaskCashImpact? fromTags(List<String> tags) {
    for (final raw in tags) {
      if (!isCashTag(raw)) continue;
      var body = raw.trim().toLowerCase().replaceAll(' ', '');
      body = body.substring(body.indexOf(':') + 1);
      var committed = true;
      if (body.startsWith('uncertain:')) {
        committed = false;
        body = body.substring('uncertain:'.length);
      } else if (body.startsWith('commit:')) {
        body = body.substring('commit:'.length);
      }

      final at = body.lastIndexOf('@');
      var probability = committed ? 1.0 : 0.5;
      if (at > 0) {
        probability = double.tryParse(body.substring(at + 1)) ?? probability;
        if (probability > 1) probability /= 100;
        body = body.substring(0, at);
      }
      final normalizedAmount =
          body.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9+.-]'), '');
      final signed = double.tryParse(normalizedAmount);
      if (signed == null || signed == 0) continue;
      return TaskCashImpact(
        direction:
            signed > 0 ? TaskCashDirection.income : TaskCashDirection.expense,
        amount: signed.abs(),
        committed: committed && probability >= 0.9,
        probability: probability.clamp(0.01, 1.0).toDouble(),
      );
    }
    return null;
  }

  /// Replaces only machine cash tags and preserves every human/project tag.
  List<String> applyTo(List<String> existing) => [
        ...existing.where((tag) => !isCashTag(tag)),
        tag,
      ];

  static List<String> clearFrom(List<String> existing) =>
      existing.where((tag) => !isCashTag(tag)).toList();
}
