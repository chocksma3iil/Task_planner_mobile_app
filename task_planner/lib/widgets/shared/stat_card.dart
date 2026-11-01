import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// Compact stat card used in dashboard and task-list stat rows.
///
/// Shows a value (large bold) with a label (small gray) and an optional icon.
/// Tapping triggers [onTap].
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.active = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = active
        ? (color ?? scheme.primary).withValues(alpha: 0.14)
        : scheme.surfaceVariant;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(radiusInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusInput),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color ?? scheme.primary),
                const SizedBox(height: 4),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
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
    );
  }
}