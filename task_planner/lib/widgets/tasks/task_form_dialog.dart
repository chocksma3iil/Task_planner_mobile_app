import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../models/models.dart';

/// Values collected by [TaskFormDialog] for create or edit.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.priority,
    this.description,
    this.dueDate,
    this.assigneeId,
  });

  final String title;
  final String? description;
  final String priority;
  final DateTime? dueDate;
  final int? assigneeId;
}

/// Create/edit form for a task. Returns a [TaskDraft] when saved.
class TaskFormDialog extends StatefulWidget {
  const TaskFormDialog({super.key, required this.members, this.initial});

  /// Members of the task's project (the only valid person assignees).
  final List<Account> members;

  /// Existing task when editing; null when creating.
  final Task? initial;

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _priority;
  late DateTime? _dueDate;
  late int? _assigneeId;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _priority = initial?.priority ?? 'medium';
    _dueDate = initial?.dueDate;
    _assigneeId = initial?.assigneeId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
