import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_planner/app/app.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/api_providers.dart';
import 'package:task_planner/providers/session_providers.dart';

import 'support/fake_api_client.dart';

import 'support/app_harness.dart';

/// Widget tests for the post-login shell: each role must see its tabs and
/// data without stuck spinners, fake emptiness, or "Logged out." states.
void main() {
  late FakeApiClient api;
  late Account admin;
  late Account owner;
  late Account user;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeApiClient();
    admin = const Account(
      id: 1,
      name: 'Root Admin',
      email: 'root@example.com',
      role: 'admin',
      status: 'active',
    );
    owner = const Account(
      id: 2,
      name: 'Olive Owner',
      email: 'olive@example.com',
      position: 'Project Manager',
      projectId: 1,
      role: 'project_owner',
      status: 'active',
    );
    user = const Account(
      id: 3,
      name: 'Bob Builder',
      email: 'bob@example.com',
      projectId: 1,
      role: 'user',
      status: 'active',
    );
    final carol = const Account(
      id: 4,
      name: 'Carol Guest',
      email: 'carol@example.com',
      projectId: 1,
      role: 'user',
      status: 'pending',
    );
    api.members.addAll([admin, owner, user, carol]);
    api.projects.add(const Project(id: 1, name: 'Alpha'));
  });

  Future<void> pumpApp(WidgetTester tester, Account account) async {
    api.me = account;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
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

  testWidgets('admin sees three tabs and the full roster in Members', (
    tester,
  ) async {
    await pumpApp(tester, admin);
    await settle(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Logged out.'), findsNothing);

    await tester.tap(find.text('Members'));
    await settle(tester);

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

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('Projects'), findsNothing);
      expect(find.text('No members yet'), findsNothing);
      expect(find.text('Logged out.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Waiting for confirmation'), findsOneWidget);
      expect(find.text('Bob Builder'), findsWidgets);
      expect(find.text('Carol Guest'), findsWidgets);
    },
  );

  testWidgets('plain user sees names but no status or pending section', (
    tester,
  ) async {
    await pumpApp(tester, user);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Waiting for confirmation'), findsNothing);
    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.text('Carol Guest'), findsWidgets);
    expect(find.text('No members yet'), findsNothing);
    expect(find.text('Logged out.'), findsNothing);
    // Status chips are owner/admin only (access-control skill).
    expect(find.text('active'), findsNothing);
    expect(find.text('pending'), findsNothing);
  });

  testWidgets('owner Tasks tab loads without waiting on the projects stream', (
    tester,
  ) async {
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

  testWidgets('theme picker switches the app to dark and persists it', (
    tester,
  ) async {
    await pumpApp(tester, user);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('themeMode'), 'dark');
  });

  testWidgets('tapping a task edits it through the API', (tester) async {
    api.tasks.add(
      Task(
        id: 9,
        title: 'Draft title',
        projectId: 1,
        priority: 'low',
        createdAt: DateTime.now(),
      ),
    );

    await pumpApp(tester, user);
    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Draft title'));
    await tester.pump();
    expect(find.text('Edit task'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Draft title'),
      'Edited title',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.tasks.single.title, 'Edited title');
    expect(find.text('Edited title'), findsOneWidget);
    expect(find.text('Draft title'), findsNothing);
  });

  testWidgets('Mine tab shows only tasks assigned to the logged-in user', (
    tester,
  ) async {
    final now = DateTime.now();
    api.tasks.addAll([
      Task(
        id: 1,
        title: 'Assigned to Bob',
        projectId: 1,
        assigneeId: user.id,
        createdAt: now,
      ),
      Task(
        id: 2,
        title: 'Whole project task',
        projectId: 1,
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
    ]);

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

  testWidgets('admin has no personal Mine tab', (tester) async {
    await pumpApp(tester, admin);

    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Mine'), findsNothing);
    expect(find.byTooltip('Add user'), findsNothing);
  });

  testWidgets('role changes made elsewhere refresh when the app resumes', (
    tester,
  ) async {
    await pumpApp(tester, user);
    expect(find.text('Planner'), findsOneWidget);

    // The admin changes this account to viewer while the app is backgrounded.
    api.me = const Account(
      id: 3,
      name: 'Bob Builder',
      email: 'bob@example.com',
      projectId: 1,
      role: 'viewer',
      status: 'active',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Viewer tabs only, and the shell stays usable (no stale index).
    expect(find.text('Planner'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Logged out.'), findsNothing);
  });
}
