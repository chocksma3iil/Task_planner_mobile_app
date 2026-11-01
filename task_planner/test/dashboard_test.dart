import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// Dashboard widget tests: the KPIs must come from the analytics endpoint,
/// and the recent-activity section must distinguish "empty" from "failed".
void main() {
  testWidgets('dashboard shows project KPIs and the empty activity state', (
    tester,
  ) async {
    final fixture = Fixture();
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    fixture.api
      ..addTask(
        Task(
          id: 1,
          title: 'Done task',
          status: 'completed',
          priority: 'high',
          projectId: 1,
          createdAt: now,
          completedAt: now,
        ),
      )
      ..addTask(
        Task(
          id: 2,
          title: 'Late task',
          priority: 'low',
          projectId: 1,
          dueDate: yesterday,
          createdAt: now,
        ),
      )
      ..addTask(
        Task(
          id: 3,
          title: 'Open task',
          priority: 'medium',
          projectId: 1,
          dueDate: now.add(const Duration(days: 3)),
          createdAt: now,
        ),
      );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);

    expect(find.text('Project Dashboard'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Completion rate'), findsOneWidget);
    // 3 tasks: 1 completed, 2 pending, 1 overdue, 33 % completion.
    expect(find.text('3'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    expect(find.text('33%'), findsWidgets);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('No recent activity'), findsOneWidget);
  });

  testWidgets('dashboard lists the recent events of the selected project', (
    tester,
  ) async {
    final fixture = Fixture();
    // Events of another project must never leak into the dashboard.
    final other = fixture.api.addProject(
      Project(id: 2, name: 'Beta', createdAt: DateTime(2026, 1, 1)),
    );
    fixture.api.addAnalyticsEvent(
      other.id,
      'task_created',
      taskId: 99,
      actor: fixture.owner,
    );
    fixture.api.addAnalyticsEvent(
      fixture.project.id,
      'task_created',
      taskId: 2,
      actor: fixture.owner,
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);

    expect(find.text('Olive Owner'), findsOneWidget);
    expect(find.text('Created a task (task #2)'), findsOneWidget);
    expect(find.text('Created a task (task #99)'), findsNothing);
    expect(find.text('No recent activity'), findsNothing);
  });
}
