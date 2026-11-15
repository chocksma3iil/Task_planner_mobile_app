import '../models/models.dart';
import 'api_client.dart';

/// Read-only access to the admin audit trail (D06).
///
/// The server restricts the endpoint to admins; this service only transports
/// the query and parses the page.
class AuditService {
  AuditService(this._client);

  final ApiClient _client;

  /// One page of audit entries, newest first, optionally scoped to a single
  /// project when [projectId] is given.
  Future<AuditLogList> fetchPage({
    int? projectId,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = StringBuffer('/audit-logs?limit=$limit&offset=$offset');
    if (projectId != null) {
      query.write('&project_id=$projectId');
    }
    final json = await _client.get(query.toString()) as Map<String, dynamic>;
    return AuditLogList.fromJson(json);
  }
}
