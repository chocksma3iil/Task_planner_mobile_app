/// One audit-trail row returned by the backend (D06).
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    this.actorId,
    required this.actorName,
    required this.action,
    required this.entityType,
    this.entityId,
    this.projectId,
    this.details,
    required this.createdAt,
  });

  final int id;
  final int? actorId;
  final String actorName;

  /// Machine action, e.g. `project.created` or `member.role_changed`.
  final String action;
  final String entityType; // project, member, ...
  final int? entityId;
  final int? projectId;

  /// JSON object as text (small payload describing the change).
  final String? details;
  final DateTime createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
    id: json['id'] as int,
    actorId: json['actor_id'] as int?,
    actorName: json['actor_name'] as String,
    action: json['action'] as String,
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as int?,
    projectId: json['project_id'] as int?,
    details: json['details'] as String?,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime(2000),
  );
}

/// One page of audit entries, newest first.
class AuditLogList {
  const AuditLogList({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AuditLogEntry> items;
  final int total;
  final int limit;
  final int offset;

  factory AuditLogList.fromJson(Map<String, dynamic> json) => AuditLogList(
    items: (json['items'] as List)
        .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: json['total'] as int,
    limit: json['limit'] as int,
    offset: json['offset'] as int,
  );
}
