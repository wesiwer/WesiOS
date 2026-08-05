import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/chats/models/chat_attachment.dart';
import 'package:wesios/features/chats/models/chat_message.dart';

/// Описание вложения.
///
/// Сам файл лежит на диске, а в сообщении — только это описание. Если оно
/// разъедется с файлом или не переживёт перенос, вложение превратится в
/// пустую карточку, которую не открыть и не понять.
void main() {
  group('тип содержимого', () {
    test('картинки узнаются по расширению', () {
      for (final name in ['фото.jpg', 'СКАН.PNG', 'a.jpeg', 'x.webp']) {
        final file = ChatAttachment(
            name: name, path: '/x', sizeBytes: 1, mime: ChatAttachment.mimeOf(name));
        expect(file.isImage, isTrue, reason: name);
      }
    });

    test('документ картинкой не считается', () {
      for (final name in ['договор.pdf', 'смета.xlsx', 'архив.zip']) {
        final file = ChatAttachment(
            name: name, path: '/x', sizeBytes: 1, mime: ChatAttachment.mimeOf(name));
        expect(file.isImage, isFalse, reason: name);
      }
    });

    test('решение принимается по типу, а не по имени', () {
      // Файл «отчёт.jpg», который на самом деле не картинка, иначе ронял бы
      // отрисовку ленты попыткой его нарисовать.
      const file = ChatAttachment(
        name: 'отчёт.jpg',
        path: '/x',
        sizeBytes: 1,
        mime: 'application/pdf',
      );
      expect(file.isImage, isFalse);
    });

    test('незнакомое расширение не роняет разбор', () {
      expect(ChatAttachment.mimeOf('нечто.мутное'),
          'application/octet-stream');
      expect(ChatAttachment.mimeOf('безрасширения'),
          'application/octet-stream');
    });
  });

  group('размер словами', () {
    test('байты, килобайты и мегабайты', () {
      String label(int bytes) => ChatAttachment(
            name: 'x', path: '/x', sizeBytes: bytes, mime: 'text/plain',
          ).sizeLabel;

      expect(label(512), contains('Б'));
      expect(label(2048), contains('КБ'));
      expect(label(5 * 1024 * 1024), contains('МБ'));
    });
  });

  group('перенос описания', () {
    test('переживает круг через карту', () {
      const file = ChatAttachment(
        name: 'Договор №12.pdf',
        path: '/данные/чат/договор.pdf',
        sizeBytes: 345678,
        mime: 'application/pdf',
        sha256: 'abc123',
      );
      final back = ChatAttachment.tryParse(file.toMap())!;
      expect(back.name, file.name);
      expect(back.path, file.path);
      expect(back.sizeBytes, file.sizeBytes);
      expect(back.mime, file.mime);
      expect(back.sha256, file.sha256);
    });

    test('битое описание не разбирается, а не подставляет пустоту', () {
      expect(ChatAttachment.tryParse(null), isNull);
      expect(ChatAttachment.tryParse('строка'), isNull);
      expect(ChatAttachment.tryParse(const {'size': '10'}), isNull);
      expect(ChatAttachment.tryParse(const {'name': ''}), isNull);
    });

    test('приехавшее без пути — это описание без файла', () {
      // Так будет выглядеть вложение, приехавшее с сервера до того, как
      // сам файл скачан. Показать его надо, открыть — нельзя.
      final file = ChatAttachment.tryParse(const {
        'name': 'смета.xlsx',
        'size': '1024',
        'mime': 'application/vnd.ms-excel',
      })!;
      expect(file.isHere, isFalse);
      expect(file.name, 'смета.xlsx');
    });
  });

  group('вложение внутри сообщения', () {
    ChatMessage withFile(Map<String, String>? raw) => ChatMessage(
          id: 'm1',
          chatId: 'c1',
          authorId: 'own',
          body: 'Вот договор',
          at: DateTime.utc(2026, 8, 5),
          kind: MessageKind.file,
          attachmentRaw: raw,
        );

    test('читается из сообщения', () {
      const file = ChatAttachment(
          name: 'д.pdf', path: '/x/д.pdf', sizeBytes: 10, mime: 'application/pdf');
      expect(withFile(file.toMap()).attachment?.name, 'д.pdf');
    });

    test('сообщение без вложения не ломается', () {
      expect(withFile(null).attachment, isNull);
    });

    test('битое вложение не отнимает текст сообщения', () {
      // Потерять слова из-за испорченного описания файла хуже, чем потерять
      // описание.
      final m = withFile(const {'size': '10'});
      expect(m.attachment, isNull);
      expect(m.body, 'Вот договор');
    });

    test('переживает круг через JSON вместе с сообщением', () {
      const file = ChatAttachment(
          name: 'смета.xlsx',
          path: '/x/смета.xlsx',
          sizeBytes: 2048,
          mime: 'application/vnd.ms-excel');
      final back = ChatMessage.tryParse(withFile(file.toMap()).toJson())!;
      expect(back.kind, MessageKind.file);
      expect(back.attachment?.name, 'смета.xlsx');
      expect(back.attachment?.sizeBytes, 2048);
    });
  });
}
