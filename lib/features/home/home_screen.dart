import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_update_card.dart';
import '../../core/widgets/quote_mind_charge.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_clock.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/widgets/wesi_quote_card.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../../widgets/glass_card.dart';
import '../analytics/analytics_screen.dart';
import '../calculator/calculator_screen.dart';
import '../tasks/tasks_screen.dart';
import '../team/models/team_permissions.dart';
import '../team/services/team_service.dart';
import '../treasury/models/transaction_model.dart';
import '../treasury/services/treasury_service.dart';
import '../treasury/treasury_screen.dart';
import '../treasury/widgets/add_transaction_dialog.dart';
import 'more_tab.dart';
import 'widgets/alerts_sheet.dart';
import 'widgets/global_search_sheet.dart';
import 'widgets/home_agenda.dart';
import 'widgets/home_month_calendar.dart';
import 'widgets/home_pulse.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
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

  void _onTabTap(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _built.add(index);
    });
    _fadeCtrl.forward(from: 0);
  }

  List<_TabSpec> get _tabs {
    final permissions = TeamService.currentPermissions;
    return [
      const _TabSpec(
        id: 'home',
        icon: Icons.dashboard_outlined,
        labelKey: 'dashboard',
      ),
      if (permissions.allows(TeamModules.tasks))
        const _TabSpec(
          id: 'tasks',
          icon: Icons.task_alt,
          labelKey: 'tasks',
        ),
      if (permissions.allows(TeamModules.treasury))
        const _TabSpec(
          id: 'treasury',
          icon: Icons.account_balance_wallet,
          labelKey: 'finances',
        ),
      if (permissions.allows(TeamModules.analytics))
        const _TabSpec(
          id: 'analytics',
          icon: Icons.analytics,
          labelKey: 'analytics',
        ),
      const _TabSpec(
        id: 'more',
        icon: Icons.more_horiz,
        labelKey: 'more',
      ),
    ];
  }

  Widget _tab(int index, String language) {
    if (!_built.contains(index)) return const SizedBox.shrink();
    final tabs = _tabs;
    if (index >= tabs.length) return const SizedBox.shrink();
    final key = ValueKey('tab_${tabs[index].id}_$language');
    switch (tabs[index].id) {
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
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: WesiLocale.localeNotifier,
          builder: (context, language, _) =>
              _buildScaffold(context, language),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, String language) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: background,
      body: FadeTransition(
        opacity: _fade,
        child: IndexedStack(
          index: _selectedIndex.clamp(0, _tabs.length - 1),
          children: List.generate(
            _tabs.length,
            (index) => _tab(index, language),
          ),
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
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _breakdown = breakdown;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 10, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: WesiContextMenu(
                          title: 'WesiOS',
                          description: WesiLocale.isRussian
                              ? 'WesiOS — Business Operating System. Управляйте бизнесом по-новому.'
                              : 'WesiOS — Business Operating System. Manage your business in a new way.',
                          purpose: WesiLocale.isRussian
                              ? 'Центральная панель управления всеми системами Wesi'
                              : 'Central dashboard for all Wesi systems',
                          children: const [WesiWordmark(size: 26)],
                        ),
                      ),
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
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: WesiLocale.isRussian
                                  ? 'Открыть календарь · долгий тап — стиль часов'
                                  : 'Open calendar · long-press for clock style',
                              child: GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  '/calendar',
                                ),
                                onLongPress: () {
                                  final next = WesiClock.savedStyle ==
                                          ClockStyle.digital
                                      ? ClockStyle.analog
                                      : ClockStyle.digital;
                                  WesiClock.setStyle(next);
                                  setState(() {});
                                },
                                child: const Align(
                                  alignment: Alignment.centerLeft,
                                  child: WesiClock(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const HomeMonthCalendar(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: QuoteMindCharge(expanded: true),
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    const SizedBox(height: 8),
                    Text(
                      CurrencyService.format(_balance),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _chip(
                          WesiLocale.get('total_income'),
                          CurrencyService.format(_breakdown['income'] ?? 0),
                          AppTheme.accentGreen,
                        ),
                        const SizedBox(width: 12),
                        _chip(
                          WesiLocale.get('total_expenses'),
                          CurrencyService.format(_breakdown['expense'] ?? 0),
                          AppTheme.accentRed,
                        ),
                        const SizedBox(width: 12),
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
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 4 : 2;
                  const gap = 12.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final actions = <Widget>[
                    _Quick(
                      icon: Icons.add_circle,
                      label: WesiLocale.isRussian ? 'Доход' : 'Income',
                      onTap: () => _showAddTransaction(
                        context,
                        TransactionType.income,
                      ),
                    ),
                    _Quick(
                      icon: Icons.remove_circle,
                      label: WesiLocale.isRussian ? 'Траты' : 'Expense',
                      onTap: () => _showAddTransaction(
                        context,
                        TransactionType.expense,
                      ),
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
                        .map((action) => SizedBox(width: width, child: action))
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
    BuildContext context,
    TransactionType type,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: type,
        symbol: CurrencyService.symbol,
      ),
    );
    if (result == null) return;
    final transaction = TransactionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: result['title'],
      amount: result['amount'],
      type: type,
      date: result['date'] as DateTime? ?? DateTime.now(),
      category: result['category'],
      description: result['description'],
      isRecurring: result['isRecurring'] ?? false,
      recurringPeriod: result['recurringPeriod'],
    );
    await _service.addTransaction(transaction);
    await _loadBalance();
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
            const SizedBox(height: 4),
            Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
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

  const _Quick({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_Quick> createState() => _QuickState();
}

class _QuickState extends State<_Quick> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
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
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _active ? AppTheme.surfaceLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? AppTheme.accent
                  : _hovered
                      ? AppTheme.accent.withOpacity(0.5)
                      : AppTheme.glassBorder,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(widget.icon, color: AppTheme.accent, size: 28),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _active
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            widget.icon,
            color: _hovered ? AppTheme.accent : AppTheme.textPrimary,
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
  bool _hovered = false;

  void _menu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _item(WesiLocale.get('profile'), Icons.person_outline, '/profile'),
        _item(WesiLocale.get('settings'), Icons.settings_outlined, '/settings'),
        _item(
          WesiLocale.get('keys_and_tokens'),
          Icons.vpn_key_outlined,
          '/keys',
        ),
        const PopupMenuDivider(),
        _item(WesiLocale.get('about_wesios'), Icons.info_outline, '/founder'),
      ],
    ).then((route) {
      if (route != null) navigator.pushNamed(route);
    });
  }

  PopupMenuItem<String> _item(
    String label,
    IconData icon,
    String route,
  ) {
    return PopupMenuItem(
      value: route,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _menu(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _hovered
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
