import '../../audio/models/audio_vault_models.dart';
import '../../team/models/employee_model.dart';
import '../../team/models/team_permissions.dart';
import '../models/file_share_models.dart';

/// Можно ли, и если нет — почему.
///
/// Отдельный тип, а не `bool`: человеку, которому отказали, нужна причина, а
/// не пустая кнопка. Разбираться, почему бит не приходит, по одному «нельзя»
/// невозможно.
class FileAccessDecision {
  final bool allowed;

  /// Короткий код для тестов и журнала.
  final String code;

  /// Объяснение человеку.
  final String reason;

  /// Решение требует явного подтверждения владельца — само по себе не
  /// открывает и не закрывает.
  final bool needsOwnerConfirmation;

  const FileAccessDecision.allow({this.code = 'ok'})
      : allowed = true,
        reason = '',
        needsOwnerConfirmation = false;

  const FileAccessDecision.confirm(this.code, this.reason)
      : allowed = true,
        needsOwnerConfirmation = true;

  const FileAccessDecision.deny(this.code, this.reason)
      : allowed = false,
        needsOwnerConfirmation = false;
}

/// Кто и какие файлы может запрашивать и отдавать.
///
/// Правила живут отдельно от передачи намеренно: их надо проверять без сети
/// и менять, не трогая транспорт. Ошибка здесь стоит дороже, чем неудачная
/// передача, — переданный не тому wav обратно не забрать.
class FileAccessPolicy {
  /// Может ли [requester] просить файл.
  static FileAccessDecision canRequest({
    required EmployeeModel requester,
    required ShareSubjectKind subjectKind,
    required String subjectId,
    BeatEntry? beat,
    List<FileAccessGrant> grants = const [],
    required DateTime now,
  }) {
    switch (subjectKind) {
      case ShareSubjectKind.beat:
        if (!requester.permissions.allows(TeamModules.audio)) {
          return const FileAccessDecision.deny(
            'no-module',
            'Раздел с битами закрыт',
          );
        }
        // Автор бита не спрашивает разрешения на собственную работу.
        if (beat != null && beat.authorEmployeeId == requester.id) {
          return const FileAccessDecision.allow(code: 'author');
        }
        return _byGrant(
          requester: requester,
          subjectKind: subjectKind,
          subjectId: subjectId,
          grants: grants,
          now: now,
          fallbackReason: 'Доступ к файлам этого бита не открыт',
        );

      case ShareSubjectKind.employeeDocument:
        // Свои документы человек забирает без чужого разрешения.
        if (subjectId == requester.id) {
          return const FileAccessDecision.allow(code: 'own-documents');
        }
        // Чужие — только у того, кто ведёт кадры. Права на раздел «Контакты»
        // мало: видеть карточку и открывать чужой паспорт — разные вещи.
        if (requester.permissions.canManageTeam) {
          return const FileAccessDecision.allow(code: 'hr');
        }
        return _byGrant(
          requester: requester,
          subjectKind: subjectKind,
          subjectId: subjectId,
          grants: grants,
          now: now,
          fallbackReason: 'Чужие документы доступны только кадровику',
        );
    }
  }

  /// Может ли [holder] отдать файл [requester].
  ///
  /// Проверяется у отдающего, а не только у просящего: устройство просящего
  /// может соврать о своих правах, а отдающее решает своей головой.
  static FileAccessDecision canRelease({
    required EmployeeModel holder,
    required EmployeeModel requester,
    required ShareSubjectKind subjectKind,
    required String subjectId,
    BeatEntry? beat,
    List<FileAccessGrant> grants = const [],
    required DateTime now,
  }) {
    // Отсутствие бита — причина более основательная, чем отсутствие
    // доступа, и проверяется раньше: иначе на пропавшую запись человек
    // получил бы «доступ не открыт» и пошёл бы просить разрешение, которое
    // ничего не изменит.
    if (subjectKind == ShareSubjectKind.beat && beat == null) {
      return const FileAccessDecision.deny(
        'unknown-beat',
        'Бит не найден в каталоге',
      );
    }

    // Дальше то же, что и для запроса: если просить нельзя, то и отдавать
    // нечего обсуждать.
    final ask = canRequest(
      requester: requester,
      subjectKind: subjectKind,
      subjectId: subjectId,
      beat: beat,
      grants: grants,
      now: now,
    );
    if (!ask.allowed) return ask;

    if (subjectKind == ShareSubjectKind.employeeDocument) {
      // Документы раздаёт только их владелец или кадровик — даже если у
      // отдающего копия почему-то оказалась.
      final mine = subjectId == holder.id;
      if (!mine && !holder.permissions.canManageTeam) {
        return const FileAccessDecision.deny(
          'not-document-owner',
          'Отдавать чужие документы нельзя',
        );
      }
      return const FileAccessDecision.allow(code: 'documents');
    }

    // Раздавать дальше может автор или тот, кому это разрешили явно.
    final isAuthor = beat!.authorEmployeeId == holder.id;
    final mayReshare = grants.any((g) =>
        g.subjectKind == subjectKind &&
        g.subjectId == subjectId &&
        g.employeeId == holder.id &&
        g.canReshare &&
        g.isActiveAt(now));
    if (!isAuthor && !mayReshare) {
      return const FileAccessDecision.deny(
        'no-reshare',
        'Раздавать этот бит дальше вам не разрешали',
      );
    }

    // Действующая аренда — не запрет, но и не пустяк: файл сданного бита
    // уходит за пределы того, о чём договаривались, и решать это должен
    // человек, а не правило.
    final lease = beat.lease;
    if (lease != null &&
        !lease.endsAt.isBefore(now) &&
        !lease.startsAt.isAfter(now) &&
        requester.id != beat.authorEmployeeId) {
      return FileAccessDecision.confirm(
        'active-lease',
        'Бит сдан ${lease.artistName} до '
            '${lease.endsAt.day}.${lease.endsAt.month}.${lease.endsAt.year}. '
            'Передача файла выходит за рамки договорённости — подтвердите, '
            'что это осознанно.',
      );
    }

    return const FileAccessDecision.allow(code: 'author-or-reshare');
  }

  static FileAccessDecision _byGrant({
    required EmployeeModel requester,
    required ShareSubjectKind subjectKind,
    required String subjectId,
    required List<FileAccessGrant> grants,
    required DateTime now,
    required String fallbackReason,
  }) {
    final mine = grants.where((g) =>
        g.subjectKind == subjectKind &&
        g.subjectId == subjectId &&
        g.employeeId == requester.id);
    if (mine.isEmpty) {
      return FileAccessDecision.deny('no-grant', fallbackReason);
    }
    if (mine.any((g) => g.isActiveAt(now))) {
      return const FileAccessDecision.allow(code: 'granted');
    }
    // Разрешение было, но кончилось. Это другая история, чем «не давали
    // никогда», и человеку стоит сказать именно её: понятно, что просить.
    return const FileAccessDecision.deny(
      'grant-expired',
      'Доступ был открыт, но срок истёк',
    );
  }
}
