/// A notification returned by the backend.
class Notification {
  const Notification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.payload,
    this.readAt,
    required this.createdAt,
  });

  final int id;
  final String type; // task_created, task_assigned, task_completed, ...
  final String title;
  final String? body;
  final String? payload; // e.g. task id as string
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  factory Notification.fromJson(Map<String, dynamic> json) => Notification(
    id: json['id'] as int,
    type: json['type'] as String,
    title: json['title'] as String,
    body: json['body'] as String?,
    payload: json['payload'] as String?,
    readAt: _parseDate(json['read_at']),
    createdAt: _parseDate(json['created_at'])!,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'payload': payload,
    'read_at': readAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
