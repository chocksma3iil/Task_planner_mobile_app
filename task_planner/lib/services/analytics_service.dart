/// Analytics operations against the API.
import '../models/models.dart';
import '../services/api_client.dart';

class AnalyticsService {
  AnalyticsService(this._client);

  final ApiClient _client;

  /// Dashboard metrics for one project.
  Future<DashboardStats> getDashboard(int projectId) async {
    final json = await _client.get(
      '/analytics/dashboard?project_id=$projectId',
    ) as Map<String, dynamic>;
    return DashboardStats.fromJson(json);
  }
}
