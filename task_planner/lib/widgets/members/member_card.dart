import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/formatters.dart';
import '../../core/rules.dart';
import '../../models/models.dart';

/// One member row. Flat design: no elevation, no shadows, no gradients.
///
/// Status chips and the confirm action are owner/team-lead information;
/// callers pass the flags from the access rules.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    required this.showStatus,
    required this.showRole,
    required this.canConfirm,
    this.onConfirm,
    this.canChangeRole = false,
    this.onRoleChangePressed,
  });

  final Account member;
  final bool showStatus;
  final bool showRole;
  final bool canConfirm;
  final VoidCallback? onConfirm;

  /// Admins only: shows the role menu for eligible accounts.
  final bool canChangeRole;
  final VoidCallback? onRoleChangePressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = member.status == MemberStatus.pending;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          initialsOf(member.name),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              member.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showStatus) ...[
            const SizedBox(width: 8),
            _StatusChip(
              pending: pending,
              status: member.status,
            ),
          ],
        ],
      ),
      // Role chip, role menu, and confirm action live on their own line so
      // the trailing area never starves the title on narrow screens.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              if (member.position != null) member.position!,
              member.email,
            ].join(' · '),
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (showRole || canChangeRole || canConfirm) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (showRole)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(radiusChip),
                    ),
                    child: Text(
                      member.role,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const Spacer(),
                if (canChangeRole)
                  IconButton(
                    tooltip: 'Change role',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: onRoleChangePressed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (canConfirm)
                  FilledButton.tonal(
                    onPressed: onConfirm,
                    child: const Text('Confirm'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Status chip for member status (pending / active).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.pending, required this.status});

  final bool pending;
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = pending
        ? Theme.of(context).colorScheme.primary
        : successColor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radiusChip),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
