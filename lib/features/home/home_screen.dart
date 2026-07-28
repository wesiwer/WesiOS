import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../treasury/treasury_screen.dart';
import '../treasury/widgets/add_transaction_dialog.dart';
import '../treasury/models/transaction_model.dart';
import '../treasury/services/treasury_service.dart';
import '../tasks/tasks_screen.dart';
import '../analytics/analytics_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const _DashboardTab(),
      const TasksScreen(),
      const TreasuryScreen(),
      const AnalyticsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          border: const Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.accentOrange,
          unselectedItemColor: AppTheme.textMuted,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard_outlined),
              label: WesiLocale.get('dashboard'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.task_alt),
              label: WesiLocale.get('tasks'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_balance_wallet),
              label: WesiLocale.get('finances'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.analytics),
              label: WesiLocale.get('analytics'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.more_horiz),
              label: WesiLocale.get('more'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final sym = CurrencyService.symbol;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, kTitleBarHeight + 8, 16, 16),
              child: Row(
                children: [
                  WesiContextMenu(
                    title: 'WesiOS',
                    description: WesiLocale.isRussian
                        ? 'WesiOS — Business Operating System. Управляйте бизнесом по-новому.'
                        : 'WesiOS — Business Operating System. Manage your business in a new way.',
                    purpose: WesiLocale.isRussian
                        ? 'Центральная панель управления всеми системами Wesi'
                        : 'Central dashboard for all Wesi systems',
                    children: const [
                      Text(
                        'WesiOS',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _HoverIconButton(icon: Icons.search, onTap: () {}),
                  const SizedBox(width: 8),
                  _HoverIconButton(
                    icon: Icons.notifications_outlined,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  const _ProfileDropdown(),
                ],
              ),
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
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$sym 0',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _chip(WesiLocale.get('operational'), '$sym 0',
                            AppTheme.accentGreen),
                        const SizedBox(width: 12),
                        _chip(WesiLocale.get('marketing'), '$sym 0',
                            AppTheme.accentOrange),
                        const SizedBox(width: 12),
                        _chip(WesiLocale.get('reserve'), '$sym 0',
                            AppTheme.textSecondary),
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
              child: Row(
                children: [
                  Expanded(
                    child: _Quick(
                      icon: Icons.add_circle,
                      label: WesiLocale.isRussian ? 'Продажа' : 'Sale',
                      onTap: () => _showAddTransaction(context, TransactionType.income),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Quick(
                      icon: Icons.remove_circle,
                      label: WesiLocale.isRussian ? 'Траты' : 'Expense',
                      onTap: () => _showAddTransaction(context, TransactionType.expense),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Quick(
                      icon: Icons.mic,
                      label: WesiLocale.get('wesi_voice_title'),
                      onTap: () => Navigator.pushNamed(context, '/tasks'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Quick(
                      icon: Icons.calculate,
                      label: WesiLocale.get('wesi_calculator_title'),
                      onTap: () => Navigator.pushNamed(context, '/calculator'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }


  Future<void> _showAddTransaction(BuildContext context, TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: type,
        symbol: CurrencyService.symbol,
      ),
    );
    if (result != null) {
      final service = TreasuryService();
      final tx = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: result['title'],
        amount: result['amount'],
        type: type,
        date: DateTime.now(),
        category: result['category'],
        description: result['description'],
        isRecurring: result['isRecurring'] ?? false,
        recurringPeriod: result['recurringPeriod'],
      );
      await service.addTransaction(tx);
      // Refresh dashboard balance
      if (mounted) setState(() {});
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
            const SizedBox(height: 4),
            Text(amount,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _h ? AppTheme.surfaceLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _h
                  ? AppTheme.accentOrange.withOpacity(0.5)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Column(
            children: [
              Icon(widget.icon, color: AppTheme.accentOrange, size: 28),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _h ? AppTheme.textPrimary : AppTheme.textSecondary,
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _h ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.icon,
            color: _h ? AppTheme.accentOrange : AppTheme.textPrimary,
            size: 24,
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
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
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
      if (r != null) Navigator.pushNamed(context, r);
    });
  }

  PopupMenuItem<String> _item(String label, IconData icon, String route) {
    return PopupMenuItem(
      value: route,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _h ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _h
                  ? AppTheme.accentOrange.withOpacity(0.4)
                  : Colors.transparent,
            ),
          ),
          child: const WesiAvatar(size: 32),
        ),
      ),
    );
  }
}
