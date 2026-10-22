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
class ProjectsTab extends ConsumerWidget {
  const ProjectsTab({super.key});

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
        final projects = ref.watch(projectsProvider);
        final membersAsync = ref.watch(visibleMembersProvider);
        // null means "not ready yet" — distinct from a genuinely empty list.
        final memberList = membersAsync.when(
          data: (list) => list,
          loading: () => null,
          error: (_, _) => null,
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            tooltip: 'Create project',
            onPressed: () => _createDialog(context, ref),
            child: const Icon(Icons.add),
          ),
          body: projects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(
              message: 'Could not load projects: $e',
              onRetry: () => ref.invalidate(projectsProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.folder_open,
                  title: 'No projects yet',
                  hint: 'Tap + to create one',
                );
              }
              final byId = {
                for (final m in memberList ?? const <Account>[]) m.id: m,
              };
              final candidates = byId.values
                  .where((m) => m.status == 'active')
                  .toList(growable: false);
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(projectsProvider);
                  try {
                    await ref
                        .read(projectsProvider.future)
                        .timeout(const Duration(seconds: 3));
                  } on TimeoutException {
                    // The stream keeps updating in the background.
                  }
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
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
                    );
                  },
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
