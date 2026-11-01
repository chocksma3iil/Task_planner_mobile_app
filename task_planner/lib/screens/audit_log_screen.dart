import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';

/// Admin audit trail (D06): sensitive actions, newest first, with an optional
/// project filter. The server enforces the admin-only read.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  int? _projectId;

  @override
  Widget build(BuildContext context) {
    final projects =
        ref.watch(projectListProvider).value?.items ?? const <Project>[];
    final provider = auditLogProvider(_projectId);
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          if (projects.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'Filter by project',
              icon: const Icon(Icons.filter_list),
              onSelected: (value) =>
                  setState(() => _projectId = value == -1 ? null : value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: -1, child: Text('All projects')),
                for (final project in projects)
                  PopupMenuItem(value: project.id, child: Text(project.name)),
              ],
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(provider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(provider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Could not load the audit log: $e',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return const EmptyState(
                scrollable: true,
                icon: Icons.history,
                title: 'No audit entries',
                hint: 'Sensitive actions will appear here.',
              );
            }
            return ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _AuditTile(entry: page.items[index]),
            );
          },
        ),
      ),
    );
  }
}

/// One audit row: human action label, actor, target, and timestamp.
class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          _iconFor(entry.entityType),
          size: 20,
          color: scheme.onPrimaryContainer,
        ),
      ),
      title: Text(actionLabel(entry.action)),
      subtitle: Text(
        '${entry.actorName} · ${entry.entityType} '
        '#${entry.entityId ?? '—'} · ${_timestamp(entry.createdAt)}',
      ),
    );
  }
}

/// Human label for an audit action; unknown actions fall back to the raw code.
String actionLabel(String action) => switch (action) {
  'project.created' => 'Project created',
  'project.archived' => 'Project archived',
  'project.restored' => 'Project restored',
  'project.owner_assigned' => 'Project owner assigned',
  'member.created' => 'Member created',
  'member.confirmed' => 'Member confirmed',
  'member.role_changed' => 'Member role changed',
  _ => action,
};

IconData _iconFor(String entityType) => switch (entityType) {
  'project' => Icons.folder_outlined,
  'member' => Icons.person_outline,
  _ => Icons.history,
};

String _timestamp(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${formatDate(date)} ${two(date.hour)}:${two(date.minute)}';
}
