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
import '../widgets/ai/ai_dialogs.dart';

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

enum _AiAction { weeklyPlan, briefing, capture, toggleAi }

class _PlannerTabState extends ConsumerState<PlannerTab> {
  int? _selectedProjectId;
  String _query = '';
  bool _aiBusy = false;

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
    final projectList =
        ref.watch(projectListProvider).value?.items ?? const <Project>[];
    Project? currentProject;
    for (final project in projectList) {
      if (project.id == projectId) {
        currentProject = project;
        break;
      }
    }
    final aiEnabled = currentProject?.aiOptIn;
    final canManageAi = isAdmin(user.role) ||
        (isOwnerOrAdmin(user.role) && currentProject?.ownerId == user.id);
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
                            icon: _aiBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 18),
                            label: Text(
                              _aiBusy
                                  ? 'Asking the local AI model…'
                                  : 'AI actions',
                            ),
                            onPressed: _aiBusy
                                ? null
                                : () => _openAiSheet(
                                      context,
                                      projectId: projectId,
                                      project: currentProject,
                                      aiEnabled: aiEnabled,
                                      canManageAi: canManageAi,
                                    ),
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

  Future<void> _openAiSheet(
    BuildContext context, {
    required int projectId,
    required Project? project,
    required bool? aiEnabled,
    required bool canManageAi,
  }) async {
    final action = await showModalBottomSheet<_AiAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'AI actions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Weekly plan'),
              subtitle: const Text('Propose tasks for the coming week'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_AiAction.weeklyPlan),
            ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Project briefing'),
              subtitle: const Text('Summarise the current state'),
              onTap: () => Navigator.of(sheetContext).pop(_AiAction.briefing),
            ),
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Create a task from text'),
              subtitle: const Text('Turn a sentence into a task'),
              onTap: () => Navigator.of(sheetContext).pop(_AiAction.capture),
            ),
            if (canManageAi) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  aiEnabled == true
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                ),
                title: Text(
                  aiEnabled == true ? 'Disable AI' : 'Enable AI',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  aiEnabled == true
                      ? 'Stop using AI for this project'
                      : 'Allow AI proposals for this project',
                ),
                onTap: () => Navigator.of(sheetContext).pop(_AiAction.toggleAi),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }

    if (action == _AiAction.toggleAi) {
      await _setAi(context, projectId: projectId, enabled: aiEnabled != true);
      return;
    }

    final allowed = await _ensureAiEnabled(
      context,
      projectId: projectId,
      project: project,
      aiEnabled: aiEnabled,
      canManageAi: canManageAi,
    );
    if (!allowed || !context.mounted) {
      return;
    }

    switch (action) {
      case _AiAction.weeklyPlan:
        await _proposeWeeklyPlan(context, projectId);
        break;
      case _AiAction.briefing:
        await _showBriefing(context, projectId);
        break;
      case _AiAction.capture:
        await _captureTask(context, projectId);
        break;
      case _AiAction.toggleAi:
        break; // handled above
    }
  }

  Future<bool> _ensureAiEnabled(
    BuildContext context, {
    required int projectId,
    required Project? project,
    required bool? aiEnabled,
    required bool canManageAi,
  }) async {
    if (aiEnabled != false) {
      return true;
    }
    final name = project?.name ?? 'this project';
    if (canManageAi) {
      final enable = await showEnableAiDialog(context, name);
      if (!enable) {
        return false;
      }
      return _setAi(context, projectId: projectId, enabled: true);
    }
    if (context.mounted) {
      showAppSnackBar(
        context,
        'AI is disabled for this project. Ask an admin or the project '
        'owner to enable it.',
      );
    }
    return false;
  }

  Future<bool> _setAi(
    BuildContext context, {
    required int projectId,
    required bool enabled,
  }) async {
    try {
      await ref
          .read(projectServiceProvider)
          .setAiOptIn(projectId: projectId, enabled: enabled);
      await ref.read(projectListProvider.notifier).refresh();
      if (context.mounted) {
        showAppSnackBar(
          context,
          enabled ? 'AI enabled for this project.' : 'AI disabled.',
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
      return false;
    }
  }

  /// Runs a slow AI call behind the busy state and surfaces API errors.
  Future<T?> _runAi<T>(
    BuildContext context,
    Future<T> Function() run,
  ) async {
    setState(() => _aiBusy = true);
    try {
      return await run();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _aiBusy = false);
      }
    }
  }

  Future<void> _proposeWeeklyPlan(BuildContext context, int projectId) async {
    final proposal = await _runAi(
      context,
      () => ref.read(aiServiceProvider).weeklyPlan(projectId),
    );
    if (proposal == null || !context.mounted) {
      return;
    }
    final selected = await showWeeklyPlanDialog(context, proposal);
    if (selected == null || selected.isEmpty || !context.mounted) {
      return;
    }
    try {
      for (final task in selected) {
        await ref.read(taskServiceProvider).createTask(
              projectId: projectId,
              title: task.title,
              description: task.description,
              priority: task.priority,
              dueDate:
                  task.dueDate == null ? null : DateTime.tryParse(task.dueDate!),
            );
      }
      await ref.read(projectTasksProvider(projectId).notifier).refresh();
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Created ${selected.length} task(s) from the AI plan.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _showBriefing(BuildContext context, int projectId) async {
    final proposal = await _runAi(
      context,
      () => ref.read(aiServiceProvider).briefing(projectId),
    );
    if (proposal != null && context.mounted) {
      await showBriefingDialog(context, proposal);
    }
  }

  Future<void> _captureTask(BuildContext context, int projectId) async {
    final text = await showCaptureInputDialog(context);
    if (text == null || text.trim().isEmpty || !context.mounted) {
      return;
    }
    final proposal = await _runAi(
      context,
      () => ref.read(aiServiceProvider).capture(projectId, text),
    );
    if (proposal == null || !context.mounted) {
      return;
    }
    final approved = await showCaptureProposalDialog(context, proposal);
    if (!approved) {
      return;
    }
    try {
      await ref.read(taskServiceProvider).createTask(
            projectId: projectId,
            title: proposal.title,
            description: proposal.description,
            priority: proposal.priority,
            dueDate: proposal.dueDate == null
                ? null
                : DateTime.tryParse(proposal.dueDate!),
          );
      await ref.read(projectTasksProvider(projectId).notifier).refresh();
      if (context.mounted) {
        showAppSnackBar(context, 'Task created from the AI proposal.');
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}
