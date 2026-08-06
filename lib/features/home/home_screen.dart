import 'package:flutter/material.dart';
import '../../core/feedback/wesi_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../calculator/calculator_screen.dart';
import '../treasury/treasury_screen.dart';
import '../treasury/widgets/add_transaction_dialog.dart';
import '../treasury/models/transaction_model.dart';
import '../treasury/services/treasury_service.dart';
import '../tasks/tasks_screen.dart';
import 'widgets/home_agenda.dart';
import 'widgets/alerts_sheet.dart';
import 'widgets/global_search_sheet.dart';
import 'widgets/home_pulse.dart';
import '../../core/widgets/app_update_card.dart';
import '../analytics/analytics_screen.dart';
import 'more_tab.dart';
import '../team/models/team_permissions.dart';
import '../team/services/team_service.dart';
import '../../core/widgets/wesi_clock.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/wesi_quote_card.dart';
import '../../core/widgets/quote_mind_charge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  /// Ленивая инициализация вкладок: тяжёлые экраны (Treasury) строятся
  /// только после первого открытия, иначе первый кадр Home лагает.
  final Set<int> _built = {0};

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      value: 1,
    );
    _fade = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onTabTap(int i) {
    if (i == _selectedIndex) return;
    WesiFeedback.select();
    setState(() {
      _selectedIndex = i;
      _built.add(i);
    });
    _fadeCtrl.forward(from: 0);
  }

  /// Вкладки, доступные тому, кто сейчас в приложении.
  ///
  /// Закрытая вкладка не показывается серой и не спрашивает пароль — её нет
  /// вовсе. Человек не должен догадываться о существовании разделов, куда
  /// его не пускали: замок на видном месте это приглашение постучаться.
  ///
  /// «Главная» и «Ещё» есть всегда: без первой некуда попасть после входа,
  /// без второй не добраться до настроек и профиля.
  List<_TabSpec> get _tabs {
    final p = TeamService.currentPermissions;
    return [
      const _TabSpec(id: 'home', icon: Icons.dashboard_outlined, labelKey: 'dashboard'),
      if (p.allows(TeamModules.tasks))
        const _TabSpec(id: 'tasks', icon: Icons.task_alt, labelKey: 'tasks'),
      if (p.allows(TeamModules.treasury))
        const _TabSpec(
            id: 'treasury',
            icon: Icons.account_balance_wallet,
            labelKey: 'finances'),
      if (p.allows(TeamModules.analytics))
        const _TabSpec(
            id: 'analytics', icon: Icons.analytics, labelKey: 'analytics'),
      const _TabSpec(id: 'more', icon: Icons.more_horiz, labelKey: 'more'),
    ];
  }

  Widget _tab(int i, String lang) {
    if (!_built.contains(i)) return const SizedBox.shrink();
    final tabs = _tabs;
    if (i >= tabs.length) return const SizedBox.shrink();
    final key = ValueKey('tab_${tabs[i].id}_$lang');
    switch (tabs[i].id) {
      case 'home':
        return _DashboardTab(key: key);
      case 'tasks':
        return TasksScreen(key: key);
      case 'treasury':
        return TreasuryScreen(key: key);
      case 'analytics':
        return AnalyticsScreen(key: key);
      default:
        return MoreTab(key: key);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем и локаль, и тему: иначе при смене темы Scaffold/вкладки
    // остаются со старыми AppTheme.* цветами до setState (смена вкладки).
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: WesiLocale.localeNotifier,
          builder: (context, lang, _) => _buildScaffold(context, lang),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, String lang) {
    // scaffoldBackgroundColor из Theme — AnimatedTheme плавно интерполирует.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fade,
        child: IndexedStack(
          index: _selectedIndex.clamp(0, _tabs.length - 1),
          children: List.generate(_tabs.length, (i) => _tab(i, lang)),
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          border: Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex.clamp(0, _tabs.length - 1),
          onTap: _onTabTap,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.accent,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: [
            for (final tab in _tabs)
              BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: WesiLocale.get(tab.labelKey),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({super.key});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final TreasuryService _service = TreasuryService();
  double _balance = 0;
  Map<String, double> _breakdown = const {};

  @override
  void initState() {
    super.initState();
    _loadBalance();
    TreasuryService.revision.addListener(_loadBalance);
  }

  @override
  void dispose() {
    TreasuryService.revision.removeListener(_loadBalance);
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final balance = await _service.getCurrentBalance();
    final breakdown = await _service.getBalanceBreakdown();
    if (mounted) {
      setState(() {
        _balance = balance;
        _breakdown = breakdown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Шапка: слева лого, часы и месяц, справа — иконки
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Левая колонка: лого сверху, часы с месяцем под ним
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WesiContextMenu(
                          title: 'WesiOS',
                          description: WesiLocale.isRussian
                              ? 'WesiOS — Business Operating System. Управляйте бизнесом по-новому.'
                              : 'WesiOS — Business Operating System. Manage your business in a new way.',
                          purpose: WesiLocale.isRussian
                              ? 'Центральная панель управления всеми системами Wesi'
                              : 'Central dashboard for all Wesi systems',
                          children: [
                            WesiWordmark(size: 26),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Часы — вход в календарь; долгий тап переключает стиль
                        Tooltip(
                          message: WesiLocale.isRussian
                              ? 'Открыть календарь · долгий тап — стиль часов'
                              : 'Open calendar · long-press for clock style',
                          child: GestureDetector(
                            onTap: () =>
                                Navigator.pushNamed(context, '/calendar'),
                            onLongPress: () {
                              final next =
                                  WesiClock.savedStyle == ClockStyle.digital
                                      ? ClockStyle.analog
                                      : ClockStyle.digital;
                              WesiClock.setStyle(next);
                              setState(() {});
                            },
                            child: const WesiClock(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Справа только иконки, и колонка занимает ровно столько,
                  // сколько им нужно: всё остальное отдано часам с месяцем.
                  // Раньше здесь стоял ещё и заряд мыслей — он забирал
                  // четыре девятых ширины, и календарю рядом с часами
                  // доставалось 72 px, где числа уже не прочитать.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HoverIconButton(
                            icon: Icons.search,
                            onTap: () => GlobalSearchSheet.show(context),
                          ),
                          const SizedBox(width: 6),
                          const AlertsBell(size: 28),
                          const SizedBox(width: 6),
                          const _ProfileDropdown(),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Заряд и цитата — одной ширины и одной колонкой: это про одно и
          // то же, и разная ширина читалась как «блок не доехал». Развилки
          // «широкий экран — в шапку, узкий — под неё» больше нет: на
          // широком заряд всё равно оказывался вдвое уже соседа.
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: QuoteMindCharge(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: WesiQuoteCard(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppUpdateBanner(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      WesiLocale.get('balance_wesi_inc'),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      CurrencyService.format(_balance),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        _chip(
                          WesiLocale.get('total_income'),
                          CurrencyService.format(_breakdown['income'] ?? 0),
                          AppTheme.accentGreen,
                        ),
                        SizedBox(width: 12),
                        _chip(
                          WesiLocale.get('total_expenses'),
                          CurrencyService.format(_breakdown['expense'] ?? 0),
                          AppTheme.accentRed,
                        ),
                        SizedBox(width: 12),
                        _chip(
                          WesiLocale.get('net'),
                          CurrencyService.format(_breakdown['net'] ?? 0),
                          AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 560 ? 4 : 2;
                  const gap = 12.0;
                  final width =
                      (c.maxWidth - gap * (columns - 1)) / columns;
                  final actions = <Widget>[
                    _Quick(
                      icon: Icons.add_circle,
                      label: WesiLocale.isRussian ? 'Доход' : 'Income',
                      onTap: () =>
                          _showAddTransaction(context, TransactionType.income),
                    ),
                    _Quick(
                      icon: Icons.remove_circle,
                      label: WesiLocale.isRussian ? 'Траты' : 'Expense',
                      onTap: () =>
                          _showAddTransaction(context, TransactionType.expense),
                    ),
                    _Quick(
                      icon: Icons.playlist_add_check,
                      label: WesiLocale.isRussian ? 'Задача' : 'Task',
                      onTap: () => Navigator.pushNamed(context, '/tasks'),
                    ),
                    _Quick(
                      icon: Icons.calculate,
                      label: WesiLocale.get('wesi_calculator_title'),
                      onTap: CalculatorOverlay.show,
                    ),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: actions
                        .map((a) => SizedBox(width: width, child: a))
                        .toList(),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: HomePulse(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: HomeAgenda(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Future<void> _showAddTransaction(
      BuildContext context, TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: type,
        symbol: CurrencyService.symbol,
      ),
    );
    if (result != null) {
      final tx = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: result['title'],
        amount: result['amount'],
        type: type,
        // Дата из диалога, а не «сейчас»: в диалоге есть календарь, и раньше
        // выбранное в нём молча выбрасывалось — операция всегда получалась
        // сегодняшней и вставала в начало истории вместо своего места.
        date: result['date'] as DateTime? ?? DateTime.now(),
        category: result['category'],
        description: result['description'],
        isRecurring: result['isRecurring'] ?? false,
        recurringPeriod: result['recurringPeriod'],
      );
      await _service.addTransaction(tx);
      await _loadBalance();
    }
  }

  Widget _chip(String label, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: color)),
            SizedBox(height: 4),
            Text(amount,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Quick(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_Quick> createState() => _QuickState();
}

class _QuickState extends State<_Quick> {
  bool _h = false;
  bool _f = false;

  bool get _active => _h || _f;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _h = v),
      onShowFocusHighlight: (v) => setState(() => _f = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _active ? AppTheme.surfaceLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _f
                  ? AppTheme.accent
                  : _h
                      ? AppTheme.accent.withOpacity(0.5)
                      : AppTheme.glassBorder,
              width: _f ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(widget.icon, color: AppTheme.accent, size: 28),
              SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _active ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HoverIconButton({required this.icon, required this.onTap});

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _h ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            widget.icon,
            color: _h ? AppTheme.accent : AppTheme.textPrimary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _ProfileDropdown extends StatefulWidget {
  const _ProfileDropdown();

  @override
  State<_ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<_ProfileDropdown> {
  bool _h = false;

  void _menu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: pos,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _item(WesiLocale.get('profile'), Icons.person_outline, '/profile'),
        _item(WesiLocale.get('settings'), Icons.settings_outlined, '/settings'),
        _item(
          WesiLocale.get('keys_and_tokens'),
          Icons.vpn_key_outlined,
          '/profile',
        ),
        const PopupMenuDivider(),
        _item(WesiLocale.get('about_wesios'), Icons.info_outline, '/founder'),
      ],
    ).then((r) {
      if (r != null) navigator.pushNamed(r);
    });
  }

  PopupMenuItem<String> _item(String label, IconData icon, String route) {
    return PopupMenuItem(
      value: route,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _menu(context),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _h ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _h
                  ? AppTheme.accent.withOpacity(0.4)
                  : Colors.transparent,
            ),
          ),
          child: const WesiAvatar(size: 36),
        ),
      ),
    );
  }
}


/// Одна вкладка нижней панели.
class _TabSpec {
  final String id;
  final IconData icon;
  final String labelKey;

  const _TabSpec({
    required this.id,
    required this.icon,
    required this.labelKey,
  });
}
