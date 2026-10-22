import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rules.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/shared/error_state.dart';
import '../widgets/tasks/task_list.dart';

/// Scoped task list. Admins pick any project; others see their own project
/// and do not wait on the projects stream at all.
class TasksTab extends ConsumerStatefulWidget {
  const TasksTab({super.key});

  @override
  ConsumerState<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends ConsumerState<TasksTab> {
  int? _selectedProjectId;

  @override
  Widget build(BuildContext context) {
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
        if (!isAdmin(user.role)) {
          return _content(context, user, adminProjects: null);
        }
        final projects = ref.watch(projectsProvider);
        return projects.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Could not load projects: $e',
            onRetry: () => ref.invalidate(projectsProvider),
          ),
          data: (list) => _content(context, user, adminProjects: list),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    Account user, {
    required List<Project>? adminProjects,
  }) {
    int? effective;
    if (adminProjects != null) {
      effective =
          _selectedProjectId ??
          (adminProjects.isEmpty ? null : adminProjects.first.id);
    } else {
      effective = user.projectId;
    }
    return Column(
      children: [
        if (adminProjects != null && adminProjects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Project',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              initialValue: effective,
              items: [
                for (final p in adminProjects)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _selectedProjectId = v),
            ),
          ),
        Expanded(
          child: effective == null
              ? const Center(child: Text('No project available.'))
              : TaskList(
                  tasksProvider: projectTasksProvider(effective),
                  projectId: effective,
                ),
        ),
      ],
    );
  }
}
