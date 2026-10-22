import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/member_service.dart';
import '../services/project_service.dart';
import '../services/task_service.dart';
import 'api_providers.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

final taskServiceProvider = Provider<TaskService>(
  (ref) => TaskService(ref.watch(apiClientProvider)),
);

final memberServiceProvider = Provider<MemberService>(
  (ref) => MemberService(ref.watch(apiClientProvider)),
);

final projectServiceProvider = Provider<ProjectService>(
  (ref) => ProjectService(ref.watch(apiClientProvider)),
);

final projectsProvider = StreamProvider<List<Project>>(
  (ref) => ref.watch(projectServiceProvider).watchProjects(),
);

final projectTasksProvider = StreamProvider.family<List<Task>, int>((
  ref,
  projectId,
) {
  return ref.watch(taskServiceProvider).watchProjectTasks(projectId);
});

/// Tasks assigned to the logged-in person (the "Mine" tab).
final myTasksProvider = StreamProvider.family<List<Task>, int>((
  ref,
  assigneeId,
) {
  return ref.watch(taskServiceProvider).watchTasksAssignedTo(assigneeId);
});

/// Members visible to the caller (server-scoped by role and project).
final visibleMembersProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(memberServiceProvider).watchVisibleMembers(),
);
