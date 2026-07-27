import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';

/// Wesi Treasury Dashboard — полноэкранный дашборд с заглушками
/// Показывает расположение всех будущих модулей по ТЗ
class TreasuryDashboardScreen extends StatelessWidget {
  const TreasuryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Sidebar Navigation
          _buildSidebar(),
          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(),
                // Dashboard Grid
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Key Metrics
                        _buildMetricsRow(),
                        const SizedBox(height: 24),
                        // Row 2: Charts
                        _buildChartsRow(),
                        const SizedBox(height: 24),
                        // Row 3: Tables & Lists
                        _buildDataRow(),
                        const SizedBox(height: 24),
                        // Row 4: AI Insights & Alerts
                        _buildInsightsRow(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final items = [
      ('Dashboard', Icons.dashboard, true),
      ('Transactions', Icons.receipt_long, false),
      ('Forecast', Icons.trending_up, false),
      ('Recurring', Icons.repeat, false),
      ('Anomalies', Icons.warning_amber, false),
      ('Reports', Icons.assessment, false),
      ('Settings', Icons.settings, false),
    ];

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppTheme.carbonDark.withOpacity(0.5),
        border: Border(
          right: BorderSide(color: AppTheme.glassBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo
          Row(
            children: [
              const SizedBox(width: 20),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.accentOrange, Color(0xFFFFD700)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Wesi Treasury',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Nav Items
          ...items.map((item) => _buildNavItem(item.$1, item.$2, item.$3)),
          const Spacer(),
          // User mini profile
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.carbonDark, AppTheme.carbonMid],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accentOrange.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.person, size: 16, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User',
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Admin',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(String label, IconData icon, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.accentOrange.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
          ? Border.all(color: AppTheme.accentOrange.withOpacity(0.3))
          : null,
      ),
      child: ListTile(
        leading: Icon(icon, size: 20, color: isActive ? AppTheme.accentOrange : AppTheme.textMuted),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        dense: true,
        onTap: () {},
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(0.9),
        border: Border(bottom: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: Row(
        children: [
          const Text(
            'Dashboard Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          // Search placeholder
          Container(
            width: 280,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                SizedBox(width: 8),
                Text(
                  'Search transactions, reports...',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Notifications placeholder
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_outlined, size: 18, color: AppTheme.textSecondary),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    final metrics = [
      ('Total Balance', '\$47,250.00', '+12.4%', AppTheme.accentGreen, Icons.account_balance_wallet),
      ('Monthly Income', '\$8,420.00', '+5.2%', AppTheme.accentGreen, Icons.arrow_upward),
      ('Monthly Expenses', '\$3,180.00', '-2.1%', AppTheme.accentRed, Icons.arrow_downward),
      ('Net Savings', '\$5,240.00', '+8.7%', AppTheme.accentOrange, Icons.savings),
    ];

    return Row(
      children: metrics.map((m) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.surface.withOpacity(0.6),
                AppTheme.surface.withOpacity(0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(m.$5, size: 16, color: m.$4.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    m.$1,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                m.$2,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: m.$4.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  m.$3,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: m.$4,
                  ),
                ),
              ),
            ],
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildChartsRow() {
    return Row(
      children: [
        // Main Chart placeholder
        Expanded(
          flex: 2,
          child: Container(
            height: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Balance History & Forecast',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        _LegendDot(AppTheme.accentOrange, 'Forecast'),
                        SizedBox(width: 12),
                        _LegendDot(Colors.white, 'History'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppTheme.accentOrange.withOpacity(0.1),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 48,
                            color: AppTheme.accentOrange.withOpacity(0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'P10 / P50 / P90 Forecast Chart',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Monte-Carlo simulation with confidence intervals',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Secondary Chart placeholder
        Expanded(
          child: Container(
            height: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expense Breakdown',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pie_chart_outline,
                          size: 48,
                          color: AppTheme.accentOrange.withOpacity(0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Category Distribution',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataRow() {
    return Row(
      children: [
        // Recent Transactions Table
        Expanded(
          flex: 3,
          child: Container(
            height: 280,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'View All →',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.carbonDark.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('Date', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                      Expanded(flex: 3, child: Text('Description', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text('Category', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                      Expanded(child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Placeholder rows
                ...List.generate(4, (i) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('2026-07-${20 + i}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                      Expanded(flex: 3, child: Text('Transaction ${i + 1}', style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary))),
                      Expanded(flex: 2, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ['Software', 'Marketing', 'Office', 'Salaries'][i],
                          style: const TextStyle(fontSize: 10, color: AppTheme.accentOrange),
                        ),
                      )),
                      Expanded(child: Text(
                        ['+\$2,400', '-\$850', '+\$1,200', '-\$3,000'][i],
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: i % 2 == 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                        ),
                      )),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Quick Actions
        Expanded(
          child: Container(
            height: 280,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildQuickActionBtn('Add Income', Icons.add_circle, AppTheme.accentGreen),
                const SizedBox(height: 8),
                _buildQuickActionBtn('Add Expense', Icons.remove_circle, AppTheme.accentRed),
                const SizedBox(height: 8),
                _buildQuickActionBtn('Set Recurring', Icons.repeat, AppTheme.accentOrange),
                const SizedBox(height: 8),
                _buildQuickActionBtn('Export Report', Icons.download, AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionBtn(String label, IconData icon, Color color) {
    return HoverButton(
      onTap: () {},
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      backgroundColor: AppTheme.surface.withOpacity(0.3),
      hoverColor: color.withOpacity(0.1),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsRow() {
    return Row(
      children: [
        // AI Insights
        Expanded(
          child: Container(
            height: 200,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accentOrange.withOpacity(0.08),
                  AppTheme.surface.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentOrange.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome, size: 18, color: AppTheme.accentOrange),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'AI Insights',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '• Your spending on Software increased by 23% this month',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
                ),
                const Text(
                  '• Projected to reach \$52k by end of quarter (P50)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
                ),
                const Text(
                  '• 2 anomalies detected in recurring payments',
                  style: TextStyle(fontSize: 12, color: AppTheme.accentRed, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Alerts
        Expanded(
          child: Container(
            height: 200,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accentRed.withOpacity(0.05),
                  AppTheme.surface.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentRed.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.notifications_active, size: 18, color: AppTheme.accentRed.withOpacity(0.8)),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Alerts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAlertItem('Unusual expense: Server Repair \$15,000', '2 days ago'),
                const SizedBox(height: 8),
                _buildAlertItem('Recurring payment failed: AWS', '5 days ago'),
                const SizedBox(height: 8),
                _buildAlertItem('Budget threshold reached: Marketing', '1 week ago'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertItem(String message, String time) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppTheme.accentRed.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        Text(
          time,
          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }
}
