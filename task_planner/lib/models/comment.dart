/// A comment attached to a task.
class Comment {
  const Comment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.body,
    this.mentions = const [],
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  final int id;
  final int taskId;
  final int authorId;
  final String body;
  final List<int> mentions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as int,
    taskId: json['task_id'] as int,
    authorId: json['author_id'] as int,
    body: json['body'] as String,
    mentions: (json['mentions'] as List? ?? <int>[]).cast<int>(),
    createdAt: _parseDate(json['created_at'])!,
    editedAt: _parseDate(json['edited_at']),
    deletedAt: _parseDate(json['deleted_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'task_id': taskId,
    'author_id': authorId,
    'body': body,
    'mentions': mentions,
    'created_at': createdAt.toIso8601String(),
    'edited_at': editedAt?.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
