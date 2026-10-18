import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../../../core/error_state.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/session_providers.dart';
import 'providers.dart';

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
        final scheme = Theme.of(context).colorScheme;
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
            onPressed: () => _createDialog(context, ref, user),
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
                return _emptyState(context, scheme);
              }
              final byId = {
                for (final m in memberList ?? const <Assignee>[]) m.id: m,
              };
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(projectsProvider);
                  try {
                    await ref
                        .read(projectsProvider.future)
                        .timeout(const Duration(seconds: 3));
                  } on TimeoutException {
                    // Stream keeps updating in the background.
                  }
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _card(
                    context,
                    ref,
                    user,
                    list[i],
                    byId,
                    membersReady: memberList != null,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'No projects yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to create one',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    Assignee admin,
    Project project,
    Map<int, Assignee> byId, {
    required bool membersReady,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final owner = project.ownerId == null ? null : byId[project.ownerId];
    final active = project.status == 'active';
    final statusColor = active ? scheme.primary : scheme.outline;
    final ownerText = !membersReady
        ? 'Loading…'
        : (owner?.name ?? 'No owner yet');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (project.description != null &&
                          project.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            project.description!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    project.status,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: owner == null
                      ? scheme.surfaceContainerHighest
                      : scheme.secondaryContainer,
                  foregroundColor:
                      owner == null ? scheme.outline : scheme.onSecondaryContainer,
                  child: owner == null
                      ? const Icon(Icons.person_outline, size: 16)
                      : Text(
                          initialsOf(owner.name),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ownerText,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Owner',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _ownerMenu(context, ref, admin, project, byId,
                    membersReady: membersReady),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownerMenu(
    BuildContext context,
    WidgetRef ref,
    Assignee admin,
    Project project,
    Map<int, Assignee> byId, {
    required bool membersReady,
  }) {
    return PopupMenuButton<int>(
      tooltip: 'Assign owner',
      icon: const Icon(Icons.more_vert),
      onSelected: (id) async {
        try {
          await ref.read(projectServiceProvider).assignOwner(
                actor: admin,
                projectId: project.id,
                ownerId: id,
              );
        } on StateError catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      },
      itemBuilder: (context) {
        if (!membersReady) {
          return [
            const PopupMenuItem<int>(
              enabled: false,
              child: Text('Loading members…'),
            ),
          ];
        }
        final candidates =
            byId.values.where((m) => m.status == 'active').toList();
        return [
          const PopupMenuItem<int>(
            enabled: false,
            child: Text(
              'Assign owner',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final c in candidates)
            PopupMenuItem<int>(
              value: c.id,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                    child: Text(
                      initialsOf(c.name),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (project.ownerId == c.id)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ];
      },
    );
  }

  Future<void> _createDialog(
      BuildContext context, WidgetRef ref, Assignee admin) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created == true && context.mounted) {
      try {
        await ref.read(projectServiceProvider).createProject(
              actor: admin,
              name: name.text.trim(),
              description: description.text.trim().isEmpty
                  ? null
                  : description.text.trim(),
            );
      } on StateError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    name.dispose();
    description.dispose();
  }
}
