import 'package:drift/drift.dart';

import '../../../core/database.dart';
import '../../../core/rules.dart';

/// Task operations with assignment and scope enforcement.
///
/// A task belongs to a project and is assigned either to the whole project
/// ([assigneeId] null) or to one person from that project — never both.
class TaskService {
  TaskService(this._db);

  final AppDatabase _db;

  Future<Task> createTask({
    required Assignee actor,
    required int projectId,
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
    int? assigneeId,
  }) async {
    _requireProjectAccess(actor, projectId);
    await _checkAssignee(projectId, assigneeId);
    final id = await _db.into(_db.tasks).insert(
          TasksCompanion.insert(
            title: title,
            description: Value(description),
            priority: Value(priority),
            dueDate: Value(dueDate),
            projectId: projectId,
            assigneeId: Value(assigneeId),
          ),
        );
    return _byId(id);
  }

  Future<Task> completeTask({
    required Assignee actor,
    required int taskId,
  }) async {
    final task = await _byId(taskId);
    _requireProjectAccess(actor, task.projectId);
    final now = DateTime.now();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const Value(TaskStatus.completed),
        completedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return _byId(taskId);
  }

  Future<Task> reopenTask({
    required Assignee actor,
    required int taskId,
  }) async {
    final task = await _byId(taskId);
    _requireProjectAccess(actor, task.projectId);
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const Value(TaskStatus.todo),
        completedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return _byId(taskId);
  }

  Future<void> deleteTask({
    required Assignee actor,
    required int taskId,
  }) async {
    final task = await _byId(taskId);
    _requireProjectAccess(actor, task.projectId);
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(taskId))).go();
  }

  /// Tasks of one project, newest first.
  Stream<List<Task>> watchProjectTasks(int projectId) {
    return (_db.select(_db.tasks)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Tasks assigned to one person, newest first.
  ///
  /// The id comes from the logged-in session, and assignment already
  /// restricts people to their own project, so this is scope-safe.
  Stream<List<Task>> watchTasksAssignedTo(int assigneeId) {
    return (_db.select(_db.tasks)
          ..where((t) => t.assigneeId.equals(assigneeId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Every task, for admins.
  Stream<List<Task>> watchAllTasks() {
    return (_db.select(_db.tasks)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  void _requireProjectAccess(Assignee actor, int projectId) {
    if (!isAdmin(actor.role) && actor.projectId != projectId) {
      throw StateError('You can only manage your own project tasks.');
    }
  }

  Future<void> _checkAssignee(int projectId, int? assigneeId) async {
    if (assigneeId == null) {
      return;
    }
    final assignee = await (_db.select(_db.assignees)
          ..where((t) => t.id.equals(assigneeId)))
        .getSingle();
    if (!canLogIn(assignee.status)) {
      throw StateError('Tasks can only be assigned to active members.');
    }
    validateTaskAssignment(
      taskProjectId: projectId,
      assigneeId: assigneeId,
      assigneeProjectId: assignee.projectId,
    );
  }

  Future<Task> _byId(int id) {
    return (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingle();
  }
}
