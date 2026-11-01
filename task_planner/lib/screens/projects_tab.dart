import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/projects/create_project_dialog.dart';
import '../widgets/projects/project_card.dart';
import '../widgets/shared/app_snackbar.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';

/// Admin-only project management: create projects and assign owners.
class ProjectsTab extends ConsumerStatefulWidget {
  const ProjectsTab({super.key});

  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab> {
  final _scrollController = ScrollController();
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  bool get _isLoadingMore {
    final state = ref.read(projectListProvider);
    return state.hasValue && state.value!.isLoadingMore;
  }

  Future<void> _loadMore() async {
    await ref.read(projectListProvider.notifier).loadMore();
  }

  Future<void> _refresh() async {
    await ref.read(projectListProvider.notifier).refresh();
  }

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
        final projectsState = ref.watch(
          projectListProvider,
        );
        final membersAsync = ref.watch(visibleMembersProvider);
        // null means "not ready yet" — distinct from a genuinely empty list.
        final memberList = membersAsync.when(
          data: (paginated) => paginated.items,
          loading: () => null,
          error: (_, _) => null,
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(_showArchived ? 'Archived Projects' : 'Projects'),
            actions: [
              IconButton(
                tooltip: _showArchived ? 'Show active' : 'Show archived',
                icon: Icon(
                  _showArchived
                      ? Icons.restore_from_trash
                      : Icons.archive,
                ),
                onPressed: () => setState(() => _showArchived = !_showArchived),
              ),
            ],
          ),
          floatingActionButton: _showArchived
              ? null
              : FloatingActionButton(
                  tooltip: 'Create project',
                  onPressed: () => _createDialog(context, ref),
                  child: const Icon(Icons.add),
                ),
          body: projectsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(
              message: 'Could not load projects: $e',
              onRetry: _refresh,
            ),
            data: (paginated) {
              final list = paginated.items
                  .where((p) =>
                      _showArchived ? p.status == 'archived' : p.status != 'archived')
                  .toList(growable: false);
              if (list.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: EmptyState(
                    scrollable: true,
                    icon: Icons.folder_open,
                    title: _showArchived
                        ? 'No archived projects'
                        : 'No projects yet',
                    hint: _showArchived
                        ? 'Archive a project to see it here'
                        : 'Tap + to create one',
                  ),
                );
              }
              final byId = {
                for (final m in memberList ?? const <Account>[]) m.id: m,
              };
              final candidates = byId.values
                  .where((m) => m.status == 'active')
                  .toList(growable: false);
              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollEndNotification &&
                      notification.metrics.pixels >=
                          notification.metrics.maxScrollExtent - 200 &&
                      !paginated.isLoadingMore &&
                      paginated.hasMore) {
                    _loadMore();
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    itemCount: list.length + (paginated.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == list.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final project = list[i];
                      final owner = project.ownerId == null
                          ? null
                          : byId[project.ownerId];
                      return ProjectCard(
                        project: project,
                        owner: owner,
                        membersReady: memberList != null,
                        candidates: candidates,
                        onAssignOwner: (ownerId) =>
                            _assignOwner(context, ref, project, ownerId),
                        onArchive: project.status == 'active'
                            ? () => _archiveProject(context, ref, project.id)
                            : null,
                        onRestore: project.status == 'archived'
                            ? () => _restoreProject(context, ref, project.id)
                            : null,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _assignOwner(
    BuildContext context,
    WidgetRef ref,
    Project project,
    int ownerId,
  ) async {
    try {
      await ref
          .read(projectServiceProvider)
          .assignOwner(projectId: project.id, ownerId: ownerId);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _archiveProject(
    BuildContext context,
    WidgetRef ref,
    int projectId,
  ) async {
    try {
      await ref.read(projectServiceProvider).archiveProject(projectId: projectId);
      if (context.mounted) {
        showAppSnackBar(context, 'Project archived');
      }
      // The service pings DataSync, so the paginated feed reloads page one.
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _restoreProject(
    BuildContext context,
    WidgetRef ref,
    int projectId,
  ) async {
    try {
      await ref.read(projectServiceProvider).restoreProject(projectId: projectId);
      if (context.mounted) {
        showAppSnackBar(context, 'Project restored');
      }
      // The service pings DataSync, so the paginated feed reloads page one.
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<ProjectDraft>(
      context: context,
      builder: (_) => const CreateProjectDialog(),
    );
    if (draft == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(projectServiceProvider)
          .createProject(name: draft.name, description: draft.description);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}