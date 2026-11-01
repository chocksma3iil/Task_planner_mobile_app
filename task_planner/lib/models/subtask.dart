/// A subtask (checklist item) attached to a task.
class Subtask {
  const Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    required this.completed,
    required this.sortOrder,
    required this.createdAt,
  });

  final int id;
  final int taskId;
  final String title;
  final bool completed;
  final int sortOrder;
  final DateTime createdAt;

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
    id: json['id'] as int,
    taskId: json['task_id'] as int,
    title: json['title'] as String,
    completed: json['completed'] as bool? ?? false,
    sortOrder: json['sort_order'] as int? ?? 0,
    createdAt: _parseDate(json['created_at'])!,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'task_id': taskId,
    'title': title,
    'completed': completed,
    'sort_order': sortOrder,
    'created_at': createdAt.toIso8601String(),
  };
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
