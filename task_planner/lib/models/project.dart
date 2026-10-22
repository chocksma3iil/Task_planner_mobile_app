/// A project row returned by the backend.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.status = 'active',
    this.ownerId,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? description;
  final String status;
  final int? ownerId;
  final DateTime? createdAt;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    status: json['status'] as String? ?? 'active',
    ownerId: json['owner_id'] as int?,
    createdAt: _parseDate(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'status': status,
    'owner_id': ownerId,
    'created_at': createdAt?.toIso8601String(),
  };
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
