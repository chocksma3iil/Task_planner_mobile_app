/// A task row returned by the backend.
///
/// A task is assigned either to its project as a whole ([assigneeId] null) or
/// to one person from that project — never both.
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description,
    this.status = 'todo',
    this.priority = 'medium',
    this.dueDate,
    required this.projectId,
    this.assigneeId,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final int id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final int projectId;
  final int? assigneeId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as int,
    title: json['title'] as String,
    description: json['description'] as String?,
    status: json['status'] as String? ?? 'todo',
    priority: json['priority'] as String? ?? 'medium',
    dueDate: _parseDate(json['due_date']),
    projectId: json['project_id'] as int,
    assigneeId: json['assignee_id'] as int?,
    createdAt: _parseDate(json['created_at']),
    updatedAt: _parseDate(json['updated_at']),
    completedAt: _parseDate(json['completed_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'status': status,
    'priority': priority,
    'due_date': _dateOnly(dueDate),
    'project_id': projectId,
    'assignee_id': assigneeId,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };
}

String? _dateOnly(DateTime? value) => value?.toIso8601String().split('T').first;

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
