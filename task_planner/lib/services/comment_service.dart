/// Comment operations against the API.
import '../models/models.dart';
import '../services/api_client.dart';

class CommentService {
  CommentService(this._client);

  final ApiClient _client;

  /// List all comments of a task.
  Future<List<Comment>> list(int taskId) async {
    final json = await _client.get('/tasks/$taskId/comments') as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a comment on a task.
  Future<Comment> create({
    required int taskId,
    required String body,
    int? parentId,
  }) async {
    final json = await _client.post('/tasks/$taskId/comments', {
      'task_id': taskId,
      'body': body,
      'parent_id': parentId,
    }) as Map<String, dynamic>;
    return Comment.fromJson(json);
  }

  /// Update a comment (body only).
  Future<Comment> update({
    required int commentId,
    required String body,
  }) async {
    final json = await _client.patch('/comments/$commentId', {
      'body': body,
    }) as Map<String, dynamic>;
    return Comment.fromJson(json);
  }

  /// Delete a comment (soft delete).
  Future<void> delete(int commentId) async {
    await _client.delete('/comments/$commentId');
  }
}