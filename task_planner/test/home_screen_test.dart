import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/app/app.dart';
import 'package:task_planner/core/database.dart';
import 'package:task_planner/features/auth/application/auth_service.dart';
import 'package:task_planner/features/auth/presentation/session_providers.dart';
import 'package:task_planner/features/settings/application/theme_mode_provider.dart';
import 'package:task_planner/features/tasks/application/member_service.dart';
import 'package:task_planner/features/tasks/application/project_service.dart';
import 'package:task_planner/features/tasks/application/task_service.dart';

/// Widget tests for the post-login shell: each role must see its tabs and
/// data without stuck spinners, fake emptiness, or "Logged out." states.
void main() {
  late AppDatabase db;
  late Assignee admin;
  late Assignee owner;
  late Assignee user;

  setUp(() async {
    final auth = AuthService(db = AppDatabase.memory());
    final members = MemberService(db);
    final projects = ProjectService(db);
    admin = await auth.signUp(
      name: 'Root Admin',
      email: 'root@example.com',
      password: 'pw',
    );
    final project =
        await projects.createProject(actor: admin, name: 'Alpha');
    owner = await members.createUser(
      actor: admin,
      name: 'Olive Owner',
      email: 'olive@example.com',
      password: 'pw',
      position: 'Project Manager',
      projectId: project.id,
    );
    await projects.assignOwner(
        actor: admin, projectId: project.id, ownerId: owner.id);
    user = await members.createUser(
      actor: admin,
      name: 'Bob Builder',
      email: 'bob@example.com',
      password: 'pw',
      projectId: project.id,
    );
    await auth.signUp(
      name: 'Carol Guest',
      email: 'carol@example.com',
      password: 'pw',
      projectId: project.id,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, Assignee account) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(sessionUserIdProvider.notifier).set(account.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TaskPlannerApp(),
      ),
    );
    // Never pumpAndSettle: a stuck loading spinner would hang the test.
    // Fixed pumps are exactly what surfaces the reported symptoms.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('admin sees three tabs and the full roster in Members',
      (tester) async {
    await pumpApp(tester, admin);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Logged out.'), findsNothing);

    await tester.tap(find.text('Members'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Root Admin'), findsWidgets);
    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.text('Bob Builder'), findsWidgets);
    expect(find.text('Carol Guest'), findsWidgets);
    expect(find.text('Waiting for confirmation'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'project owner lands on Members with roster and pending section',
      (tester) async {
    await pumpApp(tester, owner);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Projects'), findsNothing);
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Logged out.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Waiting for confirmation'), findsOneWidget);
    expect(find.text('Bob Builder'), findsWidgets);
    expect(find.text('Carol Guest'), findsWidgets);
  });

  testWidgets('plain user sees names but no status or pending section',
      (tester) async {
    await pumpApp(tester, user);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Waiting for confirmation'), findsNothing);
    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.text('Carol Guest'), findsWidgets);
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Logged out.'), findsNothing);
    // Status chips are owner/admin only (access-control skill).
    expect(find.text('active'), findsNothing);
    expect(find.text('pending'), findsNothing);
  });

  testWidgets('owner Tasks tab loads without waiting on the projects stream',
      (tester) async {
    await pumpApp(tester, owner);

    await tester.tap(find.text('Tasks'));
    // One frame to build the tab and subscribe to the task stream, then
    // time for the stream to emit and a frame to render it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No tasks here'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });

  testWidgets('theme picker switches the app to dark and persists it',
      (tester) async {
    await pumpApp(tester, user);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(await SettingsService(db).read('themeMode'), 'dark');
  });

  testWidgets('Mine tab shows only tasks assigned to the logged-in user',
      (tester) async {
    final taskService = TaskService(db);
    await taskService.createTask(
      actor: admin,
      projectId: owner.projectId!,
      title: 'Assigned to Bob',
      assigneeId: user.id,
    );
    await taskService.createTask(
      actor: admin,
      projectId: owner.projectId!,
      title: 'Whole project task',
    );

    await pumpApp(tester, user);

    await tester.tap(find.text('Mine'));
    // One frame to switch tabs and subscribe, then time for the stream.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Assigned to me'), findsOneWidget);
    expect(find.text('Assigned to Bob'), findsOneWidget);
    expect(find.text('Whole project task'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
