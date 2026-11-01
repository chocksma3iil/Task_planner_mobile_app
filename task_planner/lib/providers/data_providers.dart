import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/audit_service.dart';
import '../services/auth_service.dart';
import '../services/data_sync.dart';
import '../services/export_service.dart';
import '../services/member_service.dart';
import '../services/notification_service.dart';
import '../services/project_service.dart';
import '../services/subtask_service.dart';
import '../services/task_service.dart';
import '../services/comment_service.dart';
import '../services/ai_service.dart';
import 'api_providers.dart';
import 'session_providers.dart';

// --- Pagination state ---

class PaginatedList<T> {
  const PaginatedList({
    required this.items,
    this.page = 1,
    this.pageSize = 20,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  PaginatedList<T> copyWith({
    List<T>? items,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
  }) {
    return PaginatedList<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }

  PaginatedList<T> get firstPageLoading => copyWith(page: 1, isLoading: true, error: null);

  PaginatedList<T> get loadingMore => copyWith(isLoadingMore: true, error: null);
}

// --- Paginated feeds ---

/// One page returned by a paginated service call.
class PageResult<T> {
  const PageResult({required this.items, required this.total});

  final List<T> items;
  final int total;
}

/// Emits a new tick after every successful mutation (DataSync ping), so
/// paginated feeds reload their first page without a provider invalidation.
final dataSyncTickProvider = StreamProvider<int>((ref) {
  var tick = 0;
  return DataSync.instance.changes.map((_) => ++tick);
});

/// Shared accumulation logic for a paginated feed.
///
/// The first page loads on build. [loadMore] appends the next page, removes
/// duplicates by [keyOf], and stops when the server's total is reached.
/// Mutations reload the first page so the visible rows stay fresh.
abstract class PaginatedNotifier<T> extends AsyncNotifier<PaginatedList<T>> {
  int get pageSize => 20;

  /// Stable identity of one row, used to drop duplicates across pages.
  Object keyOf(T item);

  /// Fetches one page starting at [offset].
  Future<PageResult<T>> fetchPage({
    required int offset,
    required int limit,
  });

  /// Incremented when a refresh/reload starts so stale responses are ignored.
  int _generation = 0;

  @override
  Future<PaginatedList<T>> build() async {
    // A different account sees a different scope, so rebuild the feed.
    ref.watch(sessionUserIdProvider);
    // Mutations ping DataSync; reload page one while keeping rows visible.
    ref.listen(dataSyncTickProvider, (_, _) => _reload());
    final page = await fetchPage(offset: 0, limit: pageSize);
    return _buildList(page);
  }

  PaginatedList<T> _buildList(PageResult<T> page, {int number = 1}) {
    return PaginatedList<T>(
      items: page.items,
      page: number,
      pageSize: pageSize,
      hasMore: page.items.length < page.total,
    );
  }

  /// Appends the next page. Safe to call repeatedly while scrolling.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.isLoading ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await fetchPage(
        offset: current.items.length,
        limit: pageSize,
      );
      if (!ref.mounted || generation != _generation) {
        return;
      }
      final seen = current.items.map(keyOf).toSet();
      final merged = [
        ...current.items,
        ...page.items.where((item) => !seen.contains(keyOf(item))),
      ];
      state = AsyncData(
        PaginatedList<T>(
          items: merged,
          page: current.page + 1,
          pageSize: pageSize,
          hasMore: merged.length < page.total,
        ),
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      // Keep the rows already loaded; the next scroll retries.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Reloads the first page (pull-to-refresh and retry actions).
  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final page = await fetchPage(offset: 0, limit: pageSize);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AsyncData(_buildList(page));
    } catch (e, st) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AsyncError(e, st);
    }
  }

  /// Reloads page one after a mutation; failures keep the last good page.
  Future<void> _reload() async {
    if (state.isLoading) {
      return;
    }
    final generation = ++_generation;
    try {
      final page = await fetchPage(offset: 0, limit: pageSize);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AsyncData(_buildList(page));
    } catch (_) {
      // A transient failure must not replace visible rows with an error.
    }
  }
}

// --- Providers ---

final projectServiceProvider = Provider<ProjectService>(
  (ref) => ProjectService(ref.watch(apiClientProvider)),
);

final taskServiceProvider = Provider<TaskService>(
  (ref) => TaskService(ref.watch(apiClientProvider)),
);

final memberServiceProvider = Provider<MemberService>(
  (ref) => MemberService(ref.watch(apiClientProvider)),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

class ProjectListNotifier extends PaginatedNotifier<Project> {
  @override
  Object keyOf(Project item) => item.id;

  @override
  Future<PageResult<Project>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final page = await ref
        .read(projectServiceProvider)
        .fetchProjects(limit: limit, offset: offset);
    return PageResult(items: page.items, total: page.total);
  }
}

/// All projects, paginated and accumulated across pages.
final projectListProvider =
    AsyncNotifierProvider<ProjectListNotifier, PaginatedList<Project>>(
      ProjectListNotifier.new,
    );

class ProjectTasksNotifier extends PaginatedNotifier<Task> {
  ProjectTasksNotifier(this.projectId);

  final int projectId;

  @override
  Object keyOf(Task item) => item.id;

  @override
  Future<PageResult<Task>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final page = await ref
        .read(taskServiceProvider)
        .fetchProjectTasks(projectId, limit: limit, offset: offset);
    return PageResult(items: page.items, total: page.total);
  }
}

/// Tasks of one project, paginated. Family key is [projectId].
final projectTasksProvider =
    AsyncNotifierProvider.family<
      ProjectTasksNotifier,
      PaginatedList<Task>,
      int
    >(ProjectTasksNotifier.new);

class MyTasksNotifier extends PaginatedNotifier<Task> {
  MyTasksNotifier(this.assigneeId);

  final int assigneeId;

  @override
  Object keyOf(Task item) => item.id;

  @override
  Future<PageResult<Task>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final page = await ref
        .read(taskServiceProvider)
        .fetchTasksAssignedTo(assigneeId, limit: limit, offset: offset);
    return PageResult(items: page.items, total: page.total);
  }
}

/// Tasks assigned to one person, paginated. Family key is [assigneeId].
final myTasksProvider =
    AsyncNotifierProvider.family<MyTasksNotifier, PaginatedList<Task>, int>(
      MyTasksNotifier.new,
    );

class VisibleMembersNotifier extends PaginatedNotifier<Account> {
  @override
  Object keyOf(Account item) => item.id;

  @override
  Future<PageResult<Account>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final page = await ref
        .read(memberServiceProvider)
        .fetchVisibleMembers(limit: limit, offset: offset);
    return PageResult(items: page.items, total: page.total);
  }
}

/// Members visible to the caller, paginated and accumulated across pages.
final visibleMembersProvider =
    AsyncNotifierProvider<VisibleMembersNotifier, PaginatedList<Account>>(
      VisibleMembersNotifier.new,
    );

/// Notification service.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.watch(apiClientProvider)),
);

/// First page of the caller's notifications.
final notificationListProvider = FutureProvider<NotificationList>((ref) async {
  ref.watch(sessionUserIdProvider);
  final service = ref.watch(notificationServiceProvider);
  return service.list(limit: 20, offset: 0);
});

/// First page of unread notifications.
final unreadNotificationListProvider = FutureProvider<NotificationList>((ref) async {
  ref.watch(sessionUserIdProvider);
  final service = ref.watch(notificationServiceProvider);
  return service.list(limit: 20, offset: 0, unreadOnly: true);
});

/// Audit service (D06).
final auditServiceProvider = Provider<AuditService>(
  (ref) => AuditService(ref.watch(apiClientProvider)),
);

/// Project report export service (E03).
final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(apiClientProvider)),
);

/// First page of the admin audit trail; `null` means every project.
final auditLogProvider = FutureProvider.family<AuditLogList, int?>((
  ref,
  projectId,
) async {
  ref.watch(sessionUserIdProvider);
  final service = ref.watch(auditServiceProvider);
  return service.fetchPage(projectId: projectId);
});

/// Analytics service.
final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(ref.watch(apiClientProvider)),
);

/// Subtask service.
final subtaskServiceProvider = Provider<SubtaskService>(
  (ref) => SubtaskService(ref.watch(apiClientProvider)),
);

/// Comment service.
final commentServiceProvider = Provider<CommentService>(
  (ref) => CommentService(ref.watch(apiClientProvider)),
);

/// AI service (v2.0): read-only proposals, human approval required to write.
final aiServiceProvider = Provider<AiService>(
  (ref) => AiService(ref.watch(apiClientProvider)),
);

/// Dashboard stats for one project. Family key is [projectId].
final dashboardStatsProvider = FutureProvider.family<DashboardStats, int>(
  (ref, projectId) async {
    ref.watch(sessionUserIdProvider);
    final service = ref.watch(analyticsServiceProvider);
    return service.getDashboard(projectId);
  },
);
