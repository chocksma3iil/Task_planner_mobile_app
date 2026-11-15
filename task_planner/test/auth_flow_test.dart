import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/api_providers.dart';
import 'package:task_planner/providers/data_providers.dart';
import 'package:task_planner/providers/session_providers.dart';

import 'support/app_harness.dart';
import 'support/fake_api_client.dart';

void main() {
  testWidgets('login success opens the role tabs and stores a token', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.enterText(find.byType(TextField).at(0), 'root@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    expect(api.token, 'fake-token');
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Projects'), findsWidgets);
  });

  testWidgets('a successful login remembers the email for next time', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.enterText(find.byType(TextField).at(0), 'root@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_login_email'), 'root@example.com');
    // The password itself is never stored.
    expect(prefs.getString('last_login_password'), isNull);
  });

  testWidgets('the remembered email is pre-filled on the login screen', (
    tester,
  ) async {
    final api = FakeApiClient();
    await pumpTaskPlanner(
      tester,
      api,
      prefs: const {'last_login_email': 'saved@example.com'},
    );
    await settle(tester);

    final emailField = tester.widget<TextField>(find.byType(TextField).first);
    expect(emailField.controller?.text, 'saved@example.com');
    final passwordField = tester.widget<TextField>(
      find.byType(TextField).at(1),
    );
    expect(passwordField.controller?.text, isEmpty);
  });

  testWidgets('login shows the server message for a wrong password', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.enterText(find.byType(TextField).at(0), 'root@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNothing);
  });

  testWidgets('pending accounts are blocked with the approval message', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 2,
        name: 'Sara',
        email: 'sara@example.com',
        projectId: 1,
        role: 'user',
        status: 'pending',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.enterText(find.byType(TextField).at(0), 'sara@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    expect(
      find.text('Account is waiting for project owner confirmation.'),
      findsOneWidget,
    );
    expect(find.byType(NavigationDestination), findsNothing);
  });

  testWidgets(
    'first sign-up explains the admin bootstrap and returns to login',
    (tester) async {
      final api = FakeApiClient();
      await pumpTaskPlanner(tester, api);

      await tester.tap(find.text('Create an account'));
      await settle(tester);
      expect(find.textContaining('first account'), findsOneWidget);
      expect(find.text('Project to join'), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), 'Root Admin');
      await tester.enterText(find.byType(TextField).at(1), 'root@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
      await settle(tester);

      expect(
        find.text('Admin account created. You can log in now.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
      expect(api.members.single.role, 'admin');
      expect(api.members.single.status, 'active');
    },
  );

  testWidgets(
    'later sign-up requires a project and creates a pending account',
    (tester) async {
      final fixture = Fixture();
      await pumpTaskPlanner(tester, fixture.api);

      await tester.tap(find.text('Create an account'));
      await settle(tester);
      expect(find.text('Project to join'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Sara');
      await tester.enterText(find.byType(TextField).at(1), 'sara@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
      await settle(tester);
      expect(find.text('Choose a project to join.'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Alpha').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
      await settle(tester);

      expect(
        find.textContaining('Wait for project owner confirmation'),
        findsOneWidget,
      );
      final sara = fixture.api.members.firstWhere(
        (m) => m.email == 'sara@example.com',
      );
      expect(sara.status, 'pending');
      expect(sara.projectId, fixture.project.id);
    },
  );

  testWidgets('logout clears the session and returns to the login screen', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api.setToken('existing-token');
    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.user,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text('Log out'));
    await settle(tester);

    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(fixture.api.token, isNull);
    expect(container.read(sessionUserIdProvider), isNull);
  });

  test(
    'a new session reloads the roster instead of reusing the old scope',
    () async {
      final fixture = Fixture();
      fixture.api.addProject(
        Project(id: 2, name: 'Beta', createdAt: DateTime(2026, 1, 1)),
      );
      fixture.api.addAccount(
        Account(
          id: 5,
          name: 'Bruno Beta',
          email: 'bruno@example.com',
          projectId: 2,
          role: 'project_owner',
          status: 'active',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      fixture.api.me = fixture.user;
      fixture.api.setToken('user-token');
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(fixture.api)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(visibleMembersProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(sessionUserIdProvider.notifier).set(fixture.user.id);
      final scoped = await container.read(visibleMembersProvider.future);
      expect(scoped.items.map((m) => m.name), isNot(contains('Bruno Beta')));

      fixture.api.clearToken();
      container.read(sessionUserIdProvider.notifier).set(null);
      fixture.api.setToken('admin-token');
      fixture.api.me = fixture.admin;
      container.read(sessionUserIdProvider.notifier).set(fixture.admin.id);

      final all = await container.read(visibleMembersProvider.future);
      expect(all.items.map((m) => m.name), contains('Bruno Beta'));
      expect(all.items.map((m) => m.name), contains('Bob Builder'));
    },
  );

  testWidgets('a saved token restores the session at startup', (tester) async {
    final fixture = Fixture();
    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.owner,
      prefs: const {'session_token': 'saved-token'},
      setSession: false,
    );

    expect(container.read(sessionUserIdProvider), fixture.owner.id);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsNothing);
  });

  testWidgets('a rejected saved token returns to the login screen', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api.unauthorized = true;
    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.owner,
      prefs: const {'session_token': 'stale-token'},
      setSession: false,
    );

    expect(container.read(sessionUserIdProvider), isNull);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });
}
