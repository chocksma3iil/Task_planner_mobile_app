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

  /// Tasks of one project, newest first.
  Stream<List<Task>> watchProjectTasks(int projectId) =>
      _watch('/tasks?project_id=$projectId');

  /// Tasks assigned to one person, newest first.
  Stream<List<Task>> watchTasksAssignedTo(int assigneeId) =>
      _watch('/tasks?assignee_id=$assigneeId');

  Stream<List<Task>> _watch(String path) {
    return watchFromApi(() async {
      final json = await _client.get(path) as List<dynamic>;
      return json
          .map((row) => Task.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
    });
  }
}

String? _dateOnly(DateTime? date) => date?.toIso8601String().split('T').first;
