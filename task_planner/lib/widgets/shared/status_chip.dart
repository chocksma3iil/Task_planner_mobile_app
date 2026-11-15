import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// Status chip for task state (todo / completed).
///
/// Task model only supports 'todo' and 'completed' statuses — no 'running'
/// or 'rejected' states exist in the data model, so this chip only renders
/// those two states.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  Color _color(BuildContext context) => switch (status) {
        'completed' => successColor(Theme.of(context).brightness),
        _ => Theme.of(context).colorScheme.outlineVariant,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final label = status == 'completed' ? 'Completed' : 'Todo';
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
