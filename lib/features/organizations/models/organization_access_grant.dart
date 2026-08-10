import 'package:hive/hive.dart';

part 'organization_access_grant.g.dart';

class OrganizationPermissions {
  OrganizationPermissions._();

  static const String view = 'view';
  static const String createTransactions = 'create_transactions';
  static const String editTransactions = 'edit_transactions';
  static const String manageAccounts = 'manage_accounts';
  static const String manageRecurring = 'manage_recurring';
  static const String viewForecast = 'view_forecast';
  static const String manageOrgSettings = 'manage_org_settings';
  static const String manageMembers = 'manage_members';

  static const List<String> all = [
    view,
    createTransactions,
    editTransactions,
    manageAccounts,
    manageRecurring,
    viewForecast,
    manageOrgSettings,
    manageMembers,
  ];
}

@HiveType(typeId: 82)
class OrganizationAccessGrant {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String employeeId;
  @HiveField(2)
  final String organizationId;
  @HiveField(3)
  final bool includeSubtree;
  @HiveField(4)
  final bool canViewTeamFinance;
  @HiveField(5)
  final bool canViewSelfFinance;
  @HiveField(6)
  final List<String> permissions;
  @HiveField(7)
  final DateTime createdAt;
  @HiveField(8)
  final DateTime updatedAt;
  @HiveField(9)
  final String createdBy;

  const OrganizationAccessGrant({
    required this.id,
    required this.employeeId,
    required this.organizationId,
    this.includeSubtree = false,
    this.canViewTeamFinance = false,
    this.canViewSelfFinance = true,
    this.permissions = const [OrganizationPermissions.view],
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  bool allows(String permission) => permissions.contains(permission);

  OrganizationAccessGrant copyWith({
    bool? includeSubtree,
    bool? canViewTeamFinance,
    bool? canViewSelfFinance,
    List<String>? permissions,
    DateTime? updatedAt,
  }) =>
      OrganizationAccessGrant(
        id: id,
        employeeId: employeeId,
        organizationId: organizationId,
        includeSubtree: includeSubtree ?? this.includeSubtree,
        canViewTeamFinance: canViewTeamFinance ?? this.canViewTeamFinance,
        canViewSelfFinance: canViewSelfFinance ?? this.canViewSelfFinance,
        permissions: permissions ?? this.permissions,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        createdBy: createdBy,
      );
}
