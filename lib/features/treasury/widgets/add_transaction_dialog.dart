import 'package:flutter/material.dart';
import '../../../core/feedback/wesi_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';
import '../models/transaction_model.dart';
import '../services/category_service.dart';
import 'category_editor_dialog.dart';

/// Public add/edit transaction dialog. Person attribution is optional: money
/// always belongs to an organization, while ownerEmployeeId adds the human
/// dimension when the event can honestly be attributed to someone.
class AddTransactionDialog extends StatefulWidget {
  final TransactionType type;
  final String symbol;
  final TransactionModel? initial;

  const AddTransactionDialog({
    super.key,
    required this.type,
    required this.symbol,
    this.initial,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late String _category;
  bool _isRecurring = false;
  RecurringPeriod? _recurringPeriod;
  DateTime _selectedDate = DateTime.now();
  List<EmployeeModel> _ownerCandidates = const [];
  String? _ownerEmployeeId;

  List<String> get _categories => CategoryService.forType(widget.type);

  @override
  void initState() {
    super.initState();
    final tx = widget.initial;
    if (tx != null) {
      _titleCtrl.text = tx.title;
      _amountCtrl.text = _trimZeros(CurrencyService.fromRub(tx.amount));
      _descCtrl.text = tx.description ?? '';
      _isRecurring = tx.isRecurring;
      _recurringPeriod = tx.recurringPeriod;
      _selectedDate = tx.date;
      _ownerEmployeeId = tx.ownerEmployeeId;
      final cat = tx.category;
      _category =
          (cat != null && _categories.contains(cat)) ? cat : _categories.last;
    } else {
      _category = _categories.last;
      _ownerEmployeeId = TeamService.current?.id;
    }
    _loadOwnerCandidates();
  }

  Future<void> _loadOwnerCandidates() async {
    final current = TeamService.current;
    if (current == null) return;
    final orgId = OrganizationContext.currentOrganizationId;
    final maySeeTeam = current.isOwner ||
        await OrganizationAccessService.canViewTeamFinance(orgId);
    final candidates = <EmployeeModel>[];
    if (!maySeeTeam) {
      candidates.add(current);
    } else {
      for (final employee in TeamService.all) {
        if (employee.isOwner) {
          candidates.add(employee);
          continue;
        }
        final visible = await OrganizationAccessService.visibleOrganizationIds(
          employeeId: employee.id,
        );
        if (visible.contains(orgId)) candidates.add(employee);
      }
    }
    if (_ownerEmployeeId != null &&
        !candidates.any((e) => e.id == _ownerEmployeeId)) {
      final existing = TeamService.byId(_ownerEmployeeId!);
      if (existing != null && maySeeTeam) candidates.add(existing);
    }
    if (mounted) setState(() => _ownerCandidates = candidates);
  }

  static String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.accent,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = DateTime(d.year, d.month, d.day);
    if (picked == today) return WesiLocale.isRussian ? 'Сегодня' : 'Today';
    final diff = picked.difference(today).inDays;
    if (diff == 1) return WesiLocale.isRussian ? 'Завтра' : 'Tomorrow';
    if (diff == -1) return WesiLocale.isRussian ? 'Вчера' : 'Yesterday';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final title = widget.initial != null
        ? WesiLocale.get('edit_operation')
        : isIncome
            ? (WesiLocale.isRussian ? 'Доход' : 'Income')
            : (WesiLocale.isRussian ? 'Трата' : 'Expense');

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: SingleChildScrollView(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: WesiLocale.get('title')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: WesiLocale.get('amount'),
                  prefixText: '${widget.symbol} ',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _categories.contains(_category)
                          ? _category
                          : _categories.last,
                      dropdownColor: AppTheme.surface,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: WesiLocale.get('category')),
                      items: _categories
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppTheme.textPrimary)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _category = v ?? _categories.last),
                    ),
                  ),
                  IconButton(
                    tooltip: WesiLocale.isRussian
                        ? 'Изменить категории'
                        : 'Edit categories',
                    icon: Icon(Icons.tune, size: 18, color: AppTheme.accent),
                    onPressed: () async {
                      await CategoryEditorDialog.show(context, widget.type);
                      if (!mounted) return;
                      setState(() {
                        if (!_categories.contains(_category)) {
                          _category = _categories.last;
                        }
                      });
                    },
                  ),
                ],
              ),
              if (_ownerCandidates.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _ownerEmployeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: WesiLocale.isRussian
                        ? 'Ответственный / чей вклад'
                        : 'Owner / responsible',
                    helperText: WesiLocale.isRussian
                        ? 'Если деньги нельзя честно отнести к человеку — оставь без ответственного.'
                        : 'Leave empty when the money cannot honestly be attributed to a person.',
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(WesiLocale.isRussian
                          ? 'Только организация'
                          : 'Organization only'),
                    ),
                    for (final employee in _ownerCandidates)
                      DropdownMenuItem<String?>(
                        value: employee.id,
                        child: Text(employee.displayName),
                      ),
                  ],
                  onChanged: (v) => setState(() => _ownerEmployeeId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                    labelText: WesiLocale.get('description_optional')),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isRecurring,
                onChanged: (v) => setState(() {
                  _isRecurring = v;
                  _recurringPeriod ??= RecurringPeriod.monthly;
                }),
                title: Text(WesiLocale.isRussian
                    ? 'Регулярная операция'
                    : 'Recurring operation'),
              ),
              if (_isRecurring) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<RecurringPeriod>(
                  value: _recurringPeriod ?? RecurringPeriod.monthly,
                  decoration: InputDecoration(
                    labelText: WesiLocale.isRussian ? 'Период' : 'Period',
                  ),
                  items: const [
                    DropdownMenuItem(value: RecurringPeriod.daily, child: Text('Daily / Ежедневно')),
                    DropdownMenuItem(value: RecurringPeriod.weekly, child: Text('Weekly / Еженедельно')),
                    DropdownMenuItem(value: RecurringPeriod.monthly, child: Text('Monthly / Ежемесячно')),
                    DropdownMenuItem(value: RecurringPeriod.yearly, child: Text('Yearly / Ежегодно')),
                  ],
                  onChanged: (v) => setState(() => _recurringPeriod = v),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: AppTheme.accent),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _formatDate(_selectedDate),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: GestureDetector(
                      onTap: _pickTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.schedule, size: 18, color: AppTheme.accent),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(_selectedDate),
                              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(WesiLocale.get('cancel'),
                          style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  ),
                  Expanded(
                    child: HoverButton(
                      onTap: () {
                        final amount = double.tryParse(
                          _amountCtrl.text.trim().replaceAll(',', '.'),
                        );
                        if (_titleCtrl.text.isNotEmpty && amount != null) {
                          final rub = CurrencyService.toRub(amount);
                          WesiFeedback.success();
                          Navigator.pop(context, {
                            'title': _titleCtrl.text,
                            'amount': rub,
                            'category': _category,
                            'description': _descCtrl.text,
                            'isRecurring': _isRecurring,
                            'recurringPeriod':
                                _isRecurring ? _recurringPeriod : null,
                            'date': _selectedDate,
                            'ownerEmployeeId': _ownerEmployeeId,
                          });
                        }
                      },
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                      child: Center(
                        child: Text(WesiLocale.get('save'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
