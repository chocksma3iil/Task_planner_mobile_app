import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_tokens.dart';
import '../core/rules.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/shared/app_snackbar.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';
import '../widgets/shared/search_field.dart';
import '../widgets/shared/section_header.dart';
import '../widgets/tasks/task_tile.dart';
import '../widgets/tasks/task_form_dialog.dart';
import '../widgets/tasks/comment_sheet.dart';

/// Planner view: groups tasks by urgency (overdue, today, upcoming, no due
/// date, completed) across the user's visible scope.
///
/// Admins pick a project first; others see their own project's tasks.
///
/// Flat design: no elevation, no shadows, no gradients. Surface colors come
/// from the semantic theme tokens.
class PlannerTab extends ConsumerStatefulWidget {
  const PlannerTab({super.key});

  @override
  ConsumerState<PlannerTab> createState() => _PlannerTabState();
}

class _PlannerTabState extends ConsumerState<PlannerTab> {
  int? _selectedProjectId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: ErrorState(
          message: 'Could not load account: $e',
          onRetry: () => ref.invalidate(currentUserProvider),
        ),
      ),
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('Logged out.')));
        }

        final isAdminUser = isAdmin(user.role);

        if (isAdminUser) {
          return _buildAdminPlanner(context, user);
        }

        if (user.projectId == null) {
          return const Scaffold(
            body: Center(child: Text('No project assigned.')),
          );
        }
        return _buildPlannerBody(
          context,
          user,
          projectId: user.projectId!,
        );
      },
    );
  }

  Widget _buildAdminPlanner(BuildContext context, Account user) {
    final projectsAsync = ref.watch(projectListProvider);

    return projectsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: ErrorState(
          message: 'Could not load projects: $e',
          onRetry: () => ref.invalidate(projectListProvider),
        ),
      ),
      data: (projectsPaginated) {
        final projects = projectsPaginated.items;
        if (projects.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No projects available.')),
          );
        }
        final selectedId = _selectedProjectId ?? projects.first.id;
        return _buildPlannerBody(
          context,
          user,
          projectId: selectedId,
          allProjects: projects,
          isAdminUser: true,
        );
      },
    );
  }

  Widget _buildPlannerBody(
    BuildContext context,
    Account user, {
    required int projectId,
    List<Project>? allProjects,
    bool isAdminUser = false,
  }) {
    final tasksAsync = ref.watch(projectTasksProvider(projectId));
    final canMutate = !isViewer(user.role);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: canMutate
          ? FloatingActionButton(
              tooltip: 'Add task',
              onPressed: () => _openForm(context, projectId),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.read(projectTasksProvider(projectId).notifier).refresh(),
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Could not load tasks: $e',
            onRetry: () async =>
                ref.read(projectTasksProvider(projectId).notifier).refresh(),
          ),
          data: (paginated) {
            final list = paginated.items;
            final searched = _query.isEmpty
                ? list
                : list
                    .where(
                      (t) =>
                          t.title.toLowerCase().contains(_query) ||
                          (t.description?.toLowerCase().contains(_query) ??
                              false),
                    )
                    .toList();
            final now = DateTime.now();
            final overdue = <Task>[];
            final today = <Task>[];
            final upcoming = <Task>[];
            final noDate = <Task>[];
            final completed = <Task>[];
            for (final t in searched) {
              if (t.status == TaskStatus.completed) {
                completed.add(t);
              } else if (t.dueDate == null) {
                noDate.add(t);
              } else if (isOverdue(
                status: t.status,
                dueDate: t.dueDate,
                now: now,
              )) {
                overdue.add(t);
              } else if (isDueToday(
                status: t.status,
                dueDate: t.dueDate,
                now: now,
              )) {
                today.add(t);
              } else {
                upcoming.add(t);
              }
            }

            final hasContent =
                overdue.isNotEmpty ||
                today.isNotEmpty ||
                upcoming.isNotEmpty ||
                noDate.isNotEmpty ||
                completed.isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Project picker (admin only).
                if (isAdminUser &&
                    allProjects != null &&
                    allProjects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      spaceM, spaceL, spaceM, spaceXs,
                    ),
                    child: DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Project',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                      value: projectId,
                      items: [
                        for (final p in allProjects)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedProjectId = v);
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    spaceM, spaceS, spaceM, spaceXs,
                  ),
                  child: DebouncedSearchField(
                    hintText: 'Search tasks',
                    onChanged: (query) =>
                        setState(() => _query = query),
                  ),
                ),
                if (canMutate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      spaceM, spaceS, spaceM, spaceXs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Propose weekly plan (AI)'),
                            onPressed: () =>
                                _proposeWeeklyPlan(context, projectId),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: !hasContent
                      ? const EmptyState(
                          scrollable: true,
                          icon: Icons.checklist_rounded,
                          title: 'No tasks here',
                          hint: 'Tap + to add one',
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollEndNotification &&
                                notification.metrics.pixels >=
                                    notification.metrics.maxScrollExtent -
                                        200 &&
                                paginated.hasMore &&
                                !paginated.isLoadingMore) {
                              ref
                                  .read(
                                    projectTasksProvider(projectId).notifier,
                                  )
                                  .loadMore();
                            }
                            return false;
                          },
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              spaceM, spaceS, spaceM, spaceXL,
                            ),
                            children: [
                              if (overdue.isNotEmpty) ...[
                                const SectionHeader('Overdue'),
                                for (final t in overdue) ...[
                                  _taskRow(context, t, canMutate: canMutate),
                                  const SizedBox(height: spaceS),
                                ],
                              ],
                              if (today.isNotEmpty) ...[
                                const SectionHeader('Today'),
                                for (final t in today) ...[
                                  _taskRow(context, t, canMutate: canMutate),
                                  const SizedBox(height: spaceS),
                                ],
                              ],
                              if (upcoming.isNotEmpty) ...[
                                const SectionHeader('Upcoming'),
                                for (final t in upcoming) ...[
                                  _taskRow(context, t, canMutate: canMutate),
                                  const SizedBox(height: spaceS),
                                ],
                              ],
                              if (noDate.isNotEmpty) ...[
                                const SectionHeader('No due date'),
                                for (final t in noDate) ...[
                                  _taskRow(context, t, canMutate: canMutate),
                                  const SizedBox(height: spaceS),
                                ],
                              ],
                              if (completed.isNotEmpty) ...[
                                const SectionHeader('Completed'),
                                for (final t in completed) ...[
                                  _taskRow(context, t, canMutate: canMutate),
                                  const SizedBox(height: spaceS),
                                ],
                              ],
                              if (paginated.hasMore)
                                const Padding(
                                  padding: EdgeInsets.all(spaceL),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, Task task, {required bool canMutate}) {
    return TaskTile(
      task: task,
      assigneeLabel: task.assigneeId == null
          ? 'Whole project'
          : 'Assigned member',
      onToggle: () => _toggle(task),
      onDelete: () => _delete(task),
      onSwipe: (_) async => false,
      onTap: () => _openEdit(context, task),
      canMutate: canMutate,
    );
  }

  Future<void> _openForm(BuildContext context, int projectId) async {
    final membersState = ref.read(visibleMembersProvider);
    if (!membersState.hasValue) {
      return;
    }
    final members = membersState.value!.items
        .where((m) => m.projectId == projectId)
        .toList(growable: false);
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskFormDialog(members: members),
    );
    if (draft == null || !context.mounted) {
      return;
    }
    try {
      await ref.read(taskServiceProvider).createTask(
            projectId: projectId,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueDate: draft.dueDate,
            assigneeId: draft.assigneeId,
          );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _openEdit(BuildContext context, Task task) async {
    final membersState = ref.read(visibleMembersProvider);
    if (!membersState.hasValue) {
      return;
    }
    final members = membersState.value!.items
        .where((m) => m.projectId == task.projectId)
        .toList(growable: false);
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskFormDialog(
        members: members,
        initial: task,
      ),
    );
    if (draft == null || !context.mounted) {
      return;
    }
    try {
      await ref.read(taskServiceProvider).updateTask(
            taskId: task.id,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueDate: draft.dueDate,
            assigneeId: draft.assigneeId,
          );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _toggle(Task task) async {
    final service = ref.read(taskServiceProvider);
    try {
      if (task.status == TaskStatus.completed) {
        await service.reopenTask(taskId: task.id);
      } else {
        await service.completeTask(taskId: task.id);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _delete(Task task) async {
    final service = ref.read(taskServiceProvider);
    try {
      await service.deleteTask(taskId: task.id);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _proposeWeeklyPlan(BuildContext context, int projectId) async {
    try {
      await ref.read(aiServiceProvider).weeklyPlan(projectId);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}
