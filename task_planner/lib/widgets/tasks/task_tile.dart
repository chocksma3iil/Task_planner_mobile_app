import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/rules.dart';
import '../../models/models.dart';
import 'priority_chip.dart';
import 'swipe_background.dart';

/// One task row: checkbox, title, priority, due date, assignee, and swipe
/// actions. Rendering only; the list owns the service calls.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.assigneeLabel,
    required this.onToggle,
    required this.onDelete,
    required this.onSwipe,
    required this.onTap,
  });

  final Task task;
  final String assigneeLabel;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final Future<bool> Function(DismissDirection direction) onSwipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == TaskStatus.completed;
    final overdue = isOverdue(
      status: task.status,
      dueDate: task.dueDate,
      now: DateTime.now(),
    );
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: onSwipe,
      background: SwipeBackground(start: true, done: done),
      secondaryBackground: SwipeBackground(start: false, done: done),
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Checkbox(value: done, onChanged: (_) => onToggle()),
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
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: done ? scheme.onSurfaceVariant : null,
                              ),
                            ),
                          ),
                          PriorityChip(priority: task.priority),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          if (task.dueDate != null)
                            _MetaIcon(
                              icon: Icons.event_outlined,
                              text: formatDate(task.dueDate!),
                              color: overdue
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          if (overdue)
                            _MetaIcon(
                              icon: Icons.warning_amber_rounded,
                              text: 'Overdue',
                              color: scheme.error,
                            ),
                          _MetaIcon(
                            icon: task.assigneeId == null
                                ? Icons.groups_outlined
                                : Icons.person_outline,
                            text: assigneeLabel,
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
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaIcon extends StatelessWidget {
  const _MetaIcon({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }
}
