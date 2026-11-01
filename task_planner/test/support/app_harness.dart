import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_planner/app/app.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/api_providers.dart';
import 'package:task_planner/providers/session_providers.dart';

import 'fake_api_client.dart';

/// Boots the real app against [api].
///
/// Pass [account] to start with an open session; leave it null to exercise
/// the login/sign-up flow. A fixed pump loop avoids `pumpAndSettle` hanging
/// on an unexpectedly stuck spinner.
Future<ProviderContainer> pumpTaskPlanner(
  WidgetTester tester,
  FakeApiClient api, {
  Account? account,
  Map<String, Object> prefs = const {},
  bool setSession = true,
  // `Override` is not exported by flutter_riverpod 3.x, so the parameter is
  // untyped and each caller passes its own override list.
  List<dynamic> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  api.me = account;
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api), ...overrides],
  );
  addTearDown(container.dispose);
  if (account != null && setSession) {
    container.read(sessionUserIdProvider.notifier).set(account.id);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TaskPlannerApp(),
    ),
  );
  await settle(tester);
  return container;
}

/// Pumps a bounded number of frames so streams and animations can emit.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Standard fixture: admin, project Alpha, an active owner, and an active user.
class Fixture {
  Fixture()
    : admin = Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
      ),
      owner = Account(
        id: 2,
        name: 'Olive Owner',
        email: 'olive@example.com',
        position: 'Project Manager',
        projectId: 1,
        role: 'project_owner',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
      ),
      user = Account(
        id: 3,
        name: 'Bob Builder',
        email: 'bob@example.com',
        projectId: 1,
        role: 'user',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
      ),
      pending = Account(
        id: 4,
        name: 'Carol Guest',
        email: 'carol@example.com',
        projectId: 1,
        role: 'user',
        status: 'pending',
        createdAt: DateTime(2026, 1, 1),
      ),
      viewer = Account(
        id: 5,
        name: 'Viewy McViewface',
        email: 'viewer@example.com',
        projectId: 1,
        role: 'viewer',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
      ),
      project = Project(
        id: 1,
        name: 'Alpha',
        ownerId: 2,
        createdAt: DateTime(2026, 1, 1),
      ) {
    api = FakeApiClient();
    api.addProject(project);
    api.addAccount(admin);
    api.addAccount(owner);
    api.addAccount(user);
    api.addAccount(pending);
    api.addAccount(viewer);
  }

  late final FakeApiClient api;
  final Account admin;
  final Account owner;
  final Account user;
  final Account pending;
  final Account viewer;
  final Project project;
}
