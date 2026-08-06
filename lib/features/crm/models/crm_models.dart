enum CrmClientStatus { lead, active, paused, archived }

enum DealStage { newLead, qualification, proposal, negotiation, won, lost }

enum InteractionKind { note, call, email, meeting, message }

class CrmClient {
  final String id;
  final String name;
  final String company;
  final String phone;
  final String email;
  final String website;
  final String address;
  final String source;
  final String owner;
  final String notes;
  final CrmClientStatus status;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextContactAt;

  const CrmClient({
    required this.id,
    required this.name,
    this.company = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.address = '',
    this.source = '',
    this.owner = '',
    this.notes = '',
    this.status = CrmClientStatus.lead,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.nextContactAt,
  });

  String get displayName => company.trim().isEmpty ? name : '$name · $company';

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final chars = words.take(2).map((e) => e[0].toUpperCase()).join();
    return chars.isEmpty ? '?' : chars;
  }

  bool get followUpOverdue => nextContactAt != null &&
      nextContactAt!.isBefore(DateTime.now()) &&
      status != CrmClientStatus.archived;

  CrmClient copyWith({
    String? name,
    String? company,
    String? phone,
    String? email,
    String? website,
    String? address,
    String? source,
    String? owner,
    String? notes,
    CrmClientStatus? status,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? nextContactAt,
    bool clearNextContact = false,
  }) {
    return CrmClient(
      id: id,
      name: name ?? this.name,
      company: company ?? this.company,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      address: address ?? this.address,
      source: source ?? this.source,
      owner: owner ?? this.owner,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nextContactAt:
          clearNextContact ? null : (nextContactAt ?? this.nextContactAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'company': company,
        'phone': phone,
        'email': email,
        'website': website,
        'address': address,
        'source': source,
        'owner': owner,
        'notes': notes,
        'status': status.name,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'nextContactAt': nextContactAt?.toIso8601String(),
      };

  static CrmClient? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (id.isEmpty || name.isEmpty || created == null) return null;
    final statusName = '${json['status'] ?? ''}';
    final status = CrmClientStatus.values.where((e) => e.name == statusName);
    return CrmClient(
      id: id,
      name: name,
      company: '${json['company'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      email: '${json['email'] ?? ''}',
      website: '${json['website'] ?? ''}',
      address: '${json['address'] ?? ''}',
      source: '${json['source'] ?? ''}',
      owner: '${json['owner'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      status: status.isEmpty ? CrmClientStatus.lead : status.first,
      tags: [for (final e in (json['tags'] as List? ?? const [])) '$e'],
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
      nextContactAt: DateTime.tryParse('${json['nextContactAt'] ?? ''}'),
    );
  }
}

class CrmDeal {
  final String id;
  final String clientId;
  final String title;
  final double amount;
  final String currency;
  final DealStage stage;
  final int probability;
  final String notes;
  final String transactionId;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expectedCloseAt;
  final DateTime? closedAt;

  const CrmDeal({
    required this.id,
    required this.clientId,
    required this.title,
    this.amount = 0,
    this.currency = 'RUB',
    this.stage = DealStage.newLead,
    this.probability = 10,
    this.notes = '',
    this.transactionId = '',
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.expectedCloseAt,
    this.closedAt,
  });

  bool get isOpen => stage != DealStage.won && stage != DealStage.lost;
  double get weightedAmount => amount * probability.clamp(0, 100) / 100;

  CrmDeal copyWith({
    String? clientId,
    String? title,
    double? amount,
    String? currency,
    DealStage? stage,
    int? probability,
    String? notes,
    String? transactionId,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? expectedCloseAt,
    bool clearExpectedClose = false,
    DateTime? closedAt,
    bool clearClosedAt = false,
  }) {
    return CrmDeal(
      id: id,
      clientId: clientId ?? this.clientId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      stage: stage ?? this.stage,
      probability: (probability ?? this.probability).clamp(0, 100),
      notes: notes ?? this.notes,
      transactionId: transactionId ?? this.transactionId,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expectedCloseAt: clearExpectedClose
          ? null
          : (expectedCloseAt ?? this.expectedCloseAt),
      closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'title': title,
        'amount': amount,
        'currency': currency,
        'stage': stage.name,
        'probability': probability,
        'notes': notes,
        'transactionId': transactionId,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'expectedCloseAt': expectedCloseAt?.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
      };

  static CrmDeal? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final clientId = '${json['clientId'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (id.isEmpty || clientId.isEmpty || title.isEmpty || created == null) {
      return null;
    }
    final stageName = '${json['stage'] ?? ''}';
    final stage = DealStage.values.where((e) => e.name == stageName);
    final rawAmount = json['amount'];
    final rawProbability = json['probability'];
    return CrmDeal(
      id: id,
      clientId: clientId,
      title: title,
      amount: rawAmount is num ? rawAmount.toDouble() : double.tryParse('$rawAmount') ?? 0,
      currency: '${json['currency'] ?? 'RUB'}',
      stage: stage.isEmpty ? DealStage.newLead : stage.first,
      probability: rawProbability is num
          ? rawProbability.toInt().clamp(0, 100)
          : (int.tryParse('$rawProbability') ?? 10).clamp(0, 100),
      notes: '${json['notes'] ?? ''}',
      transactionId: '${json['transactionId'] ?? ''}',
      tags: [for (final e in (json['tags'] as List? ?? const [])) '$e'],
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
      expectedCloseAt: DateTime.tryParse('${json['expectedCloseAt'] ?? ''}'),
      closedAt: DateTime.tryParse('${json['closedAt'] ?? ''}'),
    );
  }
}

class CrmInteraction {
  final String id;
  final String clientId;
  final String? dealId;
  final InteractionKind kind;
  final String title;
  final String details;
  final String author;
  final DateTime at;
  final DateTime? nextActionAt;

  const CrmInteraction({
    required this.id,
    required this.clientId,
    this.dealId,
    this.kind = InteractionKind.note,
    required this.title,
    this.details = '',
    this.author = '',
    required this.at,
    this.nextActionAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'dealId': dealId,
        'kind': kind.name,
        'title': title,
        'details': details,
        'author': author,
        'at': at.toIso8601String(),
        'nextActionAt': nextActionAt?.toIso8601String(),
      };

  static CrmInteraction? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final clientId = '${json['clientId'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final at = DateTime.tryParse('${json['at'] ?? ''}');
    if (id.isEmpty || clientId.isEmpty || title.isEmpty || at == null) {
      return null;
    }
    final kindName = '${json['kind'] ?? ''}';
    final kind = InteractionKind.values.where((e) => e.name == kindName);
    final dealRaw = '${json['dealId'] ?? ''}'.trim();
    return CrmInteraction(
      id: id,
      clientId: clientId,
      dealId: dealRaw.isEmpty ? null : dealRaw,
      kind: kind.isEmpty ? InteractionKind.note : kind.first,
      title: title,
      details: '${json['details'] ?? ''}',
      author: '${json['author'] ?? ''}',
      at: at,
      nextActionAt: DateTime.tryParse('${json['nextActionAt'] ?? ''}'),
    );
  }
}

class CrmSummary {
  final int clients;
  final int activeClients;
  final int openDeals;
  final int wonDeals;
  final int overdueFollowUps;
  final double pipelineAmount;
  final double weightedPipeline;
  final double wonAmount;

  const CrmSummary({
    required this.clients,
    required this.activeClients,
    required this.openDeals,
    required this.wonDeals,
    required this.overdueFollowUps,
    required this.pipelineAmount,
    required this.weightedPipeline,
    required this.wonAmount,
  });
}