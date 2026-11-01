import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/data_providers.dart';
import '../widgets/shared/app_snackbar.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';

/// Notifications screen: lists the caller's in-app notifications with
/// unread/read distinction and mark-as-read support.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final provider = _unreadOnly
        ? unreadNotificationListProvider
        : notificationListProvider;
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: _unreadOnly ? 'Show all' : 'Unread only',
            icon: Icon(
              _unreadOnly ? Icons.mark_email_read : Icons.email_outlined,
            ),
            onPressed: () {
              setState(() => _unreadOnly = !_unreadOnly);
              ref.invalidate(provider);
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(provider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(provider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Could not load notifications: $e',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (list) {
            if (list.items.isEmpty) {
              return EmptyState(
                scrollable: true,
                icon: Icons.notifications_none,
                title: _unreadOnly ? 'No unread notifications' : 'No notifications',
                hint: 'You will see updates here when tasks or members change.',
              );
            }
            return ListView.separated(
              itemCount: list.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = list.items[index];
                return _NotificationTile(
                  notification: n,
                  onTap: () => _markRead([n.id]),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _markRead(List<int> ids) async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.markRead(ids);
      ref.invalidate(notificationListProvider);
      ref.invalidate(unreadNotificationListProvider);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}

/// One notification row.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final Notification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = notification.isUnread;
    return Material(
      color: unread ? scheme.primaryContainer.withValues(alpha: 0.12) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: unread ? FontWeight.bold : FontWeight.normal,
            color: unread ? null : scheme.onSurfaceVariant,
          ),
        ),
        subtitle: notification.body != null
            ? Text(
                notification.body!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: unread ? null : scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              Icon(Icons.circle, size: 8, color: scheme.primary),
            const SizedBox(height: 4),
            Text(
              _relativeTime(notification.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _relativeTime(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inDays >= 1) {
      return '${diff.inDays}d ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours}h ago';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes}m ago';
    }
    return 'Just now';
  }
}
