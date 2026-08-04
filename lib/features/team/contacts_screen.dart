import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'employee_editor_screen.dart';
import 'models/employee_model.dart';
import 'services/contact_actions.dart';
import 'services/team_service.dart';
import 'team_stats_screen.dart';
import 'widgets/employee_notes_sheet.dart';

/// Контакты — список сотрудников и партнёров.
///
/// Открытая часть карточки (имя, должность, телефон, почта, соцсети) видна
/// всем: список затем и нужен, чтобы люди могли друг с другом связаться.
/// Скрытая часть — заметки — открывается долгим нажатием или правым кликом и
/// только тем, кому владелец это разрешил.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _search = '';

  bool get _ru => WesiLocale.isRussian;
  bool get _canManage => TeamService.currentPermissions.canManageTeam;
  bool get _canSeeNotes => TeamService.currentPermissions.canSeeNotes;

  @override
  void initState() {
    super.initState();
    TeamService.revision.addListener(_refresh);
    // Карточка владельца заводится сама: без неё список пуст даже там, где
    // человек точно есть — он сам.
    TeamService.ensureOwner();
  }

  @override
  void dispose() {
    TeamService.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<EmployeeModel> get _visible {
    final q = _search.trim().toLowerCase();
    final all = TeamService.all;
    if (q.isEmpty) return all;
    return all.where((e) {
      return e.displayName.toLowerCase().contains(q) ||
          e.position.toLowerCase().contains(q) ||
          e.login.contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.phone.contains(q);
    }).toList();
  }

  Future<void> _add() async {
    final created = await EmployeeEditorScreen.open(context);
    if (created != null && mounted) setState(() {});
  }

  Future<void> _edit(EmployeeModel employee) async {
    await EmployeeEditorScreen.open(context, initial: employee);
    if (mounted) setState(() {});
  }

  void _showNotes(EmployeeModel employee) {
    if (!_canSeeNotes) return;
    EmployeeNotesSheet.show(context, employee);
  }

  @override
  Widget build(BuildContext context) {
    final people = _visible;

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
              label: Text(
                _ru ? 'Сотрудник' : 'Employee',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WesiTitle(_ru ? 'Контакты' : 'Contacts', size: 22),
                        const SizedBox(height: 2),
                        Text(
                          people.isEmpty
                              ? (_ru ? 'Пока никого' : 'Nobody yet')
                              : '${people.length} ${_ru ? 'чел.' : 'people'}',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _ru ? 'Показатели' : 'Performance',
                    icon: Icon(Icons.insights_outlined,
                        color: AppTheme.textPrimary),
                    onPressed: () => TeamStatsScreen.open(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                height: 40,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: AppTheme.textMuted),
                    hintText: _ru ? 'Поиск по людям' : 'Search people',
                    hintStyle:
                        TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: people.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: people.length,
                      itemBuilder: (context, i) => _card(people[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 40, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              _search.isNotEmpty
                  ? (_ru ? 'Никого не нашлось' : 'Nobody found')
                  : _canManage
                      ? (_ru
                          ? 'Добавьте первого человека — кнопка внизу.\n'
                              'Логин и пароль система выдаст сама.'
                          : 'Add the first person with the button below.')
                      : (_ru ? 'Список пуст' : 'The list is empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(EmployeeModel e) {
    // Долгое нажатие — для телефона, правый клик — для компьютера. Оба ведут
    // в одно и то же место: скрытые заметки.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _showNotes(e),
        onSecondaryTap: () => _showNotes(e),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: e.isOwner
                  ? AppTheme.accent.withOpacity(0.35)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WesiAvatar(size: 42, index: e.avatarIndex),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.displayName,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary),
                              ),
                            ),
                            if (e.isOwner) ...[
                              const SizedBox(width: 8),
                              _tag(_ru ? 'владелец' : 'owner'),
                            ],
                          ],
                        ),
                        if (e.position.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            e.position,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.accent),
                          ),
                        ],
                        if (e.nickname.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('@${e.nickname}',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  if (_canManage)
                    IconButton(
                      tooltip: _ru ? 'Изменить' : 'Edit',
                      icon: Icon(Icons.tune,
                          size: 18, color: AppTheme.textMuted),
                      onPressed: () => _edit(e),
                    ),
                ],
              ),
              if (e.hasContacts) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (e.phone.trim().isNotEmpty)
                      _chip(
                        icon: Icons.phone,
                        label: e.phone,
                        onTap: () => _tapPhone(e.phone),
                      ),
                    if (e.email.trim().isNotEmpty)
                      _chip(
                        icon: Icons.alternate_email,
                        label: e.email,
                        onTap: () => _tapEmail(e.email),
                      ),
                    for (final entry in e.socials.entries)
                      if (entry.value.trim().isNotEmpty)
                        _chip(
                          icon: Icons.link,
                          label: entry.key,
                          onTap: () => _tapSocial(entry.key, entry.value),
                        ),
                  ],
                ),
              ],
              if (_canSeeNotes && e.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.sticky_note_2_outlined,
                        size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      _ru
                          ? 'Есть заметка — долгое нажатие'
                          : 'Has a note — long press',
                      style:
                          TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent)),
      );

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return HoverButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      backgroundColor: AppTheme.surfaceLight.withOpacity(0.6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _tapPhone(String phone) async {
    final result = await ContactActions.phone(phone);
    if (!mounted) return;
    final text = switch (result) {
      PhoneActionResult.copied =>
        _ru ? 'Номер скопирован' : 'Number copied',
      PhoneActionResult.invalid =>
        _ru ? 'В номере нет цифр' : 'No digits in the number',
      PhoneActionResult.dialed => null,
    };
    if (text != null) _toast(text);
  }

  Future<void> _tapEmail(String email) async {
    final ok = await ContactActions.email(email);
    if (!mounted || ok) return;
    _toast(_ru ? 'Не удалось открыть почту' : 'Could not open mail');
  }

  Future<void> _tapSocial(String network, String value) async {
    final ok = await ContactActions.social(network, value);
    if (!mounted || ok) return;
    _toast(_ru ? 'Ссылка не открылась' : 'Could not open the link');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
