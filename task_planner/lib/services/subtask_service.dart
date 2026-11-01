/// Subtask operations against the API.
import '../models/models.dart';
import '../services/api_client.dart';

class SubtaskService {
  SubtaskService(this._client);

  final ApiClient _client;

  /// List all subtasks of a task.
  Future<List<Subtask>> list(int taskId) async {
    final json =
        await _client.get('/tasks/$taskId/subtasks') as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items
        .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a subtask on a task.
  Future<Subtask> create({
    required int taskId,
    required String title,
    bool completed = false,
    int sortOrder = 0,
  }) async {
    final json = await _client.post('/tasks/$taskId/subtasks', {
      'task_id': taskId,
      'title': title,
      'completed': completed,
      'sort_order': sortOrder,
    }) as Map<String, dynamic>;
    return Subtask.fromJson(json);
  }

  /// Update a subtask (title / completed / sort_order).
  Future<Subtask> update({
    required int subtaskId,
    String? title,
    bool? completed,
    int? sortOrder,
  }) async {
    final changes = <String, dynamic>{};
    if (title != null) changes['title'] = title;
    if (completed != null) changes['completed'] = completed;
    if (sortOrder != null) changes['sort_order'] = sortOrder;
    final json = await _client.patch('/tasks/subtasks/$subtaskId', changes) as Map<String, dynamic>;
    return Subtask.fromJson(json);
  }

  /// Delete a subtask.
  Future<void> delete(int subtaskId) async {
    await _client.delete('/tasks/subtasks/$subtaskId');
  }
}
