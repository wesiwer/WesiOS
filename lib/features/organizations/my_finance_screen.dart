import 'package:flutter/material.dart';

import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
import '../team/services/team_service.dart';
import '../treasury/services/forecast_engine.dart';
import 'services/employee_finance_service.dart';
import 'services/organization_access_service.dart';
import 'services/organization_context.dart';
import 'widgets/organization_switcher.dart';

class MyFinanceScreen extends StatefulWidget {
  const MyFinanceScreen({super.key});

  @override
  State<MyFinanceScreen> createState() => _MyFinanceScreenState();
}

class _MyFinanceScreenState extends State<MyFinanceScreen> {
  EmployeeFinanceView _view = EmployeeFinanceView.self;
  EmployeeFinanceMetrics? _self;
  List<EmployeeFinanceRow> _team = const [];
  ForecastResult _forecast = ForecastResult.empty();
  bool _canTeam = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    OrganizationContext.revision.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    OrganizationContext.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final orgId = OrganizationContext.currentOrganizationId;
    final canTeam = TeamService.current?.isOwner == true ||
        await OrganizationAccessService.canViewTeamFinance(orgId);
    final self = await EmployeeFinanceService.self(periodDays: 30);
    final forecast = await EmployeeFinanceService.selfForecast(days: 30);
    var team = <EmployeeFinanceRow>[];
    if (canTeam && _view != EmployeeFinanceView.self) {
      team = await EmployeeFinanceService.teamBreakdown(
        organizationId: orgId,
        view: _view,
        periodDays: 30,
      );
    }
    if (!mounted) return;
    setState(() {
      _canTeam = canTeam;
      _self = self;
      _forecast = forecast;
      _team = team;
      _loading = false;
      if (!canTeam) _view = EmployeeFinanceView.self;
    });
  }

  String _money(double value) => CurrencyService.format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Мои финансы'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: OrganizationSwitcher(compact: true)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  _viewSelector(),
                  const SizedBox(height: 16),
                  if (_view == EmployeeFinanceView.self)
                    _selfView()
                  else
                    _managerView(),
                ],
              ),
            ),
    );
  }

  Widget _viewSelector() {
    if (!_canTeam) return const SizedBox.shrink();
    return SegmentedButton<EmployeeFinanceView>(
      segments: const [
        ButtonSegment(value: EmployeeFinanceView.self, label: Text('Мои')),
        ButtonSegment(value: EmployeeFinanceView.organization, label: Text('Организация')),
        ButtonSegment(value: EmployeeFinanceView.subtree, label: Text('Ветка')),
      ],
      selected: {_view},
      onSelectionChanged: (value) async {
        setState(() => _view = value.first);
        await _load();
      },
    );
  }

  Widget _selfView() {
    final m = _self;
    if (m == null) return const SizedBox.shrink();
    final forecast30 = _forecast.p50.isEmpty ? null : _forecast.p50.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Мой вклад', _money(m.contribution), Icons.trending_up, AppTheme.accentGreen),
            _metric('Мои расходы', _money(m.expenses), Icons.trending_down, AppTheme.accentRed),
            _metric('Мой net', _money(m.net), Icons.balance_outlined, AppTheme.accent),
            _metric('Регулярные обязательства', _money(m.recurringObligations), Icons.repeat_rounded, AppTheme.textSecondary),
          ],
        ),
        const SizedBox(height: 18),
        _section(
          'Личный прогноз вклада',
          forecast30 == null
              ? 'Недостаточно персональных данных для прогноза.'
              : 'Ожидаемый P50 через 30 дней: ${_money(forecast30)}. Это contribution forecast, а не баланс организации.',
        ),
        const SizedBox(height: 12),
        _section(
          'Ближайшие денежные события',
          m.upcoming.isEmpty
              ? 'На 30 дней персональных событий нет.'
              : m.upcoming.take(6).map((e) => '${e.title}: ${_money(e.amount)}').join('\n'),
        ),
        if (m.overdueEvents > 0) ...[
          const SizedBox(height: 12),
          _section('Просрочки', '${m.overdueEvents} денежных задач требуют внимания.'),
        ],
      ],
    );
  }

  Widget _managerView() {
    final contribution = _team.fold<double>(0, (s, r) => s + r.metrics.contribution);
    final expenses = _team.fold<double>(0, (s, r) => s + r.metrics.expenses);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Вклад команды', _money(contribution), Icons.groups_2_outlined, AppTheme.accentGreen),
            _metric('Расходы команды', _money(expenses), Icons.payments_outlined, AppTheme.accentRed),
            _metric('Net команды', _money(contribution - expenses), Icons.balance_outlined, AppTheme.accent),
          ],
        ),
        const SizedBox(height: 18),
        Text('По сотрудникам',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (_team.isEmpty)
          _section('Нет данных', 'Нет доступных персональных финансовых показателей в выбранном контуре.')
        else
          for (final row in _team)
            Card(
              child: ListTile(
                title: Text(row.employee.displayName),
                subtitle: Text('${row.employee.position}\nВклад ${_money(row.metrics.contribution)} • Расходы ${_money(row.metrics.expenses)}'),
                isThreeLine: true,
                trailing: Text(
                  _money(row.metrics.net),
                  style: TextStyle(
                    color: row.metrics.net >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _section(String title, String body) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.34),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: AppTheme.textSecondary, height: 1.45)),
          ],
        ),
      );
}
