/// An account row returned by the backend.
///
/// Accounts double as project members and task assignees: the server keeps one
/// row per person (table `assignees`). JSON keys are snake_case to match the
/// FastAPI serializers.
class Account {
  const Account({
    required this.id,
    required this.name,
    this.position,
    this.projectId,
    required this.email,
    required this.role,
    required this.status,
    this.approvedBy,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? position;
  final int? projectId;
  final String email;
  final String role;
  final String status;
  final int? approvedBy;
  final DateTime? createdAt;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as int,
    name: json['name'] as String,
    position: json['position'] as String?,
    projectId: json['project_id'] as int?,
    email: json['email'] as String,
    role: json['role'] as String,
    status: json['status'] as String,
    approvedBy: json['approved_by'] as int?,
    createdAt: _parseDate(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'position': position,
    'project_id': projectId,
    'email': email,
    'role': role,
    'status': status,
    'approved_by': approvedBy,
    'created_at': createdAt?.toIso8601String(),
  };
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
