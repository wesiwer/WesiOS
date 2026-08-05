import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/services/employee_documents_service.dart';
import 'package:wesios/features/team/widgets/employee_notes_sheet.dart';

void main() {
  test('employee dossier exposes private document contract', () {
    final document = EmployeeDocument(
      id: 'doc-1',
      name: 'contract.pdf',
      extension: 'pdf',
      bytes: Uint8List.fromList(const [1, 2, 3]),
      addedAt: DateTime(2026, 8, 5),
    );

    expect(EmployeeDocumentsService.maxFileBytes, 10 * 1024 * 1024);
    expect(document.sizeBytes, 3);
    expect(document.toMap()['name'], 'contract.pdf');
    expect(EmployeeNotesSheet, isNotNull);
  });
}
