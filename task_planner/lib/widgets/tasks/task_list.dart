import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rules.dart';
import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../shared/app_snackbar.dart';
import '../shared/empty_state.dart';
import '../shared/error_state.dart';
import '../shared/search_field.dart';
import '../shared/section_header.dart';
import 'task_filters.dart';
import 'task_form_dialog.dart';
import 'task_stats.dart';
import 'task_tile.dart';

/// Shared task list used by the Tasks and Mine tabs.
///
/// Shows search, stats cards, filter chips, grouped sections, swipe actions
/// with undo, and pull-to-refresh. [projectId] is the project used when
/// creating a task (null hides the add button).
class TaskList extends ConsumerStatefulWidget {
  const TaskList({
    super.key,
    required this.tasksProvider,
    required this.projectId,
  });

  final StreamProvider<List<Task>> tasksProvider;
  final int? projectId;

  @override
  ConsumerState<TaskList> createState() => _TaskListState();
}

class _TaskListState extends ConsumerState<TaskList> {
  String _filter = 'all';
  String _query = '';

  bool _matches(Task task, DateTime now) {
    switch (_filter) {
      case 'today':
        return isDueToday(status: task.status, dueDate: task.dueDate, now: now);
      case 'upcoming':
        return isUpcoming(status: task.status, dueDate: task.dueDate, now: now);
      case 'overdue':
        return isOverdue(status: task.status, dueDate: task.dueDate, now: now);
      case 'done':
        return task.status == TaskStatus.completed;
      case 'all':
      default:
        return true;
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(widget.tasksProvider);
    try {
      await ref
          .read(widget.tasksProvider.future)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // The stream keeps updating in the background.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(widget.tasksProvider);
    final members =
        ref.watch(visibleMembersProvider).value ?? const <Account>[];
    final memberById = {for (final m in members) m.id: m};
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.projectId == null
          ? null
          : FloatingActionButton(
              tooltip: 'Add task',
              onPressed: _openForm,
              child: const Icon(Icons.add),
            ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Could not load tasks: $e',
          onRetry: () => ref.invalidate(widget.tasksProvider),
        ),
        data: (list) => _body(context, list, memberById),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<Task> list,
    Map<int, Account> memberById,
  ) {
    final now = DateTime.now();
    final matched = _query.isEmpty
        ? list
        : list.where((t) => t.title.toLowerCase().contains(_query)).toList();
    final shown = matched.where((t) => _matches(t, now)).toList();

    // Stats are a snapshot of the whole scope (independent of search and the
    // active filter).
    var dueToday = 0;
    var overdue = 0;
    var done = 0;
    for (final t in list) {
      if (t.status == TaskStatus.completed) {
        done++;
      } else if (isOverdue(status: t.status, dueDate: t.dueDate, now: now)) {
        overdue++;
      } else if (isDueToday(status: t.status, dueDate: t.dueDate, now: now)) {
        dueToday++;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: DebouncedSearchField(
            hintText: 'Search tasks',
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        TaskStats(
          dueToday: dueToday,
          overdue: overdue,
          done: done,
          activeFilter: _filter,
          onSelected: (filter) => setState(() => _filter = filter),
        ),
        TaskFilterBar(
          selected: _filter,
          onSelected: (filter) => setState(() => _filter = filter),
        ),
        Expanded(child: _listArea(context, shown, memberById, now)),
      ],
    );
  }

  Widget _listArea(
    BuildContext context,
    List<Task> shown,
    Map<int, Account> memberById,
    DateTime now,
  ) {
    if (shown.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: const EmptyState(
          scrollable: true,
          icon: Icons.checklist_rounded,
          title: 'No tasks here',
          hint: 'Tap + to add one',
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
            return SectionHeader(header);
          }
          final task = row.task!;
          final assignee = task.assigneeId == null
              ? null
              : memberById[task.assigneeId];
          return TaskTile(
            task: task,
            assigneeLabel: task.assigneeId == null
                ? 'Whole project'
                : (assignee?.name ?? 'Assigned member'),
            onToggle: () => _toggle(task),
            onDelete: () => _delete(task),
            onSwipe: (direction) => _onSwipe(direction, task),
            onTap: () => _openEdit(task),
          );
        },
      ),
    );
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
      _snackWithUndo(
        'Task deleted',
        () => service.createTask(
          projectId: task.projectId,
          title: task.title,
          description: task.description,
          priority: task.priority,
          dueDate: task.dueDate,
          assigneeId: task.assigneeId,
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  /// Handles a swipe; returns false so the row is never dismissed locally —
  /// the task stream re-renders the real state.
  Future<bool> _onSwipe(DismissDirection direction, Task task) async {
    final service = ref.read(taskServiceProvider);
    final done = task.status == TaskStatus.completed;
    try {
      if (direction == DismissDirection.startToEnd) {
        if (done) {
          await service.reopenTask(taskId: task.id);
          _snackWithUndo(
            'Task reopened',
            () => service.completeTask(taskId: task.id),
          );
        } else {
          await service.completeTask(taskId: task.id);
          _snackWithUndo(
            'Task completed',
            () => service.reopenTask(taskId: task.id),
          );
        }
      } else {
        await service.deleteTask(taskId: task.id);
        _snackWithUndo(
          'Task deleted',
          () => service.createTask(
            projectId: task.projectId,
            title: task.title,
            description: task.description,
            priority: task.priority,
            dueDate: task.dueDate,
            assigneeId: task.assigneeId,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
    return false;
  }

  void _snackWithUndo(String message, Future<void> Function() action) {
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      message,
      actionLabel: 'Undo',
      onAction: () async {
        try {
          await action();
        } catch (e) {
          if (mounted) {
            showAppSnackBar(context, userMessage(e));
          }
        }
      },
    );
  }

  /// Members of [projectId], or null when they could not be loaded.
  Future<List<Account>?> _membersFor(int projectId) async {
    final List<Account> all;
    try {
      all = await ref.read(visibleMembersProvider.future);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
      return null;
    }
    return all.where((m) => m.projectId == projectId).toList(growable: false);
  }

  Future<void> _openForm() async {
    final projectId = widget.projectId;
    if (projectId == null) {
      return;
    }
    final members = await _membersFor(projectId);
    if (members == null || !mounted) {
      return;
    }
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskFormDialog(members: members),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(taskServiceProvider)
          .createTask(
            projectId: projectId,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueDate: draft.dueDate,
            assigneeId: draft.assigneeId,
          );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _openEdit(Task task) async {
    final members = await _membersFor(task.projectId);
    if (members == null || !mounted) {
      return;
    }
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskFormDialog(members: members, initial: task),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(taskServiceProvider)
          .updateTask(
            taskId: task.id,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueDate: draft.dueDate,
            assigneeId: draft.assigneeId,
          );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}
