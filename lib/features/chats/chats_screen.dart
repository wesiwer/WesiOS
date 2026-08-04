import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';
import 'models/chat_policy.dart';

/// Чаты — заготовка.
///
/// Экран честно помечен как незаконченный: переписки ещё нет, есть каркас
/// под неё. Показывать пустой список с полем ввода, которое ничего не
/// отправляет, было бы хуже — человек решил бы, что сообщение ушло.
///
/// Что здесь уже настоящее: список людей берётся из состава (TeamService),
/// поэтому когда появится сервер, останется подключить передачу сообщений, а
/// не собирать экран заново. Папки — как в Telegram: раскладка по темам, а
/// не по одному признаку.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  int _folder = 0;

  bool get _ru => WesiLocale.isRussian;

  List<String> get _folders => _ru
      ? const ['Все', 'Рабочие', 'Личные', 'Группы']
      : const ['All', 'Work', 'Personal', 'Groups'];

  /// Какому типу переписки соответствует выбранная папка.
  ///
  /// null — папка сборная, одного правила для неё нет, и врать про него
  /// хуже, чем промолчать.
  ChatKind? get _kind => switch (_folder) {
        1 => ChatKind.work,
        2 => ChatKind.personal,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final people = TeamService.all
        .where((e) => e.id != TeamService.current?.id)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: WesiTitle(_ru ? 'Чаты' : 'Chats', size: 22),
                  ),
                ],
              ),
            ),
            // Полоса папок прокручивается: на узком телефоне четыре ярлыка в
            // Row вылезают за край, и последний становится недоступен.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  for (var i = 0; i < _folders.length; i++) ...[
                    GestureDetector(
                      onTap: () => setState(() => _folder = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: i == _folder
                              ? AppTheme.accent.withOpacity(0.16)
                              : AppTheme.surface.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: i == _folder
                                ? AppTheme.accent.withOpacity(0.5)
                                : AppTheme.glassBorder,
                          ),
                        ),
                        child: Text(
                          _folders[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == _folder
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i == _folder
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (_kind != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: Row(
                  children: [
                    Icon(
                      _kind == ChatKind.work
                          ? Icons.badge_outlined
                          : Icons.lock_outline,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ChatEnvelopePolicy.describe(_kind!, russian: _ru),
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.construction,
                        size: 17, color: AppTheme.textMuted),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        _ru
                            ? 'Переписка появится вместе с сервером — '
                                'сообщениям нужно место, общее для всех '
                                'устройств. Здесь пока каркас: папки и список '
                                'людей, с кем можно будет говорить.'
                            : 'Messaging arrives with the server — messages '
                                'need a place shared by all devices. This is '
                                'the frame: folders and the list of people.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _folder == 3
                  ? _groupsPlaceholder()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: people.length,
                      itemBuilder: (context, i) {
                        final e = people[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: AppTheme.glassBorder),
                            ),
                            child: Row(
                              children: [
                                WesiAvatar(size: 38, index: e.avatarIndex, photo: e.photo),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.displayName,
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary)),
                                      const SizedBox(height: 2),
                                      Text(
                                        e.position.isNotEmpty
                                            ? e.position
                                            : (_ru
                                                ? 'Переписка будет здесь'
                                                : 'Chat will live here'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chat_bubble_outline,
                                    size: 16, color: AppTheme.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupsPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 40, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              _ru
                  ? 'Групповые чаты собираются из людей в контактах.\n'
                      'Появятся вместе с сервером.'
                  : 'Group chats are assembled from contacts.\n'
                      'They arrive with the server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
