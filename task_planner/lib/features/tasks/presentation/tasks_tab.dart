import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../../../core/error_state.dart';
import '../../../core/rules.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/session_providers.dart';
import 'providers.dart';

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
    Assignee user, {
    required List<Project>? adminProjects,
  }) {
    int? effective;
    if (adminProjects != null) {
      effective = _selectedProjectId ??
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
              : _TaskList(projectId: effective, viewer: user),
        ),
      ],
    );
  }
}

class _TaskList extends ConsumerStatefulWidget {
  const _TaskList({required this.projectId, required this.viewer});

  final int projectId;
  final Assignee viewer;

  @override
  ConsumerState<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends ConsumerState<_TaskList> {
  String _filter = 'all';
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  static const _filters = {
    'all': 'All',
    'today': 'Today',
    'upcoming': 'Upcoming',
    'overdue': 'Overdue',
    'done': 'Done',
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _query = value.trim().toLowerCase());
      }
    });
    setState(() {});
  }

  bool _matches(Task task, DateTime now) {
    switch (_filter) {
      case 'today':
        return isDueToday(
            status: task.status, dueDate: task.dueDate, now: now);
      case 'upcoming':
        return isUpcoming(
            status: task.status, dueDate: task.dueDate, now: now);
      case 'overdue':
        return isOverdue(
            status: task.status, dueDate: task.dueDate, now: now);
      case 'done':
        return task.status == TaskStatus.completed;
      case 'all':
      default:
        return true;
    }
  }

  Future<void> _refresh() async {
    final provider = projectTasksProvider(widget.projectId);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future).timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Stream keeps updating in the background.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(projectTasksProvider(widget.projectId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => _addDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Could not load tasks: $e',
          onRetry: () => ref.invalidate(projectTasksProvider(widget.projectId)),
        ),
        data: (list) => _body(context, ref, list),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, List<Task> list) {
    final now = DateTime.now();
    final matched = _query.isEmpty
        ? list
        : list
            .where((t) => t.title.toLowerCase().contains(_query))
            .toList();
    final shown = matched.where((t) => _matches(t, now)).toList();

    // Stats are a snapshot of the whole project (independent of search
    // and the active filter).
    var dueToday = 0;
    var overdue = 0;
    var done = 0;
    for (final t in list) {
      if (t.status == TaskStatus.completed) {
        done++;
      } else if (isOverdue(
          status: t.status, dueDate: t.dueDate, now: now)) {
        overdue++;
      } else if (isDueToday(
          status: t.status, dueDate: t.dueDate, now: now)) {
        dueToday++;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search tasks',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(
            children: [
              _StatCard(
                label: 'Due today',
                count: dueToday,
                icon: Icons.event_outlined,
                color: Theme.of(context).colorScheme.tertiary,
                active: _filter == 'today',
                onTap: () => setState(() => _filter = 'today'),
              ),
              const SizedBox(width: 8),
              _StatCard(
                label: 'Overdue',
                count: overdue,
                icon: Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                active: _filter == 'overdue',
                onTap: () => setState(() => _filter = 'overdue'),
              ),
              const SizedBox(width: 8),
              _StatCard(
                label: 'Done',
                count: done,
                icon: Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
                active: _filter == 'done',
                onTap: () => setState(() => _filter = 'done'),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              for (final entry in _filters.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _listArea(context, ref, shown, now),
        ),
      ],
    );
  }

  Widget _listArea(
      BuildContext context, WidgetRef ref, List<Task> shown, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    if (shown.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.checklist_rounded,
                        size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'No tasks here',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap + to add one',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Grouped sections in every view; empty sections are skipped.
    final rows = <({String? header, Task? task})>[];
    final overdueT = <Task>[];
    final todayT = <Task>[];
    final upcomingT = <Task>[];
    final noDateT = <Task>[];
    final completedT = <Task>[];
    for (final t in shown) {
      if (t.status == TaskStatus.completed) {
        completedT.add(t);
      } else if (t.dueDate == null) {
        noDateT.add(t);
      } else if (isOverdue(status: t.status, dueDate: t.dueDate, now: now)) {
        overdueT.add(t);
      } else if (isDueToday(status: t.status, dueDate: t.dueDate, now: now)) {
        todayT.add(t);
      } else {
        upcomingT.add(t);
      }
    }
    for (final section in <(String, List<Task>)>[
      ('Overdue', overdueT),
      ('Today', todayT),
      ('Upcoming', upcomingT),
      ('No due date', noDateT),
      ('Completed', completedT),
    ]) {
      if (section.$2.isEmpty) {
        continue;
      }
      rows.add((header: section.$1, task: null));
      for (final t in section.$2) {
        rows.add((header: null, task: t));
      }
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          final header = row.header;
          if (header != null) {
            return sectionHeader(context, header);
          }
          return _taskRow(context, ref, row.task!);
        },
      ),
    );
  }

  Widget _taskRow(BuildContext context, WidgetRef ref, Task task) {
    final done = task.status == TaskStatus.completed;
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) => _onSwipe(direction, task),
      background: _swipeBackground(context, start: true, done: done),
      secondaryBackground: _swipeBackground(context, start: false, done: done),
      child: _card(context, ref, task),
    );
  }

  Widget _swipeBackground(
      BuildContext context, {required bool start, required bool done}) {
    final scheme = Theme.of(context).colorScheme;
    final color = start
        ? (done ? scheme.tertiary : scheme.primary)
        : scheme.error;
    final icon = start
        ? (done ? Icons.undo : Icons.check_circle_outline)
        : Icons.delete_outline;
    final label = start ? (done ? 'Reopen' : 'Complete') : 'Delete';
    final children = start
        ? <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700)),
          ]
        : <Widget>[
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Icon(icon, color: color),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: color.withValues(alpha: 0.15),
      alignment: start ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// Handles a swipe: right completes (or reopens), left deletes — each
  /// with an undo action. Returns false so the row is never dismissed
  /// locally; the task stream re-renders the real state.
  Future<bool> _onSwipe(DismissDirection direction, Task task) async {
    final service = ref.read(taskServiceProvider);
    final done = task.status == TaskStatus.completed;
    try {
      if (direction == DismissDirection.startToEnd) {
        if (done) {
          await service.reopenTask(actor: widget.viewer, taskId: task.id);
          _snack('Task reopened', actionLabel: 'Undo', onAction: () async {
            try {
              await service.completeTask(
                  actor: widget.viewer, taskId: task.id);
            } on StateError catch (e) {
              _snack(e.message);
            }
          });
        } else {
          await service.completeTask(actor: widget.viewer, taskId: task.id);
          _snack('Task completed', actionLabel: 'Undo', onAction: () async {
            try {
              await service.reopenTask(
                  actor: widget.viewer, taskId: task.id);
            } on StateError catch (e) {
              _snack(e.message);
            }
          });
        }
      } else {
        await service.deleteTask(actor: widget.viewer, taskId: task.id);
        _snack('Task deleted', actionLabel: 'Undo', onAction: () async {
          try {
            await service.createTask(
              actor: widget.viewer,
              projectId: task.projectId,
              title: task.title,
              description: task.description,
              priority: task.priority,
              dueDate: task.dueDate,
              assigneeId: task.assigneeId,
            );
          } on StateError catch (e) {
            _snack(e.message);
          } on ArgumentError catch (e) {
            _snack(e.message);
          }
        });
      }
    } on StateError catch (e) {
      _snack(e.message);
    } on ArgumentError catch (e) {
      _snack(e.message);
    }
    return false;
  }

  void _snack(String message,
      {String? actionLabel, Future<void> Function()? onAction}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: () {
                  onAction?.call();
                },
              ),
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Task task) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == TaskStatus.completed;
    final overdue = isOverdue(
      status: task.status,
      dueDate: task.dueDate,
      now: DateTime.now(),
    );
    final service = ref.read(taskServiceProvider);
    final members = ref.watch(visibleMembersProvider).when(
          data: (list) => list,
          loading: () => const <Assignee>[],
          error: (_, _) => const <Assignee>[],
        );
    Assignee? assignee;
    if (task.assigneeId != null) {
      for (final m in members) {
        if (m.id == task.assigneeId) {
          assignee = m;
          break;
        }
      }
    }
    final assigneeText = task.assigneeId == null
        ? 'Whole project'
        : (assignee?.name ?? 'Assigned member');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (_) async {
                try {
                  if (done) {
                    await service.reopenTask(
                        actor: widget.viewer, taskId: task.id);
                  } else {
                    await service.completeTask(
                        actor: widget.viewer, taskId: task.id);
                  }
                } on StateError catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            color: done ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                      ),
                      _PriorityChip(priority: task.priority),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (task.dueDate != null)
                        _metaIcon(
                          icon: Icons.event_outlined,
                          text: _date(task.dueDate!),
                          color:
                              overdue ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      if (overdue)
                        _metaIcon(
                          icon: Icons.warning_amber_rounded,
                          text: 'Overdue',
                          color: scheme.error,
                        ),
                      _metaIcon(
                        icon: assignee == null
                            ? Icons.groups_outlined
                            : Icons.person_outline,
                        text: assigneeText,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: scheme.outline),
              onPressed: () async {
                try {
                  await service.deleteTask(
                      actor: widget.viewer, taskId: task.id);
                } on StateError catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaIcon({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    String priority = 'medium';
    DateTime? dueDate;
    int? assigneeId;
    final members = await ref
        .read(memberServiceProvider)
        .watchVisibleMembers(widget.viewer)
        .first;
    final projectMembers =
        members.where((m) => m.projectId == widget.projectId).toList();
    if (!context.mounted) {
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Priority'),
                  initialValue: priority,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => priority = v ?? 'medium'),
                ),
                DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(labelText: 'Assign to'),
                  initialValue: assigneeId,
                  items: [
                    const DropdownMenuItem(
                      child: Text('Whole project'),
                    ),
                    for (final m in projectMembers)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text('${m.name} (${m.position ?? 'member'})'),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => assigneeId = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dueDate == null
                            ? 'No due date'
                            : 'Due: ${_date(dueDate!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 3650)),
                        );
                        setDialogState(() => dueDate = picked);
                      },
                      child: const Text('Pick date'),
                    ),
                  ],
                ),
              ],
            ),
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
      ),
    );
    if (created == true && context.mounted) {
      try {
        await ref.read(taskServiceProvider).createTask(
              actor: widget.viewer,
              projectId: widget.projectId,
              title: title.text.trim(),
              priority: priority,
              dueDate: dueDate,
              assigneeId: assigneeId,
            );
      } on StateError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } on ArgumentError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    title.dispose();
  }

  String _date(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

/// Compact animated statistic shown above the task list. Tapping it applies
/// the matching filter.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: color.withValues(alpha: active ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: count),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small colored pill showing the task priority.
class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(context, priority);
    final label = priority[0].toUpperCase() + priority.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
