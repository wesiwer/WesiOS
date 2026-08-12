import 'package:flutter/material.dart';

import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
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
  int _periodDays = 30;
  EmployeeFinanceMetrics? _self;
  EmployeeFinanceMetrics? _previousSelf;
  OrganizationFinanceMetrics? _organization;
  List<EmployeeFinanceRow> _team = const [];
  ForecastResult _forecast = ForecastResult.empty();
  bool _canOrganization = false;
  bool _canSubtree = false;
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
    final canOrganization =
        await OrganizationAccessService.canViewOrganizationFinance(orgId);
    final canSubtree = canOrganization &&
        await OrganizationAccessService.canUseSubtreeFinance(orgId);
    final canTeam = await OrganizationAccessService.canViewTeamFinance(orgId);

    var effectiveView = _view;
    if (effectiveView == EmployeeFinanceView.organization && !canOrganization) {
      effectiveView = EmployeeFinanceView.self;
    }
    if (effectiveView == EmployeeFinanceView.subtree && !canSubtree) {
      effectiveView = canOrganization
          ? EmployeeFinanceView.organization
          : EmployeeFinanceView.self;
    }

    final comparison = await EmployeeFinanceService.selfComparison(
      periodDays: _periodDays,
    );
    final self = comparison.current;
    final previousSelf = comparison.previous;
    final forecast = await EmployeeFinanceService.selfForecast(days: 30);
    OrganizationFinanceMetrics? organization;
    var team = <EmployeeFinanceRow>[];
    if (effectiveView != EmployeeFinanceView.self) {
      organization = await EmployeeFinanceService.organizationFinance(
        organizationId: orgId,
        view: effectiveView,
        periodDays: _periodDays,
      );
      if (canTeam) {
        team = await EmployeeFinanceService.teamBreakdown(
          organizationId: orgId,
          view: effectiveView,
          periodDays: _periodDays,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _view = effectiveView;
      _canOrganization = canOrganization;
      _canSubtree = canSubtree;
      _canTeam = canTeam;
      _self = self;
      _previousSelf = previousSelf;
      _organization = organization;
      _forecast = forecast;
      _team = team;
      _loading = false;
    });
  }

  String _money(double value) => CurrencyService.format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Финансовые показатели'),
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
                  _periodSelector(),
                  const SizedBox(height: 12),
                  _viewSelector(),
                  const SizedBox(height: 16),
                  if (_view == EmployeeFinanceView.self)
                    _selfView()
                  else
                    _organizationView(),
                ],
              ),
            ),
    );
  }

  Widget _periodSelector() => Wrap(
        spacing: 8,
        children: [
          for (final days in const [7, 30, 90])
            ChoiceChip(
              label: Text('$days дн.'),
              selected: _periodDays == days,
              onSelected: (_) async {
                if (_periodDays == days) return;
                setState(() => _periodDays = days);
                await _load();
              },
            ),
        ],
      );

  Widget _viewSelector() {
    final segments = <ButtonSegment<EmployeeFinanceView>>[
      const ButtonSegment(
        value: EmployeeFinanceView.self,
        label: Text('Мои'),
        icon: Icon(Icons.person_outline),
      ),
      if (_canOrganization)
        const ButtonSegment(
          value: EmployeeFinanceView.organization,
          label: Text('Организация'),
          icon: Icon(Icons.business_outlined),
        ),
      if (_canSubtree)
        const ButtonSegment(
          value: EmployeeFinanceView.subtree,
          label: Text('Ветка'),
          icon: Icon(Icons.account_tree_outlined),
        ),
    ];
    if (segments.length == 1) return const SizedBox.shrink();
    return SegmentedButton<EmployeeFinanceView>(
      segments: segments,
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
        _section(
          'Личный контур',
          'Этот режим показывает только показатели текущего пользователя в выбранном доступном контуре. Руководящая роль не заменяет личный режим.',
        ),
        const SizedBox(height: 12),
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
          'Динамика к предыдущим $_periodDays дням',
          _comparisonText(m, _previousSelf),
        ),
        const SizedBox(height: 12),
        _section(
          'Личные риски',
          _riskText(m),
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

  Widget _organizationView() {
    final metrics = _organization;
    if (metrics == null) {
      return _section('Нет доступа', 'Финансовый контур организации недоступен.');
    }
    final scopeLabel = _view == EmployeeFinanceView.subtree
        ? 'Ветка: организация + доступные дочерние'
        : 'Только выбранная организация';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          scopeLabel,
          'Агрегированные показатели не раскрывают персональную атрибуцию сотрудников. Личные строки команды требуют отдельного права.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Доходы контура', _money(metrics.income), Icons.trending_up, AppTheme.accentGreen),
            _metric('Расходы контура', _money(metrics.expenses), Icons.trending_down, AppTheme.accentRed),
            _metric('Net контура', _money(metrics.net), Icons.balance_outlined, AppTheme.accent),
            _metric('Регулярные обязательства', _money(metrics.recurringObligations), Icons.repeat_rounded, AppTheme.textSecondary),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'По сотрудникам',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        if (!_canTeam)
          _section(
            'Персональная разбивка скрыта',
            'У тебя есть доступ к агрегатам этого подразделения, но нет отдельного права canViewTeamFinance на чужие личные показатели.',
          )
        else if (_team.isEmpty)
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

  String _delta(double current, double previous) {
    if (previous == 0) {
      if (current == 0) return '0%';
      return current > 0 ? '+новое' : '-новое';
    }
    final value = (current - previous) / previous.abs() * 100;
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(0)}%';
  }

  String _comparisonText(
    EmployeeFinanceMetrics current,
    EmployeeFinanceMetrics? previous,
  ) {
    if (previous == null) return 'Нет базы для сравнения.';
    return 'Вклад ${_delta(current.contribution, previous.contribution)} • '
        'расходы ${_delta(current.expenses, previous.expenses)} • '
        'net ${_delta(current.net, previous.net)}.';
  }

  String _riskText(EmployeeFinanceMetrics metrics) {
    final risks = <String>[];
    if (metrics.overdueEvents > 0) {
      risks.add('просроченные денежные задачи: ${metrics.overdueEvents}');
    }
    if (metrics.missedDealExpectations > 0) {
      risks.add('сделки позже ожидаемой даты: ${metrics.missedDealExpectations}');
    }
    if (metrics.anomalousExpenses > 0) {
      risks.add('аномальные расходы: ${metrics.anomalousExpenses}');
    }
    return risks.isEmpty ? 'Активных персональных финансовых рисков не найдено.' : risks.join(' • ');
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
