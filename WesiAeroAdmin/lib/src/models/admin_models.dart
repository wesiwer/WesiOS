class AdminSnapshot {
  const AdminSnapshot({
    required this.revision,
    required this.generatedAt,
    required this.counts,
    required this.servers,
    required this.plans,
    required this.licenses,
    required this.payments,
    required this.paymentSettings,
  });

  final int revision;
  final DateTime generatedAt;
  final AdminCounts counts;
  final List<AdminServer> servers;
  final List<AdminPlan> plans;
  final List<AdminLicense> licenses;
  final List<AdminPayment> payments;
  final List<AdminPaymentSetting> paymentSettings;

  factory AdminSnapshot.fromJson(Map<String, dynamic> json) => AdminSnapshot(
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
            DateTime.now(),
        counts: AdminCounts.fromJson(
          json['counts'] as Map<String, dynamic>? ?? const {},
        ),
        servers: _list(json['servers'], AdminServer.fromJson),
        plans: _list(json['plans'], AdminPlan.fromJson),
        licenses: _list(json['licenses'], AdminLicense.fromJson),
        payments: _list(json['payments'], AdminPayment.fromJson),
        paymentSettings:
            _list(json['paymentSettings'], AdminPaymentSetting.fromJson),
      );
}

class AdminCounts {
  const AdminCounts({
    required this.servers,
    required this.serversOnline,
    required this.licenses,
    required this.licensesActive,
    required this.devices,
    required this.payments,
    required this.paymentsPaid,
    required this.revenueMinor,
  });

  final int servers;
  final int serversOnline;
  final int licenses;
  final int licensesActive;
  final int devices;
  final int payments;
  final int paymentsPaid;
  final int revenueMinor;

  factory AdminCounts.fromJson(Map<String, dynamic> json) => AdminCounts(
        servers: _int(json['servers']),
        serversOnline: _int(json['serversOnline']),
        licenses: _int(json['licenses']),
        licensesActive: _int(json['licensesActive']),
        devices: _int(json['devices']),
        payments: _int(json['payments']),
        paymentsPaid: _int(json['paymentsPaid']),
        revenueMinor: _int(json['revenueMinor']),
      );
}

class AdminServer {
  const AdminServer({
    required this.id,
    required this.displayName,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.endpoint,
    required this.protocols,
    required this.load,
    required this.online,
    required this.recommended,
    required this.capacity,
    required this.tags,
    required this.notes,
    required this.transportConfig,
  });

  final String id;
  final String displayName;
  final String city;
  final String country;
  final String countryCode;
  final String endpoint;
  final List<String> protocols;
  final double load;
  final bool online;
  final bool recommended;
  final int capacity;
  final List<String> tags;
  final String notes;
  final Map<String, dynamic> transportConfig;

  factory AdminServer.fromJson(Map<String, dynamic> json) => AdminServer(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? json['city'] as String,
        city: json['city'] as String? ?? '',
        country: json['country'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? '',
        protocols: (json['protocols'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        load: (json['load'] as num?)?.toDouble() ?? 0,
        online: json['online'] as bool? ?? false,
        recommended: json['recommended'] as bool? ?? false,
        capacity: _int(json['capacity']),
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        notes: json['notes'] as String? ?? '',
        transportConfig:
            json['transportConfig'] as Map<String, dynamic>? ?? const {},
      );
}

class AdminPlan {
  const AdminPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.currency,
    required this.enabled,
    required this.pricing,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String description;
  final String currency;
  final bool enabled;
  final Map<String, dynamic> pricing;
  final int sortOrder;

  factory AdminPlan.fromJson(Map<String, dynamic> json) => AdminPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        currency: json['currency'] as String? ?? 'RUB',
        enabled: json['enabled'] as bool? ?? true,
        pricing: json['pricing'] as Map<String, dynamic>? ?? const {},
        sortOrder: _int(json['sortOrder']),
      );

  int price(String mode, int duration, String field) =>
      _int(((pricing[mode] as Map<String, dynamic>?)?[duration.toString()]
          as Map<String, dynamic>?)?[field]);
}

class AdminLicense {
  const AdminLicense({
    required this.id,
    required this.maskedKey,
    required this.planId,
    required this.source,
    required this.ipMode,
    required this.deviceLimit,
    required this.deviceCount,
    required this.durationDays,
    required this.status,
    required this.issuedAt,
    required this.expiresAt,
    required this.paymentId,
    required this.note,
  });

  final String id;
  final String maskedKey;
  final String? planId;
  final String source;
  final String ipMode;
  final int deviceLimit;
  final int deviceCount;
  final int durationDays;
  final String status;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? paymentId;
  final String note;

  bool get active => status == 'active' && expiresAt.isAfter(DateTime.now());

  factory AdminLicense.fromJson(Map<String, dynamic> json) => AdminLicense(
        id: json['id'] as String,
        maskedKey: json['maskedKey'] as String? ?? 'WA1-••••••••',
        planId: json['planId'] as String?,
        source: json['source'] as String? ?? 'admin',
        ipMode: json['ipMode'] as String? ?? 'shared',
        deviceLimit: _int(json['deviceLimit']),
        deviceCount: _int(json['deviceCount']),
        durationDays: _int(json['durationDays']),
        status: json['status'] as String? ?? 'active',
        issuedAt: DateTime.parse(json['issuedAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        paymentId: json['paymentId'] as String?,
        note: json['note'] as String? ?? '',
      );
}

class AdminPayment {
  const AdminPayment({
    required this.id,
    required this.provider,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.planId,
    required this.ipMode,
    required this.deviceLimit,
    required this.durationDays,
    required this.createdAt,
  });

  final String id;
  final String provider;
  final String status;
  final int amountMinor;
  final String currency;
  final String planId;
  final String ipMode;
  final int deviceLimit;
  final int durationDays;
  final DateTime createdAt;

  factory AdminPayment.fromJson(Map<String, dynamic> json) => AdminPayment(
        id: json['id'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        amountMinor: _int(json['amountMinor']),
        currency: json['currency'] as String? ?? 'RUB',
        planId: json['planId'] as String,
        ipMode: json['ipMode'] as String,
        deviceLimit: _int(json['deviceLimit']),
        durationDays: _int(json['durationDays']),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AdminPaymentSetting {
  const AdminPaymentSetting({
    required this.provider,
    required this.enabled,
    required this.testMode,
    required this.publicConfig,
  });

  final String provider;
  final bool enabled;
  final bool testMode;
  final Map<String, dynamic> publicConfig;

  factory AdminPaymentSetting.fromJson(Map<String, dynamic> json) =>
      AdminPaymentSetting(
        provider: json['provider'] as String,
        enabled: json['enabled'] as bool? ?? false,
        testMode: json['testMode'] as bool? ?? true,
        publicConfig:
            json['publicConfig'] as Map<String, dynamic>? ?? const {},
      );
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) parse) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => parse(item as Map<String, dynamic>))
      .toList(growable: false);
}

int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
