import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/crm_models.dart';
import 'services/crm_service.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  int _tab = 0;
  String _query = '';
  CrmClientStatus? _statusFilter;

  bool get _ru => WesiLocale.isRussian;

  Future<_CrmData> _load() async {
    final clients = await CrmService.clients();
    final deals = await CrmService.deals();
    final interactions = await CrmService.interactions();
    final summary = await CrmService.summary();
    return _CrmData(
      clients: clients,
      deals: deals,
      interactions: interactions,
      summary: summary,
    );
  }

  Future<void> _addClient() async {
    final value = await _ClientEditorSheet.show(context);
    if (value != null) await CrmService.saveClient(value);
  }

  Future<void> _addDeal(_CrmData data) async {
    if (data.clients
        .where((value) => value.status != CrmClientStatus.archived)
        .isEmpty) {
      _message(_ru
          ? 'Сначала добавьте клиента — сделка всегда относится к клиенту.'
          : 'Add a client first — every deal belongs to a client.');
      return;
    }
    final value = await _DealEditorSheet.show(context, data.clients);
    if (value != null) await CrmService.saveDeal(value);
  }

  Future<void> _addInteraction(_CrmData data) async {
    if (data.clients
        .where((value) => value.status != CrmClientStatus.archived)
        .isEmpty) {
      _message(_ru
          ? 'Сначала добавьте клиента.'
          : 'Add a client first.');
      return;
    }
    final value = await _InteractionEditorSheet.show(
      context,
      clients: data.clients,
      deals: data.deals,
    );
    if (value != null) await CrmService.saveInteraction(value);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: CrmService.revision,
        builder: (context, __, ___) => FutureBuilder<_CrmData>(
          future: _load(),
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                backgroundColor: AppTheme.background,
                title: const WesiTitle('CRM', size: 20),
                actions: [
                  if (data != null)
                    PopupMenuButton<String>(
                      tooltip: _ru ? 'Добавить' : 'Add',
                      icon: Icon(Icons.add_circle_outline,
                          color: AppTheme.accent),
                      onSelected: (value) {
                        if (value == 'client') _addClient();
                        if (value == 'deal') _addDeal(data);
                        if (value == 'interaction') _addInteraction(data);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'client',
                          child: _menuRow(Icons.person_add_alt_1,
                              _ru ? 'Новый клиент' : 'New client'),
                        ),
                        PopupMenuItem(
                          value: 'deal',
                          child: _menuRow(Icons.handshake_outlined,
                              _ru ? 'Новая сделка' : 'New deal'),
                        ),
                        PopupMenuItem(
                          value: 'interaction',
                          child: _menuRow(Icons.add_comment_outlined,
                              _ru ? 'Новое касание' : 'New interaction'),
                        ),
                      ],
                    ),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 4),
                ],
              ),
              floatingActionButton: data == null
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: _addClient,
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(_ru ? 'Клиент' : 'Client'),
                    ),
              body: snapshot.connectionState == ConnectionState.waiting &&
                      data == null
                  ? Center(
                      child: CircularProgressIndicator(color: AppTheme.accent))
                  : data == null
                      ? _error(snapshot.error)
                      : Column(
                          children: [
                            _summaryStrip(data.summary),
                            _tabs(),
                            Expanded(
                              child: IndexedStack(
                                index: _tab,
                                children: [
                                  _overview(data),
                                  _pipeline(data),
                                  _clients(data),
                                  _activity(data),
                                ],
                              ),
                            ),
                          ],
                        ),
            );
          },
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text(text),
        ],
      );

  Widget _error(Object? error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '${_ru ? 'Не удалось открыть CRM' : 'Could not open CRM'}\n$error',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );

  Widget _summaryStrip(CrmSummary value) {
    final cards = [
      _Metric(
        icon: Icons.groups_2_outlined,
        label: _ru ? 'Клиенты' : 'Clients',
        value: '${value.clients}',
        detail: _ru
            ? '${value.activeClients} активных'
            : '${value.activeClients} active',
      ),
      _Metric(
        icon: Icons.account_tree_outlined,
        label: _ru ? 'Открытые сделки' : 'Open deals',
        value: '${value.openDeals}',
        detail: _money(value.pipelineAmount),
      ),
      _Metric(
        icon: Icons.auto_graph,
        label: _ru ? 'Взвешенный прогноз' : 'Weighted forecast',
        value: _money(value.weightedPipeline),
        detail: _ru ? 'с учётом вероятности' : 'probability adjusted',
      ),
      _Metric(
        icon: Icons.notifications_active_outlined,
        label: _ru ? 'Просроченные касания' : 'Overdue follow-ups',
        value: '${value.overdueFollowUps}',
        detail: value.overdueFollowUps == 0
            ? (_ru ? 'всё под контролем' : 'all under control')
            : (_ru ? 'требуют внимания' : 'need attention'),
        warning: value.overdueFollowUps > 0,
      ),
    ];

    return SizedBox(
      height: 114,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) => _metricCard(cards[index]),
      ),
    );
  }

  Widget _metricCard(_Metric metric) {
    final color = metric.warning ? AppTheme.accentRed : AppTheme.accent;
    return Container(
      width: 205,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: metric.warning
              ? AppTheme.accentRed.withOpacity(.32)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withOpacity(.12),
            ),
            child: Icon(metric.icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                const SizedBox(height: 2),
                Text(metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                Text(metric.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final values = [
      (_ru ? 'Обзор' : 'Overview', Icons.dashboard_outlined),
      (_ru ? 'Воронка' : 'Pipeline', Icons.view_kanban_outlined),
      (_ru ? 'Клиенты' : 'Clients', Icons.people_alt_outlined),
      (_ru ? 'История' : 'Activity', Icons.history),
    ];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final selected = index == _tab;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _tab = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected
                    ? AppTheme.accent.withOpacity(.15)
                    : AppTheme.surface.withOpacity(.35),
                border: Border.all(
                  color: selected
                      ? AppTheme.accent.withOpacity(.5)
                      : AppTheme.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(values[index].$2,
                      size: 16,
                      color: selected ? AppTheme.accent : AppTheme.textMuted),
                  const SizedBox(width: 7),
                  Text(values[index].$1,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _overview(_CrmData data) {
    final followUps = data.clients
        .where((value) => value.nextContactAt != null &&
            value.status != CrmClientStatus.archived)
        .toList()
      ..sort((a, b) => a.nextContactAt!.compareTo(b.nextContactAt!));
    final recent = data.interactions.take(8).toList();
    final won = data.deals.where((value) => value.stage == DealStage.won).length;
    final lost = data.deals.where((value) => value.stage == DealStage.lost).length;
    final conversion = won + lost == 0 ? 0.0 : won / (won + lost);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final left = _panel(
              title: _ru ? 'Ближайшие касания' : 'Upcoming follow-ups',
              icon: Icons.event_repeat,
              child: followUps.isEmpty
                  ? _emptyBlock(
                      _ru
                          ? 'Нет запланированных повторных контактов'
                          : 'No follow-ups scheduled',
                      Icons.event_available_outlined,
                    )
                  : Column(
                      children: [
                        for (final client in followUps.take(6))
                          _followUpRow(client),
                      ],
                    ),
            );
            final right = _panel(
              title: _ru ? 'Здоровье продаж' : 'Sales health',
              icon: Icons.monitor_heart_outlined,
              child: Column(
                children: [
                  _progressRow(
                    _ru ? 'Конверсия закрытых сделок' : 'Closed-deal conversion',
                    conversion,
                    '${(conversion * 100).round()}%',
                  ),
                  const SizedBox(height: 18),
                  _progressRow(
                    _ru ? 'Активные клиенты' : 'Active clients',
                    data.summary.clients == 0
                        ? 0
                        : data.summary.activeClients / data.summary.clients,
                    '${data.summary.activeClients}/${data.summary.clients}',
                  ),
                  const SizedBox(height: 18),
                  _progressRow(
                    _ru ? 'Выиграно сделок' : 'Deals won',
                    data.deals.isEmpty ? 0 : won / data.deals.length,
                    '$won',
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _miniValue(
                            _ru ? 'Выручка' : 'Won value',
                            _money(data.summary.wonAmount),
                            AppTheme.accentGreen),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniValue(
                            _ru ? 'Потеряно' : 'Lost',
                            '$lost',
                            AppTheme.accentRed),
                      ),
                    ],
                  ),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  Expanded(child: right),
                ],
              );
            }
            return Column(children: [left, const SizedBox(height: 12), right]);
          },
        ),
        const SizedBox(height: 12),
        _panel(
          title: _ru ? 'Последние касания' : 'Recent activity',
          icon: Icons.bolt_outlined,
          trailing: TextButton(
            onPressed: () => setState(() => _tab = 3),
            child: Text(_ru ? 'Вся история' : 'All activity'),
          ),
          child: recent.isEmpty
              ? _emptyBlock(
                  _ru
                      ? 'История появится после первого звонка, письма или заметки'
                      : 'Activity appears after the first call, email, or note',
                  Icons.history_toggle_off,
                )
              : Column(
                  children: [
                    for (final interaction in recent)
                      _interactionRow(interaction, data),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _followUpRow(CrmClient client) {
    final overdue = client.followUpOverdue;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openClient(client),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            _avatar(client),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text(
                    client.company.isEmpty
                        ? (_ru ? 'Без компании' : 'No company')
                        : client.company,
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: (overdue ? AppTheme.accentRed : AppTheme.accent)
                    .withOpacity(.1),
              ),
              child: Text(
                _date(client.nextContactAt!),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: overdue ? AppTheme.accentRed : AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressRow(String label, double value, String end) {
    final progress = value.clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ),
            Text(end,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: AppTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation(AppTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _miniValue(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      );

  Widget _pipeline(_CrmData data) {
    final clients = {for (final value in data.clients) value.id: value};
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final stage in DealStage.values) ...[
              _stageColumn(
                stage,
                data.deals.where((value) => value.stage == stage).toList(),
                clients,
                data,
                constraints.maxHeight,
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stageColumn(
    DealStage stage,
    List<CrmDeal> deals,
    Map<String, CrmClient> clients,
    _CrmData data,
    double maxHeight,
  ) {
    final color = _stageColor(stage);
    final total = deals.fold<double>(0, (sum, value) => sum + value.amount);
    return Container(
      width: 278,
      constraints: BoxConstraints(minHeight: maxHeight - 28),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_stageLabel(stage, _ru),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withOpacity(.12),
                ),
                child: Text('${deals.length}',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_money(total),
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          ),
          const SizedBox(height: 10),
          if (deals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Text(
                _ru ? 'Пока пусто' : 'Nothing here yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            )
          else
            for (final deal in deals)
              _dealCard(deal, clients[deal.clientId], data),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final value = await _DealEditorSheet.show(
                context,
                data.clients,
                initialStage: stage,
              );
              if (value != null) await CrmService.saveDeal(value);
            },
            icon: const Icon(Icons.add, size: 17),
            label: Text(_ru ? 'Добавить сделку' : 'Add deal'),
          ),
        ],
      ),
    );
  }

  Widget _dealCard(CrmDeal deal, CrmClient? client, _CrmData data) {
    final overdue = deal.expectedCloseAt != null &&
        deal.expectedCloseAt!.isBefore(DateTime.now()) &&
        deal.isOpen;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.72),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: overdue
              ? AppTheme.accentRed.withOpacity(.38)
              : AppTheme.glassBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => _editDeal(deal, data.clients),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(deal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary)),
                  ),
                  PopupMenuButton<DealStage>(
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    tooltip: _ru ? 'Переместить' : 'Move',
                    icon: Icon(Icons.more_horiz, color: AppTheme.textMuted),
                    onSelected: (stage) => CrmService.moveDeal(deal.id, stage),
                    itemBuilder: (_) => [
                      for (final stage in DealStage.values)
                        PopupMenuItem(
                          value: stage,
                          enabled: stage != deal.stage,
                          child: Text(_stageLabel(stage, _ru)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                client?.displayName ?? (_ru ? 'Клиент удалён' : 'Client removed'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Text(_money(deal.amount, deal.currency),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary)),
                  ),
                  Text('${deal.probability}%',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent)),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: deal.probability / 100,
                  minHeight: 4,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(_stageColor(deal.stage)),
                ),
              ),
              if (deal.expectedCloseAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 13,
                        color: overdue
                            ? AppTheme.accentRed
                            : AppTheme.textMuted),
                    const SizedBox(width: 5),
                    Text(_date(deal.expectedCloseAt!),
                        style: TextStyle(
                            fontSize: 10,
                            color: overdue
                                ? AppTheme.accentRed
                                : AppTheme.textMuted)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _clients(_CrmData data) {
    final filtered = data.clients.where((client) {
      if (_statusFilter != null && client.status != _statusFilter) return false;
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return [
        client.name,
        client.company,
        client.phone,
        client.email,
        client.tags.join(' '),
      ].join(' ').toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: _ru
                  ? 'Поиск по имени, компании, телефону, тегам…'
                  : 'Search name, company, phone, tags…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: AppTheme.surface.withOpacity(.48),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip(null, _ru ? 'Все' : 'All'),
              for (final status in CrmClientStatus.values) ...[
                const SizedBox(width: 7),
                _filterChip(status, _clientStatusLabel(status, _ru)),
              ],
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyBlock(
                  _ru ? 'Клиенты не найдены' : 'No clients found',
                  Icons.person_search_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (_, index) =>
                      _clientCard(filtered[index], data),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(CrmClientStatus? value, String label) {
    final selected = _statusFilter == value;
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = value),
      label: Text(label),
      selectedColor: AppTheme.accent.withOpacity(.15),
      checkmarkColor: AppTheme.accent,
      side: BorderSide(
          color: selected ? AppTheme.accent : AppTheme.glassBorder),
      labelStyle: TextStyle(
        fontSize: 11,
        color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
      ),
    );
  }

  Widget _clientCard(CrmClient client, _CrmData data) {
    final deals = data.deals.where((value) => value.clientId == client.id);
    final open = deals.where((value) => value.isOpen).length;
    final amount = deals
        .where((value) => value.isOpen)
        .fold<double>(0, (sum, value) => sum + value.amount);
    final statusColor = _clientStatusColor(client.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openClient(client),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.48),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: client.followUpOverdue
                  ? AppTheme.accentRed.withOpacity(.34)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Row(
            children: [
              _avatar(client, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(client.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary)),
                        ),
                        const SizedBox(width: 7),
                        _statusBadge(
                            _clientStatusLabel(client.status, _ru), statusColor),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.company.isEmpty
                          ? (_ru ? 'Частный клиент' : 'Individual client')
                          : client.company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 5,
                      children: [
                        _tiny(Icons.handshake_outlined,
                            _ru ? '$open открытых' : '$open open'),
                        _tiny(Icons.payments_outlined, _money(amount)),
                        if (client.nextContactAt != null)
                          _tiny(
                            Icons.event_repeat,
                            _date(client.nextContactAt!),
                            color: client.followUpOverdue
                                ? AppTheme.accentRed
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activity(_CrmData data) {
    if (data.interactions.isEmpty) {
      return _emptyBlock(
        _ru
            ? 'Добавьте звонок, письмо, встречу или заметку — вся история отношений будет здесь'
            : 'Add a call, email, meeting, or note — the full relationship history appears here',
        Icons.forum_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: data.interactions.length,
      itemBuilder: (_, index) => _interactionTimeline(
          data.interactions[index], data, index == data.interactions.length - 1),
    );
  }

  Widget _interactionTimeline(
      CrmInteraction interaction, _CrmData data, bool last) {
    final client = data.clientById(interaction.clientId);
    final color = _interactionColor(interaction.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(.13),
                  border: Border.all(color: color.withOpacity(.42)),
                ),
                child: Icon(_interactionIcon(interaction.kind),
                    size: 14, color: color),
              ),
              if (!last)
                Container(
                  width: 1,
                  height: 86,
                  color: AppTheme.glassBorder,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: client == null ? null : () => _openClient(client),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(.43),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(interaction.title,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary)),
                        ),
                        Text(_dateTime(interaction.at),
                            style: TextStyle(
                                fontSize: 9.5, color: AppTheme.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${client?.displayName ?? (_ru ? 'Клиент удалён' : 'Client removed')} · ${_interactionLabel(interaction.kind, _ru)}',
                      style:
                          TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                    ),
                    if (interaction.details.trim().isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(interaction.details,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: AppTheme.textSecondary)),
                    ],
                    if (interaction.nextActionAt != null) ...[
                      const SizedBox(height: 8),
                      _tiny(Icons.next_plan_outlined,
                          '${_ru ? 'Следующий шаг' : 'Next action'}: ${_date(interaction.nextActionAt!)}',
                          color: AppTheme.accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _interactionRow(CrmInteraction interaction, _CrmData data) {
    final client = data.clientById(interaction.clientId);
    final color = _interactionColor(interaction.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: client == null ? null : () => _openClient(client),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: color.withOpacity(.12),
              ),
              child: Icon(_interactionIcon(interaction.kind),
                  size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(interaction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text(client?.displayName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Text(_date(interaction.at),
                style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.46),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _emptyBlock(String text, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: AppTheme.textMuted.withOpacity(.62)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppTheme.textMuted)),
            ],
          ),
        ),
      );

  Widget _avatar(CrmClient client, {double size = 36}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withOpacity(.85),
              AppTheme.accent.withOpacity(.38),
            ],
          ),
        ),
        child: Text(client.initials,
            style: TextStyle(
                fontSize: size * .3,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      );

  Widget _statusBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withOpacity(.12),
          border: Border.all(color: color.withOpacity(.25)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  Widget _tiny(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 9.8, color: color ?? AppTheme.textMuted)),
        ],
      );

  Future<void> _openClient(CrmClient client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CrmClientDetailScreen(clientId: client.id)),
    );
  }

  Future<void> _editDeal(CrmDeal deal, List<CrmClient> clients) async {
    final value = await _DealEditorSheet.show(context, clients, existing: deal);
    if (value != null) await CrmService.saveDeal(value);
  }

  String _money(double value, [String currency = 'RUB']) {
    final symbol = switch (currency.toUpperCase()) {
      'USD' => r'$',
      'EUR' => '€',
      _ => '₽',
    };
    return NumberFormat.currency(
      locale: _ru ? 'ru_RU' : 'en_US',
      symbol: symbol,
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }

  String _date(DateTime value) =>
      DateFormat(_ru ? 'dd.MM.yyyy' : 'MMM d, yyyy').format(value.toLocal());

  String _dateTime(DateTime value) => DateFormat(
        _ru ? 'dd.MM.yy HH:mm' : 'MMM d, HH:mm',
      ).format(value.toLocal());
}

class CrmClientDetailScreen extends StatefulWidget {
  final String clientId;
  const CrmClientDetailScreen({super.key, required this.clientId});

  @override
  State<CrmClientDetailScreen> createState() => _CrmClientDetailScreenState();
}

class _CrmClientDetailScreenState extends State<CrmClientDetailScreen> {
  bool get _ru => WesiLocale.isRussian;

  Future<_ClientDetailData?> _load() async {
    final clients = await CrmService.clients();
    CrmClient? client;
    for (final value in clients) {
      if (value.id == widget.clientId) client = value;
    }
    if (client == null) return null;
    return _ClientDetailData(
      client: client,
      deals: await CrmService.dealsForClient(client.id),
      interactions: await CrmService.interactionsForClient(client.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CrmService.revision,
      builder: (context, _, __) => FutureBuilder<_ClientDetailData?>(
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
              backgroundColor: AppTheme.background,
              title: WesiTitle(_ru ? 'Карточка клиента' : 'Client card', size: 18),
              actions: [
                if (data != null)
                  IconButton(
                    tooltip: _ru ? 'Редактировать' : 'Edit',
                    onPressed: () async {
                      final edited = await _ClientEditorSheet.show(
                        context,
                        existing: data.client,
                      );
                      if (edited != null) await CrmService.saveClient(edited);
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                SizedBox(width: kHasCustomTitleBar ? 140 : 4),
              ],
            ),
            body: data == null
                ? snapshot.connectionState == ConnectionState.waiting
                    ? Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent))
                    : Center(
                        child: Text(_ru ? 'Клиент не найден' : 'Client not found'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                    children: [
                      _hero(data),
                      const SizedBox(height: 12),
                      _contacts(data.client),
                      const SizedBox(height: 12),
                      _notes(data.client),
                      const SizedBox(height: 12),
                      _deals(data),
                      const SizedBox(height: 12),
                      _history(data),
                    ],
                  ),
            floatingActionButton: data == null
                ? null
                : FloatingActionButton.extended(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    onPressed: () => _addInteraction(data),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(_ru ? 'Касание' : 'Interaction'),
                  ),
          );
        },
      ),
    );
  }

  Widget _hero(_ClientDetailData data) {
    final open = data.deals.where((value) => value.isOpen).toList();
    final amount = open.fold<double>(0, (sum, value) => sum + value.amount);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withOpacity(.18),
            AppTheme.surface.withOpacity(.58),
          ],
        ),
        border: Border.all(color: AppTheme.accent.withOpacity(.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: AppTheme.accent.withOpacity(.88),
                ),
                child: Text(data.client.initials,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.client.name,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      data.client.company.isEmpty
                          ? (_ru ? 'Частный клиент' : 'Individual client')
                          : data.client.company,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 7),
                    _statusBadge(
                      _clientStatusLabel(data.client.status, _ru),
                      _clientStatusColor(data.client.status),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _stat(_ru ? 'Сделки' : 'Deals', '${data.deals.length}')),
              const SizedBox(width: 8),
              Expanded(child: _stat(_ru ? 'Открыто' : 'Open', '${open.length}')),
              const SizedBox(width: 8),
              Expanded(child: _stat(_ru ? 'Воронка' : 'Pipeline', _money(amount))),
            ],
          ),
          if (data.client.nextContactAt != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: (data.client.followUpOverdue
                        ? AppTheme.accentRed
                        : AppTheme.accent)
                    .withOpacity(.1),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_repeat,
                      size: 17,
                      color: data.client.followUpOverdue
                          ? AppTheme.accentRed
                          : AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_ru ? 'Следующий контакт' : 'Next contact'}: ${_date(data.client.nextContactAt!)}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: data.client.followUpOverdue
                              ? AppTheme.accentRed
                              : AppTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contacts(CrmClient client) => _section(
        _ru ? 'Контактные данные' : 'Contact details',
        Icons.contact_page_outlined,
        Column(
          children: [
            _contact(Icons.phone_outlined, _ru ? 'Телефон' : 'Phone', client.phone),
            _contact(Icons.email_outlined, 'Email', client.email),
            _contact(Icons.language, _ru ? 'Сайт' : 'Website', client.website),
            _contact(Icons.location_on_outlined, _ru ? 'Адрес' : 'Address', client.address),
            _contact(Icons.campaign_outlined, _ru ? 'Источник' : 'Source', client.source),
            _contact(Icons.person_outline, _ru ? 'Ответственный' : 'Owner', client.owner),
            if (client.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in client.tags)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(tag, style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _notes(CrmClient client) => _section(
        _ru ? 'Приватные заметки' : 'Private notes',
        Icons.sticky_note_2_outlined,
        Text(
          client.notes.trim().isEmpty
              ? (_ru ? 'Заметок пока нет' : 'No notes yet')
              : client.notes,
          style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: client.notes.trim().isEmpty
                  ? AppTheme.textMuted
                  : AppTheme.textSecondary),
        ),
      );

  Widget _deals(_ClientDetailData data) => _section(
        _ru ? 'Сделки' : 'Deals',
        Icons.handshake_outlined,
        Column(
          children: [
            if (data.deals.isEmpty)
              _empty(_ru ? 'Сделок пока нет' : 'No deals yet')
            else
              for (final deal in data.deals)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: _stageColor(deal.stage).withOpacity(.12),
                    ),
                    child: Icon(Icons.payments_outlined,
                        size: 18, color: _stageColor(deal.stage)),
                  ),
                  title: Text(deal.title,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  subtitle: Text(
                    '${_stageLabel(deal.stage, _ru)} · ${deal.probability}%',
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  ),
                  trailing: Text(_money(deal.amount, deal.currency),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                  onTap: () async {
                    final edited = await _DealEditorSheet.show(
                      context,
                      [data.client],
                      existing: deal,
                    );
                    if (edited != null) await CrmService.saveDeal(edited);
                  },
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final deal = await _DealEditorSheet.show(
                    context,
                    [data.client],
                    initialClientId: data.client.id,
                  );
                  if (deal != null) await CrmService.saveDeal(deal);
                },
                icon: const Icon(Icons.add),
                label: Text(_ru ? 'Добавить сделку' : 'Add deal'),
              ),
            ),
          ],
        ),
      );

  Widget _history(_ClientDetailData data) => _section(
        _ru ? 'История отношений' : 'Relationship history',
        Icons.history,
        Column(
          children: [
            if (data.interactions.isEmpty)
              _empty(_ru ? 'Касаний пока нет' : 'No interactions yet')
            else
              for (final item in data.interactions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: _interactionColor(item.kind).withOpacity(.12),
                    ),
                    child: Icon(_interactionIcon(item.kind),
                        size: 18, color: _interactionColor(item.kind)),
                  ),
                  title: Text(item.title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  subtitle: Text(
                    '${_interactionLabel(item.kind, _ru)} · ${_dateTime(item.at)}${item.details.isEmpty ? '' : '\n${item.details}'}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        color: AppTheme.textMuted),
                  ),
                ),
          ],
        ),
      );

  Future<void> _addInteraction(_ClientDetailData data) async {
    final value = await _InteractionEditorSheet.show(
      context,
      clients: [data.client],
      deals: data.deals,
      initialClientId: data.client.id,
    );
    if (value != null) await CrmService.saveInteraction(value);
  }

  Widget _section(String title, IconData icon, Widget child) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.46),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _contact(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 9),
          SizedBox(
            width: 94,
            child: Text(label,
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
          ],
        ),
      );

  Widget _statusBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withOpacity(.12),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(text,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ),
      );

  String _money(double value, [String currency = 'RUB']) {
    final symbol = currency == 'USD' ? r'$' : currency == 'EUR' ? '€' : '₽';
    return NumberFormat.currency(
      locale: _ru ? 'ru_RU' : 'en_US',
      symbol: symbol,
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }

  String _date(DateTime value) =>
      DateFormat(_ru ? 'dd.MM.yyyy' : 'MMM d, yyyy').format(value.toLocal());
  String _dateTime(DateTime value) =>
      DateFormat(_ru ? 'dd.MM.yy HH:mm' : 'MMM d, HH:mm').format(value.toLocal());
}

class _ClientEditorSheet extends StatefulWidget {
  final CrmClient? existing;
  const _ClientEditorSheet({this.existing});

  static Future<CrmClient?> show(
    BuildContext context, {
    CrmClient? existing,
  }) =>
      showModalBottomSheet<CrmClient>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ClientEditorSheet(existing: existing),
      );

  @override
  State<_ClientEditorSheet> createState() => _ClientEditorSheetState();
}

class _ClientEditorSheetState extends State<_ClientEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _website;
  late final TextEditingController _address;
  late final TextEditingController _source;
  late final TextEditingController _owner;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  late CrmClientStatus _status;
  DateTime? _nextContact;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _name = TextEditingController(text: value?.name ?? '');
    _company = TextEditingController(text: value?.company ?? '');
    _phone = TextEditingController(text: value?.phone ?? '');
    _email = TextEditingController(text: value?.email ?? '');
    _website = TextEditingController(text: value?.website ?? '');
    _address = TextEditingController(text: value?.address ?? '');
    _source = TextEditingController(text: value?.source ?? '');
    _owner = TextEditingController(text: value?.owner ?? '');
    _notes = TextEditingController(text: value?.notes ?? '');
    _tags = TextEditingController(text: value?.tags.join(', ') ?? '');
    _status = value?.status ?? CrmClientStatus.lead;
    _nextContact = value?.nextContactAt;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _company,
      _phone,
      _email,
      _website,
      _address,
      _source,
      _owner,
      _notes,
      _tags,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      context,
      title: widget.existing == null
          ? (_ru ? 'Новый клиент' : 'New client')
          : (_ru ? 'Редактировать клиента' : 'Edit client'),
      child: Form(
        key: _form,
        child: Column(
          children: [
            _field(_name, _ru ? 'Имя или контактное лицо' : 'Name or contact',
                required: true),
            _field(_company, _ru ? 'Компания' : 'Company'),
            Row(
              children: [
                Expanded(child: _field(_phone, _ru ? 'Телефон' : 'Phone')),
                const SizedBox(width: 10),
                Expanded(child: _field(_email, 'Email')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field(_website, _ru ? 'Сайт' : 'Website')),
                const SizedBox(width: 10),
                Expanded(child: _field(_source, _ru ? 'Источник' : 'Source')),
              ],
            ),
            _field(_address, _ru ? 'Адрес' : 'Address'),
            _field(_owner, _ru ? 'Ответственный' : 'Owner'),
            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),
            DropdownButtonFormField<CrmClientStatus>(
              value: _status,
              decoration: _decoration(_ru ? 'Статус' : 'Status'),
              items: [
                for (final value in CrmClientStatus.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_clientStatusLabel(value, _ru)),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: 10),
            _datePicker(
              context,
              label: _ru ? 'Следующий контакт' : 'Next contact',
              value: _nextContact,
              onChanged: (value) => setState(() => _nextContact = value),
            ),
            const SizedBox(height: 10),
            _field(_notes, _ru ? 'Приватные заметки' : 'Private notes',
                lines: 4),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_ru ? 'Сохранить клиента' : 'Save client'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final existing = widget.existing;
    Navigator.pop(
      context,
      CrmClient(
        id: existing?.id ?? CrmService.newId('client'),
        name: _name.text.trim(),
        company: _company.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        website: _website.text.trim(),
        address: _address.text.trim(),
        source: _source.text.trim(),
        owner: _owner.text.trim(),
        notes: _notes.text.trim(),
        status: _status,
        tags: _tags.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        nextContactAt: _nextContact,
      ),
    );
  }
}

class _DealEditorSheet extends StatefulWidget {
  final List<CrmClient> clients;
  final CrmDeal? existing;
  final DealStage? initialStage;
  final String? initialClientId;

  const _DealEditorSheet({
    required this.clients,
    this.existing,
    this.initialStage,
    this.initialClientId,
  });

  static Future<CrmDeal?> show(
    BuildContext context,
    List<CrmClient> clients, {
    CrmDeal? existing,
    DealStage? initialStage,
    String? initialClientId,
  }) =>
      showModalBottomSheet<CrmDeal>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DealEditorSheet(
          clients: clients,
          existing: existing,
          initialStage: initialStage,
          initialClientId: initialClientId,
        ),
      );

  @override
  State<_DealEditorSheet> createState() => _DealEditorSheetState();
}

class _DealEditorSheetState extends State<_DealEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late final TextEditingController _transaction;
  late final TextEditingController _tags;
  late String _clientId;
  late String _currency;
  late DealStage _stage;
  late double _probability;
  DateTime? _expectedClose;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    final active = widget.clients
        .where((client) => client.status != CrmClientStatus.archived)
        .toList();
    final available = active.isEmpty ? widget.clients : active;
    _clientId = value?.clientId ??
        widget.initialClientId ??
        (available.isEmpty ? '' : available.first.id);
    _title = TextEditingController(text: value?.title ?? '');
    _amount = TextEditingController(
        text: value == null || value.amount == 0 ? '' : '${value.amount}');
    _notes = TextEditingController(text: value?.notes ?? '');
    _transaction = TextEditingController(text: value?.transactionId ?? '');
    _tags = TextEditingController(text: value?.tags.join(', ') ?? '');
    _currency = value?.currency ?? 'RUB';
    _stage = value?.stage ?? widget.initialStage ?? DealStage.newLead;
    _probability = (value?.probability ?? _defaultProbability(_stage)).toDouble();
    _expectedClose = value?.expectedCloseAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    _transaction.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      context,
      title: widget.existing == null
          ? (_ru ? 'Новая сделка' : 'New deal')
          : (_ru ? 'Редактировать сделку' : 'Edit deal'),
      child: Form(
        key: _form,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _clientId.isEmpty ? null : _clientId,
              decoration: _decoration(_ru ? 'Клиент' : 'Client'),
              items: [
                for (final client in widget.clients)
                  DropdownMenuItem(
                    value: client.id,
                    child: Text(client.displayName,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (value) => value == null || value.isEmpty
                  ? (_ru ? 'Выберите клиента' : 'Choose a client')
                  : null,
              onChanged: (value) => setState(() => _clientId = value!),
            ),
            const SizedBox(height: 10),
            _field(_title, _ru ? 'Название сделки' : 'Deal title',
                required: true),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field(
                    _amount,
                    _ru ? 'Сумма' : 'Amount',
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: _decoration(_ru ? 'Валюта' : 'Currency'),
                    items: const [
                      DropdownMenuItem(value: 'RUB', child: Text('RUB')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                    ],
                    onChanged: (value) => setState(() => _currency = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<DealStage>(
              value: _stage,
              decoration: _decoration(_ru ? 'Этап воронки' : 'Pipeline stage'),
              items: [
                for (final value in DealStage.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_stageLabel(value, _ru)),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _stage = value!;
                  _probability = _defaultProbability(value).toDouble();
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(_ru ? 'Вероятность' : 'Probability',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Text('${_probability.round()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppTheme.accent)),
              ],
            ),
            Slider(
              value: _probability,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (value) => setState(() => _probability = value),
            ),
            _datePicker(
              context,
              label: _ru ? 'Плановая дата закрытия' : 'Expected close date',
              value: _expectedClose,
              onChanged: (value) => setState(() => _expectedClose = value),
            ),
            const SizedBox(height: 10),
            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),
            _field(_transaction,
                _ru ? 'ID операции Treasury (необязательно)' : 'Treasury transaction ID (optional)'),
            _field(_notes, _ru ? 'Условия и заметки' : 'Terms and notes',
                lines: 4),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.existing != null)
                  IconButton.filledTonal(
                    tooltip: _ru ? 'Удалить' : 'Delete',
                    onPressed: () async {
                      await CrmService.deleteDeal(widget.existing!.id);
                      if (mounted) Navigator.pop(context);
                    },
                    icon: Icon(Icons.delete_outline, color: AppTheme.accentRed),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_ru ? 'Сохранить сделку' : 'Save deal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final amount = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    final now = DateTime.now();
    final existing = widget.existing;
    Navigator.pop(
      context,
      CrmDeal(
        id: existing?.id ?? CrmService.newId('deal'),
        clientId: _clientId,
        title: _title.text.trim(),
        amount: amount,
        currency: _currency,
        stage: _stage,
        probability: _probability.round(),
        notes: _notes.text.trim(),
        transactionId: _transaction.text.trim(),
        tags: _tags.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        expectedCloseAt: _expectedClose,
        closedAt: existing?.closedAt,
      ),
    );
  }
}

class _InteractionEditorSheet extends StatefulWidget {
  final List<CrmClient> clients;
  final List<CrmDeal> deals;
  final String? initialClientId;

  const _InteractionEditorSheet({
    required this.clients,
    required this.deals,
    this.initialClientId,
  });

  static Future<CrmInteraction?> show(
    BuildContext context, {
    required List<CrmClient> clients,
    required List<CrmDeal> deals,
    String? initialClientId,
  }) =>
      showModalBottomSheet<CrmInteraction>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _InteractionEditorSheet(
          clients: clients,
          deals: deals,
          initialClientId: initialClientId,
        ),
      );

  @override
  State<_InteractionEditorSheet> createState() =>
      _InteractionEditorSheetState();
}

class _InteractionEditorSheetState extends State<_InteractionEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _details;
  late final TextEditingController _author;
  late String _clientId;
  String? _dealId;
  InteractionKind _kind = InteractionKind.note;
  DateTime _at = DateTime.now();
  DateTime? _nextAction;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _details = TextEditingController();
    _author = TextEditingController();
    _clientId = widget.initialClientId ??
        (widget.clients.isEmpty ? '' : widget.clients.first.id);
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deals = widget.deals
        .where((value) => value.clientId == _clientId)
        .toList();
    if (_dealId != null && !deals.any((value) => value.id == _dealId)) {
      _dealId = null;
    }
    return _sheet(
      context,
      title: _ru ? 'Новое касание' : 'New interaction',
      child: Form(
        key: _form,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _clientId.isEmpty ? null : _clientId,
              decoration: _decoration(_ru ? 'Клиент' : 'Client'),
              items: [
                for (final client in widget.clients)
                  DropdownMenuItem(
                      value: client.id, child: Text(client.displayName)),
              ],
              validator: (value) => value == null || value.isEmpty
                  ? (_ru ? 'Выберите клиента' : 'Choose a client')
                  : null,
              onChanged: (value) => setState(() {
                _clientId = value!;
                _dealId = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<InteractionKind>(
              value: _kind,
              decoration: _decoration(_ru ? 'Тип касания' : 'Interaction type'),
              items: [
                for (final value in InteractionKind.values)
                  DropdownMenuItem(
                    value: value,
                    child: Row(
                      children: [
                        Icon(_interactionIcon(value), size: 17),
                        const SizedBox(width: 8),
                        Text(_interactionLabel(value, _ru)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 10),
            if (deals.isNotEmpty)
              DropdownButtonFormField<String?>(
                value: _dealId,
                decoration: _decoration(_ru ? 'Связанная сделка' : 'Related deal'),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(_ru ? 'Без сделки' : 'No deal'),
                  ),
                  for (final deal in deals)
                    DropdownMenuItem<String?>(
                        value: deal.id, child: Text(deal.title)),
                ],
                onChanged: (value) => setState(() => _dealId = value),
              ),
            if (deals.isNotEmpty) const SizedBox(height: 10),
            _field(_title, _ru ? 'Краткий итог' : 'Summary', required: true),
            _field(_details, _ru ? 'Подробности' : 'Details', lines: 4),
            _field(_author, _ru ? 'Кто общался' : 'Handled by'),
            _dateTimePicker(
              context,
              label: _ru ? 'Дата и время' : 'Date and time',
              value: _at,
              onChanged: (value) => setState(() => _at = value),
            ),
            const SizedBox(height: 10),
            _datePicker(
              context,
              label: _ru ? 'Следующий шаг' : 'Next action',
              value: _nextAction,
              onChanged: (value) => setState(() => _nextAction = value),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_ru ? 'Сохранить касание' : 'Save interaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      CrmInteraction(
        id: CrmService.newId('interaction'),
        clientId: _clientId,
        dealId: _dealId,
        kind: _kind,
        title: _title.text.trim(),
        details: _details.text.trim(),
        author: _author.text.trim(),
        at: _at,
        nextActionAt: _nextAction,
      ),
    );
  }
}

class _CrmData {
  final List<CrmClient> clients;
  final List<CrmDeal> deals;
  final List<CrmInteraction> interactions;
  final CrmSummary summary;

  const _CrmData({
    required this.clients,
    required this.deals,
    required this.interactions,
    required this.summary,
  });

  CrmClient? clientById(String id) {
    for (final value in clients) {
      if (value.id == id) return value;
    }
    return null;
  }
}

class _ClientDetailData {
  final CrmClient client;
  final List<CrmDeal> deals;
  final List<CrmInteraction> interactions;

  const _ClientDetailData({
    required this.client,
    required this.deals,
    required this.interactions,
  });
}

class _Metric {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool warning;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.warning = false,
  });
}

Widget _sheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    decoration: BoxDecoration(
      color: AppTheme.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      border: Border.all(color: AppTheme.glassBorder),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withOpacity(.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: WesiTitle(title, size: 18)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = false,
  int lines = 1,
  TextInputType? keyboard,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType: keyboard,
      validator: required
          ? (value) => value == null || value.trim().isEmpty
              ? '$label — обязательное поле'
              : null
          : null,
      decoration: _decoration(label),
    ),
  );
}

InputDecoration _decoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.surface.withOpacity(.52),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: AppTheme.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: AppTheme.glassBorder),
      ),
    );

Widget _datePicker(
  BuildContext context, {
  required String label,
  required DateTime? value,
  required ValueChanged<DateTime?> onChanged,
}) {
  final ru = WesiLocale.isRussian;
  return InkWell(
    borderRadius: BorderRadius.circular(13),
    onTap: () async {
      final chosen = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (chosen != null) onChanged(chosen);
    },
    child: InputDecorator(
      decoration: _decoration(label).copyWith(
        suffixIcon: value == null
            ? const Icon(Icons.calendar_month_outlined)
            : IconButton(
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              ),
      ),
      child: Text(
        value == null
            ? (ru ? 'Не выбрано' : 'Not selected')
            : DateFormat(ru ? 'dd.MM.yyyy' : 'MMM d, yyyy').format(value),
        style: TextStyle(
            color: value == null ? AppTheme.textMuted : AppTheme.textPrimary),
      ),
    ),
  );
}

Widget _dateTimePicker(
  BuildContext context, {
  required String label,
  required DateTime value,
  required ValueChanged<DateTime> onChanged,
}) {
  final ru = WesiLocale.isRussian;
  return InkWell(
    borderRadius: BorderRadius.circular(13),
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(value),
      );
      if (time == null) return;
      onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
    },
    child: InputDecorator(
      decoration: _decoration(label).copyWith(
        suffixIcon: const Icon(Icons.schedule),
      ),
      child: Text(DateFormat(ru ? 'dd.MM.yyyy HH:mm' : 'MMM d, yyyy HH:mm')
          .format(value)),
    ),
  );
}

int _defaultProbability(DealStage stage) => switch (stage) {
      DealStage.newLead => 10,
      DealStage.qualification => 25,
      DealStage.proposal => 45,
      DealStage.negotiation => 70,
      DealStage.won => 100,
      DealStage.lost => 0,
    };

String _stageLabel(DealStage stage, bool ru) => switch (stage) {
      DealStage.newLead => ru ? 'Новый лид' : 'New lead',
      DealStage.qualification => ru ? 'Квалификация' : 'Qualification',
      DealStage.proposal => ru ? 'Предложение' : 'Proposal',
      DealStage.negotiation => ru ? 'Переговоры' : 'Negotiation',
      DealStage.won => ru ? 'Выиграно' : 'Won',
      DealStage.lost => ru ? 'Проиграно' : 'Lost',
    };

Color _stageColor(DealStage stage) => switch (stage) {
      DealStage.newLead => const Color(0xFF60A5FA),
      DealStage.qualification => const Color(0xFFA78BFA),
      DealStage.proposal => const Color(0xFFF59E0B),
      DealStage.negotiation => AppTheme.accent,
      DealStage.won => AppTheme.accentGreen,
      DealStage.lost => AppTheme.accentRed,
    };

String _clientStatusLabel(CrmClientStatus status, bool ru) => switch (status) {
      CrmClientStatus.lead => ru ? 'Лид' : 'Lead',
      CrmClientStatus.active => ru ? 'Активный' : 'Active',
      CrmClientStatus.paused => ru ? 'Пауза' : 'Paused',
      CrmClientStatus.archived => ru ? 'Архив' : 'Archived',
    };

Color _clientStatusColor(CrmClientStatus status) => switch (status) {
      CrmClientStatus.lead => const Color(0xFF60A5FA),
      CrmClientStatus.active => AppTheme.accentGreen,
      CrmClientStatus.paused => const Color(0xFFF59E0B),
      CrmClientStatus.archived => AppTheme.textMuted,
    };

String _interactionLabel(InteractionKind kind, bool ru) => switch (kind) {
      InteractionKind.note => ru ? 'Заметка' : 'Note',
      InteractionKind.call => ru ? 'Звонок' : 'Call',
      InteractionKind.email => ru ? 'Письмо' : 'Email',
      InteractionKind.meeting => ru ? 'Встреча' : 'Meeting',
      InteractionKind.message => ru ? 'Сообщение' : 'Message',
    };

IconData _interactionIcon(InteractionKind kind) => switch (kind) {
      InteractionKind.note => Icons.sticky_note_2_outlined,
      InteractionKind.call => Icons.call_outlined,
      InteractionKind.email => Icons.email_outlined,
      InteractionKind.meeting => Icons.groups_outlined,
      InteractionKind.message => Icons.chat_bubble_outline,
    };

Color _interactionColor(InteractionKind kind) => switch (kind) {
      InteractionKind.note => const Color(0xFFA78BFA),
      InteractionKind.call => AppTheme.accentGreen,
      InteractionKind.email => const Color(0xFF60A5FA),
      InteractionKind.meeting => AppTheme.accent,
      InteractionKind.message => const Color(0xFF22D3EE),
    };
