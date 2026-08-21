import 'gateway_models.dart';

enum AeroIpMode {
  shared,
  dedicated;

  String get title => switch (this) {
        AeroIpMode.shared => 'Общий IP',
        AeroIpMode.dedicated => 'Индивидуальный IP',
      };

  String get wireName => name;
}

enum AeroPaymentProvider {
  mock,
  yookassa,
  cryptoPay;

  String get wireName => switch (this) {
        AeroPaymentProvider.mock => 'mock',
        AeroPaymentProvider.yookassa => 'yookassa',
        AeroPaymentProvider.cryptoPay => 'crypto_pay',
      };

  String get title => switch (this) {
        AeroPaymentProvider.mock => 'Тестовая оплата',
        AeroPaymentProvider.yookassa => 'СБП',
        AeroPaymentProvider.cryptoPay => 'Криптовалюта',
      };

  static AeroPaymentProvider fromWire(String value) => switch (value) {
        'yookassa' => AeroPaymentProvider.yookassa,
        'crypto_pay' => AeroPaymentProvider.cryptoPay,
        _ => AeroPaymentProvider.mock,
      };
}

class TariffRate {
  const TariffRate({required this.base, required this.extraDevice});

  final int base;
  final int extraDevice;

  factory TariffRate.fromJson(Map<String, dynamic> json) => TariffRate(
        base: (json['base'] as num).toInt(),
        extraDevice: (json['extraDevice'] as num).toInt(),
      );
}

class TariffPlan {
  const TariffPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.currency,
    required this.pricing,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final String currency;
  final bool enabled;
  final Map<AeroIpMode, Map<int, TariffRate>> pricing;

  factory TariffPlan.fromJson(Map<String, dynamic> json) {
    final rawPricing = json['pricing'] as Map<String, dynamic>;
    return TariffPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      currency: json['currency'] as String? ?? 'RUB',
      enabled: json['enabled'] as bool? ?? true,
      pricing: {
        for (final mode in AeroIpMode.values)
          mode: {
            for (final entry
                in (rawPricing[mode.wireName] as Map<String, dynamic>).entries)
              int.parse(entry.key):
                  TariffRate.fromJson(entry.value as Map<String, dynamic>),
          },
      },
    );
  }

  int amountFor(AeroIpMode mode, int devices, int durationDays) {
    final rate = pricing[mode]?[durationDays];
    if (rate == null) return 0;
    return rate.base + rate.extraDevice * (devices - 1);
  }
}

class AeroPaymentMethod {
  const AeroPaymentMethod({
    required this.provider,
    required this.label,
    required this.testMode,
  });

  final AeroPaymentProvider provider;
  final String label;
  final bool testMode;

  factory AeroPaymentMethod.fromJson(Map<String, dynamic> json) =>
      AeroPaymentMethod(
        provider: AeroPaymentProvider.fromWire(json['provider'] as String),
        label: json['label'] as String? ??
            AeroPaymentProvider.fromWire(json['provider'] as String).title,
        testMode: json['testMode'] as bool? ?? false,
      );
}

class AeroCatalog {
  const AeroCatalog({
    required this.revision,
    required this.plans,
    required this.servers,
    required this.paymentMethods,
    required this.demo,
  });

  final int revision;
  final List<TariffPlan> plans;
  final List<GatewayNode> servers;
  final List<AeroPaymentMethod> paymentMethods;
  final bool demo;

  factory AeroCatalog.fromJson(Map<String, dynamic> json, {bool demo = false}) {
    return AeroCatalog(
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      plans: (json['plans'] as List<dynamic>? ?? const [])
          .map((item) => TariffPlan.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      servers: (json['servers'] as List<dynamic>? ?? const [])
          .map((item) => gatewayNodeFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      paymentMethods: (json['paymentMethods'] as List<dynamic>? ?? const [])
          .map((item) => AeroPaymentMethod.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      demo: demo,
    );
  }
}

class AeroQuote {
  const AeroQuote({
    required this.amountMinor,
    required this.currency,
    required this.displayAmount,
  });

  final int amountMinor;
  final String currency;
  final String displayAmount;

  factory AeroQuote.fromJson(Map<String, dynamic> json) => AeroQuote(
        amountMinor: (json['amountMinor'] as num).toInt(),
        currency: json['currency'] as String,
        displayAmount: json['displayAmount'] as String? ??
            '${((json['amountMinor'] as num).toInt() / 100).toStringAsFixed(2)} ${json['currency']}',
      );
}

class AeroLicense {
  const AeroLicense({
    required this.id,
    required this.planId,
    required this.ipMode,
    required this.deviceLimit,
    required this.deviceCount,
    required this.durationDays,
    required this.status,
    required this.expiresAt,
    required this.maskedKey,
  });

  final String id;
  final String? planId;
  final AeroIpMode ipMode;
  final int deviceLimit;
  final int deviceCount;
  final int durationDays;
  final String status;
  final DateTime expiresAt;
  final String maskedKey;

  bool get isActive => status == 'active' && expiresAt.isAfter(DateTime.now());

  factory AeroLicense.fromJson(Map<String, dynamic> json) => AeroLicense(
        id: json['id'] as String,
        planId: json['planId'] as String?,
        ipMode: json['ipMode'] == 'dedicated'
            ? AeroIpMode.dedicated
            : AeroIpMode.shared,
        deviceLimit: (json['deviceLimit'] as num).toInt(),
        deviceCount: (json['deviceCount'] as num?)?.toInt() ?? 0,
        durationDays: (json['durationDays'] as num).toInt(),
        status: json['status'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        maskedKey: json['maskedKey'] as String? ?? 'WA1-••••••••',
      );
}

class CheckoutOrder {
  const CheckoutOrder({
    required this.id,
    required this.provider,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.claimToken,
    this.checkoutUrl,
    this.key,
    this.license,
  });

  final String id;
  final AeroPaymentProvider provider;
  final String status;
  final int amountMinor;
  final String currency;
  final String claimToken;
  final String? checkoutUrl;
  final String? key;
  final AeroLicense? license;

  bool get paid => status == 'paid' && key != null && license != null;

  factory CheckoutOrder.fromJson(
    Map<String, dynamic> json, {
    required String claimToken,
  }) {
    final order = json['order'] as Map<String, dynamic>? ?? json;
    final rawLicense = json['license'];
    return CheckoutOrder(
      id: order['id'] as String,
      provider: AeroPaymentProvider.fromWire(order['provider'] as String),
      status: order['status'] as String,
      amountMinor: (order['amountMinor'] as num).toInt(),
      currency: order['currency'] as String,
      claimToken: claimToken,
      checkoutUrl: order['checkoutUrl'] as String?,
      key: json['key'] as String?,
      license: rawLicense is Map<String, dynamic>
          ? AeroLicense.fromJson(rawLicense)
          : null,
    );
  }
}

GatewayNode gatewayNodeFromJson(Map<String, dynamic> json) {
  return GatewayNode(
    id: json['id'] as String,
    city: json['city'] as String? ?? 'Unknown',
    country: json['country'] as String? ?? 'Unknown',
    countryCode: json['countryCode'] as String? ?? '',
    endpoint: json['endpoint'] as String? ?? '',
    pingMs: (json['pingMs'] as num?)?.toInt() ?? 0,
    load: (json['load'] as num?)?.toDouble() ?? 0,
    protocols: (json['protocols'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((name) => GatewayProtocol.values.firstWhere(
              (item) => item.wireName == name,
              orElse: () => GatewayProtocol.automatic,
            ))
        .where((item) => item != GatewayProtocol.automatic)
        .toSet(),
    recommended: json['recommended'] as bool? ?? false,
  );
}
