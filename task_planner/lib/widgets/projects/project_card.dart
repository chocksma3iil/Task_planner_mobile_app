import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../models/models.dart';

/// One project card with its owner and the admin owner-assignment menu.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.owner,
    required this.membersReady,
    required this.candidates,
    required this.onAssignOwner,
  });

  final Project project;
  final Account? owner;
  final bool membersReady;
  final List<Account> candidates;
  final ValueChanged<int> onAssignOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
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
                  foregroundColor: owner == null
                      ? scheme.outline
                      : scheme.onSecondaryContainer,
                  child: owner == null
                      ? const Icon(Icons.person_outline, size: 16)
                      : Text(
                          initialsOf(owner!.name),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
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
                _ownerMenu(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownerMenu(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Assign owner',
      icon: const Icon(Icons.more_vert),
      onSelected: onAssignOwner,
      itemBuilder: (context) {
        if (!membersReady) {
          return const [
            PopupMenuItem<int>(enabled: false, child: Text('Loading members…')),
          ];
        }
        return [
          const PopupMenuItem<int>(
            enabled: false,
            child: Text(
              'Assign owner',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final candidate in candidates)
            PopupMenuItem<int>(
              value: candidate.id,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    foregroundColor: Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer,
                    child: Text(
                      initialsOf(candidate.name),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      candidate.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (project.ownerId == candidate.id)
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
}
