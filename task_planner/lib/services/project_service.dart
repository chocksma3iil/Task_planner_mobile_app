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

  Future<Project> archiveProject({required int projectId}) async {
    final json = await _client.patch('/projects/$projectId/archive');
    DataSync.instance.ping();
    return Project.fromJson(json as Map<String, dynamic>);
  }

  Future<Project> restoreProject({required int projectId}) async {
    final json = await _client.patch('/projects/$projectId/restore');
    DataSync.instance.ping();
    return Project.fromJson(json as Map<String, dynamic>);
  }

  /// Enable or disable AI for a project (admin or project owner).
  Future<Project> setAiOptIn({
    required int projectId,
    required bool enabled,
  }) async {
    final json = await _client.patch('/projects/$projectId/ai-opt-in', {
      'ai_opt_in': enabled,
    });
    DataSync.instance.ping();
    return Project.fromJson(json as Map<String, dynamic>);
  }

  /// One page of projects, sorted by name. The API list is public so the
  /// sign-up screen can offer projects before login. Set [includeArchived]
  /// to also return archived projects.
  Future<ProjectList> fetchProjects({
    int limit = 20,
    int offset = 0,
    bool includeArchived = true,
  }) async {
    final json = await _client.get(
      '/projects?limit=$limit&offset=$offset'
      '${includeArchived ? '&include_archived=true' : ''}',
    ) as Map<String, dynamic>;
    return ProjectList.fromJson(json);
  }

  /// All projects, refreshed after every mutation. Kept for callers that only
  /// need the first page as a stream.
  Stream<ProjectList> watchProjects({
    int page = 1,
    int pageSize = 20,
    bool includeArchived = true,
  }) {
    final offset = (page - 1) * pageSize;
    return watchFromApi(
      () => fetchProjects(
        limit: pageSize,
        offset: offset,
        includeArchived: includeArchived,
      ),
    );
  }
}
