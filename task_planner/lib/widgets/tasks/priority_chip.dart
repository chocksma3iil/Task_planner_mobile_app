import 'package:flutter/material.dart';

/// Small colored pill showing the task priority.
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority});

  final String priority;

  Color _color(ColorScheme scheme) => switch (priority) {
    'high' => scheme.error,
    'medium' => scheme.tertiary,
    'low' => scheme.primary,
    _ => scheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(Theme.of(context).colorScheme);
    final label = priority.isEmpty
        ? ''
        : priority[0].toUpperCase() + priority.substring(1);
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
