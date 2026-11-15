import '../models/models.dart';
import '../services/api_client.dart';

class NotificationService {
  NotificationService(this._client);

  final ApiClient _client;

  /// List the caller's notifications.
  Future<NotificationList> list({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (unreadOnly) 'unread_only': 'true',
    };
    final qs = query.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final json = await _client.get('/notifications?$qs') as Map<String, dynamic>;
    return NotificationList.fromJson(json);
  }

  /// Mark notifications as read.
  Future<void> markRead(List<int> ids) async {
    await _client.patch('/notifications/read', {
      'notification_ids': ids,
    });
  }
}

/// Paginated response for notification lists.
class NotificationList {
  const NotificationList({
    required this.items,
    required this.total,
    required this.unread,
    required this.limit,
    required this.offset,
  });

  final List<Notification> items;
  final int total;
  final int unread;
  final int limit;
  final int offset;

  factory NotificationList.fromJson(Map<String, dynamic> json) => NotificationList(
    items: (json['items'] as List)
        .map((e) => Notification.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: json['total'] as int,
    unread: json['unread'] as int,
    limit: json['limit'] as int,
    offset: json['offset'] as int,
  );

  bool get hasMore => offset + items.length < total;
}
