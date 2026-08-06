enum RoadmapItemKind { phase, milestone }

enum RoadmapItemStatus { planned, inProgress, blocked, done }

class RoadmapProject {
  final String id;
  final String title;
  final String description;
  final String owner;
  final List<String> tags;
  final int colorValue;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;

  const RoadmapProject({
    required this.id,
    required this.title,
    this.description = '',
    this.owner = '',
    this.tags = const [],
    this.colorValue = 0xFFF97316,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
  });

  Duration get duration => endDate.difference(startDate);
  bool get isLate => endDate.isBefore(DateTime.now()) && !archived;

  RoadmapProject copyWith({
    String? title,
    String? description,
    String? owner,
    List<String>? tags,
    int? colorValue,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? updatedAt,
    bool? archived,
  }) {
    return RoadmapProject(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      owner: owner ?? this.owner,
      tags: tags ?? this.tags,
      colorValue: colorValue ?? this.colorValue,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'owner': owner,
        'tags': tags,
        'colorValue': colorValue,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'archived': archived,
      };

  static RoadmapProject? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final start = DateTime.tryParse('${json['startDate'] ?? ''}');
    final end = DateTime.tryParse('${json['endDate'] ?? ''}');
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (id.isEmpty || title.isEmpty || start == null || end == null || created == null) {
      return null;
    }
    final rawColor = json['colorValue'];
    return RoadmapProject(
      id: id,
      title: title,
      description: '${json['description'] ?? ''}',
      owner: '${json['owner'] ?? ''}',
      tags: [for (final value in (json['tags'] as List? ?? const [])) '$value'],
      colorValue: rawColor is num
          ? rawColor.toInt()
          : int.tryParse('$rawColor') ?? 0xFFF97316,
      startDate: start,
      endDate: end,
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
      archived: json['archived'] == true,
    );
  }
}

class RoadmapItem {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final RoadmapItemKind kind;
  final RoadmapItemStatus status;
  final String assignee;
  final DateTime startDate;
  final DateTime endDate;
  final int progress;
  final int order;
  final List<String> dependencyIds;
  final List<String> linkedTaskIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoadmapItem({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.kind = RoadmapItemKind.phase,
    this.status = RoadmapItemStatus.planned,
    this.assignee = '',
    required this.startDate,
    required this.endDate,
    this.progress = 0,
    this.order = 0,
    this.dependencyIds = const [],
    this.linkedTaskIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDone => status == RoadmapItemStatus.done || progress >= 100;
  bool get isBlocked => status == RoadmapItemStatus.blocked;
  bool get isOverdue => endDate.isBefore(DateTime.now()) && !isDone;
  Duration get duration => endDate.difference(startDate);

  RoadmapItem copyWith({
    String? projectId,
    String? title,
    String? description,
    RoadmapItemKind? kind,
    RoadmapItemStatus? status,
    String? assignee,
    DateTime? startDate,
    DateTime? endDate,
    int? progress,
    int? order,
    List<String>? dependencyIds,
    List<String>? linkedTaskIds,
    DateTime? updatedAt,
  }) {
    return RoadmapItem(
      id: id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      assignee: assignee ?? this.assignee,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      progress: (progress ?? this.progress).clamp(0, 100).toInt(),
      order: order ?? this.order,
      dependencyIds: dependencyIds ?? this.dependencyIds,
      linkedTaskIds: linkedTaskIds ?? this.linkedTaskIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'description': description,
        'kind': kind.name,
        'status': status.name,
        'assignee': assignee,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'progress': progress,
        'order': order,
        'dependencyIds': dependencyIds,
        'linkedTaskIds': linkedTaskIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static RoadmapItem? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final projectId = '${json['projectId'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final start = DateTime.tryParse('${json['startDate'] ?? ''}');
    final end = DateTime.tryParse('${json['endDate'] ?? ''}');
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (id.isEmpty || projectId.isEmpty || title.isEmpty || start == null || end == null || created == null) {
      return null;
    }
    final kindName = '${json['kind'] ?? ''}';
    final statusName = '${json['status'] ?? ''}';
    final kind = RoadmapItemKind.values.where((value) => value.name == kindName);
    final status = RoadmapItemStatus.values.where((value) => value.name == statusName);
    final rawProgress = json['progress'];
    final rawOrder = json['order'];
    return RoadmapItem(
      id: id,
      projectId: projectId,
      title: title,
      description: '${json['description'] ?? ''}',
      kind: kind.isEmpty ? RoadmapItemKind.phase : kind.first,
      status: status.isEmpty ? RoadmapItemStatus.planned : status.first,
      assignee: '${json['assignee'] ?? ''}',
      startDate: start,
      endDate: end,
      progress: (rawProgress is num
              ? rawProgress.toInt()
              : int.tryParse('$rawProgress') ?? 0)
          .clamp(0, 100)
          .toInt(),
      order: rawOrder is num ? rawOrder.toInt() : int.tryParse('$rawOrder') ?? 0,
      dependencyIds: [
        for (final value in (json['dependencyIds'] as List? ?? const [])) '$value'
      ],
      linkedTaskIds: [
        for (final value in (json['linkedTaskIds'] as List? ?? const [])) '$value'
      ],
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
    );
  }
}

class RoadmapSummary {
  final int projects;
  final int activeProjects;
  final int items;
  final int milestones;
  final int blocked;
  final int overdue;
  final int completed;
  final double averageProgress;

  const RoadmapSummary({
    required this.projects,
    required this.activeProjects,
    required this.items,
    required this.milestones,
    required this.blocked,
    required this.overdue,
    required this.completed,
    required this.averageProgress,
  });
}