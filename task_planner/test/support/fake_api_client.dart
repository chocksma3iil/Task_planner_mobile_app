import 'package:task_planner/models/models.dart';
import 'package:task_planner/services/api_client.dart';

/// In-memory stand-in for the FastAPI backend.
///
/// It serves the same JSON shapes as the real API and mirrors the main
/// scoping/assignment rules so widget tests exercise the real services,
/// providers, and screens without a network or database.
class FakeApiClient implements ApiClient {
  FakeApiClient();

  @override
  String get baseUrl => 'http://fake.test';

  /// Current session account. Set it directly to simulate an open session.
  Account? me;

  final List<Project> projects = [];
  final List<Account> members = [];
  final List<Task> tasks = [];
  final List<Subtask> subtasks = [];
  final List<Comment> comments = [];
  final List<Notification> notifications = [];

  /// Analytics events, in backend JSON shape plus a `project_id` used to
  /// scope the dashboard response. Newest first is not required: the fake
  /// sorts by `created_at` descending when serving.
  final List<Map<String, dynamic>> analyticsEvents = [];
  final Map<String, String> passwords = {};

  /// Outstanding password-reset codes by email (`forgot-password`). Codes are
  /// deterministic so tests can redeem them.
  final Map<String, String> resetCodes = {};

  /// Audit-trail rows (`audit-logs`) in backend JSON shape, oldest first.
  final List<Map<String, dynamic>> auditLogs = [];

  /// Force a read failure when set (message is surfaced by the screens).
  String? projectsError;
  String? membersError;
  String? tasksError;
  String? notificationsError;

  String? _token;
  void Function()? _onUnauthorized;

  /// When true, every request behaves like an expired session (401).
  bool unauthorized = false;
  int _nextProjectId = 1;
  int _nextAccountId = 1;
  int _nextTaskId = 1;
  int _nextSubtaskId = 1;
  int _nextCommentId = 1;

  String? get token => _token;

  @override
  void setToken(String token) => _token = token;

  @override
  void clearToken() => _token = null;

  @override
  void setUnauthorizedHandler(void Function()? handler) =>
      _onUnauthorized = handler;

  void _guardUnauthorized() {
    if (!unauthorized) {
      return;
    }
    _onUnauthorized?.call();
    throw StateError('Invalid or expired token.');
  }

  /// Adds a roster account (and its password) and returns it.
  Account addAccount(Account account, {String password = 'password123'}) {
    members.add(account);
    passwords[account.email] = password;
    if (account.id >= _nextAccountId) {
      _nextAccountId = account.id + 1;
    }
    return account;
  }

  /// Adds a project and returns it.
  Project addProject(Project project) {
    projects.add(project);
    if (project.id >= _nextProjectId) {
      _nextProjectId = project.id + 1;
    }
    return project;
  }

  /// Adds a task and returns it.
  Task addTask(Task task) {
    tasks.add(task);
    if (task.id >= _nextTaskId) {
      _nextTaskId = task.id + 1;
    }
    return task;
  }

  /// Adds a notification for the signed-in account and returns it.
  Notification addNotification(Notification notification) {
    notifications.add(notification);
    return notification;
  }

  /// Adds an audit-trail row and returns its backend JSON.
  Map<String, dynamic> addAuditLog({
    required String action,
    required Account actor,
    String entityType = 'member',
    int? entityId,
    int? projectId,
    String? details,
    DateTime? createdAt,
  }) {
    final entry = <String, dynamic>{
      'id': auditLogs.length + 1,
      'actor_id': actor.id,
      'actor_name': actor.name,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'project_id': projectId,
      'details': details,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
    auditLogs.add(entry);
    return entry;
  }

  /// Adds a dashboard event for [projectId] and returns its backend JSON.
  Map<String, dynamic> addAnalyticsEvent(
    int projectId,
    String eventType, {
    int? taskId,
    required Account actor,
    DateTime? createdAt,
  }) {
    final event = <String, dynamic>{
      'id': analyticsEvents.length + 1,
      'project_id': projectId,
      'event_type': eventType,
      'task_id': taskId,
      'actor_id': actor.id,
      'actor_name': actor.name,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
    analyticsEvents.add(event);
    return event;
  }

  /// Raw bytes served by [getBytes], keyed by any substring of the path.
  final Map<String, List<int>> exportBytes = {};

  /// Every path requested through [getBytes], in order.
  final List<String> byteRequests = [];

  @override
  Future<List<int>> getBytes(String path) async {
    _guardUnauthorized();
    byteRequests.add(path);
    for (final entry in exportBytes.entries) {
      if (path.contains(entry.key)) {
        return entry.value;
      }
    }
    throw StateError('Unexpected download $path');
  }

  @override
  Future<dynamic> get(String path) async {
    _guardUnauthorized();
    final uri = Uri.parse('http://fake.test$path');
    switch (uri.path) {
      case '/auth/me':
        final account = me;
        if (account == null) {
          throw StateError('Not signed in.');
        }
        return account.toJson();
      case '/projects':
        if (projectsError != null) {
          throw StateError(projectsError!);
        }
        final includeArchived =
            uri.queryParameters['include_archived'] == 'true';
        final visible = includeArchived
            ? projects
            : projects.where((p) => p.status != 'archived').toList();
        return _pageJson(visible.map((p) => p.toJson()).toList(), uri);
      case '/members':
        if (membersError != null) {
          throw StateError(membersError!);
        }
        return _pageJson(
          _visibleMembers().map((m) => m.toJson()).toList(),
          uri,
        );
      case '/tasks':
        if (tasksError != null) {
          throw StateError(tasksError!);
        }
        return _pageJson(_tasks(uri).map((t) => t.toJson()).toList(), uri);
      case '/analytics/dashboard':
        return _dashboard(uri);
      case '/notifications':
        return _notificationPage(uri);
      case '/audit-logs':
        return _auditPage(uri);
    }
    final subtaskMatch = RegExp(r'^/tasks/(\d+)/subtasks$').firstMatch(uri.path);
    if (subtaskMatch != null) {
      final taskId = int.parse(subtaskMatch.group(1)!);
      final items = subtasks
          .where((s) => s.taskId == taskId)
          .map((s) => s.toJson())
          .toList();
      return {'items': items, 'total': items.length};
    }
    final commentMatch = RegExp(r'^/tasks/(\d+)/comments$').firstMatch(uri.path);
    if (commentMatch != null) {
      final taskId = int.parse(commentMatch.group(1)!);
      final items = comments
          .where((c) => c.taskId == taskId && c.deletedAt == null)
          .map((c) => c.toJson())
          .toList();
      return {'items': items, 'total': items.length};
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    _guardUnauthorized();
    final data = body ?? const <String, dynamic>{};
    if (path == '/auth/login') {
      return _login(data);
    }
    if (path == '/auth/signup') {
      return _signup(data);
    }
    if (path == '/auth/forgot-password') {
      return _forgotPassword(data);
    }
    if (path == '/auth/reset-password') {
      return _resetPassword(data);
    }
    if (path == '/projects') {
      _requireAdmin();
      final project = Project(
        id: _nextProjectId++,
        name: data['name'] as String,
        description: data['description'] as String?,
        createdAt: DateTime.now(),
      );
      projects.add(project);
      return project.toJson();
    }
    final ownerMatch = RegExp(r'^/projects/(\d+)/assign-owner$').firstMatch(path);
    if (ownerMatch != null) {
      _requireAdmin();
      final projectId = int.parse(ownerMatch.group(1)!);
      final ownerId = data['owner_id'] as int;
      final index = projects.indexWhere((p) => p.id == projectId);
      final memberIndex = members.indexWhere((m) => m.id == ownerId);
      if (index == -1 || memberIndex == -1) {
        throw StateError('Project or account not found.');
      }
      final project = _copyProject(projects[index], ownerId: ownerId);
      projects[index] = project;
      members[memberIndex] = _copyAccount(
        members[memberIndex],
        role: 'project_owner',
        projectId: projectId,
      );
      return project.toJson();
    }
    if (path == '/members') {
      return _createMember(data);
    }
    final confirmMatch = RegExp(r'^/members/(\d+)/confirm$').firstMatch(path);
    if (confirmMatch != null) {
      return _confirmMember(int.parse(confirmMatch.group(1)!)).toJson();
    }
    final roleMatch = RegExp(r'^/members/(\d+)/role$').firstMatch(path);
    if (roleMatch != null) {
      _requireAdmin();
      final index = members.indexWhere(
        (m) => m.id == int.parse(roleMatch.group(1)!),
      );
      if (index == -1) {
        throw StateError('Account not found.');
      }
      members[index] = _copyAccount(
        members[index],
        role: data['role'] as String,
      );
      return members[index].toJson();
    }
    if (path == '/tasks') {
      return _createTask(data).toJson();
    }
    final bulkMatch = RegExp(r'^/tasks/bulk/(complete|reassign|delete)$').firstMatch(path);
    if (bulkMatch != null) {
      _requireCanMutate();
      final ids = (data['task_ids'] as List).cast<int>();
      final results = <Map<String, dynamic>>[];
      for (final id in ids) {
        try {
          // Mirror the backend: one failure must not abort the batch.
          if (bulkMatch.group(1) == 'complete') {
            _completeTask(id);
          } else if (bulkMatch.group(1) == 'reassign') {
            _updateTask(id, {'assignee_id': data['assignee_id']});
          } else {
            final index = tasks.indexWhere((t) => t.id == id);
            if (index == -1) {
              throw StateError('Task not found.');
            }
            tasks.removeAt(index);
          }
          results.add({'task_id': id, 'success': true});
        } catch (e) {
          results.add({'task_id': id, 'success': false, 'error': '$e'});
        }
      }
      return {
        'results': results,
        'total': results.length,
        'succeeded': results.where((r) => r['success'] == true).length,
        'failed': results.where((r) => r['success'] != true).length,
      };
    }
    final subtaskMatch = RegExp(r'^/tasks/(\d+)/subtasks$').firstMatch(path);
    if (subtaskMatch != null) {
      _requireCanMutate();
      final subtask = Subtask(
        id: _nextSubtaskId++,
        taskId: int.parse(subtaskMatch.group(1)!),
        title: data['title'] as String,
        completed: data['completed'] as bool? ?? false,
        sortOrder: data['sort_order'] as int? ?? 0,
        createdAt: DateTime.now(),
      );
      subtasks.add(subtask);
      return subtask.toJson();
    }
    final commentMatch = RegExp(r'^/tasks/(\d+)/comments$').firstMatch(path);
    if (commentMatch != null) {
      _requireCanMutate();
      final comment = Comment(
        id: _nextCommentId++,
        taskId: int.parse(commentMatch.group(1)!),
        authorId: me!.id,
        body: data['body'] as String,
        mentions: (data['mentions'] as List? ?? <int>[]).cast<int>(),
        createdAt: DateTime.now(),
      );
      comments.add(comment);
      return comment.toJson();
    }
    final aiWeeklyMatch = RegExp(r'^/ai/weekly-plan').firstMatch(path);
    if (aiWeeklyMatch != null) {
      _requireCanMutate();
      final qs = aiWeeklyMatch.group(0)!;
      final projectId = int.parse(qs.split('project_id=').last);
      final project = projects.firstWhere((p) => p.id == projectId);
      if (!project.aiOptIn) {
        throw StateError('AI is disabled for this project.');
      }
      return {
        'title': 'Weekly Plan',
        'tasks': [
          {
            'title': 'Review AI-generated tasks',
            'description': 'Proposed by the AI layer',
            'priority': 'medium',
            'due_date': null,
            'status': 'todo',
          },
        ],
      };
    }
    final aiDecomposeMatch = RegExp(r'^/ai/decompose').firstMatch(path);
    if (aiDecomposeMatch != null) {
      _requireCanMutate();
      return {
        'subtasks': [
          {'title': 'Design', 'description': 'AI-generated subtask', 'priority': 'medium'},
          {'title': 'Implement', 'description': 'AI-generated subtask', 'priority': 'medium'},
          {'title': 'Test', 'description': 'AI-generated subtask', 'priority': 'medium'},
        ],
      };
    }
    final aiBriefingMatch = RegExp(r'^/ai/briefing').firstMatch(path);
    if (aiBriefingMatch != null) {
      _requireCanMutate();
      return {'briefing': 'AI briefing: project is on track.'};
    }
    final aiCaptureMatch = RegExp(r'^/ai/capture$').firstMatch(path);
    if (aiCaptureMatch != null) {
      _requireCanMutate();
      return {
        'title': 'Extracted task',
        'description': 'From natural language input',
        'priority': 'medium',
        'due_date': null,
        'status': 'todo',
      };
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<dynamic> postSlow(
    String path, [
    Map<String, dynamic>? body,
    Duration? timeout,
  ]) =>
      post(path, body);

  @override
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    _guardUnauthorized();
    final data = body ?? const <String, dynamic>{};
    final archiveMatch = RegExp(
      r'^/projects/(\d+)/(archive|restore)$',
    ).firstMatch(path);
    if (archiveMatch != null) {
      _requireAdmin();
      final projectId = int.parse(archiveMatch.group(1)!);
      final index = projects.indexWhere((p) => p.id == projectId);
      if (index == -1) {
        throw StateError('Project not found.');
      }
      projects[index] = _copyProject(
        projects[index],
        status: archiveMatch.group(2) == 'archive' ? 'archived' : 'active',
      );
      return projects[index].toJson();
    }
    final aiOptInMatch = RegExp(r'^/projects/(\d+)/ai-opt-in$').firstMatch(path);
    if (aiOptInMatch != null) {
      final actor = _requireSignedIn();
      final projectId = int.parse(aiOptInMatch.group(1)!);
      final index = projects.indexWhere((p) => p.id == projectId);
      if (index == -1) {
        throw StateError('Project not found.');
      }
      final old = projects[index];
      final canManage =
          actor.role == 'admin' ||
          (actor.role == 'project_owner' && old.ownerId == actor.id);
      if (!canManage) {
        throw StateError('Only an admin or project owner can toggle AI.');
      }
      final aiOptIn = data['ai_opt_in'] as bool? ?? false;
      projects[index] = Project(
        id: old.id,
        name: old.name,
        description: old.description,
        status: old.status,
        ownerId: old.ownerId,
        aiOptIn: aiOptIn,
        createdAt: old.createdAt,
      );
      return projects[index].toJson();
    }
    if (path == '/notifications/read') {
      // The backend silently skips ids that are not the caller's and returns
      // how many rows were actually marked (decision 2026-10-27).
      final ids = (data['notification_ids'] as List).cast<int>().toSet();
      var updated = 0;
      for (var i = 0; i < notifications.length; i += 1) {
        final current = notifications[i];
        if (!ids.contains(current.id) || current.readAt != null) {
          continue;
        }
        notifications[i] = _copyNotification(current, readAt: DateTime.now());
        updated += 1;
      }
      return {'updated': updated};
    }
    final completeMatch = RegExp(r'^/tasks/(\d+)/complete$').firstMatch(path);
    if (completeMatch != null) {
      return _completeTask(int.parse(completeMatch.group(1)!)).toJson();
    }
    final reopenMatch = RegExp(r'^/tasks/(\d+)/reopen$').firstMatch(path);
    if (reopenMatch != null) {
      return _reopenTask(int.parse(reopenMatch.group(1)!)).toJson();
    }
    final editMatch = RegExp(r'^/tasks/(\d+)$').firstMatch(path);
    if (editMatch != null) {
      return _updateTask(int.parse(editMatch.group(1)!), data).toJson();
    }
    final subtaskMatch = RegExp(r'^/tasks/subtasks/(\d+)$').firstMatch(path);
    if (subtaskMatch != null) {
      _requireCanMutate();
      final index = subtasks.indexWhere(
        (s) => s.id == int.parse(subtaskMatch.group(1)!),
      );
      if (index == -1) {
        throw StateError('Subtask not found.');
      }
      final current = subtasks[index];
      final updated = Subtask(
        id: current.id,
        taskId: current.taskId,
        title: (data['title'] as String?) ?? current.title,
        completed: (data['completed'] as bool?) ?? current.completed,
        sortOrder: (data['sort_order'] as int?) ?? current.sortOrder,
        createdAt: current.createdAt,
      );
      subtasks[index] = updated;
      return updated.toJson();
    }
    final commentMatch = RegExp(r'^/tasks/comments/(\d+)$').firstMatch(path);
    if (commentMatch != null) {
      final id = int.parse(commentMatch.group(1)!);
      final index = comments.indexWhere((c) => c.id == id);
      if (index == -1 || comments[index].deletedAt != null) {
        throw StateError('Comment not found.');
      }
      final current = comments[index];
      // Only author can edit.
      if (current.authorId != me!.id) {
        throw StateError('You can only edit your own comments.');
      }
      final updated = Comment(
        id: current.id,
        taskId: current.taskId,
        authorId: current.authorId,
        body: (data['body'] as String?) ?? current.body,
        mentions: current.mentions,
        createdAt: current.createdAt,
        editedAt: DateTime.now(),
        deletedAt: current.deletedAt,
      );
      comments[index] = updated;
      return updated.toJson();
    }
    throw StateError('Unexpected PATCH $path');
  }

  @override
  Future<dynamic> delete(String path) async {
    _guardUnauthorized();
    _requireCanMutate();
    final subtaskMatch = RegExp(r'^/tasks/subtasks/(\d+)$').firstMatch(path);
    if (subtaskMatch != null) {
      final id = int.parse(subtaskMatch.group(1)!);
      subtasks.removeWhere((s) => s.id == id);
      return null;
    }
    final commentMatch = RegExp(r'^/tasks/comments/(\d+)$').firstMatch(path);
    if (commentMatch != null) {
      final id = int.parse(commentMatch.group(1)!);
      final index = comments.indexWhere((c) => c.id == id);
      if (index == -1) {
        throw StateError('Comment not found.');
      }
      // Only author can soft-delete.
      if (comments[index].authorId != me!.id) {
        throw StateError('You can only delete your own comments.');
      }
      comments[index] = Comment(
        id: comments[index].id,
        taskId: comments[index].taskId,
        authorId: comments[index].authorId,
        body: comments[index].body,
        mentions: comments[index].mentions,
        createdAt: comments[index].createdAt,
        deletedAt: DateTime.now(),
      );
      return null;
    }
    final match = RegExp(r'^/tasks/(\d+)$').firstMatch(path);
    if (match == null) {
      throw StateError('Unexpected DELETE $path');
    }
    final id = int.parse(match.group(1)!);
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw StateError('Task not found.');
    }
    tasks.removeAt(index);
    return null;
  }

  Map<String, dynamic> _login(Map<String, dynamic> data) {
    final email = (data['email'] as String).trim().toLowerCase();
    final password = data['password'] as String;
    final account = members.where((m) => m.email == email).firstOrNull;
    if (account == null || passwords[email] != password) {
      throw StateError('Wrong email or password.');
    }
    if (account.status != 'active') {
      throw StateError('Account is waiting for project owner confirmation.');
    }
    me = account;
    _token = 'fake-token';
    return {
      'access_token': _token,
      'token_type': 'bearer',
      'account': account.toJson(),
    };
  }

  Map<String, dynamic> _forgotPassword(Map<String, dynamic> data) {
    final email = (data['email'] as String).trim().toLowerCase();
    // Mirror the server: the answer never reveals whether the account exists.
    final account = members.where((m) => m.email == email).firstOrNull;
    if (account != null && account.status == 'active') {
      resetCodes[email] = 'reset-code-1';
    }
    return {'message': 'If the account exists, a reset code has been sent.'};
  }

  Map<String, dynamic> _resetPassword(Map<String, dynamic> data) {
    final email = (data['email'] as String).trim().toLowerCase();
    final code = (data['code'] as String).trim();
    if (resetCodes[email] != code) {
      throw StateError('Invalid or expired reset code.');
    }
    resetCodes.remove(email);
    passwords[email] = data['new_password'] as String;
    return {'message': 'Password updated. Log in with the new password.'};
  }

  Map<String, dynamic> _signup(Map<String, dynamic> data) {
    final email = (data['email'] as String).trim().toLowerCase();
    if (members.any((m) => m.email == email)) {
      throw StateError('An account with this email already exists.');
    }
    final first = members.isEmpty;
    final projectId = data['project_id'] as int?;
    if (!first) {
      if (projectId == null) {
        throw ArgumentError('Choose a project to join.');
      }
      if (!projects.any((p) => p.id == projectId)) {
        throw StateError('Project not found.');
      }
    }
    final account = Account(
      id: _nextAccountId++,
      name: data['name'] as String,
      email: email,
      position: data['position'] as String?,
      projectId: first ? null : projectId,
      role: first ? 'admin' : 'user',
      status: first ? 'active' : 'pending',
      createdAt: DateTime.now(),
    );
    addAccount(account, password: data['password'] as String);
    return account.toJson();
  }

  Map<String, dynamic> _createMember(Map<String, dynamic> data) {
    final actor = _requireSignedIn();
    _requireCanMutate();
    final role = (data['role'] as String?) ?? 'user';
    final projectId = data['project_id'] as int?;
    if (actor.role != 'admin' &&
        (role != 'user' || projectId != actor.projectId)) {
      throw StateError('Owners can only add plain users to their project.');
    }
    final email = (data['email'] as String).trim().toLowerCase();
    if (members.any((m) => m.email == email)) {
      throw StateError('An account with this email already exists.');
    }
    if (role != 'user' && actor.role != 'admin') {
      throw StateError('Only an admin can do this.');
    }
    final account = Account(
      id: _nextAccountId++,
      name: data['name'] as String,
      email: email,
      position: data['position'] as String?,
      projectId: projectId,
      role: role,
      status: 'active',
      approvedBy: actor.id,
      createdAt: DateTime.now(),
    );
    addAccount(account, password: data['password'] as String);
    return account.toJson();
  }

  Account _confirmMember(int userId) {
    final actor = _requireSignedIn();
    _requireCanMutate();
    final index = members.indexWhere((m) => m.id == userId);
    if (index == -1) {
      throw StateError('Account not found.');
    }
    final target = members[index];
    if (actor.role != 'admin' &&
        (actor.projectId == null || target.projectId != actor.projectId)) {
      throw StateError('You can only confirm your own project members.');
    }
    members[index] = _copyAccount(
      target,
      status: 'active',
      approvedBy: actor.id,
    );
    return members[index];
  }

  Task _createTask(Map<String, dynamic> data) {
    final actor = _requireSignedIn();
    _requireCanMutate();
    final projectId = data['project_id'] as int;
    if (actor.role != 'admin' && actor.projectId != projectId) {
      throw StateError('You can only manage your own project tasks.');
    }
    final assigneeId = data['assignee_id'] as int?;
    if (assigneeId != null) {
      final assignee = members.where((m) => m.id == assigneeId).firstOrNull;
      if (assignee == null) {
        throw StateError('Account not found.');
      }
      if (assignee.status != 'active') {
        throw StateError('Tasks can only be assigned to active members.');
      }
      if (assignee.projectId != projectId) {
        throw ArgumentError('Assignee must belong to the task project.');
      }
    }
    final dueRaw = data['due_date'] as String?;
    final task = Task(
      id: _nextTaskId++,
      title: (data['title'] as String).trim(),
      description: data['description'] as String?,
      priority: (data['priority'] as String?) ?? 'medium',
      dueDate: dueRaw == null ? null : DateTime.tryParse(dueRaw),
      projectId: projectId,
      assigneeId: assigneeId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    tasks.add(task);
    return task;
  }

  Task _updateTask(int id, Map<String, dynamic> data) {
    _requireCanMutate();
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw StateError('Task not found.');
    }
    final current = tasks[index];
    if (data.containsKey('assignee_id') && data['assignee_id'] != null) {
      final assigneeId = data['assignee_id'] as int;
      final assignee = members.where((m) => m.id == assigneeId).firstOrNull;
      if (assignee == null) {
        throw StateError('Account not found.');
      }
      if (assignee.status != 'active') {
        throw StateError('Tasks can only be assigned to active members.');
      }
      if (assignee.projectId != current.projectId) {
        throw ArgumentError('Assignee must belong to the task project.');
      }
    }
    final dueRaw = data['due_date'] as String?;
    final updated = Task(
      id: current.id,
      title: (data['title'] as String?) ?? current.title,
      description: data.containsKey('description')
          ? data['description'] as String?
          : current.description,
      status: current.status,
      priority: (data['priority'] as String?) ?? current.priority,
      dueDate: data.containsKey('due_date')
          ? (dueRaw == null ? null : DateTime.tryParse(dueRaw))
          : current.dueDate,
      projectId: current.projectId,
      assigneeId: data.containsKey('assignee_id')
          ? data['assignee_id'] as int?
          : current.assigneeId,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      completedAt: current.completedAt,
    );
    tasks[index] = updated;
    return updated;
  }

  Task _completeTask(int id) {
    _requireCanMutate();
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw StateError('Task not found.');
    }
    final current = tasks[index];
    tasks[index] = Task(
      id: current.id,
      title: current.title,
      description: current.description,
      status: 'completed',
      priority: current.priority,
      dueDate: current.dueDate,
      projectId: current.projectId,
      assigneeId: current.assigneeId,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      completedAt: DateTime.now(),
    );
    return tasks[index];
  }

  Task _reopenTask(int id) {
    _requireCanMutate();
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw StateError('Task not found.');
    }
    final current = tasks[index];
    tasks[index] = Task(
      id: current.id,
      title: current.title,
      description: current.description,
      status: 'todo',
      priority: current.priority,
      dueDate: current.dueDate,
      projectId: current.projectId,
      assigneeId: current.assigneeId,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    return tasks[index];
  }

  List<Account> _visibleMembers() {
    final viewer = _requireSignedIn();
    if (viewer.role == 'admin') {
      return members;
    }
    if (viewer.projectId == null) {
      throw StateError('Account has not been assigned to a project.');
    }
    return members
        .where((m) => m.projectId == viewer.projectId)
        .toList(growable: false);
  }

  List<Task> _tasks(Uri uri) {
    final projectId = int.tryParse(uri.queryParameters['project_id'] ?? '');
    final assigneeId = int.tryParse(uri.queryParameters['assignee_id'] ?? '');
    if ((projectId == null) == (assigneeId == null)) {
      throw StateError('Provide project_id or assignee_id.');
    }
    final viewer = _requireSignedIn();
    final List<Task> filtered;
    if (projectId != null) {
      if (viewer.role != 'admin' && viewer.projectId != projectId) {
        throw StateError('You can only view your own project tasks.');
      }
      filtered = tasks.where((t) => t.projectId == projectId).toList();
    } else {
      filtered = tasks.where((t) => t.assigneeId == assigneeId).toList();
    }
    final sorted = List<Task>.of(filtered)
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );
    return sorted;
  }

  Account _requireSignedIn() {
    final account = me;
    if (account == null) {
      throw StateError('Not signed in.');
    }
    return account;
  }

  /// Wraps a full result set in the paginated envelope the services parse.
  Map<String, dynamic> _pageJson(
    List<Map<String, dynamic>> all,
    Uri uri,
  ) {
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '') ?? 20;
    final offset = int.tryParse(uri.queryParameters['offset'] ?? '') ?? 0;
    final items = all.skip(offset).take(limit).toList();
    return {
      'items': items,
      'total': all.length,
      'limit': limit,
      'offset': offset,
    };
  }

  /// Mirrors `GET /analytics/dashboard`: project-scoped KPIs plus events.
  Map<String, dynamic> _dashboard(Uri uri) {
    final viewer = _requireSignedIn();
    final projectId = int.tryParse(uri.queryParameters['project_id'] ?? '');
    if (projectId == null) {
      throw StateError('project_id is required.');
    }
    final project = projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) {
      throw StateError('Project not found.');
    }
    if (viewer.role != 'admin' && viewer.projectId != projectId) {
      throw StateError('You can only view your own project analytics.');
    }
    final scoped = tasks.where((t) => t.projectId == projectId).toList();
    final completed = scoped
        .where((t) => t.status == 'completed')
        .length;
    final pending = scoped.length - completed;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var overdue = 0;
    final priorityMix = <String, int>{'low': 0, 'medium': 0, 'high': 0};
    for (final task in scoped) {
      priorityMix[task.priority] = (priorityMix[task.priority] ?? 0) + 1;
      final due = task.dueDate;
      if (task.status != 'completed' &&
          due != null &&
          DateTime(due.year, due.month, due.day).isBefore(today)) {
        overdue += 1;
      }
    }
    final events = analyticsEvents
        .where((e) => e['project_id'] == projectId)
        .toList()
      ..sort(
        (a, b) => (b['created_at'] as String).compareTo(
          a['created_at'] as String,
        ),
      );
    return {
      'project_id': projectId,
      'project_name': project.name,
      'total_tasks': scoped.length,
      'completed_tasks': completed,
      'pending_tasks': pending,
      'overdue_tasks': overdue,
      'completion_rate': scoped.isEmpty ? 0.0 : completed * 100 / scoped.length,
      'overdue_rate': scoped.isEmpty ? 0.0 : overdue * 100 / scoped.length,
      'priority_mix': priorityMix,
      'velocity_per_week': completed / 4,
      'recent_events': [
        for (final event in events.take(20))
          {
            for (final entry in event.entries)
              if (entry.key != 'project_id') entry.key: entry.value,
          },
      ],
    };
  }

  /// Mirrors `GET /audit-logs`: admin-only, newest first, optionally scoped
  /// to one project.
  Map<String, dynamic> _auditPage(Uri uri) {
    final viewer = _requireSignedIn();
    if (viewer.role != 'admin') {
      throw StateError('Only an admin can do this.');
    }
    final projectId = int.tryParse(uri.queryParameters['project_id'] ?? '');
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '') ?? 50;
    final offset = int.tryParse(uri.queryParameters['offset'] ?? '') ?? 0;
    final filtered = auditLogs
        .where((e) => projectId == null || e['project_id'] == projectId)
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return {
      'items': filtered.skip(offset).take(limit).toList(),
      'total': filtered.length,
      'limit': limit,
      'offset': offset,
    };
  }

  /// Mirrors `GET /notifications`: the caller's notifications, optionally
  /// unread only, newest first, with the unread count over the filter.
  Map<String, dynamic> _notificationPage(Uri uri) {
    if (notificationsError != null) {
      throw StateError(notificationsError!);
    }
    _requireSignedIn();
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '') ?? 20;
    final offset = int.tryParse(uri.queryParameters['offset'] ?? '') ?? 0;
    final unreadOnly = uri.queryParameters['unread_only'] == 'true';
    final filtered = notifications
        .where((n) => !unreadOnly || n.isUnread)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return {
      'items': filtered.skip(offset).take(limit).map((n) => n.toJson()).toList(),
      'total': filtered.length,
      'unread': notifications.where((n) => n.isUnread).length,
      'limit': limit,
      'offset': offset,
    };
  }

  void _requireAdmin() {
    if (_requireSignedIn().role != 'admin') {
      throw StateError('Only an admin can do this.');
    }
  }

  /// Viewers are read-only on the server; mutations are refused up front.
  void _requireCanMutate() {
    if (_requireSignedIn().role == 'viewer') {
      throw StateError('A viewer cannot change data.');
    }
  }
}

Account _copyAccount(
  Account account, {
  String? role,
  int? projectId,
  String? status,
  int? approvedBy,
}) {
  return Account(
    id: account.id,
    name: account.name,
    position: account.position,
    projectId: projectId ?? account.projectId,
    email: account.email,
    role: role ?? account.role,
    status: status ?? account.status,
    approvedBy: approvedBy ?? account.approvedBy,
    createdAt: account.createdAt,
  );
}

Project _copyProject(Project project, {int? ownerId, String? status}) {
  return Project(
    id: project.id,
    name: project.name,
    description: project.description,
    status: status ?? project.status,
    ownerId: ownerId ?? project.ownerId,
    createdAt: project.createdAt,
  );
}

Notification _copyNotification(Notification notification, {DateTime? readAt}) {
  return Notification(
    id: notification.id,
    type: notification.type,
    title: notification.title,
    body: notification.body,
    payload: notification.payload,
    readAt: readAt ?? notification.readAt,
    createdAt: notification.createdAt,
  );
}

