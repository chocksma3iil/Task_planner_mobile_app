import 'package:flutter/material.dart';

/// Filter chips and their labels, in display order.
const Map<String, String> taskFilters = {
  'all': 'All',
  'today': 'Today',
  'upcoming': 'Upcoming',
  'overdue': 'Overdue',
  'done': 'Done',
};

/// Horizontal filter chips for the task list.
class TaskFilterBar extends StatelessWidget {
  const TaskFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final entry in taskFilters.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: selected == entry.key,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}
