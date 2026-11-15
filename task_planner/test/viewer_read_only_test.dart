import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// A viewer is read-only: the UI hides every mutation entry point and the
/// shell only exposes the three viewer tabs (members, tasks, mine).
void main() {
  testWidgets('viewer sees read-only tabs and no mutation actions', (
    tester,
  ) async {
    final fixture = Fixture();
    final viewer = const Account(
      id: 9,
      name: 'Vera Viewer',
      email: 'vera@example.com',
      projectId: 1,
      role: 'viewer',
      status: 'active',
      createdAt: null,
    );
    fixture.api
      ..addAccount(viewer)
      ..addTask(
        Task(
          id: 1,
          title: 'Read-only task',
          priority: 'low',
          projectId: 1,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

    await pumpTaskPlanner(tester, fixture.api, account: viewer);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Planner'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);

    await tester.tap(find.text('Tasks'));
    await settle(tester);

    expect(find.text('Read-only task'), findsOneWidget);
    expect(find.byTooltip('Add task'), findsNothing);
    expect(find.byTooltip('Delete selected'), findsNothing);
    // The completion checkbox exists but is disabled for a viewer.
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(checkbox.onChanged, isNull);

    await tester.tap(find.text('Members'));
    await settle(tester);

    expect(find.byTooltip('Add user'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Waiting for confirmation'), findsNothing);
    expect(find.text('active'), findsNothing);
    expect(find.text('pending'), findsNothing);
    // Names stay visible to everyone in the project.
    expect(find.text('Bob Builder'), findsWidgets);
  });

  testWidgets('the API refuses viewer mutations', (tester) async {
    final fixture = Fixture();
    final viewer = const Account(
      id: 9,
      name: 'Vera Viewer',
      email: 'vera@example.com',
      projectId: 1,
      role: 'viewer',
      status: 'active',
      createdAt: null,
    );
    fixture.api
      ..addAccount(viewer)
      ..me = viewer;

    await expectLater(
      fixture.api.post('/tasks', {
        'project_id': 1,
        'title': 'Viewer task',
        'priority': 'low',
      }),
      throwsStateError,
    );
    await expectLater(
      fixture.api.post('/tasks/bulk/delete', {
        'task_ids': const [1],
      }),
      throwsStateError,
    );
  });
}
