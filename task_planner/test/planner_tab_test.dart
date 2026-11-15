import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/widgets/shared/section_header.dart';
import 'package:task_planner/widgets/tasks/task_tile.dart';

import 'support/app_harness.dart';

/// C12: the Planner tab groups tasks by urgency, supports inline add/edit and
/// completion, and lets an admin pick the project to plan.
void main() {
  Future<void> openPlanner(WidgetTester tester) async {
    await tester.tap(find.text('Planner'));
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  testWidgets('owner sees the urgency sections built from the project tasks', (
    tester,
  ) async {
    final fixture = Fixture();
    final now = DateTime.now();
    fixture.api
      ..addTask(
        Task(
          id: 1,
          title: 'Late deliverable',
          projectId: fixture.project.id,
          dueDate: now.subtract(const Duration(days: 2)),
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      )
      ..addTask(
        Task(
          id: 2,
          title: 'Today deliverable',
          projectId: fixture.project.id,
          dueDate: now,
          createdAt: now.subtract(const Duration(minutes: 4)),
        ),
      )
      ..addTask(
        Task(
          id: 3,
          title: 'Later deliverable',
          projectId: fixture.project.id,
          dueDate: now.add(const Duration(days: 3)),
          createdAt: now.subtract(const Duration(minutes: 3)),
        ),
      )
      ..addTask(
        Task(
          id: 4,
          title: 'Undated deliverable',
          projectId: fixture.project.id,
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
      )
      ..addTask(
        Task(
          id: 5,
          title: 'Finished deliverable',
          projectId: fixture.project.id,
          status: 'completed',
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
      );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await openPlanner(tester);

    // The list is lazy: reach every header by scrolling.
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    for (final header in [
      'Overdue',
      'Today',
      'Upcoming',
      'No due date',
      'Completed',
    ]) {
      final section = find.widgetWithText(SectionHeader, header);
      await tester.scrollUntilVisible(section, 150, scrollable: scrollable);
      expect(section, findsOneWidget);
    }

    // Search narrows the sections without losing the grouping.
    await search(tester, 'late');
    expect(find.text('Late deliverable'), findsOneWidget);
    expect(find.text('Today deliverable'), findsNothing);
    expect(find.text('Finished deliverable'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
  });

  testWidgets('owner adds, edits, and completes a task from the planner', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await openPlanner(tester);

    expect(find.text('No tasks here'), findsOneWidget);

    // Add: the inline form only enables its button once a title is typed.
    await tester.tap(find.byTooltip('Add task'));
    await settle(tester);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      'Planner task',
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    final created = fixture.api.tasks.single;
    expect(created.title, 'Planner task');
    expect(created.projectId, fixture.project.id);
    expect(find.text('Planner task'), findsOneWidget);
    expect(find.widgetWithText(SectionHeader, 'No due date'), findsOneWidget);

    // Edit: tapping the row opens the inline form pre-filled.
    await tester.tap(find.text('Planner task'));
    await settle(tester);
    final editDialog = find.widgetWithText(AlertDialog, 'Edit task');
    expect(editDialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: editDialog, matching: find.byType(TextField)).first,
      'Renamed task',
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(fixture.api.tasks.single.title, 'Renamed task');
    expect(fixture.api.tasks.single.id, created.id);
    expect(find.text('Renamed task'), findsOneWidget);
    expect(find.text('Planner task'), findsNothing);

    // Complete: the checkbox is wired to the same service as the Tasks tab.
    final tile = find.ancestor(
      of: find.text('Renamed task'),
      matching: find.byType(TaskTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    await settle(tester);

    expect(fixture.api.tasks.single.status, 'completed');
    expect(fixture.api.tasks.single.completedAt, isNotNull);
  });

  testWidgets('admin picks the project to plan', (tester) async {
    final fixture = Fixture();
    final base = DateTime(2026, 1, 1, 10);
    fixture.api
      ..addProject(
        Project(id: 2, name: 'Beta', createdAt: DateTime(2026, 1, 2)),
      )
      ..addTask(
        Task(
          id: 1,
          title: 'Alpha task',
          projectId: fixture.project.id,
          createdAt: base,
        ),
      )
      ..addTask(
        Task(id: 2, title: 'Beta task', projectId: 2, createdAt: base),
      );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await openPlanner(tester);

    // The picker defaults to the first project and only its tasks are shown.
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('Alpha task'), findsOneWidget);
    expect(find.text('Beta task'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    expect(find.text('Beta task'), findsOneWidget);
    expect(find.text('Alpha task'), findsNothing);
  });
}
