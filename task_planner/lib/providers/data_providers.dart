import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/member_service.dart';
import '../services/project_service.dart';
import '../services/task_service.dart';
import 'api_providers.dart';
import 'session_providers.dart';

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

/// Public project list for the sign-up picker and add-member dialog.
///
/// `GET /projects` is intentionally public, so this provider is not tied to a
/// session and can be read while logged out.
final publicProjectsProvider = StreamProvider.autoDispose<List<Project>>(
  (ref) => ref.watch(projectServiceProvider).watchProjects(),
);

/// Projects for authenticated tabs. Cleared and refetched whenever the
/// session changes so data from a previous account is never reused.
final projectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  if (ref.watch(sessionUserIdProvider) == null) {
    return Stream.value(const <Project>[]);
  }
  return ref.watch(projectServiceProvider).watchProjects();
});

final projectTasksProvider = StreamProvider.autoDispose.family<List<Task>, int>(
  (ref, projectId) {
    if (ref.watch(sessionUserIdProvider) == null) {
      return Stream.value(const <Task>[]);
    }
    return ref.watch(taskServiceProvider).watchProjectTasks(projectId);
  },
);

/// Tasks assigned to the logged-in person (the "Mine" tab).
final myTasksProvider = StreamProvider.autoDispose.family<List<Task>, int>((
  ref,
  assigneeId,
) {
  if (ref.watch(sessionUserIdProvider) == null) {
    return Stream.value(const <Task>[]);
  }
  return ref.watch(taskServiceProvider).watchTasksAssignedTo(assigneeId);
});

/// Members visible to the caller (server-scoped by role and project). Cleared
/// on logout so a previous account's roster is never shown to the next one.
final visibleMembersProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  if (ref.watch(sessionUserIdProvider) == null) {
    return Stream.value(const <Account>[]);
  }
  return ref.watch(memberServiceProvider).watchVisibleMembers();
});
