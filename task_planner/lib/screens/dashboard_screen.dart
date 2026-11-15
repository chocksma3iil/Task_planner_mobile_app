import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/rules.dart';
import '../core/design_tokens.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/shared/app_snackbar.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';
import '../widgets/shared/hero_card.dart';
import '../widgets/shared/section_header.dart';
import '../widgets/shared/stat_card.dart';

/// Dashboard screen: project health at a glance — completion rate, task counts,
/// priority mix, and recent activity.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int? _projectId;

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

        final adminProjects = isAdmin(user.role)
            ? ref.watch(projectListProvider).value?.items
            : null;
        final pid =
            _projectId ??
            user.projectId ??
            (adminProjects != null && adminProjects.isNotEmpty
                ? adminProjects.first.id
                : null);
        if (pid == null) {
          return const Scaffold(body: Center(child: Text('No project assigned.')));
        }

        final statsAsync = ref.watch(dashboardStatsProvider(pid));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Project Dashboard'),
            actions: [
              if (isAdmin(user.role)) ...[
                IconButton(
                  tooltip: 'Audit log',
                  icon: const Icon(Icons.history),
                  onPressed: () => context.push('/audit-log'),
                ),
                _ProjectPicker(
                  selected: pid,
                  onChanged: (pid) {
                    setState(() => _projectId = pid);
                    ref.invalidate(dashboardStatsProvider(pid));
                  },
                ),
              ],
              PopupMenuButton<String>(
                tooltip: 'Export',
                icon: const Icon(Icons.download_outlined),
                onSelected: (format) => _export(pid, format),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                  PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                ],
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(dashboardStatsProvider(pid)),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => ref.invalidate(dashboardStatsProvider(pid)),
            child: statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(
                message: 'Could not load dashboard: $e',
                onRetry: () => ref.invalidate(dashboardStatsProvider(pid)),
              ),
              data: (stats) => _dashboardBody(context, stats),
            ),
          ),
        );
      },
    );
  }

  /// Downloads the selected project's report (E03): bytes from the API, then
  /// saved through the injectable export service (`file_saver` in the app).
  Future<void> _export(int projectId, String format) async {
    try {
      await ref.read(exportServiceProvider).exportProject(projectId: projectId, format: format);
      if (mounted) {
        showAppSnackBar(context, '${format.toUpperCase()} report downloaded.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Widget _dashboardBody(BuildContext context, DashboardStats stats) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card: completion rate (most important metric).
          HeroCard(
            title: 'Completion rate',
            value: '${stats.completionRate.toStringAsFixed(0)}%',
            icon: Icons.track_changes,
            color: scheme.primary,
            subtitle: '${stats.completedTasks}/${stats.totalTasks} tasks done',
          ),
          const SizedBox(height: 16),

          // KPI cards: total, completed, pending, overdue.
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Total',
                  value: stats.totalTasks.toString(),
                  icon: Icons.task_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Completed',
                  value: stats.completedTasks.toString(),
                  icon: Icons.check_circle_outline,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Pending',
                  value: stats.pendingTasks.toString(),
                  icon: Icons.pending_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Overdue',
                  value: stats.overdueTasks.toString(),
                  icon: Icons.warning_outlined,
                  color: scheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Priority mix: chips from real analytics data.
          SectionHeader('Priority mix'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _priorityChip(
                  context,
                  'High',
                  stats.priorityMix['high'] ?? 0,
                  priorityHighColor(scheme.brightness),
                  stats.totalTasks,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _priorityChip(
                  context,
                  'Medium',
                  stats.priorityMix['medium'] ?? 0,
                  priorityMediumColor(scheme.brightness),
                  stats.totalTasks,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _priorityChip(
                  context,
                  'Low',
                  stats.priorityMix['low'] ?? 0,
                  priorityLowColor(scheme.brightness),
                  stats.totalTasks,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent events.
          SectionHeader('Recent activity'),
          const SizedBox(height: 8),
          if (stats.recentEvents.isEmpty)
            const EmptyState(
              icon: Icons.history,
              title: 'No recent activity',
              hint: 'Task changes will appear here.',
            )
          else
            ...[
              for (final ev in stats.recentEvents)
                _eventTile(context, ev),
            ],
        ],
      ),
    );
  }

  Widget _priorityChip(BuildContext context, String label, int count, Color color, int total) {
    final scheme = Theme.of(context).colorScheme;
    final percent = total > 0 ? ((count / total * 100).round()) : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$percent%',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(BuildContext context, AnalyticsEvent ev) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = _isToday(ev.createdAt);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          _eventIcon(ev.eventType),
          size: 14,
          color: scheme.primary,
        ),
      ),
      title: Text(
        ev.actorName,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _eventDescription(ev),
        style: TextStyle(
          fontSize: 11.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        isToday ? _timeOfDay(ev.createdAt) : _dateShort(ev.createdAt),
        style: TextStyle(
          fontSize: 10,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  IconData _eventIcon(String type) => switch (type) {
        'task_created' => Icons.add_task,
        'task_completed' => Icons.check_circle,
        'task_reopened' => Icons.restore,
        'task_deleted' => Icons.delete_outline,
        'task_assigned' => Icons.person_add,
        'comment_created' => Icons.comment,
        _ => Icons.info,
      };

  String _eventDescription(AnalyticsEvent ev) {
    final type = ev.eventType;
    final taskRef = ev.taskId == null ? '' : ' (task #${ev.taskId})';
    return switch (type) {
      'task_created' => 'Created a task$taskRef',
      'task_completed' => 'Completed a task$taskRef',
      'task_reopened' => 'Reopened a task$taskRef',
      'task_deleted' => 'Deleted a task$taskRef',
      'task_assigned' => 'Assigned a task$taskRef',
      'comment_created' => 'Added a comment$taskRef',
      _ => 'Activity$taskRef',
    };
  }

  bool _isToday(DateTime when) {
    final now = DateTime.now();
    return when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
  }

  String _timeOfDay(DateTime when) =>
      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

  String _dateShort(DateTime when) =>
      '${when.month}/${when.day}';
}

/// Project picker for admins in the dashboard app bar.
class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectListProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (paginated) {
        final projects = paginated.items;
        if (projects.isEmpty) {
          return const SizedBox.shrink();
        }
        return DropdownButton<int>(
          value: projects.any((p) => p.id == selected)
              ? selected
              : projects.first.id,
          items: [
            for (final p in projects)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) {
            if (v != null) {
              onChanged(v);
            }
          },
        );
      },
    );
  }
}