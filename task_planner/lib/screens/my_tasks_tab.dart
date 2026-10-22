import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/shared/error_state.dart';
import '../widgets/tasks/task_list.dart';

/// Tasks assigned to the logged-in person (owner or user; admins are never
/// assignees, so they do not see this tab).
class MyTasksTab extends ConsumerWidget {
  const MyTasksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentUserProvider);
    return account.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Could not load account: $e',
        onRetry: () => ref.invalidate(currentUserProvider),
      ),
      data: (user) {
        if (user == null) {
          return const Center(child: Text('Logged out.'));
        }
        if (user.projectId == null) {
          return const Center(child: Text('No project assigned.'));
        }
        return TaskList(
          tasksProvider: myTasksProvider(user.id),
          projectId: user.projectId,
        );
      },
    );
  }
}
