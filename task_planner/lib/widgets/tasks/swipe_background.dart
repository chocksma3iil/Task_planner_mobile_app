import 'package:flutter/material.dart';

/// Background revealed while swiping a task row.
class SwipeBackground extends StatelessWidget {
  const SwipeBackground({super.key, required this.start, required this.done});

  /// True for the start-to-end side (complete/reopen), false for delete.
  final bool start;
  final bool done;

  @override
  Widget build(BuildContext context) {
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
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ]
        : <Widget>[
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
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
}
