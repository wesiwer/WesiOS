import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/transaction_model.dart';
import '../services/category_service.dart';

/// Редактор списка категорий: добавить, переименовать, удалить, сбросить.
///
/// Правит набор ОДНОГО типа операций: у доходов и расходов списки разные,
/// и общий редактор смешивал бы их обратно.
class CategoryEditorDialog extends StatefulWidget {
  final TransactionType type;

  const CategoryEditorDialog({super.key, required this.type});

  static Future<void> show(BuildContext context, TransactionType type) {
    return showDialog<void>(
      context: context,
      builder: (_) => CategoryEditorDialog(type: type),
    );
  }

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  final _newCtrl = TextEditingController();
  late List<String> _items = CategoryService.forType(widget.type);

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  void _reload() =>
      setState(() => _items = CategoryService.forType(widget.type));

  Future<void> _add() async {
    final name = _newCtrl.text.trim();
    if (name.isEmpty) return;
    await CategoryService.add(widget.type, name);
    _newCtrl.clear();
    _reload();
  }

  Future<void> _rename(String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
        title: Text(WesiLocale.isRussian ? 'Переименовать' : 'Rename',
            style: const TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(WesiLocale.get('cancel'),
                style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(WesiLocale.get('save'),
                style: const TextStyle(color: AppTheme.accentOrange)),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await CategoryService.rename(widget.type, current, result);
      _reload();
    }
  }

  Future<void> _remove(String name) async {
    final ok = await CategoryService.remove(widget.type, name);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(WesiLocale.isRussian
              ? 'Нельзя удалить последнюю категорию'
              : 'Cannot delete the last category'),
        ),
      );
      return;
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
              child: Text(ru ? 'Категории' : 'Categories',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                ru
                    ? 'Свой список для текущего языка интерфейса'
                    : 'Your own list for the current interface language',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _items
                    .map((c) => ListTile(
                          dense: true,
                          title: Text(c,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textPrimary)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 17, color: AppTheme.textMuted),
                                onPressed: () => _rename(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 17, color: AppTheme.accentRed),
                                onPressed: () => _remove(c),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1, color: AppTheme.glassBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: ru ? 'Новая категория' : 'New category',
                        hintStyle: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppTheme.accentOrange),
                    onPressed: _add,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await CategoryService.resetToDefaults(widget.type);
                      _reload();
                    },
                    child: Text(ru ? 'Сбросить' : 'Reset',
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ru ? 'Готово' : 'Done',
                        style: const TextStyle(color: AppTheme.accentOrange)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
