import 'package:flutter/material.dart';

/// Snapshot counters shown above the task list. Tapping a card applies the
/// matching filter.
class TaskStats extends StatelessWidget {
  const TaskStats({
    super.key,
    required this.dueToday,
    required this.overdue,
    required this.done,
    required this.activeFilter,
    required this.onSelected,
  });

  final int dueToday;
  final int overdue;
  final int done;
  final String activeFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          _StatCard(
            label: 'Due today',
            count: dueToday,
            icon: Icons.event_outlined,
            color: scheme.tertiary,
            active: activeFilter == 'today',
            onTap: () => onSelected('today'),
          ),
          const SizedBox(width: 8),
          _StatCard(
            label: 'Overdue',
            count: overdue,
            icon: Icons.warning_amber_rounded,
            color: scheme.error,
            active: activeFilter == 'overdue',
            onTap: () => onSelected('overdue'),
          ),
          const SizedBox(width: 8),
          _StatCard(
            label: 'Done',
            count: done,
            icon: Icons.check_circle_outline,
            color: scheme.primary,
            active: activeFilter == 'done',
            onTap: () => onSelected('done'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: color.withValues(alpha: active ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: count),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
