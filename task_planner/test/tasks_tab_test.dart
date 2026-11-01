import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/widgets/shared/section_header.dart';
import 'package:task_planner/widgets/tasks/task_form_dialog.dart';

import 'support/app_harness.dart';

Future<void> _openTasks(WidgetTester tester) async {
  await tester.tap(find.text('Tasks'));
  await settle(tester);
}

void main() {
  testWidgets('creating a task keeps title, priority, and assignee', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.tap(find.byTooltip('Add task'));
    await settle(tester);
    final dialog = find.byType(TaskFormDialog);
    expect(dialog, findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.text('Title is required.'), findsOneWidget);
    expect(fixture.api.tasks, isEmpty);

    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      'Ship release',
    );
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('High').last);
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await settle(tester);
    await tester.tap(find.textContaining('Bob Builder').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    final task = fixture.api.tasks.single;
    expect(task.title, 'Ship release');
    expect(task.priority, 'high');
    expect(task.assigneeId, fixture.user.id);
    expect(find.text('Ship release'), findsOneWidget);
    expect(find.text('High'), findsWidgets);
  });

  testWidgets('assigning an inactive member is refused with a clear message', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.tap(find.byTooltip('Add task'));
    await settle(tester);
    final dialog = find.byType(TaskFormDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      'Assign to pending',
    );
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await settle(tester);
    await tester.tap(find.textContaining('Carol Guest').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    // The server rejects the assignment; the UI surfaces the reason and no
    // task is created.
    expect(
      find.text('Tasks can only be assigned to active members.'),
      findsOneWidget,
    );
    expect(fixture.api.tasks, isEmpty);
  });

  testWidgets('checkbox completes and reopens a task', (tester) async {
    final fixture = Fixture();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Finish report',
        projectId: fixture.project.id,
        createdAt: DateTime.now(),
      ),
    );
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    expect(fixture.api.tasks.single.status, 'completed');
    expect(fixture.api.tasks.single.completedAt, isNotNull);
    expect(find.text('Completed'), findsWidgets);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    expect(fixture.api.tasks.single.status, 'todo');
    expect(fixture.api.tasks.single.completedAt, isNull);
  });

  testWidgets('deleting a task can be undone', (tester) async {
    final fixture = Fixture();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Temporary task',
        projectId: fixture.project.id,
        createdAt: DateTime.now(),
      ),
    );
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(fixture.api.tasks, isEmpty);
    expect(find.text('Task deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(fixture.api.tasks.single.title, 'Temporary task');
    expect(find.text('Temporary task'), findsOneWidget);
  });

  testWidgets('filters, grouping, and search narrow the task list', (
    tester,
  ) async {
    final fixture = Fixture();
    final now = DateTime.now();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Past task',
        projectId: fixture.project.id,
        dueDate: now.subtract(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(minutes: 4)),
      ),
    );
    fixture.api.addTask(
      Task(
        id: 2,
        title: 'Today task',
        projectId: fixture.project.id,
        dueDate: now,
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
    );
    fixture.api.addTask(
      Task(
        id: 3,
        title: 'Future task',
        projectId: fixture.project.id,
        dueDate: now.add(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    );
    fixture.api.addTask(
      Task(
        id: 4,
        title: 'Someday task',
        projectId: fixture.project.id,
        createdAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    fixture.api.addTask(
      Task(
        id: 5,
        title: 'Done task',
        projectId: fixture.project.id,
        status: 'completed',
        createdAt: now,
      ),
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    // The list is lazy: scroll to each section instead of assuming every
    // header is built at once.
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

    await tester.tap(find.widgetWithText(ChoiceChip, 'Today'));
    await settle(tester);
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Past task'), findsNothing);
    expect(find.text('Future task'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
    await settle(tester);
    expect(find.text('Past task'), findsOneWidget);
    expect(find.text('Today task'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
    await settle(tester);
    expect(find.text('Done task'), findsOneWidget);
    expect(find.text('Past task'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'future');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Future task'), findsOneWidget);
    expect(find.text('Today task'), findsNothing);
  });

  testWidgets('task list errors surface with a working retry', (tester) async {
    final fixture = Fixture();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Recovered task',
        projectId: fixture.project.id,
        createdAt: DateTime.now(),
      ),
    );
    fixture.api.tasksError = 'offline';
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    expect(find.textContaining('Could not load tasks'), findsOneWidget);
    fixture.api.tasksError = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Recovered task'), findsOneWidget);
  });

  testWidgets('editing a task persists subtask completion', (tester) async {    final fixture = Fixture();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'Review spec',
        projectId: fixture.project.id,
        createdAt: DateTime.now(),
      ),
    );
    fixture.api.subtasks.add(
      Subtask(
        id: 1,
        taskId: 1,
        title: 'Check specs',
        completed: false,
        sortOrder: 0,
        createdAt: DateTime.now(),
      ),
    );
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.tap(find.text('Review spec'));
    await settle(tester);
    expect(find.byType(TaskFormDialog), findsOneWidget);

    // Ticking the box must reach the API on save; the dialog and the caller
    // used to share the same map, so the change looked like a no-op.
    final checkbox = find.descendant(
      of: find.byType(TaskFormDialog),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(fixture.api.subtasks.single.completed, isTrue);
    expect(fixture.api.subtasks.single.sortOrder, 0);
  });

  testWidgets('long-press selects tasks and bulk completes them', (
    tester,
  ) async {
    final fixture = Fixture();
    for (var i = 1; i <= 2; i += 1) {
      fixture.api.addTask(
        Task(
          id: i,
          title: 'Bulk $i',
          projectId: fixture.project.id,
          createdAt: DateTime.now(),
        ),
      );
    }
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.longPress(find.text('Bulk 1'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Bulk 2'));
    await settle(tester);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Complete selected'));
    await settle(tester);
    expect(find.text('2 completed'), findsOneWidget);
    expect(fixture.api.tasks.every((t) => t.status == 'completed'), isTrue);
  });

  testWidgets('bulk reassign applies the chosen member', (tester) async {
    final fixture = Fixture();
    for (var i = 1; i <= 2; i += 1) {
      fixture.api.addTask(
        Task(
          id: i,
          title: 'Bulk $i',
          projectId: fixture.project.id,
          createdAt: DateTime.now(),
        ),
      );
    }
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await _openTasks(tester);

    await tester.longPress(find.text('Bulk 1'));
    await settle(tester);
    await tester.tap(find.text('Bulk 2'));
    await settle(tester);
    await tester.tap(find.byTooltip('Reassign selected'));
    await settle(tester);

    final reassign = find.widgetWithText(FilledButton, 'Reassign');
    expect(tester.widget<FilledButton>(reassign).onPressed, isNull);
    await tester.tap(find.text('Olive Owner'));
    await settle(tester);
    await tester.tap(reassign);
    await settle(tester);

    expect(find.text('2 reassigned'), findsOneWidget);
    expect(
      fixture.api.tasks.every((t) => t.assigneeId == fixture.owner.id),
      isTrue,
    );
  });
}
