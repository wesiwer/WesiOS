import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import '../services/organization_access_service.dart';
import '../services/organization_context.dart';
import '../services/organization_service.dart';

class OrganizationSwitcher extends StatefulWidget {
  final bool compact;
  const OrganizationSwitcher({super.key, this.compact = false});

  @override
  State<OrganizationSwitcher> createState() => _OrganizationSwitcherState();
}

class _OrganizationSwitcherState extends State<OrganizationSwitcher> {
  OrganizationModel? _current;

  @override
  void initState() {
    super.initState();
    OrganizationContext.revision.addListener(_reload);
    OrganizationService.revision.addListener(_reload);
    OrganizationAccessService.revision.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    OrganizationContext.revision.removeListener(_reload);
    OrganizationService.revision.removeListener(_reload);
    OrganizationAccessService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final org = await OrganizationContext.currentOrganization();
    if (mounted) setState(() => _current = org);
  }

  @override
  Widget build(BuildContext context) {
    final org = _current;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _open,
      child: Container(
        constraints: BoxConstraints(maxWidth: widget.compact ? 190 : 270),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 9 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 17, color: AppTheme.accent),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    org?.name ?? 'Wesi Beats',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    OrganizationContext.scope == OrganizationScope.only
                        ? 'Только эта'
                        : 'С дочерними',
                    maxLines: 1,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.expand_more, size: 17, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      builder: (_) => const _OrganizationPickerSheet(),
    );
    await _load();
  }
}

class _OrganizationPickerSheet extends StatefulWidget {
  const _OrganizationPickerSheet();

  @override
  State<_OrganizationPickerSheet> createState() => _OrganizationPickerSheetState();
}

class _OrganizationPickerSheetState extends State<_OrganizationPickerSheet> {
  List<OrganizationModel> _orgs = const [];
  Set<String> _allowed = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await OrganizationService.all();
    final allowed = TeamService.current == null
        ? all.map((e) => e.id).toSet()
        : await OrganizationAccessService.visibleOrganizationIds();
    if (!mounted) return;
    setState(() {
      _orgs = all;
      _allowed = allowed;
      _loading = false;
    });
  }

  int _depth(OrganizationModel org) {
    var depth = 0;
    var parent = org.parentId;
    final byId = {for (final item in _orgs) item.id: item};
    final seen = <String>{org.id};
    while (parent != null && seen.add(parent)) {
      depth++;
      parent = byId[parent]?.parentId;
    }
    return depth;
  }

  Future<void> _select(String id) async {
    await OrganizationContext.selectOrganization(id);
    AccountService.revision.value++;
    TreasuryService.revision.value++;
    if (mounted) setState(() {});
  }

  Future<void> _scope(OrganizationScope scope) async {
    await OrganizationContext.setScope(scope);
    AccountService.revision.value++;
    TreasuryService.revision.value++;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Организация',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<OrganizationScope>(
                segments: const [
                  ButtonSegment(
                    value: OrganizationScope.only,
                    label: Text('Только эта'),
                    icon: Icon(Icons.business_outlined),
                  ),
                  ButtonSegment(
                    value: OrganizationScope.subtree,
                    label: Text('С дочерними'),
                    icon: Icon(Icons.account_tree_outlined),
                  ),
                ],
                selected: {OrganizationContext.scope},
                onSelectionChanged: (s) => _scope(s.first),
              ),
              const SizedBox(height: 12),
              Divider(color: AppTheme.glassBorder),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (final org in _orgs)
                            if (_allowed.contains(org.id))
                              Padding(
                                padding: EdgeInsets.only(left: _depth(org) * 18.0),
                                child: ListTile(
                                  dense: true,
                                  selected: org.id == OrganizationContext.currentOrganizationId,
                                  leading: Icon(
                                    org.isRoot
                                        ? Icons.hub_outlined
                                        : Icons.business_outlined,
                                    color: org.id == OrganizationContext.currentOrganizationId
                                        ? AppTheme.accent
                                        : AppTheme.textSecondary,
                                  ),
                                  title: Text(org.name),
                                  subtitle: Text(org.baseCurrency),
                                  trailing: org.id == OrganizationContext.currentOrganizationId
                                      ? Icon(Icons.check, color: AppTheme.accentGreen)
                                      : null,
                                  onTap: () => _select(org.id),
                                ),
                              ),
                        ],
                      ),
              ),
              FutureBuilder<bool>(
                future: OrganizationAccessService.can(
                  OrganizationContext.currentOrganizationId,
                  OrganizationPermissions.manageOrgSettings,
                ),
                builder: (context, snapshot) {
                  if (snapshot.data != true && TeamService.current?.isOwner != true) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/organizations');
                      },
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Управление организациями'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
