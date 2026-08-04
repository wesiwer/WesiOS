import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/chats/models/chat_policy.dart';

/// Кто может прочитать переписку — решение владельца, а не деталь реализации.
/// Тест здесь затем, чтобы это решение нельзя было изменить случайно:
/// «добавили корпоративный ключ во все чаты, чтобы было проще» — ровно та
/// правка, которая проходит незамеченной и отменяет договорённость.
void main() {
  group('шифрование чатов', () {
    test('рабочий чат читает владелец', () {
      expect(ChatEnvelopePolicy.ownerCanRead(ChatKind.work), isTrue);
    });

    test('личный чат владелец не читает', () {
      expect(ChatEnvelopePolicy.ownerCanRead(ChatKind.personal), isFalse);
    });

    test('в рабочем чате ключ шифруется и корпоративному ключу', () {
      final to = ChatEnvelopePolicy.keyRecipients(
          ChatKind.work, ['device-a', 'device-b']);
      expect(to, contains(ChatEnvelopePolicy.corporateKeyId));
      expect(to, containsAll(['device-a', 'device-b']));
    });

    test('в личном чате получатели — только собеседники', () {
      final to = ChatEnvelopePolicy.keyRecipients(
          ChatKind.personal, ['device-a', 'device-b']);
      expect(to, ['device-a', 'device-b']);
      expect(to, isNot(contains(ChatEnvelopePolicy.corporateKeyId)),
          reason: 'личная переписка перестала быть личной');
    });

    test('получатель не получает ключ дважды', () {
      final to = ChatEnvelopePolicy.keyRecipients(
        ChatKind.work,
        ['device-a', 'device-a', ChatEnvelopePolicy.corporateKeyId],
      );
      expect(to.length, 2);
      expect(to.toSet().length, to.length);
    });

    test('подпись под чатом говорит правду о том, кто его читает', () {
      final work = ChatEnvelopePolicy.describe(ChatKind.work, russian: true);
      final personal =
          ChatEnvelopePolicy.describe(ChatKind.personal, russian: true);
      expect(work, contains('владелец'));
      expect(personal, contains('только'));
      expect(work, isNot(personal));
    });
  });
}
