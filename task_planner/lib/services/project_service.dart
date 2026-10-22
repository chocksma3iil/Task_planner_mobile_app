import '../models/models.dart';
import 'api_client.dart';
import 'data_sync.dart';

/// Project management against the API. Only admins create projects and
/// assign owners (server-enforced from the session token).
class ProjectService {
  ProjectService(this._client);

  final ApiClient _client;

  Future<Project> createProject({
    required String name,
    String? description,
  }) async {
    final json = await _client.post('/projects', {
      'name': name,
      'description': ?description,
    });
    DataSync.instance.ping();
    return Project.fromJson(json as Map<String, dynamic>);
  }

  Future<Project> assignOwner({
    required int projectId,
    required int ownerId,
  }) async {
    final json = await _client.post('/projects/$projectId/assign-owner', {
      'owner_id': ownerId,
    });
    DataSync.instance.ping();
    return Project.fromJson(json as Map<String, dynamic>);
  }

  /// All projects, sorted by name. The API list is public so the sign-up
  /// screen can offer projects before login.
  Stream<List<Project>> watchProjects() {
    return watchFromApi(() async {
      final json = await _client.get('/projects') as List<dynamic>;
      return json
          .map((row) => Project.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
    });
  }
}
