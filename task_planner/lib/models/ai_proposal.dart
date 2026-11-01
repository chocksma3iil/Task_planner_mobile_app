/// A proposal returned by the AI layer (v2.0).
///
/// The AI never writes to the database: this is a read-only proposal that
/// the user must approve before anything is persisted.
class AiWeeklyPlanProposal {
  const AiWeeklyPlanProposal({
    required this.title,
    required this.tasks,
  });

  final String title;
  final List<AiTaskProposal> tasks;

  factory AiWeeklyPlanProposal.fromJson(Map<String, dynamic> json) => AiWeeklyPlanProposal(
    title: json['title'] as String? ?? 'Weekly Plan',
    tasks: (json['tasks'] as List? ?? const <dynamic>[])
        .map((e) => AiTaskProposal.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class AiTaskProposal {
  const AiTaskProposal({
    required this.title,
    this.description,
    required this.priority,
    this.dueDate,
    required this.status,
  });

  final String title;
  final String? description;
  final String priority;
  final String? dueDate;
  final String status;

  factory AiTaskProposal.fromJson(Map<String, dynamic> json) => AiTaskProposal(
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    priority: json['priority'] as String? ?? 'medium',
    dueDate: json['due_date'] as String?,
    status: json['status'] as String? ?? 'todo',
  );
}

class AiDecomposeProposal {
  const AiDecomposeProposal({required this.subtasks});

  final List<AiSubtaskProposal> subtasks;

  factory AiDecomposeProposal.fromJson(Map<String, dynamic> json) =>
      AiDecomposeProposal(
        subtasks: (json['subtasks'] as List? ?? const <dynamic>[])
            .map((e) => AiSubtaskProposal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AiSubtaskProposal {
  const AiSubtaskProposal({
    required this.title,
    this.description,
    required this.priority,
  });

  final String title;
  final String? description;
  final String priority;

  factory AiSubtaskProposal.fromJson(Map<String, dynamic> json) =>
      AiSubtaskProposal(
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        priority: json['priority'] as String? ?? 'medium',
      );
}

class AiBriefingProposal {
  const AiBriefingProposal({required this.briefing});

  final String briefing;

  factory AiBriefingProposal.fromJson(Map<String, dynamic> json) =>
      AiBriefingProposal(
        briefing: json['briefing'] as String? ?? '',
      );
}

class AiCaptureProposal {
  const AiCaptureProposal({
    required this.title,
    this.description,
    required this.priority,
    this.dueDate,
    required this.status,
  });

  final String title;
  final String? description;
  final String priority;
  final String? dueDate;
  final String status;

  factory AiCaptureProposal.fromJson(Map<String, dynamic> json) =>
      AiCaptureProposal(
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        priority: json['priority'] as String? ?? 'medium',
        dueDate: json['due_date'] as String?,
        status: json['status'] as String? ?? 'todo',
      );
}
