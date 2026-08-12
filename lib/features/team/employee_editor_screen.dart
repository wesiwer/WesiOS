import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/window_controls.dart';
import '../knowledge/models/article_model.dart';
import '../knowledge/services/knowledge_service.dart';
import 'models/employee_model.dart';
import 'models/team_permissions.dart';
import 'services/contact_actions.dart';
import 'services/login_pool_service.dart';
import 'services/team_service.dart';
import 'services/team_skill_service.dart';
import 'widgets/credentials_result_dialog.dart';

/// Заведение и правка сотрудника.
///
/// Один экран на оба случая намеренно: набор полей и набор прав одинаковы, а
/// два похожих экрана однажды разошлись бы — в одном появилось бы поле,
/// которого нет в другом.
class EmployeeEditorScreen extends StatefulWidget {
  final EmployeeModel? initial;

  const EmployeeEditorScreen({super.key, this.initial});

  static Future<EmployeeModel?> open(
    BuildContext context, {
    EmployeeModel? initial,
  }) {
    return Navigator.push<EmployeeModel>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeEditorScreen(initial: initial),
      ),
    );
  }

  @override
  State<EmployeeEditorScreen> createState() => _EmployeeEditorScreenState();
}

class _EmployeeEditorScreenState extends State<EmployeeEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final Map<String, TextEditingController> _socialCtrls = {};

  late TeamPermissions _permissions;
  int _avatarIndex = 0;
  Uint8List? _photo;
  bool _photoCleared = false;
  bool _saving = false;
  List<ArticleModel> _articles = const [];
  final Set<String> _skills = <String>{};
  double _weeklyCapacity = 10;
  double _minLoad = .65;
  double _maxLoad = 1.10;
  String? _managerId;
  String _alertTarget = 'manager';

  bool get _ru => WesiLocale.isRussian;
  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _permissions = e?.permissions ?? TeamPermissions.employeeDefault;
    _avatarIndex = e?.avatarIndex ?? 0;
    _photo = e?.photo;
    if (e != null) {
      _nameCtrl.text = e.fullName;
      _nickCtrl.text = e.nickname;
      _positionCtrl.text = e.position;
      _phoneCtrl.text = e.phone;
      _emailCtrl.text = e.email;
      _notesCtrl.text = e.notes;
      _skills.addAll(e.skills);
      _weeklyCapacity = e.weeklyCapacityPoints;
      _minLoad = e.workloadMinRatio;
      _maxLoad = e.workloadMaxRatio;
      _managerId = e.managerEmployeeId;
      _alertTarget = e.workloadAlertTarget;
    }
    TeamSkillService.ensureOpen().then((_) {
      if (mounted) setState(() {});
    });
    for (final network in ContactActions.knownNetworks) {
      _socialCtrls[network] =
          TextEditingController(text: e?.socials[network] ?? '');
    }
    _loadArticles();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _nickCtrl,
      _positionCtrl,
      _phoneCtrl,
      _emailCtrl,
      _notesCtrl,
      ..._socialCtrls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadArticles() async {
    final all = await KnowledgeService.getAll();
    if (mounted) setState(() => _articles = all);
  }

  Map<String, String> get _socials {
    final result = <String, String>{};
    _socialCtrls.forEach((network, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) result[network] = v;
    });
    return result;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty && _nickCtrl.text.trim().isEmpty) {
      _error(_ru ? 'Введите имя или ник' : 'Enter a name or nickname');
      return;
    }
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!TeamService.validEmployeeEmail(email)) {
      _error(_ru
          ? 'Укажите действующую электронную почту — на неё будут приходить коды входа'
          : 'Enter a valid email address for sign-in codes');
      return;
    }
    final duplicateEmail = TeamService.byEmail(email);
    if (duplicateEmail != null && duplicateEmail.id != widget.initial?.id) {
      _error(_ru
          ? 'Эта электронная почта уже используется другим сотрудником'
          : 'This email is already used by another employee');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isNew) {
        final created = await TeamService.create(
          fullName: name,
          nickname: _nickCtrl.text,
          position: _positionCtrl.text,
          phone: _phoneCtrl.text,
          email: email,
          socials: _socials,
          notes: _notesCtrl.text,
          permissions: _permissions,
          avatarIndex: _avatarIndex,
          photo: _photo,
          skills: _skills.toList(),
          weeklyCapacityPoints: _weeklyCapacity,
          workloadMinRatio: _minLoad,
          workloadMaxRatio: _maxLoad,
          managerEmployeeId: _managerId,
          workloadAlertTarget: _alertTarget,
        );
        if (created == null) {
          _error(_ru
              ? 'Не удалось создать сотрудника. Проверьте почту и данные профиля'
              : 'Unable to create the employee. Check the email and profile data');
          return;
        }
        if (!mounted) return;
        await CredentialsResultDialog.show(
          context,
          login: created.employee.login,
          password: created.password,
        );
        if (mounted) Navigator.pop(context, created.employee);
      } else {
        final updated = widget.initial!.copyWith(
          fullName: name,
          nickname: _nickCtrl.text.trim(),
          position: _positionCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: email,
          socials: _socials,
          notes: _notesCtrl.text,
          permissions: _permissions,
          avatarIndex: _avatarIndex,
          photo: _photo,
          clearPhoto: _photoCleared && _photo == null,
          skills: _skills.toList(),
          weeklyCapacityPoints: _weeklyCapacity,
          workloadMinRatio: _minLoad,
          workloadMaxRatio: _maxLoad,
          managerEmployeeId: _managerId,
          clearManager: _managerId == null,
          workloadAlertTarget: _alertTarget,
        );
        await TeamService.save(updated);
        if (mounted) Navigator.pop(context, updated);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Выбор снимка.
  ///
  /// Ограничение по размеру — не придирка: снимок с телефона весит мегабайты,
  /// а рисуется кружком в сорок точек. Карточка целиком уезжает на сервер и
  /// лежит в базе на каждом устройстве; десять сотрудников по три мегабайта
  /// — это тридцать мегабайт, которые синхронизация будет возить туда-сюда
  /// ради кружков.
  Future<void> _pickPhoto() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    if (bytes.length > TeamService.maxPhotoBytes) {
      _error(_ru
          ? 'Снимок больше ${TeamService.maxPhotoBytes ~/ 1024} КБ. '
              'Обрежьте или уменьшите его.'
          : 'Image larger than ${TeamService.maxPhotoBytes ~/ 1024} KB.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      _photoCleared = false;
    });
  }

  Future<void> _resetPassword() async {
    final e = widget.initial;
    if (e == null) return;
    final fresh = await TeamService.resetPassword(e.id);
    if (fresh == null || !mounted) return;
    await CredentialsResultDialog.show(
      context,
      login: e.login,
      password: fresh,
      isReset: true,
    );
  }

  Future<void> _remove() async {
    final e = widget.initial;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(_ru ? 'Убрать сотрудника?' : 'Remove employee?',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        content: Text(
          _ru
              ? '${e.displayName} потеряет доступ. Логин «${e.login}» вернётся '
                  'в свободные и сможет достаться кому-то другому, пароль '
                  'сотрётся.'
              : '${e.displayName} loses access. The login "${e.login}" returns '
                  'to the free pool and the password is erased.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_ru ? 'Убрать' : 'Remove',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TeamService.remove(e.id);
    if (mounted) Navigator.pop(context);
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwnerCard = widget.initial?.isOwner == true;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  8, kTitleBarInset + 8, kHasCustomTitleBar ? 148 : 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _isNew
                          ? (_ru ? 'Новый сотрудник' : 'New employee')
                          : (_ru ? 'Сотрудник' : 'Employee'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  if (_saving)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent),
                      ),
                    ),
                  HoverButton(
                    onTap: _saving ? () {} : _save,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      _isNew
                          ? (_ru ? 'Добавить' : 'Add')
                          : WesiLocale.get('save'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  if (_isNew) _loginHint(),
                  _section(_ru ? 'Кто это' : 'Who is this'),
                  _avatarRow(),
                  const SizedBox(height: 14),
                  _field(_nameCtrl, _ru ? 'Имя и фамилия' : 'Full name'),
                  _field(_nickCtrl, _ru ? 'Ник (если есть)' : 'Nickname'),
                  _field(_positionCtrl, _ru ? 'Должность' : 'Position'),
                  const SizedBox(height: 18),
                  _section(_ru ? 'Навыки' : 'Skills'),
                  _skillsEditor(),
                  const SizedBox(height: 18),
                  _section(
                      _ru ? 'Рекомендуемая нагрузка' : 'Recommended workload'),
                  _workloadEditor(),
                  const SizedBox(height: 18),
                  _section(_ru ? 'Связь — видно всем' : 'Contacts — public'),
                  _field(_phoneCtrl, _ru ? 'Телефон' : 'Phone',
                      keyboard: TextInputType.phone),
                  _field(_emailCtrl, _ru ? 'Почта *' : 'Email *',
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 6),
                  for (final network in ContactActions.knownNetworks)
                    _field(_socialCtrls[network]!, network,
                        hint: _ru ? '@имя или ссылка' : '@name or link'),
                  const SizedBox(height: 18),
                  _section(_ru ? 'Заметка — видно только вам' : 'Private note'),
                  _noteField(),
                  const SizedBox(height: 22),
                  if (!isOwnerCard) ...[
                    _section(_ru ? 'Что открыто' : 'What is open'),
                    _defaultsHint(),
                    const SizedBox(height: 10),
                    ..._moduleGroups(),
                    if (_permissions.allows(TeamModules.knowledge)) ...[
                      const SizedBox(height: 14),
                      _knowledgePicker(),
                    ],
                    const SizedBox(height: 16),
                    _section(_ru ? 'Особые права' : 'Special rights'),
                    _special(),
                  ] else
                    _ownerNotice(),
                  if (!_isNew && !isOwnerCard) ...[
                    const SizedBox(height: 26),
                    _dangerZone(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- кусочки

  Future<void> _addSkill() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(_ru ? 'Новый навык' : 'New skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText:
                _ru ? 'Например: Саунд-дизайн' : 'For example: Sound design',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_ru ? 'Добавить' : 'Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final saved = await TeamSkillService.add(value);
    if (saved != null && mounted) setState(() => _skills.add(saved));
  }

  Widget _skillsEditor() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? 'Можно выбрать несколько. Wesi AI будет учитывать их при назначении задач.'
                  : 'Select multiple. Wesi AI uses these skills for task assignment.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final skill in TeamSkillService.all)
                  FilterChip(
                    label: Text(skill),
                    selected: _skills.contains(skill),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _skills.add(skill);
                      } else {
                        _skills.remove(skill);
                      }
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(_ru ? 'Новый навык' : 'New skill'),
                  onPressed: _addSkill,
                ),
              ],
            ),
          ],
        ),
      );

  Widget _workloadEditor() {
    final managers =
        TeamService.all.where((e) => e.id != widget.initial?.id).toList();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ru
                ? 'Недельная ёмкость: ${_weeklyCapacity.toStringAsFixed(0)} баллов'
                : 'Weekly capacity: ${_weeklyCapacity.toStringAsFixed(0)} points',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
          ),
          Slider(
            value: _weeklyCapacity.clamp(4, 24),
            min: 4,
            max: 24,
            divisions: 20,
            label: _weeklyCapacity.toStringAsFixed(0),
            onChanged: (v) => setState(() => _weeklyCapacity = v),
          ),
          Text(
            _ru
                ? 'Норма: ${(_minLoad * 100).round()}–${(_maxLoad * 100).round()}% от ёмкости'
                : 'Normal range: ${(_minLoad * 100).round()}–${(_maxLoad * 100).round()}%',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          RangeSlider(
            values: RangeValues(
                _minLoad.clamp(.35, .95), _maxLoad.clamp(.75, 1.45)),
            min: .35,
            max: 1.45,
            divisions: 22,
            labels: RangeLabels(
                '${(_minLoad * 100).round()}%', '${(_maxLoad * 100).round()}%'),
            onChanged: (values) => setState(() {
              _minLoad = values.start;
              _maxLoad = values.end;
            }),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: managers.any((e) => e.id == _managerId) ? _managerId : null,
            decoration:
                InputDecoration(labelText: _ru ? 'Руководитель' : 'Manager'),
            items: [
              DropdownMenuItem<String?>(
                  value: null, child: Text(_ru ? 'Не выбран' : 'Not selected')),
              for (final manager in managers)
                DropdownMenuItem<String?>(
                    value: manager.id, child: Text(manager.displayName)),
            ],
            onChanged: (value) => setState(() => _managerId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value:
                const {'manager', 'ceo', 'both', 'off'}.contains(_alertTarget)
                    ? _alertTarget
                    : 'manager',
            decoration: InputDecoration(
              labelText: _ru ? 'Кому сообщать о нагрузке' : 'Workload alerts',
            ),
            items: [
              DropdownMenuItem(
                  value: 'manager',
                  child: Text(_ru ? 'Руководителю' : 'Manager')),
              DropdownMenuItem(
                  value: 'ceo', child: Text(_ru ? 'Только CEO' : 'CEO only')),
              DropdownMenuItem(
                  value: 'both',
                  child: Text(_ru ? 'Руководителю и CEO' : 'Manager and CEO')),
              DropdownMenuItem(
                  value: 'off', child: Text(_ru ? 'Не уведомлять' : 'Off')),
            ],
            onChanged: (value) =>
                setState(() => _alertTarget = value ?? 'manager'),
          ),
        ],
      ),
    );
  }

  Widget _loginHint() {
    final free = LoginPoolService.freeCount;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined, size: 17, color: AppTheme.accent),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              _ru
                  ? 'Логин и пароль выдаст система, когда вы нажмёте '
                      '«Добавить». Свободных логинов: $free.'
                  : 'The login and password are issued on "Add". '
                      'Free logins: $free.',
              style: TextStyle(
                  fontSize: 12, height: 1.45, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerNotice() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
        ),
        child: Text(
          _ru
              ? 'Это ваша карточка. Права владельца не урезаются и удалить '
                  'её нельзя — иначе некому будет заводить остальных.'
              : 'This is your own card. Owner rights cannot be reduced and '
                  'the card cannot be deleted.',
          style: TextStyle(
              fontSize: 12, height: 1.45, color: AppTheme.textSecondary),
        ),
      );

  Widget _defaultsHint() => Text(
        _ru
            ? 'Закрытые разделы человек не увидит вовсе — ни в меню, ни во '
                'вкладках. Главная, задачи, настройки и профиль открыты всегда.'
            : 'Closed sections are not shown at all. Home, tasks, settings '
                'and profile are always open.',
        style:
            TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.textMuted),
      );

  List<Widget> _moduleGroups() {
    final widgets = <Widget>[];
    TeamModules.groups.forEach((group, modules) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6, left: 2),
        child: Text(
          group.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppTheme.textMuted),
        ),
      ));
      for (final m in modules) {
        widgets.add(_moduleTile(m));
      }
    });
    return widgets;
  }

  Widget _moduleTile(String module) {
    final on = _permissions.allows(module);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(on ? 0.55 : 0.3),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color:
                on ? AppTheme.accent.withOpacity(0.35) : AppTheme.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ru
                        ? TeamModules.labelRu(module)
                        : TeamModules.labelEn(module),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                  if (_ru && TeamModules.hintRu(module).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(TeamModules.hintRu(module),
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ),
            Switch(
              value: on,
              activeColor: AppTheme.accent,
              onChanged: (v) => setState(
                  () => _permissions = _permissions.withModule(module, v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _knowledgePicker() {
    final folders = _articles.where((a) => a.isFolder).toList();
    final articles = _articles.where((a) => !a.isFolder).toList();

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ru ? 'Разделы базы знаний' : 'Knowledge base sections',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          _checkRow(
            label: _ru ? 'Вся база, включая будущие статьи' : 'Everything',
            value: _permissions.knowledgeAll,
            onChanged: (v) => setState(
                () => _permissions = _permissions.copyWith(knowledgeAll: v)),
          ),
          if (!_permissions.knowledgeAll) ...[
            const Divider(height: 18),
            if (_articles.isEmpty)
              Text(
                _ru ? 'Статей пока нет' : 'No articles yet',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              )
            else ...[
              if (folders.isNotEmpty) ...[
                Text(_ru ? 'Папки' : 'Folders',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                for (final f in folders)
                  _checkRow(
                    label: f.title,
                    value: _permissions.allowsArticle(f.id),
                    onChanged: (v) => setState(
                        () => _permissions = _permissions.withArticle(f.id, v)),
                    icon: Icons.folder_outlined,
                  ),
                const SizedBox(height: 8),
              ],
              Text(_ru ? 'Статьи' : 'Articles',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final a in articles)
                        _checkRow(
                          label: a.title,
                          value: _permissions.allowsArticle(a.id),
                          onChanged: (v) => setState(() =>
                              _permissions = _permissions.withArticle(a.id, v)),
                          icon: Icons.article_outlined,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _special() {
    return Column(
      children: [
        _checkRow(
          label: _ru ? 'Может заводить и править людей' : 'Can manage people',
          hint: _ru
              ? 'Сможет добавлять сотрудников и менять им доступы'
              : 'Can add employees and change their access',
          value: _permissions.canManageTeam,
          onChanged: (v) => setState(
              () => _permissions = _permissions.copyWith(canManageTeam: v)),
        ),
        _checkRow(
          label: _ru ? 'Видит показатели других' : 'Sees others\' stats',
          hint: _ru
              ? 'Без этого человек видит только свои цифры'
              : 'Without it a person sees only their own numbers',
          value: _permissions.canSeeOthersStats,
          onChanged: (v) => setState(
              () => _permissions = _permissions.copyWith(canSeeOthersStats: v)),
        ),
        _checkRow(
          label: _ru ? 'Видит скрытые заметки' : 'Sees private notes',
          hint: _ru
              ? 'Заметки в карточках сотрудников'
              : 'Notes inside employee cards',
          value: _permissions.canSeeNotes,
          onChanged: (v) => setState(
              () => _permissions = _permissions.copyWith(canSeeNotes: v)),
        ),
        _checkRow(
          label: _ru ? 'Ставить задачи другим' : 'Assign tasks to others',
          hint: _ru
              ? 'Без этого человек заводит задачи только себе. Доступ к доске '
                  'и право раздавать по ней поручения — разные вещи.'
              : 'Without this the person can only create tasks for themselves.',
          value: _permissions.canAssignTasks,
          onChanged: (v) => setState(
              () => _permissions = _permissions.copyWith(canAssignTasks: v)),
        ),
      ],
    );
  }

  Widget _checkRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? hint,
    IconData? icon,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: value ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(width: 9),
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textPrimary)),
                  if (hint != null) ...[
                    const SizedBox(height: 1),
                    Text(hint,
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarRow() {
    return Row(
      children: [
        WesiAvatar(size: 52, index: _avatarIndex, photo: _photo),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.accent, width: 1.4),
                  ),
                  child: Icon(Icons.add_a_photo_outlined,
                      size: 14, color: AppTheme.accent),
                ),
              ),
              if (_photo != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _photo = null;
                    _photoCleared = true;
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.accentRed, width: 1.4),
                    ),
                    child: Icon(Icons.delete_outline,
                        size: 14, color: AppTheme.accentRed),
                  ),
                ),
              for (var i = 0; i < WesiAvatar.avatarPresets.length; i++)
                GestureDetector(
                  onTap: () => setState(() {
                    _avatarIndex = i;
                    // Пресет отменяет снимок: иначе человек выбирает
                    // градиент, ничего не меняется, и это выглядит поломкой.
                    _photo = null;
                    _photoCleared = true;
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: WesiAvatar.avatarPresets[i].gradient,
                      border: Border.all(
                        color: i == _avatarIndex
                            ? AppTheme.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(_ru ? 'Доступ' : 'Access'),
        HoverButton(
          onTap: _resetPassword,
          padding: const EdgeInsets.symmetric(vertical: 13),
          backgroundColor: AppTheme.surface,
          child: Center(
            child: Text(
              _ru ? 'Выдать новый пароль' : 'Issue a new password',
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        HoverButton(
          onTap: _remove,
          padding: const EdgeInsets.symmetric(vertical: 13),
          backgroundColor: AppTheme.surface,
          child: Center(
            child: Text(
              _ru ? 'Убрать сотрудника' : 'Remove employee',
              style: TextStyle(fontSize: 13, color: AppTheme.accentRed),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppTheme.textMuted),
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          labelStyle: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  Widget _noteField() => TextField(
        controller: _notesCtrl,
        maxLines: 5,
        minLines: 3,
        style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: _ru
              ? 'Ставка, договорённости, всё, что не для чужих глаз'
              : 'Rate, agreements, anything not for other eyes',
          hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.surface.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.glassBorder),
          ),
        ),
      );
}
