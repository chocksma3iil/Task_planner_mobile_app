import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_tokens.dart';
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
import 'comment_sheet.dart';

/// Shared task list used by the Tasks and Mine tabs.
///
/// Shows search, stats cards, filter chips, grouped sections, swipe actions
/// with undo, and pull-to-refresh. [projectId] is the project used when
/// creating a task (null hides the add button).
class TaskListWidget extends ConsumerStatefulWidget {
  const TaskListWidget({
    super.key,
    required this.tasksProvider,
    required this.projectId,
    this.assigneeId,
    required this.onLoadFirstPage,
    required this.onLoadMore,
    this.canMutate = true,
  });

  final AsyncValue<PaginatedList<Task>> Function(WidgetRef ref) tasksProvider;
  final int? projectId;
  final int? assigneeId;
  final Future<void> Function() onLoadFirstPage;
  final Future<void> Function() onLoadMore;
  final bool canMutate;

  @override
  ConsumerState<TaskListWidget> createState() => _TaskListState();
}

class _TaskListState extends ConsumerState<TaskListWidget> {
  String _filter = 'all';
  String _query = '';
  final _scrollController = ScrollController();
  final Set<int> _selectedTaskIds = {};
  bool _bulkMode = false;

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
        _scrollController.position.maxScrollExtent - 200) {
      // The paginated notifier ignores calls while a page is already loading
      // and when the last page has been reached.
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    await widget.onLoadMore();
  }

  Future<void> _refresh() async {
    await widget.onLoadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    if (projectId == null && widget.assigneeId == null) {
      return const Center(child: Text('No project selected'));
    }

    final tasksAsync = widget.tasksProvider(ref);
    final scheme = Theme.of(context).colorScheme;
    final membersState = ref.watch(visibleMembersProvider);
    final members =
        membersState.value?.items ?? const <Account>[];
    final memberById = {for (final m in members) m.id: m};

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _bulkMode
          ? AppBar(
              title: Text('${_selectedTaskIds.length} selected'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedTaskIds.clear();
                  _bulkMode = false;
                }),
              ),
              actions: [
                if (_selectedTaskIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: () => _bulkComplete(),
                    tooltip: 'Complete selected',
                  ),
                if (_selectedTaskIds.isNotEmpty && widget.projectId != null)
                  IconButton(
                    icon: const Icon(Icons.person_add_outlined),
                    onPressed: () => _bulkReassignDialog(context),
                    tooltip: 'Reassign selected',
                  ),
                if (_selectedTaskIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _bulkDelete(),
                    tooltip: 'Delete selected',
                  ),
              ],
            )
          : null,
      floatingActionButton: _bulkMode
          ? null
          : widget.canMutate
              ? FloatingActionButton(
                  tooltip: 'Add task',
                  onPressed: _openForm,
                  child: const Icon(Icons.add),
                )
              : null,
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Could not load tasks: $e',
          onRetry: _refresh,
        ),
        data: (paginated) => _body(context, paginated, memberById),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PaginatedList<Task> paginated,
    Map<int, Account> memberById,
  ) {
    final list = paginated.items;
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
          padding: const EdgeInsets.fromLTRB(spaceM, spaceS, spaceM, spaceXs),
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
        Expanded(child: _listArea(context, shown, memberById, now, paginated)),
      ],
    );
  }

  Widget _listArea(
    BuildContext context,
    List<Task> shown,
    Map<int, Account> memberById,
    DateTime now,
    PaginatedList<Task> paginated,
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
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(spaceM, spaceS, spaceM, spaceL),
          itemCount: rows.length + (paginated.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == rows.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final row = rows[i];
            final header = row.header;
            if (header != null) {
              return SectionHeader(header);
            }
            final task = row.task!;
            final isSelected = _selectedTaskIds.contains(task.id);
            final assignee = task.assigneeId == null
                ? null
                : memberById[task.assigneeId];
            return GestureDetector(
              // Long-press enters multi-select; while selecting, a tap toggles
              // the row instead of opening the editor.
              onLongPress: _bulkMode ? null : () => _startBulk(task.id),
              child: TaskTile(
                task: task,
                assigneeLabel: task.assigneeId == null
                    ? 'Whole project'
                    : (assignee?.name ?? 'Assigned member'),
                onToggle: () => _toggle(task),
                onDelete: () => _delete(task),
                onSwipe: (direction) => _onSwipe(direction, task),
                onTap: _bulkMode
                    ? () => _toggleSelection(task.id)
                    : () => _openEdit(task),
                canMutate: widget.canMutate && !_bulkMode,
                isSelected: isSelected,
                onComment: () => showCommentSheet(context, task.id),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Enters multi-select mode with [taskId] already selected.
  void _startBulk(int taskId) {
    setState(() {
      _bulkMode = true;
      _selectedTaskIds
        ..clear()
        ..add(taskId);
    });
  }

  /// Adds or removes a task from the current bulk selection.
  void _toggleSelection(int taskId) {
    setState(() {
      if (!_selectedTaskIds.remove(taskId)) {
        _selectedTaskIds.add(taskId);
      }
    });
  }

  Future<void> _toggle(Task task) async {    final service = ref.read(taskServiceProvider);
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
    final membersState = ref.read(visibleMembersProvider);
    if (membersState.hasValue) {
      final all = membersState.value!.items;
      return all.where((m) => m.projectId == projectId).toList(growable: false);
    }
    return null;
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
      final task = await ref
          .read(taskServiceProvider)
          .createTask(
            projectId: projectId,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueDate: draft.dueDate,
            assigneeId: draft.assigneeId,
          );
      // Create subtasks.
      final subtaskService = ref.read(subtaskServiceProvider);
      int order = 0;
      for (final s in draft.subtasks) {
        await subtaskService.create(
          taskId: task.id,
          title: s['title'] as String,
          completed: s['completed'] as bool? ?? false,
          sortOrder: order++,
        );
      }
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
    // Load existing subtasks.
    final subtaskService = ref.read(subtaskServiceProvider);
    late final List<Map<String, dynamic>> existingSubtasks;
    try {
      final subs = await subtaskService.list(task.id);
      existingSubtasks = subs
          .map((s) => <String, dynamic>{
                'id': s.id,
                'title': s.title,
                'completed': s.completed,
                'sort_order': s.sortOrder,
              })
          .toList();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
      return;
    }
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (_) => TaskFormDialog(
        members: members,
        initial: task,
        initialSubtasks: existingSubtasks,
      ),
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
      // Sync subtasks: delete removed, update changed, add new.
      final existingById = {for (final s in existingSubtasks) s['id']! as int: s};
      for (final s in draft.subtasks) {
        final id = s['id'] as int?;
        final title = s['title'] as String?;
        final completed = s['completed'] as bool? ?? false;
        final sortOrder = s['sort_order'] as int? ?? 0;
        if (id == null) {
          await subtaskService.create(
            taskId: task.id,
            title: title!,
            completed: completed,
            sortOrder: sortOrder,
          );
        } else {
          final existing = existingById[id];
          if (existing != null &&
              (existing['title'] != title ||
                  existing['sort_order'] != sortOrder ||
                  existing['completed'] != completed)) {
            await subtaskService.update(
              subtaskId: id,
              title: title!,
              completed: completed,
              sortOrder: sortOrder,
            );
          }
        }
      }
      // Delete removed subtasks.
      final draftIds =
          draft.subtasks.where((s) => s['id'] != null).map((s) => s['id']! as int).toSet();
      for (final s in existingSubtasks) {
        final id = s['id'] as int;
        if (!draftIds.contains(id)) {
          await subtaskService.delete(id);
        }
      }
      } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  /// Bulk complete all selected tasks.
  Future<void> _bulkComplete() async {
    if (_selectedTaskIds.isEmpty) {
      return;
    }
    final service = ref.read(taskServiceProvider);
    try {
      final result = await service.bulkCompleteTasks(taskIds: _selectedTaskIds.toList());
      _selectedTaskIds.clear();
      _bulkMode = false;
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        '${result.succeeded} completed${result.failed > 0 ? ', ${result.failed} failed' : ''}',
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  /// Bulk delete all selected tasks.
  Future<void> _bulkDelete() async {
    if (_selectedTaskIds.isEmpty) {
      return;
    }
    final service = ref.read(taskServiceProvider);
    try {
      final result = await service.bulkDeleteTasks(taskIds: _selectedTaskIds.toList());
      _selectedTaskIds.clear();
      _bulkMode = false;
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        '${result.succeeded} deleted${result.failed > 0 ? ', ${result.failed} failed' : ''}',
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  /// Show a dialog to choose the assignee for bulk reassign.
  Future<void> _bulkReassignDialog(BuildContext context) async {
    if (_selectedTaskIds.isEmpty || widget.projectId == null) {
      return;
    }
    final members = await _membersFor(widget.projectId!);
    if (members == null || members.isEmpty || !mounted) {
      return;
    }
    int? selectedAssigneeId;
    final draft = await showDialog<int?>(
      context: context,
      builder: (_) => StatefulBuilder(
        // The choice must rebuild the dialog so the Reassign button enables.
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reassign selected tasks'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: members
                .map((m) => RadioListTile<int?>(
                      title: Text(m.name),
                      subtitle: Text(m.email),
                      value: m.id,
                      groupValue: selectedAssigneeId,
                      onChanged: (v) =>
                          setDialogState(() => selectedAssigneeId = v),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedAssigneeId == null
                  ? null
                  : () => Navigator.pop(context, selectedAssigneeId),
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    final service = ref.read(taskServiceProvider);
    try {
      final result = await service.bulkReassignTasks(
        taskIds: _selectedTaskIds.toList(),
        newAssigneeId: draft,
      );
      _selectedTaskIds.clear();
      _bulkMode = false;
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        '${result.succeeded} reassigned${result.failed > 0 ? ', ${result.failed} failed' : ''}',
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}