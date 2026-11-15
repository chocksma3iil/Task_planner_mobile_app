import '../models/models.dart';
import 'api_client.dart';
import 'data_sync.dart';

/// Task operations against the API.
///
/// A task belongs to a project and is assigned either to the whole project
/// ([assigneeId] null) or to one person from that project — never both.
/// The server enforces the rule; assignment violations surface as
/// [ArgumentError], everything else as [StateError].
class TaskService {
  TaskService(this._client);

  final ApiClient _client;

  Future<Task> createTask({
    required int projectId,
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
    int? assigneeId,
  }) async {
    final json = await _client.post('/tasks', {
      'project_id': projectId,
      'title': title,
      'description': ?description,
      'priority': priority,
      'due_date': ?_dateOnly(dueDate),
      'assignee_id': ?assigneeId,
    });
    DataSync.instance.ping();
    return Task.fromJson(json as Map<String, dynamic>);
  }

  /// Partial edit. Null [description], [dueDate], and [assigneeId] clear
  /// those fields; [projectId] never changes after creation.
  Future<Task> updateTask({
    required int taskId,
    required String title,
    String? description,
    required String priority,
    DateTime? dueDate,
    int? assigneeId,
  }) async {
    final json = await _client.patch('/tasks/$taskId', {
      'title': title,
      'description': description,
      'priority': priority,
      'due_date': _dateOnly(dueDate),
      'assignee_id': assigneeId,
    });
    DataSync.instance.ping();
    return Task.fromJson(json as Map<String, dynamic>);
  }

  Future<Task> completeTask({required int taskId}) async {
    final json = await _client.patch('/tasks/$taskId/complete');
    DataSync.instance.ping();
    return Task.fromJson(json as Map<String, dynamic>);
  }

  Future<Task> reopenTask({required int taskId}) async {
    final json = await _client.patch('/tasks/$taskId/reopen');
    DataSync.instance.ping();
    return Task.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteTask({required int taskId}) async {
    await _client.delete('/tasks/$taskId');
    DataSync.instance.ping();
  }

  /// Marks every selected task completed. The server returns one result per
  /// task so a partial failure never hides the successful rows.
  Future<BulkTaskResult> bulkCompleteTasks({required List<int> taskIds}) async {
    final json = await _client.post('/tasks/bulk/complete', {
      'task_ids': taskIds,
    });
    DataSync.instance.ping();
    return BulkTaskResult.fromJson(json as Map<String, dynamic>);
  }

  /// Reassigns every selected task to one active member of its project.
  Future<BulkTaskResult> bulkReassignTasks({
    required List<int> taskIds,
    required int newAssigneeId,
  }) async {
    final json = await _client.post('/tasks/bulk/reassign', {
      'task_ids': taskIds,
      'assignee_id': newAssigneeId,
    });
    DataSync.instance.ping();
    return BulkTaskResult.fromJson(json as Map<String, dynamic>);
  }

  /// Deletes every selected task.
  Future<BulkTaskResult> bulkDeleteTasks({required List<int> taskIds}) async {
    final json = await _client.post('/tasks/bulk/delete', {
      'task_ids': taskIds,
    });
    DataSync.instance.ping();
    return BulkTaskResult.fromJson(json as Map<String, dynamic>);
  }

  /// One page of a project's tasks, newest first.
  Future<TaskList> fetchProjectTasks(
    int projectId, {
    int limit = 20,
    int offset = 0,
  }) => _fetch('/tasks?project_id=$projectId&limit=$limit&offset=$offset');

  /// One page of one person's tasks, newest first.
  Future<TaskList> fetchTasksAssignedTo(
    int assigneeId, {
    int limit = 20,
    int offset = 0,
  }) => _fetch('/tasks?assignee_id=$assigneeId&limit=$limit&offset=$offset');

  /// Tasks of one project, refreshed after every mutation.
  Stream<TaskList> watchProjectTasks(int projectId, {int page = 1, int pageSize = 20}) =>
      watchFromApi(() => fetchProjectTasks(
            projectId,
            limit: pageSize,
            offset: (page - 1) * pageSize,
          ));

  /// Tasks assigned to one person, refreshed after every mutation.
  Stream<TaskList> watchTasksAssignedTo(int assigneeId, {int page = 1, int pageSize = 20}) =>
      watchFromApi(() => fetchTasksAssignedTo(
            assigneeId,
            limit: pageSize,
            offset: (page - 1) * pageSize,
          ));

  Future<TaskList> _fetch(String path) async {
    final json = await _client.get(path) as Map<String, dynamic>;
    return TaskList.fromJson(json);
  }
}

String? _dateOnly(DateTime? date) => date?.toIso8601String().split('T').first;
