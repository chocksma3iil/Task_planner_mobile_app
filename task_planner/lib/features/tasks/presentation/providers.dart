import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../application/member_service.dart';
import '../application/project_service.dart';
import '../application/task_service.dart';
import '../../auth/presentation/session_providers.dart';

final taskServiceProvider = Provider<TaskService>(
  (ref) => TaskService(ref.watch(databaseProvider)),
);

final memberServiceProvider = Provider<MemberService>(
  (ref) => MemberService(ref.watch(databaseProvider)),
);

final projectServiceProvider = Provider<ProjectService>(
  (ref) => ProjectService(ref.watch(databaseProvider)),
);

final projectsProvider = StreamProvider<List<Project>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.projects)
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();
});

final projectTasksProvider =
    StreamProvider.family<List<Task>, int>((ref, projectId) {
  return ref.watch(taskServiceProvider).watchProjectTasks(projectId);
});

/// Tasks assigned to the logged-in person (the "Mine" tab).
final myTasksProvider =
    StreamProvider.family<List<Task>, int>((ref, assigneeId) {
  return ref.watch(taskServiceProvider).watchTasksAssignedTo(assigneeId);
});

/// Members the logged-in user may see.
///
/// Never collapses the account-loading state into an empty list: while the
/// account row is still loading this provider stays loading, and account
/// errors propagate to the screens (which show retry states).
final visibleMembersProvider = StreamProvider<List<Assignee>>((ref) {
  final account = ref.watch(currentUserProvider);
  return account.when(
    data: (user) => user == null
        ? Stream.value(const <Assignee>[])
        : ref.read(memberServiceProvider).watchVisibleMembers(user),
    loading: () => Stream<List<Assignee>>.empty(),
    error: (e, _) => Stream<List<Assignee>>.error(e),
  );
});
