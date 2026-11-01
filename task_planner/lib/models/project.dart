/// A project row returned by the backend.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.status = 'active',
    this.ownerId,
    this.aiOptIn = false,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? description;
  final String status;
  final int? ownerId;
  final bool aiOptIn;
  final DateTime? createdAt;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    status: json['status'] as String? ?? 'active',
    ownerId: json['owner_id'] as int?,
    aiOptIn: json['ai_opt_in'] as bool? ?? false,
    createdAt: _parseDate(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'status': status,
    'owner_id': ownerId,
    'ai_opt_in': aiOptIn,
    'created_at': createdAt?.toIso8601String(),
  };
}

/// Paginated response for project lists.
class ProjectList {
  const ProjectList({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<Project> items;
  final int total;
  final int limit;
  final int offset;

  factory ProjectList.fromJson(Map<String, dynamic> json) => ProjectList(
    items: (json['items'] as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: json['total'] as int,
    limit: json['limit'] as int,
    offset: json['offset'] as int,
  );

  bool get hasMore => offset + items.length < total;
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
