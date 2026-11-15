import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// Small colored pill showing the task priority.
///
/// Colors are semantic (from [design_tokens.dart]) so they stay consistent
/// across dark and light themes. The label is derived from the priority value
/// ('high', 'medium', 'low').
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority});

  final String priority;

  Color _color(BuildContext context) => switch (priority) {
        'high' => priorityHighColor(Theme.of(context).brightness),
        'medium' => priorityMediumColor(Theme.of(context).brightness),
        'low' => priorityLowColor(Theme.of(context).brightness),
        _ => Theme.of(context).colorScheme.outlineVariant,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final label = priority.isEmpty
        ? ''
        : priority[0].toUpperCase() + priority.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radiusChip),
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

Color priorityHighColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityHighDark : priorityHighLight;

Color priorityMediumColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityMediumDark : priorityMediumLight;

Color priorityLowColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityLowDark : priorityLowLight;
