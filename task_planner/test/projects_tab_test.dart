import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/data_providers.dart';

import 'support/app_harness.dart';
import 'support/fake_api_client.dart';

void main() {
  testWidgets('admin creates a project from the Projects tab', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);

    expect(find.text('Alpha'), findsOneWidget);
    await tester.tap(find.byTooltip('Create project'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, 'Gamma');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    expect(find.text('Gamma'), findsOneWidget);
    expect(fixture.api.projects.map((p) => p.name), contains('Gamma'));
  });

  testWidgets('non-admins do not see project management', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.text('Projects'), findsNothing);
    expect(find.byTooltip('Create project'), findsNothing);
    expect(find.byTooltip('Assign owner'), findsNothing);
  });

  testWidgets('admin assigns a project owner from the card menu', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);

    await tester.tap(find.byTooltip('Assign owner'));
    await settle(tester);
    await tester.tap(find.text('Bob Builder').last);
    await settle(tester);

    expect(fixture.api.projects.single.ownerId, fixture.user.id);
    expect(
      fixture.api.members.firstWhere((m) => m.id == fixture.user.id).role,
      'project_owner',
    );
    expect(find.text('Bob Builder'), findsWidgets);
  });

  testWidgets('admin archives and restores a project', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);

    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await settle(tester);

    expect(fixture.api.projects.single.status, 'archived');
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Project archived'), findsOneWidget);

    // The archived project is reachable through the "Show archived" toggle.
    await tester.tap(find.byTooltip('Show archived'));
    await settle(tester);

    expect(find.text('Archived Projects'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settle(tester);

    expect(fixture.api.projects.single.status, 'active');
    expect(find.text('No archived projects'), findsOneWidget);

    await tester.tap(find.byTooltip('Show active'));
    await settle(tester);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('empty and failing project lists show actionable states', (
    tester,
  ) async {
    final api = FakeApiClient();
    final admin = const Account(
      id: 1,
      name: 'Root Admin',
      email: 'root@example.com',
      role: 'admin',
      status: 'active',
    );
    api.addAccount(admin);
    final container = await pumpTaskPlanner(tester, api, account: admin);
    expect(find.text('No projects yet'), findsOneWidget);

    api.projectsError = 'offline';
    // The provider keeps its cached empty list until it is invalidated.
    container.invalidate(projectListProvider);
    await tester.tap(find.text('Tasks'));
    await settle(tester);
    expect(find.textContaining('Could not load projects'), findsOneWidget);

    api.projectsError = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('No project available.'), findsOneWidget);
  });
}
