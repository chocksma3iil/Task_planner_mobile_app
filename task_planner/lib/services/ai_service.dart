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

  /// Local generation can take a minute on CPU; the normal 15 s is too short.
  static const _timeout = Duration(seconds: 200);

  /// Propose a weekly plan for [projectId].
  Future<AiWeeklyPlanProposal> weeklyPlan(int projectId) async {
    final json = await _client.postSlow(
      '/ai/weekly-plan?project_id=$projectId',
      null,
      _timeout,
    ) as Map<String, dynamic>;
    return AiWeeklyPlanProposal.fromJson(json);
  }

  /// Propose subtasks to decompose [taskId].
  Future<AiDecomposeProposal> decompose(int taskId) async {
    final json = await _client.postSlow(
      '/ai/decompose?task_id=$taskId',
      null,
      _timeout,
    ) as Map<String, dynamic>;
    return AiDecomposeProposal.fromJson(json);
  }

  /// Propose a natural-language briefing for [projectId].
  Future<AiBriefingProposal> briefing(int projectId) async {
    final json = await _client.postSlow(
      '/ai/briefing?project_id=$projectId',
      null,
      _timeout,
    ) as Map<String, dynamic>;
    return AiBriefingProposal.fromJson(json);
  }

  /// Propose a task from natural-language [text] for [projectId].
  Future<AiCaptureProposal> capture(int projectId, String text) async {
    final json = await _client.postSlow(
      '/ai/capture',
      {'project_id': projectId, 'text': text},
      _timeout,
    ) as Map<String, dynamic>;
    return AiCaptureProposal.fromJson(json);
  }
}
