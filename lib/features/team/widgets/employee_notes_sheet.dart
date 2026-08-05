import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wesi_avatar.dart';
import '../models/employee_model.dart';
import '../services/employee_documents_service.dart';
import '../services/team_service.dart';

/// Закрытое досье сотрудника.
///
/// Открывается долгим нажатием на телефоне или правой кнопкой мыши на
/// компьютере. Полная версия с продуктивностью, комментариями и документами
/// доступна только владельцу. Пользователь с отдельным правом заметок видит
/// лишь разрешённый комментарий.
class EmployeeNotesSheet extends StatefulWidget {
  final EmployeeModel employee;

  const EmployeeNotesSheet({super.key, required this.employee});

  static Future<void> show(BuildContext context, EmployeeModel employee) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => EmployeeNotesSheet(employee: employee),
    );
  }

  @override
  State<EmployeeNotesSheet> createState() => _EmployeeNotesSheetState();
}

class _EmployeeNotesSheetState extends State<EmployeeNotesSheet> {
  late EmployeeModel _employee;
  late final TextEditingController _notes;
  bool _saving = false;
  bool _addingFile = false;

  bool get _ru => WesiLocale.isRussian;
  bool get _ownerView => TeamService.isOwnerSession;
  List<EmployeeDocument> get _documents =>
      EmployeeDocumentsService.forEmployee(_employee.id);

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
    _notes = TextEditingController(text: _employee.notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    if (!_ownerView || _saving) return;
    setState(() => _saving = true);
    try {
      _employee = _employee.copyWith(notes: _notes.text.trim());
      await TeamService.save(_employee);
      if (mounted) _toast(_ru ? 'Комментарий сохранён' : 'Comment saved');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addDocument() async {
    if (!_ownerView || _addingFile) return;
    setState(() => _addingFile = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt',
          'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'webp', 'zip'
        ],
      );
      final file = picked?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      if (bytes.length > EmployeeDocumentsService.maxFileBytes) {
        _toast(_ru ? 'Файл больше 10 МБ' : 'File is larger than 10 MB', error: true);
        return;
      }
      await EmployeeDocumentsService.add(
        employeeId: _employee.id,
        name: file.name,
        extension: file.extension ?? '',
        bytes: bytes,
      );
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _addingFile = false);
    }
  }

  Future<void> _removeDocument(EmployeeDocument document) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(_ru ? 'Удалить документ?' : 'Delete document?'),
        content: Text(document.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_ru ? 'Удалить' : 'Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await EmployeeDocumentsService.remove(_employee.id, document.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .92;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.glassBorder,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
              children: [
                _header(),
                const SizedBox(height: 18),
                _facts(),
                if (_ownerView) ...[
                  const SizedBox(height: 18),
                  _productivity(),
                ],
                const SizedBox(height: 18),
                _comments(),
                if (_ownerView) ...[
                  const SizedBox(height: 18),
                  _documentsSection(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WesiAvatar(size: 58, index: _employee.avatarIndex, photo: _employee.photo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employee.displayName,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (_employee.position.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_employee.position,
                      style: TextStyle(fontSize: 13, color: AppTheme.accent)),
                ],
                const SizedBox(height: 6),
                Text(
                  _ru ? 'Закрытое досье сотрудника' : 'Private employee dossier',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: AppTheme.textMuted),
          ),
        ],
      );

  Widget _facts() {
    final now = DateTime.now();
    final tenure = now.difference(_employee.createdAt);
    final months = math.max(0,
        (now.year - _employee.createdAt.year) * 12 + now.month - _employee.createdAt.month);
    final tenureText = months >= 12
        ? (_ru
            ? '${months ~/ 12} г. ${months % 12} мес.'
            : '${months ~/ 12} y ${months % 12} mo')
        : months > 0
            ? (_ru ? '$months мес.' : '$months mo')
            : (_ru ? '${tenure.inDays} дн.' : '${tenure.inDays} days');
    return _panel(
      title: _ru ? 'Информация' : 'Information',
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          _row(_ru ? 'Логин' : 'Login', _employee.login),
          _row(_ru ? 'Добавлен' : 'Added', _date(_employee.createdAt)),
          _row(_ru ? 'Стаж в Wesi Inc' : 'Tenure at Wesi Inc', tenureText),
          if (_employee.phone.trim().isNotEmpty)
            _row(_ru ? 'Телефон' : 'Phone', _employee.phone),
          if (_employee.email.trim().isNotEmpty)
            _row(_ru ? 'Почта' : 'Email', _employee.email),
        ],
      ),
    );
  }

  Widget _productivity() {
    final stats = _employee.demoStats;
    final efficiency = (stats['efficiency'] ?? 0).clamp(0, 1).toDouble();
    final done = (stats['tasksDone'] ?? 0).round();
    final open = (stats['tasksOpen'] ?? 0).round();
    return _panel(
      title: _ru ? 'Продуктивность' : 'Productivity',
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _metric(_ru ? 'Выполнено' : 'Completed', '$done'),
              const SizedBox(width: 8),
              _metric(_ru ? 'Открыто' : 'Open', '$open'),
              const SizedBox(width: 8),
              _metric(_ru ? 'Эффективность' : 'Efficiency',
                  '${(efficiency * 100).round()}%'),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: efficiency,
              minHeight: 7,
              backgroundColor: AppTheme.surfaceLight,
              valueColor: AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stats.isEmpty
                ? (_ru ? 'Данные продуктивности пока не собраны.' : 'No productivity data yet.')
                : (_ru ? 'Показатели обновляются вместе с рабочими данными.' : 'Metrics update with work data.'),
            style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _comments() => _panel(
        title: _ru ? 'Ваши комментарии' : 'Your comments',
        icon: Icons.lock_outline,
        child: Column(
          children: [
            TextField(
              controller: _notes,
              readOnly: !_ownerView,
              minLines: 4,
              maxLines: 8,
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: _ru
                    ? 'Договорённости, впечатления, важные детали…'
                    : 'Agreements, impressions, important details…',
                filled: true,
                fillColor: AppTheme.surfaceLight.withOpacity(.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.glassBorder),
                ),
              ),
            ),
            if (_ownerView) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveNotes,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_ru ? 'Сохранить комментарий' : 'Save comment'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _documentsSection() {
    final docs = _documents;
    return _panel(
      title: _ru ? 'Документы' : 'Documents',
      icon: Icons.folder_copy_outlined,
      trailing: IconButton(
        tooltip: _ru ? 'Прикрепить документ' : 'Attach document',
        onPressed: _addingFile ? null : _addDocument,
        icon: _addingFile
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.add, color: AppTheme.accent),
      ),
      child: docs.isEmpty
          ? Text(
              _ru
                  ? 'Здесь можно хранить договоры, соглашения и другие документы сотрудника.'
                  : 'Store contracts, agreements and other employee documents here.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.textMuted),
            )
          : Column(
              children: docs.map((doc) => _documentTile(doc)).toList(),
            ),
    );
  }

  Widget _documentTile(EmployeeDocument doc) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withOpacity(.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 20, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${_size(doc.sizeBytes)} · ${_date(doc.addedAt)}',
                      style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _removeDocument(doc),
              icon: Icon(Icons.delete_outline, size: 19, color: AppTheme.accentRed),
            ),
          ],
        ),
      );

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withOpacity(.28),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _metric(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 3),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 8.5, color: AppTheme.textMuted)),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
            Expanded(
              child: SelectableText(value,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            ),
          ],
        ),
      );

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
      : '${math.max(1, bytes ~/ 1024)} КБ';

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppTheme.accentRed : null,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
