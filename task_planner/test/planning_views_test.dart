import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/core/rules.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/widgets/shared/section_header.dart';
import 'package:task_planner/widgets/tasks/task_stats.dart';

import 'support/app_harness.dart';

void main() {
  group('date boundaries', () {
    final midnight = DateTime(2026, 10, 25);

    test('the last minute of yesterday is overdue at midnight', () {
      expect(
        isOverdue(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 24, 23, 59),
          now: midnight,
        ),
        isTrue,
      );
    });

    test('the last minute of today is still due today', () {
      expect(
        isDueToday(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 25, 23, 59),
          now: midnight,
        ),
        isTrue,
      );
    });

    test('the first minute of tomorrow is upcoming', () {
      expect(
        isUpcoming(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 26),
          now: DateTime(2026, 10, 25, 23, 59),
        ),
        isTrue,
      );
    });

    test('a completed task is never overdue or due today', () {
      expect(
        isOverdue(
          status: TaskStatus.completed,
          dueDate: DateTime(2026, 10, 24),
          now: midnight,
        ),
        isFalse,
      );
      expect(
        isDueToday(
          status: TaskStatus.completed,
          dueDate: DateTime(2026, 10, 25),
          now: midnight,
        ),
        isFalse,
      );
    });
  });

  testWidgets('task sections render in planner order', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = Fixture();
    final now = DateTime.now();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Past',
        projectId: fixture.project.id,
        dueDate: now.subtract(const Duration(days: 1)),
        createdAt: now,
      ),
    );
    fixture.api.addTask(
      Task(
        id: 2,
        title: 'Today',
        projectId: fixture.project.id,
        dueDate: now,
        createdAt: now,
      ),
    );
    fixture.api.addTask(
      Task(
        id: 3,
        title: 'Future',
        projectId: fixture.project.id,
        dueDate: now.add(const Duration(days: 1)),
        createdAt: now,
      ),
    );
    fixture.api.addTask(
      Task(
        id: 4,
        title: 'Someday',
        projectId: fixture.project.id,
        createdAt: now,
      ),
    );
    fixture.api.addTask(
      Task(
        id: 5,
        title: 'Finished',
        projectId: fixture.project.id,
        status: 'completed',
        createdAt: now,
      ),
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    final headers = [
      'Overdue',
      'Today',
      'Upcoming',
      'No due date',
      'Completed',
    ];
    final positions = [
      for (final header in headers)
        tester.getTopLeft(find.widgetWithText(SectionHeader, header)).dy,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
  });

  testWidgets('stats cards apply the matching filter', (tester) async {
    final fixture = Fixture();
    final now = DateTime.now();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Overdue task',
        projectId: fixture.project.id,
        dueDate: now.subtract(const Duration(days: 1)),
        createdAt: now,
      ),
    );
    fixture.api.addTask(
      Task(
        id: 2,
        title: 'Today task',
        projectId: fixture.project.id,
        dueDate: now,
        createdAt: now,
      ),
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(TaskStats),
        matching: find.text('Due today'),
      ),
    );
    await settle(tester);
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Overdue task'), findsNothing);
  });
}
