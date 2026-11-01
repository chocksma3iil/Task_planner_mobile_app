// Pure-Dart business rules. No Flutter, no database: unit-testable in isolation.
//
// Mirrors PROJECT_BRIEF.md and docs/ARCHITECTURE_PROPOSAL.md. The services
// in `lib/services/` enforce these rules against real rows; the checks here
// are the single definition of each rule.

// Roles (cumulative: admin > project owner > team lead > user > viewer).
abstract final class Roles {
  static const admin = 'admin';
  static const projectOwner = 'project_owner';
  static const teamLead = 'team_lead';
  static const user = 'user';
  static const viewer = 'viewer';
}

// Membership states.
abstract final class MemberStatus {
  static const pending = 'pending';
  static const active = 'active';
}

// Task states.
abstract final class TaskStatus {
  static const todo = 'todo';
  static const completed = 'completed';
}

/// A task is assigned either to its project as a whole ([assigneeId] null)
/// or to exactly one person, who must belong to the task's project.
void validateTaskAssignment({
  required int taskProjectId,
  required int? assigneeId,
  required int? assigneeProjectId,
}) {
  if (assigneeId != null && assigneeProjectId != taskProjectId) {
    throw ArgumentError('Assignee must belong to the task project.');
  }
}

/// Only active accounts may log in. Pending accounts wait for owner approval.
bool canLogIn(String status) => status == MemberStatus.active;

bool isAdmin(String role) => role == Roles.admin;

bool isOwnerOrAdmin(String role) =>
    role == Roles.admin || role == Roles.projectOwner;

bool isViewer(String role) => role == Roles.viewer;

bool isTeamLead(String role) => role == Roles.teamLead;

/// Throws [StateError] unless [role] is not a viewer (i.e. can mutate).
void requireCanMutate(String role) {
  if (isViewer(role)) {
    throw StateError('Viewers cannot make changes.');
  }
}

/// Tabs visible for a role, in display order.
///
/// Admins have no personal task list (they cannot be assignees); the
/// "mine" tab is for project owners and users.
List<String> visibleTabs(String role) {
  if (isAdmin(role)) {
    return const ['projects', 'members', 'tasks', 'planner', 'dashboard'];
  }
  if (isViewer(role)) {
    return const ['members', 'tasks', 'mine'];
  }
  return const ['members', 'tasks', 'mine', 'planner', 'dashboard'];
}

/// Throws [StateError] unless [role] is admin.
void requireAdmin(String role) {
  if (!isAdmin(role)) {
    throw StateError('Only an admin can do this.');
  }
}

/// Throws [StateError] unless [role] is project owner or admin.
void requireOwnerOrAdmin(String role) {
  if (!isOwnerOrAdmin(role)) {
    throw StateError('Only a project owner or admin can do this.');
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Incomplete with a due date before today. Completed tasks are never overdue.
bool isOverdue({
  required String status,
  required DateTime? dueDate,
  required DateTime now,
}) {
  if (status == TaskStatus.completed || dueDate == null) {
    return false;
  }
  return _day(dueDate).isBefore(_day(now));
}

/// Incomplete with a due date of today. Completed tasks show under All only.
bool isDueToday({
  required String status,
  required DateTime? dueDate,
  required DateTime now,
}) {
  if (status == TaskStatus.completed || dueDate == null) {
    return false;
  }
  return _day(dueDate) == _day(now);
}

/// Incomplete with a due date after today.
bool isUpcoming({
  required String status,
  required DateTime? dueDate,
  required DateTime now,
}) {
  if (status == TaskStatus.completed || dueDate == null) {
    return false;
  }
  return _day(dueDate).isAfter(_day(now));
}
