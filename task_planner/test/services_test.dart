import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/core/database.dart';
import 'package:task_planner/core/rules.dart';
import 'package:task_planner/features/auth/application/auth_service.dart';
import 'package:task_planner/features/settings/application/theme_mode_provider.dart';
import 'package:task_planner/features/tasks/application/member_service.dart';
import 'package:task_planner/features/tasks/application/project_service.dart';
import 'package:task_planner/features/tasks/application/task_service.dart';

/// Service-level tests against an in-memory database.
void main() {
  late AppDatabase db;
  late AuthService auth;
  late MemberService members;
  late ProjectService projects;
  late TaskService tasks;

  setUp(() {
    db = AppDatabase.memory();
    auth = AuthService(db);
    members = MemberService(db);
    projects = ProjectService(db);
    tasks = TaskService(db);
  });

  tearDown(() => db.close());

  test('first sign-up becomes the active admin (bootstrap)', () async {
    final admin = await auth.signUp(
      name: 'Root',
      email: 'root@example.com',
      password: 'pw',
    );
    expect(admin.role, Roles.admin);
    expect(admin.status, MemberStatus.active);
  });

  test('later sign-ups start pending and cannot log in', () async {
    await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final admin =
        await auth.login(email: 'root@example.com', password: 'pw');
    final project =
        await projects.createProject(actor: admin, name: 'Mobile App');
    final pending = await auth.signUp(
      name: 'Sara',
      email: 'sara@example.com',
      password: 'pw',
      projectId: project.id,
    );
    expect(pending.status, MemberStatus.pending);
    expect(
      () => auth.login(email: 'sara@example.com', password: 'pw'),
      throwsStateError,
    );
  });

  test('owner confirmation activates the account and records approver',
      () async {
    final admin = await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final project =
        await projects.createProject(actor: admin, name: 'Mobile App');
    final owner = await members.createUser(
      actor: admin,
      name: 'Ahmed',
      email: 'ahmed@example.com',
      password: 'pw',
      projectId: project.id,
    );
    await projects.assignOwner(
        actor: admin, projectId: project.id, ownerId: owner.id);
    final pending = await auth.signUp(
      name: 'Sara',
      email: 'sara@example.com',
      password: 'pw',
      projectId: project.id,
    );
    final ownerLogin =
        await auth.login(email: 'ahmed@example.com', password: 'pw');
    expect(ownerLogin.role, Roles.projectOwner);
    final confirmed =
        await members.confirmUser(actor: ownerLogin, userId: pending.id);
    expect(confirmed.status, MemberStatus.active);
    expect(confirmed.approvedBy, ownerLogin.id);
    final login =
        await auth.login(email: 'sara@example.com', password: 'pw');
    expect(login.id, pending.id);
  });

  test('cross-project assignment is rejected', () async {
    final admin = await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final a = await projects.createProject(actor: admin, name: 'A');
    final b = await projects.createProject(actor: admin, name: 'B');
    final outsider = await members.createUser(
      actor: admin,
      name: 'Out',
      email: 'out@example.com',
      password: 'pw',
      projectId: b.id,
    );
    expect(
      () => tasks.createTask(
        actor: admin,
        projectId: a.id,
        title: 'Fix login',
        assigneeId: outsider.id,
      ),
      throwsArgumentError,
    );
  });

  test('completing a task stamps it, reopening clears the stamp', () async {
    final admin = await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final project =
        await projects.createProject(actor: admin, name: 'Mobile App');
    final task = await tasks.createTask(
        actor: admin, projectId: project.id, title: 'Fix login');
    expect(task.status, TaskStatus.todo);
    final done =
        await tasks.completeTask(actor: admin, taskId: task.id);
    expect(done.status, TaskStatus.completed);
    expect(done.completedAt, isNotNull);
    final reopened =
        await tasks.reopenTask(actor: admin, taskId: task.id);
    expect(reopened.status, TaskStatus.todo);
    expect(reopened.completedAt, isNull);
  });

  test('non-admins cannot create projects or change roles', () async {
    final admin = await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final project =
        await projects.createProject(actor: admin, name: 'Mobile App');
    final user = await members.createUser(
      actor: admin,
      name: 'Sara',
      email: 'sara@example.com',
      password: 'pw',
      projectId: project.id,
    );
    expect(
      () => projects.createProject(actor: user, name: 'Nope'),
      throwsStateError,
    );
    expect(
      () => members.changeRole(
          actor: user, userId: user.id, role: Roles.admin),
      throwsStateError,
    );
  });

  test('watchVisibleMembers fails clearly for a non-admin without a project',
      () async {
    final admin = await auth.signUp(
        name: 'Root', email: 'root@example.com', password: 'pw');
    final orphan = await members.createUser(
      actor: admin,
      name: 'Orphan',
      email: 'orphan@example.com',
      password: 'pw',
    );
    expect(orphan.projectId, isNull);
    expect(orphan.role, Roles.user);
    expect(
      () => members.watchVisibleMembers(orphan),
      throwsStateError,
    );
  });

  test('settings write/read round-trips and overwrites', () async {
    final settings = SettingsService(db);
    expect(await settings.read('themeMode'), isNull);
    await settings.write('themeMode', 'dark');
    expect(await settings.read('themeMode'), 'dark');
    await settings.write('themeMode', 'light');
    expect(await settings.read('themeMode'), 'light');
  });
}
