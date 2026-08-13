import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/files/models/file_share_models.dart';
import 'package:wesios/features/files/services/file_access_policy.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';

/// Правила, по которым файл уходит с одного устройства на другое.
///
/// Ошибка здесь стоит дороже неудачной передачи: переданный не тому wav
/// обратно не забрать, а бит, сданный в эксклюзивную аренду, — предмет
/// договора.
void main() {
  final now = DateTime.utc(2026, 8, 13, 12);

  EmployeeModel person(
    String id, {
    List<String> modules = const [TeamModules.audio],
    bool manageTeam = false,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        createdAt: now,
        permissions: TeamPermissions(
          moduleList: modules,
          canManageTeam: manageTeam,
        ),
      );

  BeatEntry beatOf(String authorId, {BeatLease? lease}) => BeatEntry(
        id: 'B1',
        title: 'Ночной',
        authorEmployeeId: authorId,
        lease: lease,
        createdAt: now,
        updatedAt: now,
      );

  BeatLease lease({
    required DateTime from,
    required DateTime to,
  }) =>
      BeatLease(
        id: 'L1',
        artistName: 'Студия',
        socialUrl: '',
        startsAt: from,
        endsAt: to,
        amount: 25000,
        currency: 'RUB',
        notes: '',
      );

  FileAccessGrant grant(
    String employeeId, {
    DateTime? until,
    bool reshare = false,
    ShareSubjectKind kind = ShareSubjectKind.beat,
    String subjectId = 'B1',
  }) =>
      FileAccessGrant(
        id: 'G-$employeeId',
        subjectKind: kind,
        subjectId: subjectId,
        employeeId: employeeId,
        grantedBy: 'wesi',
        grantedAt: now.subtract(const Duration(days: 1)),
        expiresAt: until,
        canReshare: reshare,
      );

  group('запрос бита', () {
    test('без доступа к разделу — нельзя даже просить', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan', modules: const []),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'no-module');
    });

    test('автор не спрашивает разрешения на свою работу', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('wesi'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.code, 'author');
    });

    test('доступ к разделу сам по себе не открывает файлы', () {
      // Видеть, что бит существует, и унести его wav — разные вещи.
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'no-grant');
    });

    test('с открытым доступом — можно', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan')],
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.code, 'granted');
    });

    test('истёкший доступ отличается от «не давали никогда»', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan', until: now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'grant-expired',
          reason: 'человеку важно знать, что просить продления, а не доступа');
    });

    test('чужой доступ не открывает мой', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('petr')],
        now: now,
      );
      expect(d.allowed, isFalse);
    });

    test('доступ к другому биту не открывает этот', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan', subjectId: 'B2')],
        now: now,
      );
      expect(d.allowed, isFalse);
    });
  });

  group('раздача бита', () {
    test('получивший бит не становится его распространителем', () {
      // У Ивана есть доступ и файл, но раздавать дальше ему не разрешали.
      final d = FileAccessPolicy.canRelease(
        holder: person('ivan'),
        requester: person('petr'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan'), grant('petr')],
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'no-reshare');
    });

    test('с разрешением раздавать — можно', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('ivan'),
        requester: person('petr'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan', reshare: true), grant('petr')],
        now: now,
      );
      expect(d.allowed, isTrue);
    });

    test('автор раздаёт свой бит без отдельного разрешения', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('wesi'),
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf('wesi'),
        grants: [grant('ivan')],
        now: now,
      );
      expect(d.allowed, isTrue);
    });

    test('действующая аренда требует осознанного подтверждения', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('wesi'),
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf(
          'wesi',
          lease: lease(
            from: now.subtract(const Duration(days: 10)),
            to: now.add(const Duration(days: 300)),
          ),
        ),
        grants: [grant('ivan')],
        now: now,
      );
      expect(d.allowed, isTrue, reason: 'это не запрет, а предупреждение');
      expect(d.needsOwnerConfirmation, isTrue);
      expect(d.code, 'active-lease');
      expect(d.reason, contains('Студия'),
          reason: 'человек должен видеть, кому сдан бит');
    });

    test('истёкшая аренда не требует подтверждения', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('wesi'),
        requester: person('ivan'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf(
          'wesi',
          lease: lease(
            from: now.subtract(const Duration(days: 400)),
            to: now.subtract(const Duration(days: 30)),
          ),
        ),
        grants: [grant('ivan')],
        now: now,
      );
      expect(d.needsOwnerConfirmation, isFalse);
    });

    test('автору его собственный бит отдают без предупреждения об аренде', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('ivan'),
        requester: person('wesi'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: beatOf(
          'wesi',
          lease: lease(
            from: now.subtract(const Duration(days: 10)),
            to: now.add(const Duration(days: 300)),
          ),
        ),
        grants: [grant('ivan', reshare: true)],
        now: now,
      );
      expect(d.needsOwnerConfirmation, isFalse);
    });

    test('бита нет в каталоге — отдавать нечего', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('wesi'),
        requester: person('wesi'),
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        beat: null,
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'unknown-beat');
    });
  });

  group('документы сотрудников', () {
    test('свои документы человек забирает сам', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan', modules: const []),
        subjectKind: ShareSubjectKind.employeeDocument,
        subjectId: 'ivan',
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.code, 'own-documents');
    });

    test('чужие документы закрыты даже при доступе к контактам', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('ivan', modules: const [TeamModules.contacts]),
        subjectKind: ShareSubjectKind.employeeDocument,
        subjectId: 'petr',
        now: now,
      );
      expect(d.allowed, isFalse,
          reason: 'видеть карточку и открывать чужой паспорт — разные вещи');
    });

    test('кадровик может', () {
      final d = FileAccessPolicy.canRequest(
        requester: person('hr', manageTeam: true),
        subjectKind: ShareSubjectKind.employeeDocument,
        subjectId: 'petr',
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.code, 'hr');
    });

    test('отдавать чужие документы нельзя, даже имея копию', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('ivan'),
        requester: person('hr', manageTeam: true),
        subjectKind: ShareSubjectKind.employeeDocument,
        subjectId: 'petr',
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.code, 'not-document-owner');
    });

    test('свои документы человек отдаёт кадровику сам', () {
      final d = FileAccessPolicy.canRelease(
        holder: person('petr'),
        requester: person('hr', manageTeam: true),
        subjectKind: ShareSubjectKind.employeeDocument,
        subjectId: 'petr',
        now: now,
      );
      expect(d.allowed, isTrue);
    });
  });

  group('разбор записей', () {
    test('запрос переживает круг через JSON', () {
      final original = FileShareRequest(
        id: 'R1',
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        fileKind: ShareFileKind.wav,
        requesterId: 'ivan',
        holderId: 'wesi',
        createdAt: now,
      );
      final back = FileShareRequest.tryParse(original.toJson())!;
      expect(back.id, 'R1');
      expect(back.fileKind, ShareFileKind.wav);
      expect(back.status, ShareRequestStatus.pending);
      expect(back.isOpen, isTrue);
    });

    test('незнакомое состояние не считается выполненным', () {
      // Запись от более новой версии не должна открывать доступ, которого
      // не давали.
      final back = FileShareRequest.tryParse({
        'id': 'R2',
        'subjectId': 'B1',
        'requesterId': 'ivan',
        'createdAt': now.toIso8601String(),
        'status': 'somethingNew',
      })!;
      expect(back.status, ShareRequestStatus.pending);
    });

    test('запись журнала хранит отпечаток переданного файла', () {
      final h = FileHandover(
        id: 'H1',
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        fileKind: ShareFileKind.wav,
        fromEmployeeId: 'wesi',
        toEmployeeId: 'ivan',
        sizeBytes: 48000000,
        checksum: 'abc123',
        at: now,
        route: ShareRoute.lan,
      );
      final back = FileHandover.tryParse(h.toJson())!;
      expect(back.checksum, 'abc123');
      expect(back.sizeBytes, 48000000);
      expect(back.route, ShareRoute.lan);
    });

    test('мусор вместо записи не разбирается, а не притворяется пустым', () {
      expect(FileShareRequest.tryParse(const {}), isNull);
      expect(FileAccessGrant.tryParse(const {'id': 'G'}), isNull);
      expect(FileHandover.tryParse(const {'id': 'H'}), isNull);
    });
  });
}
