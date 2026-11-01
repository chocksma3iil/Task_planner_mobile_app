/// AI operations against the API (v2.0).
///
/// All methods return *proposals only*. Nothing is written to the database
/// by this layer — the UI must obtain human approval before persisting.
import '../models/ai_proposal.dart';
import '../models/models.dart';
import 'api_client.dart';

class AiService {
  AiService(this._client);

  final ApiClient _client;

  /// Propose a weekly plan for [projectId].
  Future<AiWeeklyPlanProposal> weeklyPlan(int projectId) async {
    final json = await _client.post(
      '/ai/weekly-plan?project_id=$projectId',
    ) as Map<String, dynamic>;
    return AiWeeklyPlanProposal.fromJson(json);
  }

  /// Propose subtasks to decompose [taskId].
  Future<AiDecomposeProposal> decompose(int taskId) async {
    final json = await _client.post(
      '/ai/decompose?task_id=$taskId',
    ) as Map<String, dynamic>;
    return AiDecomposeProposal.fromJson(json);
  }

  /// Propose a natural-language briefing for [projectId].
  Future<AiBriefingProposal> briefing(int projectId) async {
    final json = await _client.post(
      '/ai/briefing?project_id=$projectId',
    ) as Map<String, dynamic>;
    return AiBriefingProposal.fromJson(json);
  }

  /// Propose a task from natural-language [text] for [projectId].
  Future<AiCaptureProposal> capture(int projectId, String text) async {
    final json = await _client.post(
      '/ai/capture',
      {'project_id': projectId, 'text': text},
    ) as Map<String, dynamic>;
    return AiCaptureProposal.fromJson(json);
  }
}
