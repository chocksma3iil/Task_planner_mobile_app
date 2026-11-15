import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../ai/ai_dialogs.dart';
import '../shared/app_snackbar.dart';

/// Values collected by [TaskFormDialog] for create or edit.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.priority,
    this.description,
    this.dueDate,
    this.assigneeId,
    this.subtasks = const [],
  });

  final String title;
  final String? description;
  final String priority;
  final DateTime? dueDate;
  final int? assigneeId;
  final List<Map<String, dynamic>> subtasks;
}

/// Create/edit form for a task. Returns a [TaskDraft] when saved.
class TaskFormDialog extends ConsumerStatefulWidget {
  const TaskFormDialog({
    super.key,
    required this.members,
    this.initial,
    this.initialSubtasks = const [],
  });

  /// Members of the task's project (the only valid person assignees).
  final List<Account> members;

  /// Existing task when editing; null when creating.
  final Task? initial;

  /// Pre-existing subtasks when editing (loaded separately by the screen).
  final List<Map<String, dynamic>> initialSubtasks;

  @override
  ConsumerState<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<TaskFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _priority;
  late DateTime? _dueDate;
  late int? _assigneeId;
  String? _titleError;
  final List<Map<String, dynamic>> _subtasks = []; // {id, title, completed, sort_order, _deleted}
  final TextEditingController _subtaskTitle = TextEditingController();
  int _nextSortOrder = 0;
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _priority = initial?.priority ?? 'medium';
    _dueDate = initial?.dueDate;
    _assigneeId = initial?.assigneeId;
    _subtasks.addAll(
      // Copy each map: the dialog edits them in place, and the caller keeps
      // its own snapshot to diff against on save.
      widget.initialSubtasks.map((s) => Map<String, dynamic>.of(s)),
    );
    _nextSortOrder = _subtasks.length;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _subtaskTitle.dispose();
    super.dispose();
  }

  void _addSubtask() {
    final title = _subtaskTitle.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _subtasks.add({
        'id': null,
        'title': title,
        'completed': false,
        'sort_order': _nextSortOrder++,
        '_new': true,
      });
      _subtaskTitle.clear();
    });
  }

  void _toggleSubtask(int index) {
    setState(() {
      _subtasks[index]['completed'] = !_subtasks[index]['completed'];
    });
  }

  void _removeSubtask(int index) {
    setState(() {
      final s = _subtasks[index];
      if (s['id'] != null) {
        s['_deleted'] = true;
      } else {
        _subtasks.removeAt(index);
      }
    });
  }

  Future<void> _suggestSubtasks() async {
    final task = widget.initial;
    if (task == null) {
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final proposal = await ref.read(aiServiceProvider).decompose(task.id);
      if (!mounted) {
        return;
      }
      if (proposal.subtasks.isEmpty) {
        showAppSnackBar(
          context,
          'No subtasks suggested. Check that AI is enabled for this project.',
        );
        return;
      }
      final selected = await showDecomposeDialog(context, proposal);
      if (selected == null || selected.isEmpty || !mounted) {
        return;
      }
      final service = ref.read(subtaskServiceProvider);
      final created = <Map<String, dynamic>>[];
      for (final subtask in selected) {
        final result = await service.create(
          taskId: task.id,
          title: subtask.title,
          sortOrder: _nextSortOrder++,
        );
        created.add({
          'id': result.id,
          'title': result.title,
          'completed': result.completed,
          'sort_order': result.sortOrder,
        });
      }
      if (!mounted) {
        return;
      }
      setState(() => _subtasks.addAll(created));
      showAppSnackBar(context, 'Added ${created.length} subtask(s).');
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _aiBusy = false);
      }
    }
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Title is required.');
      return;
    }
    final description = _description.text.trim();
    Navigator.of(context).pop(
      TaskDraft(
        title: title,
        description: description.isEmpty ? null : description,
        priority: _priority,
        dueDate: _dueDate,
        assigneeId: _assigneeId,
        subtasks: _subtasks
            .where((s) => s['_deleted'] != true)
            .map((s) => <String, dynamic>{
                  'id': s['id'],
                  'title': s['title'],
                  'completed': s['completed'],
                  'sort_order': s['sort_order'],
                })
            .toList(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dueDate,
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit task' : 'New task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: !editing,
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Priority'),
              initialValue: _priority,
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'medium'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              decoration: const InputDecoration(labelText: 'Assign to'),
              initialValue: _assigneeId,
              items: [
                const DropdownMenuItem(child: Text('Whole project')),
                for (final m in widget.members)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text('${m.name} (${m.position ?? 'member'})'),
                  ),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dueDate == null
                        ? 'No due date'
                        : 'Due: ${formatDate(_dueDate!)}',
                  ),
                ),
                TextButton(
                  onPressed: _pickDate,
                  child: const Text('Pick date'),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Subtask checklist.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtasks',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                if (editing)
                  TextButton.icon(
                    onPressed: _aiBusy ? null : _suggestSubtasks,
                    icon: _aiBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_aiBusy ? 'Asking AI…' : 'Suggest (AI)'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final s in _subtasks)
              if (s['_deleted'] != true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: s['completed'],
                        onChanged: (_) => _toggleSubtask(_subtasks.indexOf(s)),
                      ),
                      Expanded(
                        child: Text(s['title']),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeSubtask(_subtasks.indexOf(s)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskTitle,
                    decoration: const InputDecoration(
                      labelText: 'Add subtask',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onPressed: _addSubtask,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _aiBusy ? null : _submit,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
