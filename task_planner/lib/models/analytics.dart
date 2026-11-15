/// Analytics dashboard metrics for one project.
class DashboardStats {
  const DashboardStats({
    required this.projectId,
    required this.projectName,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.overdueTasks,
    required this.completionRate, // 0..100
    required this.overdueRate, // 0..100
    required this.priorityMix, // {"low": n, "medium": n, "high": n}
    required this.velocityPerWeek, // completed tasks per week (last 4 weeks)
    required this.recentEvents,
  });

  final int projectId;
  final String projectName;
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int overdueTasks;
  final double completionRate;
  final double overdueRate;
  final Map<String, int> priorityMix;
  final double velocityPerWeek;
  final List<AnalyticsEvent> recentEvents;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final priorityMix = <String, int>{};
    (json['priority_mix'] as Map<String, dynamic>).forEach(
      (key, value) => priorityMix[key] = value as int,
    );
    final recentEvents = <AnalyticsEvent>[];
    for (final e in (json['recent_events'] as List<dynamic>)) {
      recentEvents.add(AnalyticsEvent.fromJson(e as Map<String, dynamic>));
    }
    return DashboardStats(
      projectId: json['project_id'] as int,
      projectName: json['project_name'] as String,
      totalTasks: json['total_tasks'] as int,
      completedTasks: json['completed_tasks'] as int,
      pendingTasks: json['pending_tasks'] as int,
      overdueTasks: json['overdue_tasks'] as int,
      completionRate: (json['completion_rate'] as num).toDouble(),
      overdueRate: (json['overdue_rate'] as num).toDouble(),
      priorityMix: priorityMix,
      velocityPerWeek: (json['velocity_per_week'] as num).toDouble(),
      recentEvents: recentEvents,
    );
  }
}

/// One recent analytics event.
class AnalyticsEvent {
  const AnalyticsEvent({
    required this.id,
    required this.eventType,
    this.taskId,
    required this.actorId,
    required this.actorName,
    required this.createdAt,
  });

  final int id;
  final String eventType; // task_created, task_completed, ...
  final int? taskId;
  final int actorId;
  final String actorName;
  final DateTime createdAt;

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
    id: json['id'] as int,
    eventType: json['event_type'] as String,
    taskId: json['task_id'] as int?,
    actorId: json['actor_id'] as int,
    actorName: json['actor_name'] as String,
    createdAt: _parseDate(json['created_at'])!,
  );
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
