import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/wesi_logo.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/widgets/wesi_tooltip.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/localization/wesi_locale.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    _DashboardTab(),
    _TasksTab(),
    _TreasuryTab(),
    _AnalyticsTab(),
    _MoreTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.9),
          border: const Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.accentOrange,
          unselectedItemColor: AppTheme.textMuted,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'Задачи'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Финансы'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Аналитика'),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Ещё'),
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
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, kTitleBarHeight + 8, 16, 16),
              child: Row(
                children: [
                  const WesiLogo(size: 40),
                  const Spacer(),
                  _HoverIconButton(
                    icon: Icons.search,
                    onTap: () {},
                  ),
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
                    const Text('Баланс Wesi Inc', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    const Text('₽ 0', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildSubBalance('Операционный', '₽ 0', AppTheme.accentGreen),
                        const SizedBox(width: 12),
                        _buildSubBalance('Маркетинг', '₽ 0', AppTheme.accentOrange),
                        const SizedBox(width: 12),
                        _buildSubBalance('Резерв', '₽ 0', AppTheme.textSecondary),
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
                    child: WesiTooltip(
                      message: WesiLocale.isRussian ? 'Добавить продажу или доход' : 'Record a sale or income transaction',
                      child: _buildQuickAction(context, Icons.add_circle, 'Sales', '/treasury'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WesiTooltip(
                      message: WesiLocale.isRussian ? 'Зафиксировать расход' : 'Record an expense or outgoing payment',
                      child: _buildQuickAction(context, Icons.remove_circle, 'Expenses', '/treasury'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WesiTooltip(
                      message: WesiLocale.isRussian ? 'Голосовой ввод задачи или заметки' : 'Voice input for tasks and notes',
                      child: _buildQuickAction(context, Icons.mic, 'Voice', '/tasks'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WesiTooltip(
                      message: 'Wesi Калькулятор — быстрые расчёты',
                      child: _buildQuickAction(context, Icons.calculate, 'Калькулятор', '/calculator'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Календарь', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/calendar'),
                          child: const Text('Все', style: TextStyle(color: AppTheme.accentOrange)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCalendarEvent('Сегодня', 'Нет запланированных событий', Icons.event_available),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Задачи', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/tasks'),
                          child: const Text('Все', style: TextStyle(color: AppTheme.accentOrange)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildTaskItem('Нет активных задач', 'Создайте первую задачу', false),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildSubBalance(String label, String amount, Color color) {
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
            Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, IconData icon, String label, String route) {
    return _HoverQuickAction(
      icon: icon,
      label: label,
      onTap: () => Navigator.pushNamed(context, route),
    );
  }

  Widget _buildCalendarEvent(String date, String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentOrange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accentOrange, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskItem(String title, String subtitle, bool isDone) {
    return Row(
      children: [
        Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? AppTheme.accentGreen : AppTheme.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileDropdown extends StatefulWidget {
  @override
  State<_ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<_ProfileDropdown> {
  bool _isHovered = false;

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _buildMenuItem('Профиль', Icons.person_outline, '/profile'),
        _buildMenuItem('Настройки', Icons.settings_outlined, '/settings'),
        _buildMenuItem('Ключи и токены', Icons.vpn_key_outlined, '/profile'),
        const PopupMenuDivider(),
        _buildMenuItem('О WesiOS', Icons.info_outline, '/founder'),
      ],
    ).then((route) {
      if (route != null) {
        Navigator.pushNamed(context, route);
      }
    });
  }

  PopupMenuItem<String> _buildMenuItem(String label, IconData icon, String route) {
    return PopupMenuItem<String>(
      value: route,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showMenu(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? AppTheme.accentOrange.withOpacity(0.4) : Colors.transparent,
              width: 1,
            ),
          ),
          child: AnimatedScale(
            scale: _isHovered ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.carbonDark, AppTheme.carbonMid],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isHovered ? AppTheme.accentOrange : AppTheme.textMuted,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.person,
                size: 16,
                color: _isHovered ? AppTheme.accentOrange : AppTheme.textPrimary,
              ),
            ),
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
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? AppTheme.accentOrange.withOpacity(0.4) : Colors.transparent,
              width: 1,
            ),
          ),
          child: AnimatedScale(
            scale: _isHovered ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              widget.icon,
              color: _isHovered ? AppTheme.accentOrange : AppTheme.textPrimary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverQuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HoverQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HoverQuickAction> createState() => _HoverQuickActionState();
}

class _HoverQuickActionState extends State<_HoverQuickAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.surfaceLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? AppTheme.accentOrange.withOpacity(0.5) : AppTheme.glassBorder,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.accentOrange.withOpacity(0.1),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              AnimatedScale(
                scale: _isHovered ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  widget.icon,
                  color: AppTheme.accentOrange,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _isHovered ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: _isHovered ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Задачи', style: TextStyle(color: AppTheme.textMuted)));
}

class _TreasuryTab extends StatelessWidget {
  const _TreasuryTab();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Финансы', style: TextStyle(color: AppTheme.textMuted)));
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Аналитика', style: TextStyle(color: AppTheme.textMuted)));
}

class _MoreTab extends StatelessWidget {
  const _MoreTab();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Ещё', style: TextStyle(color: AppTheme.textMuted)));
}
